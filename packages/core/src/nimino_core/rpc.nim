## Window-scoped JSON RPC runtime.
##
## This module deliberately accepts only explicitly registered handlers.  It
## does not reflect Nim symbols, expose OS APIs, or infer a callable surface
## from arbitrary types.

import std/[algorithm, asyncfutures, json, jsonutils, macros, strutils, tables, times, typetraits]

const
  DefaultRpcTimeoutMs* = 30_000'i64
  MaximumRpcTimeoutMs* = 600_000'i64
  MaximumRpcIdLength* = 64

type
  RpcErrorCode* = enum
    invalidRequest
    methodNotAllowed
    requestCancelled
    requestTimedOut
    handlerFailed

  RpcError* = object
    code*: RpcErrorCode
    message*: string

  RpcResult* = object
    case isOk*: bool
    of true:
      value*: JsonNode
    of false:
      error*: RpcError

  RpcHandler* = proc(params: JsonNode): Future[RpcResult] {.closure.}
  RpcCancellationToken* = ref object
    ## Cooperative cancellation state for explicitly cancellable handlers.
    ## Nim futures have no universal pre-emption primitive, so handlers must
    ## check this token at safe await/IO boundaries.
    cancelled*: bool
  RpcCancellableHandler* = proc(params: JsonNode;
                                 token: RpcCancellationToken): Future[RpcResult] {.closure.}
  RpcSyncHandler* = proc(params: JsonNode): RpcResult {.closure.}
  RpcReplySink* = proc(message: string) {.closure.}

  PendingRequest = object
    future: Future[RpcResult]
    deadlineMs: int64
    token: RpcCancellationToken

  RpcRegistry* = ref object
    handlers: Table[string, RpcHandler]
    cancellableHandlers: Table[string, RpcCancellableHandler]
    notificationHandlers: Table[string, proc(params: JsonNode) {.closure.}]
    typeScriptSchemas: Table[string, tuple[paramsType, resultType: string]]
    pending: Table[string, PendingRequest]
    sink: RpcReplySink
    closed: bool

proc rpcError*(code: RpcErrorCode; message: string): RpcError {.inline.} =
  RpcError(code: code, message: message)

proc rpcSuccess*(value: JsonNode): RpcResult {.inline.} =
  RpcResult(isOk: true, value: value)

proc rpcFailure*(error: RpcError): RpcResult {.inline.} =
  RpcResult(isOk: false, error: error)

proc nowMilliseconds*(): int64 {.inline.} =
  int64(epochTime() * 1_000.0)

proc newRpcRegistry*(sink: RpcReplySink = nil): RpcRegistry =
  RpcRegistry(sink: sink)

const MaximumTypeScriptSchemaDepth = 12

proc typeScriptPrimitive(typeName: string): string =
  case typeName.toLowerAscii()
  of "string", "system.string", "cstring", "system.cstring": "string"
  of "bool", "system.bool": "boolean"
  of "int", "system.int", "int8", "system.int8", "int16", "system.int16",
     "int32", "system.int32", "int64", "system.int64", "uint", "system.uint",
     "uint8", "system.uint8", "uint16", "system.uint16", "uint32", "system.uint32",
     "uint64", "system.uint64", "float", "system.float", "float32", "system.float32",
     "float64", "system.float64": "number"
  else: ""

proc typeScriptPropertyName(field: NimNode): string =
  "'" & field.strVal.replace("\\", "\\\\").replace("'", "\\'") & "'"

proc typeScriptArrayElement(element: string): string =
  if " | " in element:
    "(" & element & ")"
  else:
    element

proc typeScriptObjectType(implementation: NimNode; depth: int): string

