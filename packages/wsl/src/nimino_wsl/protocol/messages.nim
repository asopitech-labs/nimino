import std/[json, strutils]

import ./[authentication, versioning]

type
  ProtocolErrorKind* = enum
    invalidFrame
    unexpectedEof
    frameTooLarge
    invalidMessage
    timedOut
    unsupportedVersion
    authenticationFailed

  ProtocolError* = object
    kind*: ProtocolErrorKind
    detail*: string

  ProtocolResult* = object
    case isOk*: bool
    of true:
      discard
    of false:
      failure*: ProtocolError

  ProtocolResultOf*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      failure*: ProtocolError

  ProtocolMessageKind* = enum
    hello
    ready
    request
    response
    event
    cancel
    heartbeat
    shutdown

  ProtocolMessage* = object
    version*: uint16
    kind*: ProtocolMessageKind
    sessionId*: string
    authenticationToken*: string
    requestId*: uint64
    eventId*: uint64
    methodName*: string
    payload*: string
    error*: string
    timeoutMs*: uint32

  ## Synchronous policy relay payloads.  These are embedded in a normal
  ## request/response pair so the Windows host can fail closed on timeout.
  PolicyKind* = enum
    permissionPolicy
    downloadPolicy
    navigationPolicy
    closePolicy

  PolicyRequest* = object
    kind*: PolicyKind
    windowId*: uint64
    webViewId*: uint64
    url*: string
    suggestedName*: string

  PolicyResponse* = object
    allow*: bool
    error*: string

proc `$`*(kind: PolicyKind): string =
  case kind
  of permissionPolicy: "permission"
  of downloadPolicy: "download"
  of navigationPolicy: "navigation"
  of closePolicy: "close"

proc policyRequestJson*(request: PolicyRequest): string =
  $(%*{
    "kind": $request.kind,
    "windowId": $request.windowId,
    "webViewId": $request.webViewId,
    "url": request.url,
    "suggestedName": request.suggestedName
  })

proc policyResponseJson*(response: PolicyResponse): string =
  $(%*{"allow": response.allow, "error": response.error})

proc protocolError*(kind: ProtocolErrorKind; detail: string): ProtocolError =
  ProtocolError(kind: kind, detail: detail)

proc success*(): ProtocolResult {.inline.} =
  ProtocolResult(isOk: true)

proc failure*(error: ProtocolError): ProtocolResult {.inline.} =
  ProtocolResult(isOk: false, failure: error)

proc successOf*[T](value: T): ProtocolResultOf[T] {.inline.} =
  ProtocolResultOf[T](isOk: true, value: value)

proc failureOf*[T](error: ProtocolError): ProtocolResultOf[T] {.inline.} =
  ProtocolResultOf[T](isOk: false, failure: error)

proc isKnownNativeCapability*(value: string): bool {.inline.} =
  ## Keep handshake capabilities closed over the native public API.  A newly
  ## introduced native capability therefore requires an explicit protocol
  ## update instead of becoming silently available to an older client.
  value in NativeCapabilityNames

proc nativeCapabilitiesPayload*(capabilities: openArray[string]): string =
  var values = newJArray()
  for capability in capabilities:
    values.add(%capability)
  $(%*{"capabilities": values})

proc parseNativeCapabilities*(payload: string): ProtocolResultOf[seq[string]] =
  try:
    let node = parseJson(payload)
    if node.kind != JObject or not node.hasKey("capabilities") or
        node["capabilities"].kind != JArray:
      return failureOf[seq[string]](protocolError(invalidMessage,
        "ready payload is missing capabilities"))
    var capabilities: seq[string]
    for item in node["capabilities"].items:
      if item.kind != JString or not item.getStr().isKnownNativeCapability or
          item.getStr() in capabilities:
        return failureOf[seq[string]](protocolError(invalidMessage,
          "ready payload contains an invalid capability"))
      capabilities.add(item.getStr())
    successOf(capabilities)
  except CatchableError:
    failureOf[seq[string]](protocolError(invalidMessage,
      "ready payload is malformed"))

proc parsePolicyRequest*(payload: string): ProtocolResultOf[PolicyRequest] =
  try:
    let node = parseJson(payload)
    if node.kind != JObject or not node.hasKey("kind") or
        node["kind"].kind != JString:
      return failureOf[PolicyRequest](protocolError(invalidMessage,
        "policy request is malformed"))
    let kind = case node["kind"].getStr()
      of "permission": permissionPolicy
      of "download": downloadPolicy
      of "navigation": navigationPolicy
      of "close": closePolicy
      else: return failureOf[PolicyRequest](protocolError(invalidMessage,
        "unknown policy kind"))
    let windowId = if node.hasKey("windowId") and node["windowId"].kind == JString:
        uint64(parseUInt(node["windowId"].getStr()))
      else: 0'u64
    let webViewId = if node.hasKey("webViewId") and node["webViewId"].kind == JString:
        uint64(parseUInt(node["webViewId"].getStr()))
      else: 0'u64
    let url = if node.hasKey("url") and node["url"].kind == JString:
        node["url"].getStr()
      else: ""
    if kind != closePolicy and (webViewId == 0 or not node.hasKey("url")):
      return failureOf[PolicyRequest](protocolError(invalidMessage,
        "policy request is missing webViewId or url"))
    let suggestedName = if node.hasKey("suggestedName") and
        node["suggestedName"].kind == JString: node["suggestedName"].getStr()
      else: ""
    if kind == downloadPolicy:
      if suggestedName.len > 255 or suggestedName.find({'/', '\\', '\r', '\n', '\x00'}) >= 0 or
          suggestedName in [".", ".."]:
        return failureOf[PolicyRequest](protocolError(invalidMessage,
          "download suggestedName is unsafe"))
    successOf(PolicyRequest(kind: kind,
      windowId: windowId, webViewId: webViewId,
      url: url, suggestedName: suggestedName))
  except CatchableError:
    failureOf[PolicyRequest](protocolError(invalidMessage,
      "malformed policy request"))

