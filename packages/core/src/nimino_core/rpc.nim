## Window-scoped JSON RPC runtime.
##
## This module deliberately accepts only explicitly registered handlers.  It
## does not reflect Nim symbols, expose OS APIs, or infer a callable surface
## from arbitrary types.

import std/[asyncfutures, json, jsonutils, strutils, tables, times]

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
  RpcSyncHandler* = proc(params: JsonNode): RpcResult {.closure.}
  RpcReplySink* = proc(message: string) {.closure.}

  PendingRequest = object
    future: Future[RpcResult]
    deadlineMs: int64

  RpcRegistry* = ref object
    handlers: Table[string, RpcHandler]
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

proc setReplySink*(registry: RpcRegistry; sink: RpcReplySink) =
  if registry != nil and not registry.closed:
    registry.sink = sink

proc isMethodRegistered*(registry: RpcRegistry; methodName: string): bool =
  registry != nil and registry.handlers.hasKey(methodName)

proc register*(registry: RpcRegistry; methodName: string; handler: RpcHandler): bool =
  if registry.isNil or registry.closed or methodName.len == 0 or handler.isNil:
    return false
  if registry.handlers.hasKey(methodName):
    return false
  registry.handlers[methodName] = handler
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
  registry.registerSync(methodName, proc(params: JsonNode): RpcResult =
    try:
      rpcSuccess(handler().toJson())
    except CatchableError:
      typedFailure()
  )

proc registerTyped*[T, R](registry: RpcRegistry; methodName: string;
                          handler: proc(params: T): R {.closure.}): bool =
  if handler.isNil:
    return false
  registry.registerSync(methodName, proc(params: JsonNode): RpcResult =
    try:
      rpcSuccess(handler(params.jsonTo(T)).toJson())
    except CatchableError:
      typedFailure()
  )

proc registerTypedAsync*[R](registry: RpcRegistry; methodName: string;
                            handler: proc(): Future[R] {.closure.}): bool =
  if handler.isNil:
    return false
  registry.register(methodName, proc(params: JsonNode): Future[RpcResult] =
    try:
      handler().encodeTypedFuture()
    except CatchableError:
      let failed = newFuture[RpcResult]("nimino.rpc.typedAsync")
      failed.complete(rpcFailure(rpcError(handlerFailed, "RPC handler raised an exception")))
      failed
  )

proc registerTypedAsync*[T, R](registry: RpcRegistry; methodName: string;
                               handler: proc(params: T): Future[R] {.closure.}): bool =
  if handler.isNil:
    return false
  registry.register(methodName, proc(params: JsonNode): Future[RpcResult] =
    try:
      handler(params.jsonTo(T)).encodeTypedFuture()
    except CatchableError:
      let failed = newFuture[RpcResult]("nimino.rpc.typedAsync")
      failed.complete(rpcFailure(rpcError(invalidRequest,
        "RPC parameters do not match the registered type")))
      failed
  )

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
      registry.pending.del(id)
      registry.emitError(id, rpcError(requestTimedOut, "RPC request timed out"))

proc invokeNotification(registry: RpcRegistry; methodName: string; params: JsonNode) =
  if registry.isNil or registry.closed or not registry.handlers.hasKey(methodName):
    return
  try:
    let future = registry.handlers[methodName](params)
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
  if not registry.handlers.hasKey(methodName):
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
    let future = registry.handlers[methodName](params)
    if future.isNil:
      registry.emitError(id, rpcError(handlerFailed, "RPC handler did not return a Future"))
      return
    registry.pending[id] = PendingRequest(
      future: future,
      deadlineMs: nowMs + timeout.value.getInt()
    )
    registry.tick(nowMs)
  except CatchableError:
    registry.emitError(id, rpcError(handlerFailed, "RPC handler raised an exception"))

proc handleCancel(registry: RpcRegistry; node: JsonNode) =
  let id = node.requestId()
  if not id.validRequestId() or not registry.pending.hasKey(id):
    return
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
  registry.closed = true
  registry.handlers.clear()
  registry.pending.clear()
  registry.sink = nil