proc typeScriptTypeNode(node: NimNode; depth = 0): string =
  ## This is compile-time-only and intentionally recognizes only JSON codec
  ## shapes whose TypeScript representation is unambiguous. Unsupported
  ## fields remain `unknown`, preserving declaration soundness.
  if node.isNil or depth >= MaximumTypeScriptSchemaDepth:
    return "unknown"
  let primitive = node.repr.typeScriptPrimitive()
  if primitive.len > 0:
    return primitive
  if node.kind == nnkBracketExpr and node.len >= 2:
    let constructor = node[0].repr.toLowerAscii()
    if constructor in ["seq", "system.seq"]:
      return typeScriptArrayElement(typeScriptTypeNode(node[1], depth + 1)) & "[]"
    if constructor in ["array", "system.array"] and node.len >= 3:
      return typeScriptArrayElement(typeScriptTypeNode(node[^1], depth + 1)) & "[]"
    if constructor in ["option", "options.option"]:
      return typeScriptTypeNode(node[1], depth + 1) & " | null"
    return "unknown"
  let implementation = node.getTypeImpl
  case implementation.kind
  of nnkObjectTy:
    typeScriptObjectType(implementation, depth + 1)
  of nnkEnumTy, nnkRange:
    ## `jsonutils.toJson` encodes Nim enums numerically and ranges as numbers.
    "number"
  of nnkDistinctTy:
    if implementation.len > 0:
      typeScriptTypeNode(implementation[0], depth + 1)
    else:
      "unknown"
  else:
    "unknown"

proc typeScriptObjectType(implementation: NimNode; depth: int): string =
  if implementation.len < 3 or implementation[2].kind != nnkRecList:
    return "unknown"
  var fields: seq[string]
  for definition in implementation[2]:
    ## Variant records and inheritance are left conservative in this first
    ## extractor because their JSON shape can vary with a discriminator.
    if definition.kind != nnkIdentDefs or definition.len < 3:
      return "unknown"
    let fieldType = definition[^2]
    let rendered = typeScriptTypeNode(fieldType, depth + 1)
    for index in 0 ..< definition.len - 2:
      fields.add(typeScriptPropertyName(definition[index]) & ": " & rendered)
  "{ " & fields.join("; ") & " }"

macro typeScriptType(T: typedesc): untyped =
  ## Extract a conservative inline TypeScript type from a concrete Nim type.
  ## This macro is used only after an explicit RPC handler is registered.
  let descriptor = T.getTypeImpl
  if descriptor.kind != nnkBracketExpr or descriptor.len != 2:
    return newLit("unknown")
  newLit(typeScriptTypeNode(descriptor[1]))

proc setTypeScriptSchema(registry: RpcRegistry; methodName, paramsType, resultType: string) =
  if registry != nil:
    registry.typeScriptSchemas[methodName] = (paramsType, resultType)

proc setReplySink*(registry: RpcRegistry; sink: RpcReplySink) =
  if registry != nil and not registry.closed:
    registry.sink = sink

proc isMethodRegistered*(registry: RpcRegistry; methodName: string): bool =
  registry != nil and (registry.handlers.hasKey(methodName) or
    registry.cancellableHandlers.hasKey(methodName) or
    registry.notificationHandlers.hasKey(methodName))

proc validMethodName(methodName: string): bool {.inline.} =
  if methodName.len == 0 or methodName.len > 256:
    return false
  for ch in methodName:
    if ch <= '\x20' or ch == '\x7f' or ch in {'"', '\\'}:
      return false
  true

proc registeredMethods*(registry: RpcRegistry): seq[string] =
  ## Return only explicitly registered names; handler closures never escape.
  if registry.isNil or registry.closed:
    return @[]
  for methodName in registry.handlers.keys:
    result.add(methodName)
  for methodName in registry.cancellableHandlers.keys:
    if methodName notin result:
      result.add(methodName)
  for methodName in registry.notificationHandlers.keys:
    if methodName notin result:
      result.add(methodName)
  result.sort()

proc registeredNotificationMethods*(registry: RpcRegistry): seq[string] =
  if registry.isNil or registry.closed:
    return @[]
  for methodName in registry.notificationHandlers.keys:
    result.add(methodName)
  result.sort()

proc registeredRequestMethods(registry: RpcRegistry): seq[string] =
  if registry.isNil or registry.closed:
    return @[]
  for methodName in registry.handlers.keys:
    result.add(methodName)
  for methodName in registry.cancellableHandlers.keys:
    if methodName notin result:
      result.add(methodName)
  result.sort()