proc parsePolicyResponse*(payload: string): ProtocolResultOf[PolicyResponse] =
  try:
    let node = parseJson(payload)
    if node.kind != JObject or not node.hasKey("allow") or
        node["allow"].kind != JBool:
      return failureOf[PolicyResponse](protocolError(invalidMessage,
        "policy response must contain boolean allow"))
    let error = if node.hasKey("error") and node["error"].kind == JString:
      node["error"].getStr()
    else: ""
    successOf(PolicyResponse(allow: node["allow"].getBool(), error: error))
  except CatchableError:
    failureOf[PolicyResponse](protocolError(invalidMessage,
      "malformed policy response"))

proc `$`*(kind: ProtocolMessageKind): string =
  case kind
  of hello: "hello"
  of ready: "ready"
  of request: "request"
  of response: "response"
  of event: "event"
  of cancel: "cancel"
  of heartbeat: "heartbeat"
  of shutdown: "shutdown"

proc parseMessageKind(value: string): ProtocolResultOf[ProtocolMessageKind] =
  case value
  of "hello": successOf(hello)
  of "ready": successOf(ready)
  of "request": successOf(request)
  of "response": successOf(response)
  of "event": successOf(event)
  of "cancel": successOf(cancel)
  of "heartbeat": successOf(heartbeat)
  of "shutdown": successOf(shutdown)
  else: failureOf[ProtocolMessageKind](protocolError(invalidMessage, "unknown message kind"))

proc validateVersion*(version: uint16): ProtocolResult =
  if version == ProtocolVersion:
    success()
  else:
    failure(protocolError(unsupportedVersion, "unsupported protocol version"))

proc validateHello*(message: ProtocolMessage): ProtocolResult =
  if message.kind != hello:
    return failure(protocolError(invalidMessage, "expected hello message"))
  if not message.authenticationToken.isValidAuthenticationToken:
    return failure(protocolError(authenticationFailed, "invalid authentication token"))
  message.version.validateVersion

proc validateReady*(message: ProtocolMessage): ProtocolResult =
  ## `stdout` is the protocol channel.  A host must never reflect the
  ## authentication token into its ready frame, even if a caller later logs
  ## the decoded message.
  if message.kind != ready:
    return failure(protocolError(invalidMessage, "expected ready message"))
  let version = message.version.validateVersion
  if not version.isOk:
    return version
  if message.sessionId.len == 0:
    return failure(protocolError(authenticationFailed, "host session is unavailable"))
  if message.authenticationToken.len != 0:
    return failure(protocolError(authenticationFailed,
      "host returned authentication material"))
  let capabilities = message.payload.parseNativeCapabilities()
  if not capabilities.isOk:
    return failure(capabilities.failure)
  success()

proc toJson*(message: ProtocolMessage): string =
  var node = newJObject()
  node["version"] = %int(message.version)
  node["kind"] = %($message.kind)
  node["sessionId"] = %message.sessionId
  node["authenticationToken"] = %message.authenticationToken
  node["requestId"] = %($message.requestId)
  node["eventId"] = %($message.eventId)
  node["method"] = %message.methodName
  node["payload"] = %message.payload
  node["error"] = %message.error
  node["timeoutMs"] = %int(message.timeoutMs)
  $node

proc fromJson*(encoded: string): ProtocolResultOf[ProtocolMessage] =
  try:
    let node = parseJson(encoded)
    if node.kind != JObject:
      return failureOf[ProtocolMessage](protocolError(invalidMessage, "message must be an object"))

    let version = node["version"].getInt()
    let timeoutMs = node["timeoutMs"].getInt()
    if version < 0 or version > int(high(uint16)) or timeoutMs < 0 or
        timeoutMs > int(high(uint32)):
      return failureOf[ProtocolMessage](protocolError(invalidMessage, "numeric value out of range"))

    let kind = parseMessageKind(node["kind"].getStr())
    if not kind.isOk:
      return failureOf[ProtocolMessage](kind.failure)

    let message = ProtocolMessage(
      version: uint16(version),
      kind: kind.value,
      sessionId: node["sessionId"].getStr(),
      authenticationToken: node["authenticationToken"].getStr(),
      requestId: uint64(parseUInt(node["requestId"].getStr())),
      eventId: uint64(parseUInt(node["eventId"].getStr())),
      methodName: node["method"].getStr(),
      payload: node["payload"].getStr(),
      error: node["error"].getStr(),
      timeoutMs: uint32(timeoutMs)
    )

    if message.kind == hello:
      let helloResult = message.validateHello
      if not helloResult.isOk:
        return failureOf[ProtocolMessage](helloResult.failure)

    successOf(message)
  except CatchableError:
    failureOf[ProtocolMessage](protocolError(invalidMessage, "malformed protocol message"))

proc logSummary*(message: ProtocolMessage): string =
  ## Session and authentication material deliberately have no representation
  ## in a log line.  A session ID is not a bearer token today, but keeping it
  ## out of diagnostics prevents it becoming an accidental capability later.
  "kind=" & $message.kind & " session=<redacted>" &
    " request=" & $message.requestId & " event=" & $message.eventId &
    " method=" & message.methodName
