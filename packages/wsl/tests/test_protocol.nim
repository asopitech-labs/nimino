import std/[streams, strutils]

import nimino_wsl

const ValidToken = repeat("ab", 32)

proc helloMessage(): ProtocolMessage =
  ProtocolMessage(
    version: ProtocolVersion,
    kind: hello,
    sessionId: "",
    authenticationToken: ValidToken,
    requestId: 1,
    eventId: 0,
    methodName: "",
    payload: "",
    error: "",
    timeoutMs: 1_000
  )

block validHello:
  let result = helloMessage().validateHello
  doAssert result.isOk

block hostAuthenticationRequiresTheExpectedToken:
  let authenticated = ValidToken.authenticateHello(helloMessage())
  doAssert authenticated.isOk
  let wrongToken = repeat("cd", 32).authenticateHello(helloMessage())
  doAssert not wrongToken.isOk
  doAssert wrongToken.failure.kind == authenticationFailed

  let session = validateSessionMessage("session", ProtocolMessage(
    version: ProtocolVersion,
    kind: request,
    sessionId: "session",
    methodName: "native.window.create"
  ))
  doAssert session.isOk

block invalidTokenIsRejected:
  var message = helloMessage()
  message.authenticationToken = "not-a-token"
  let result = message.validateHello
  doAssert not result.isOk
  doAssert result.failure.kind == authenticationFailed

block unsupportedVersionIsRejected:
  let result = validateVersion(ProtocolVersion + 1'u16)
  doAssert not result.isOk
  doAssert result.failure.kind == unsupportedVersion

block messageFrameRoundTrip:
  var message = helloMessage()
  message.payload = "{\"url\":\"https://example.com\"}"
  let encoded = message.encodeMessageFrame
  doAssert encoded.isOk
  let decoded = encoded.value.decodeMessageFrame
  doAssert decoded.isOk
  doAssert decoded.value.kind == hello
  doAssert decoded.value.authenticationToken == ValidToken
  doAssert decoded.value.payload == message.payload

block malformedAndOversizedFramesAreRejected:
  let incomplete = decodeFrame([byte(0), byte(0), byte(0), byte(4), byte(1)])
  doAssert not incomplete.isOk
  doAssert incomplete.failure.kind == invalidFrame

  let tooLarge = encodeFrame(newString(MaxFrameBytes + 1))
  doAssert not tooLarge.isOk
  doAssert tooLarge.failure.kind == frameTooLarge

block summariesNeverExposeTokens:
  let summary = helloMessage().logSummary
  doAssert ValidToken notin summary
  doAssert "<redacted>" == ValidToken.redactedToken
  doAssert ValidToken.secureEquals(ValidToken)
  doAssert not ValidToken.secureEquals(repeat("cd", 32))

block streamTransportRoundTrip:
  let stream = newStringStream()
  let written = stream.writeMessageTo(helloMessage())
  doAssert written.isOk
  stream.setPosition(0)
  let read = stream.readMessageFrom()
  doAssert read.isOk
  doAssert read.value.kind == hello
  doAssert read.value.authenticationToken == ValidToken

block policyPayloadRoundTrip:
  let request = PolicyRequest(kind: downloadPolicy, webViewId: 42,
    url: "https://example.com/file.zip", suggestedName: "file.zip")
  let decodedRequest = request.policyRequestJson.parsePolicyRequest()
  doAssert decodedRequest.isOk
  doAssert decodedRequest.value.kind == downloadPolicy
  doAssert decodedRequest.value.webViewId == 42
  doAssert decodedRequest.value.suggestedName == "file.zip"
  let closeRequest = PolicyRequest(kind: closePolicy, windowId: 7)
  let decodedClose = closeRequest.policyRequestJson.parsePolicyRequest()
  doAssert decodedClose.isOk
  doAssert decodedClose.value.kind == closePolicy
  doAssert decodedClose.value.windowId == 7

  let decodedResponse = policyResponseJson(PolicyResponse(allow: true)).parsePolicyResponse()
  doAssert decodedResponse.isOk
  doAssert decodedResponse.value.allow
  let malformedResponse = parsePolicyResponse("{\"allow\":\"yes\"}")
  doAssert not malformedResponse.isOk

block truncatedStreamIsRejected:
  let stream = newStringStream("\0\0")
  let read = stream.readFrameFrom()
  doAssert not read.isOk
  doAssert read.failure.kind == unexpectedEof