proc typescriptDeclarations*(registry: RpcRegistry): string =
  ## Generate a conservative declaration surface. Runtime codecs may carry
  ## richer types later; unknown keeps this output sound today.
  result = "declare global {\n  interface Window {\n    nimino: {\n"
  for methodName in registry.registeredRequestMethods():
    let escaped = methodName.replace("\\", "\\\\").replace("'", "\\'")
    let schema = registry.typeScriptSchemas.getOrDefault(methodName,
      (paramsType: "unknown", resultType: "unknown"))
    result.add("      invoke(method: '")
    result.add(escaped)
    result.add("', params?: " & schema.paramsType &
      ", options?: { timeoutMs?: number }): Promise<" & schema.resultType & ">;\n")
  for methodName in registry.registeredNotificationMethods():
    let escaped = methodName.replace("\\", "\\\\").replace("'", "\\'")
    let schema = registry.typeScriptSchemas.getOrDefault(methodName,
      (paramsType: "unknown", resultType: "unknown"))
    result.add("      notify(method: '")
    result.add(escaped)
    result.add("', params?: " & schema.paramsType & "): void;\n")
  result.add("      notify(method: string, params?: unknown): void;\n")
  result.add("    };\n  }\n}\nexport {};\n")

proc registerTypeScriptSchema*(registry: RpcRegistry; methodName, paramsType,
                               resultType: string): bool =
  ## Override conservative `unknown` declarations for an already registered
  ## method. This only affects generated declarations; runtime JSON codecs and
  ## the explicit method allow-list remain unchanged.
  if registry.isNil or registry.closed or not validMethodName(methodName) or
      not registry.isMethodRegistered(methodName) or paramsType.len == 0 or
      resultType.len == 0:
    return false
  for typeText in [paramsType, resultType]:
    for ch in typeText:
      if not (ch.isAlphaNumeric or ch in {' ', '\t', '_', '-', '.', ',',
          '<', '>', '[', ']', '|', '&', ':', '?', '(', ')', '\'', '"'}):
        return false
  registry.setTypeScriptSchema(methodName, paramsType, resultType)
  true

proc register*(registry: RpcRegistry; methodName: string; handler: RpcHandler): bool =
  if registry.isNil or registry.closed or not validMethodName(methodName) or handler.isNil or
      registry.notificationHandlers.hasKey(methodName) or
      registry.cancellableHandlers.hasKey(methodName):
    return false
  if registry.handlers.hasKey(methodName):
    return false
  registry.handlers[methodName] = handler
  true

proc registerCancellable*(registry: RpcRegistry; methodName: string;
                          handler: RpcCancellableHandler): bool =
  ## Register an explicitly cancellable request handler.  Cancellation is
  ## cooperative; the handler should inspect `token.cancelled` after awaits.
  if registry.isNil or registry.closed or not validMethodName(methodName) or handler.isNil or
      registry.notificationHandlers.hasKey(methodName) or
      registry.handlers.hasKey(methodName) or
      registry.cancellableHandlers.hasKey(methodName):
    return false
  registry.cancellableHandlers[methodName] = handler
  true

proc registerNotification*(registry: RpcRegistry; methodName: string;
                           handler: proc(params: JsonNode) {.closure.}): bool =
  ## Register an explicit fire-and-forget RPC method.  Notifications reuse
  ## the same method allow-list and never create a response or pending entry.
  if registry.isNil or registry.closed or not validMethodName(methodName) or
      handler.isNil or registry.handlers.hasKey(methodName) or
      registry.notificationHandlers.hasKey(methodName):
    return false
  registry.notificationHandlers[methodName] = handler
  true

proc registerTypedNotification*[T](registry: RpcRegistry; methodName: string;
                                   handler: proc(params: T) {.closure.}): bool =
  if handler.isNil:
    return false
  result = registry.registerNotification(methodName, proc(params: JsonNode) =
    try:
      handler(params.jsonTo(T))
    except CatchableError:
      discard)
  if result:
    registry.setTypeScriptSchema(methodName, typeScriptType(T), "void")

