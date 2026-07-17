import std/strutils

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
