import std/[json, strutils]

import ./[authentication, versioning]

type
  ProtocolErrorKind* = enum
    invalidFrame
    unexpectedEof
    frameTooLarge
    invalidMessage
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
  ## Authentication material deliberately has no representation in a log line.
  "kind=" & $message.kind & " session=" & message.sessionId &
    " request=" & $message.requestId & " event=" & $message.eventId &
    " method=" & message.methodName