proc registerTypedNotification*(registry: RpcRegistry; methodName: string;
                               handler: proc() {.closure.}): bool =
  if handler.isNil:
    return false
  result = registry.registerNotification(methodName, proc(params: JsonNode) =
    try:
      handler()
    except CatchableError:
      discard)
  if result:
    registry.setTypeScriptSchema(methodName, "void", "void")

proc unregister*(registry: RpcRegistry; methodName: string): bool =
  ## Remove one explicitly registered method. Pending requests are not
  ## cancelled here; they retain their original handler until completion.
  if registry.isNil or registry.closed or not validMethodName(methodName):
    return false
  if registry.handlers.hasKey(methodName):
    registry.handlers.del(methodName)
    registry.typeScriptSchemas.del(methodName)
  elif registry.cancellableHandlers.hasKey(methodName):
    registry.cancellableHandlers.del(methodName)
    registry.typeScriptSchemas.del(methodName)
  elif registry.notificationHandlers.hasKey(methodName):
    registry.notificationHandlers.del(methodName)
    registry.typeScriptSchemas.del(methodName)
  else:
    return false
  true

proc registerSync*(registry: RpcRegistry; methodName: string;
                   handler: RpcSyncHandler): bool =
  if handler.isNil:
    return false
  registry.register(methodName, proc(params: JsonNode): Future[RpcResult] =
    let future = newFuture[RpcResult]("nimino.rpc.sync")
    try:
      future.complete(handler(params))
    except CatchableError:
      future.complete(rpcFailure(rpcError(handlerFailed, "RPC handler raised an exception")))
    future
  )

proc typedFailure(): RpcResult =
  rpcFailure(rpcError(invalidRequest, "RPC parameters do not match the registered type"))

proc encodeTypedFuture[T](source: Future[T]): Future[RpcResult] =
  let target = newFuture[RpcResult]("nimino.rpc.typed")
  if source.isNil:
    target.complete(rpcFailure(rpcError(handlerFailed, "RPC handler did not return a Future")))
    return target
  source.addCallback(proc(completed: Future[T]) {.gcsafe.} =
    if target.finished:
      return
    if completed.failed:
      target.complete(rpcFailure(rpcError(handlerFailed, "RPC handler failed")))
      return
    try:
      target.complete(rpcSuccess(completed.read().toJson()))
    except CatchableError:
      target.complete(rpcFailure(rpcError(handlerFailed, "RPC result is not JSON serializable")))
  )
  target

proc registerTyped*[R](registry: RpcRegistry; methodName: string;
                       handler: proc(): R {.closure.}): bool =
  if handler.isNil:
    return false
  result = registry.registerSync(methodName, proc(params: JsonNode): RpcResult =
    try:
      rpcSuccess(handler().toJson())
    except CatchableError:
      typedFailure()
  )
  if result:
    registry.setTypeScriptSchema(methodName, "void", typeScriptType(R))

proc registerTyped*[T, R](registry: RpcRegistry; methodName: string;
                          handler: proc(params: T): R {.closure.}): bool =
  if handler.isNil:
    return false
  result = registry.registerSync(methodName, proc(params: JsonNode): RpcResult =
    try:
      rpcSuccess(handler(params.jsonTo(T)).toJson())
    except CatchableError:
      typedFailure()
  )
  if result:
    registry.setTypeScriptSchema(methodName, typeScriptType(T), typeScriptType(R))

proc registerTypedAsync*[R](registry: RpcRegistry; methodName: string;
                            handler: proc(): Future[R] {.closure.}): bool =
  if handler.isNil:
    return false
  result = registry.register(methodName, proc(params: JsonNode): Future[RpcResult] =
    try:
      handler().encodeTypedFuture()
    except CatchableError:
      let failed = newFuture[RpcResult]("nimino.rpc.typedAsync")
      failed.complete(rpcFailure(rpcError(handlerFailed, "RPC handler raised an exception")))
      failed
  )
  if result:
    registry.setTypeScriptSchema(methodName, "void", typeScriptType(R))

proc registerTypedAsync*[T, R](registry: RpcRegistry; methodName: string;
                               handler: proc(params: T): Future[R] {.closure.}): bool =
  if handler.isNil:
    return false
  result = registry.register(methodName, proc(params: JsonNode): Future[RpcResult] =
    try:
      handler(params.jsonTo(T)).encodeTypedFuture()
    except CatchableError:
      let failed = newFuture[RpcResult]("nimino.rpc.typedAsync")
      failed.complete(rpcFailure(rpcError(invalidRequest,
        "RPC parameters do not match the registered type")))
      failed
  )
  if result:
    registry.setTypeScriptSchema(methodName, typeScriptType(T), typeScriptType(R))

proc errorCodeName(code: RpcErrorCode): string =
  case code
  of invalidRequest: "invalidRequest"
  of methodNotAllowed: "methodNotAllowed"
  of requestCancelled: "cancelled"
  of requestTimedOut: "timeout"
  of handlerFailed: "handlerFailed"

proc emit(registry: RpcRegistry; node: JsonNode) =
  if registry.isNil or registry.closed or registry.sink.isNil:
    return
  try:
    registry.sink($node)
  except CatchableError:
    ## A transport failure is handled by the owning Window/App lifecycle.
    discard

proc emitError(registry: RpcRegistry; requestId: string; error: RpcError) =
  registry.emit(%*{
    "nimino": "rpc",
    "kind": "response",
    "id": requestId,
    "ok": false,
    "error": {
      "code": error.code.errorCodeName(),
      "message": error.message
    }
  })

proc emitSuccess(registry: RpcRegistry; requestId: string; value: JsonNode) =
  registry.emit(%*{
    "nimino": "rpc",
    "kind": "response",
    "id": requestId,
    "ok": true,
    "result": value
  })

proc validRequestId(value: string): bool =
  if value.len == 0 or value.len > MaximumRpcIdLength:
    return false
  for character in value:
    if not (character.isAlphaNumeric or character in {'-', '_'}):
      return false
  true

proc requestId(node: JsonNode): string =
  if node.hasKey("id") and node["id"].kind == JString:
    return node["id"].getStr()

proc requestTimeout(node: JsonNode): RpcResult =
  if not node.hasKey("timeoutMs"):
    return rpcSuccess(%DefaultRpcTimeoutMs)
  if node["timeoutMs"].kind != JInt:
    return rpcFailure(rpcError(invalidRequest, "timeoutMs must be an integer"))
  let value = node["timeoutMs"].getInt()
  if value <= 0 or value > MaximumRpcTimeoutMs:
    return rpcFailure(rpcError(invalidRequest, "timeoutMs is out of range"))
  rpcSuccess(%value)

proc completeRequest(registry: RpcRegistry; requestId: string;
                     future: Future[RpcResult]) =
  if registry.isNil or registry.closed or not registry.pending.hasKey(requestId):
    return
  registry.pending.del(requestId)
  if future.failed:
    registry.emitError(requestId, rpcError(handlerFailed, "RPC handler failed"))
    return
  let result = future.read()
  if result.isOk:
    registry.emitSuccess(requestId, result.value)
  else:
    registry.emitError(requestId, result.error)

proc tick*(registry: RpcRegistry; nowMs = nowMilliseconds()) =
  if registry.isNil or registry.closed:
    return
  var completed: seq[string]
  var expired: seq[string]
  for id, pending in registry.pending:
    if pending.future.finished:
      completed.add(id)
    elif pending.deadlineMs <= nowMs:
      expired.add(id)
  for id in completed:
    if registry.pending.hasKey(id):
      let future = registry.pending[id].future
      registry.completeRequest(id, future)
  for id in expired:
    if registry.pending.hasKey(id):
      if registry.pending[id].token != nil:
        registry.pending[id].token.cancelled = true
      registry.pending.del(id)
      registry.emitError(id, rpcError(requestTimedOut, "RPC request timed out"))

proc invokeNotification(registry: RpcRegistry; methodName: string; params: JsonNode) =
  if registry.isNil or registry.closed:
    return
  if registry.notificationHandlers.hasKey(methodName):
    try: registry.notificationHandlers[methodName](params)
    except CatchableError: discard
    return
  if not registry.handlers.hasKey(methodName) and
      not registry.cancellableHandlers.hasKey(methodName):
    return
  try:
    let future = if registry.cancellableHandlers.hasKey(methodName):
        registry.cancellableHandlers[methodName](params,
          RpcCancellationToken(cancelled: false))
      else:
        registry.handlers[methodName](params)
    if future.isNil:
      return
    ## Notifications intentionally have no response channel.  An async handler
    ## owns its own Future; the registry must not retain it indefinitely.
  except CatchableError:
    discard

proc handleRequest(registry: RpcRegistry; node: JsonNode; nowMs: int64) =
  let id = node.requestId()
  if not id.validRequestId():
    if id.len > 0:
      registry.emitError(id, rpcError(invalidRequest, "request id is invalid"))
    return
  if not node.hasKey("method") or node["method"].kind != JString:
    registry.emitError(id, rpcError(invalidRequest, "method must be a string"))
    return
  let methodName = node["method"].getStr()
  if not registry.handlers.hasKey(methodName) and
      not registry.cancellableHandlers.hasKey(methodName):
    registry.emitError(id, rpcError(methodNotAllowed, "RPC method is not allowed"))
    return
  if registry.pending.hasKey(id):
    registry.emitError(id, rpcError(invalidRequest, "request id is already active"))
    return
  let timeout = node.requestTimeout()
  if not timeout.isOk:
    registry.emitError(id, timeout.error)
    return
  let params = if node.hasKey("params"): node["params"] else: newJNull()
  try:
    let token = if registry.cancellableHandlers.hasKey(methodName):
        RpcCancellationToken(cancelled: false)
      else: nil
    let future = if token != nil:
        registry.cancellableHandlers[methodName](params, token)
      else:
        registry.handlers[methodName](params)
    if future.isNil:
      registry.emitError(id, rpcError(handlerFailed, "RPC handler did not return a Future"))
      return
    registry.pending[id] = PendingRequest(
      future: future,
      deadlineMs: nowMs + timeout.value.getInt(),
      token: token
    )
    registry.tick(nowMs)
  except CatchableError:
    registry.emitError(id, rpcError(handlerFailed, "RPC handler raised an exception"))

proc handleCancel(registry: RpcRegistry; node: JsonNode) =
  let id = node.requestId()
  if not id.validRequestId() or not registry.pending.hasKey(id):
    return
  if registry.pending[id].token != nil:
    registry.pending[id].token.cancelled = true
  registry.pending.del(id)
  registry.emitError(id, rpcError(requestCancelled, "RPC request was cancelled"))

proc handleMessage*(registry: RpcRegistry; message: string;
                    nowMs = nowMilliseconds()): bool =
  ## Returns true only for a message addressed to this RPC registry.
  if registry.isNil or registry.closed:
    return false
  let node = try:
    parseJson(message)
  except CatchableError:
    return false
  if node.kind != JObject or not node.hasKey("nimino") or
      node["nimino"].kind != JString or node["nimino"].getStr() != "rpc":
    return false
  if not node.hasKey("kind") or node["kind"].kind != JString:
    return true
  case node["kind"].getStr()
  of "request":
    registry.handleRequest(node, nowMs)
  of "notification":
    if node.hasKey("method") and node["method"].kind == JString:
      let params = if node.hasKey("params"): node["params"] else: newJNull()
      registry.invokeNotification(node["method"].getStr(), params)
  of "cancel":
    registry.handleCancel(node)
  else:
    discard
  true

proc close*(registry: RpcRegistry) =
  if registry.isNil or registry.closed:
    return
  for requestId in registry.pending.keys:
    registry.emitError(requestId, rpcError(requestCancelled,
      "RPC request was cancelled because the window closed"))
  registry.closed = true
  registry.handlers.clear()
  for requestId, pending in registry.pending:
    if pending.token != nil:
      pending.token.cancelled = true
  registry.cancellableHandlers.clear()
  registry.notificationHandlers.clear()
  registry.pending.clear()
  registry.sink = nil
