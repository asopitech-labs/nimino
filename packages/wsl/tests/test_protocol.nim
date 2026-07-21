import std/[json, streams, strutils]

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

block readyMustCreateANonEmptyTokenFreeSession:
  let ready = ProtocolMessage(version: ProtocolVersion, kind: ProtocolMessageKind.ready,
    sessionId: "0123456789abcdef0123456789abcdef",
    payload: nativeCapabilitiesPayload(["webPermissionEvents"]))
  doAssert ready.validateReady().isOk

  var reflected = ready
  reflected.authenticationToken = ValidToken
  let tokenResult = reflected.validateReady()
  doAssert not tokenResult.isOk
  doAssert tokenResult.failure.kind == authenticationFailed

  let missingSession = ProtocolMessage(version: ProtocolVersion,
    kind: ProtocolMessageKind.ready,
    payload: nativeCapabilitiesPayload([]))
  let sessionResult = missingSession.validateReady()
  doAssert not sessionResult.isOk
  doAssert sessionResult.failure.kind == authenticationFailed

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

block incompatibleVersionsAreRejectedInBothHandshakeDirections:
  for version in [ProtocolVersion - 1'u16, ProtocolVersion + 1'u16]:
    let versionResult = validateVersion(version)
    doAssert not versionResult.isOk
    doAssert versionResult.failure.kind == unsupportedVersion

    var staleHello = helloMessage()
    staleHello.version = version
    let hostResult = ValidToken.authenticateHello(staleHello)
    doAssert not hostResult.isOk
    doAssert hostResult.failure.kind == unsupportedVersion

    ## The Windows host receives framed JSON through HostInput.  `fromJson`
    ## must reject an incompatible hello before authentication or native setup.
    let decoded = staleHello.toJson.fromJson()
    doAssert not decoded.isOk
    doAssert decoded.failure.kind == unsupportedVersion

block readyCapabilitiesAreVersionedAndFailClosed:
  let valid = nativeCapabilitiesPayload(["multipleWebViews", "webPermissionEvents"])
  let decoded = valid.parseNativeCapabilities()
  doAssert decoded.isOk
  doAssert decoded.value == @["multipleWebViews", "webPermissionEvents"]

  let duplicate = parseNativeCapabilities("{\"capabilities\":[\"webPermissionEvents\",\"webPermissionEvents\"]}")
  doAssert not duplicate.isOk
  doAssert duplicate.failure.kind == invalidMessage

  let unknown = parseNativeCapabilities("{\"capabilities\":[\"arbitraryHostFeature\"]}")
  doAssert not unknown.isOk
  doAssert unknown.failure.kind == invalidMessage

  let missing = ProtocolMessage(version: ProtocolVersion, kind: ready,
    sessionId: "0123456789abcdef0123456789abcdef")
  let missingResult = missing.validateReady()
  doAssert not missingResult.isOk
  doAssert missingResult.failure.kind == invalidMessage

  let staleReady = ProtocolMessage(version: ProtocolVersion - 1'u16,
    kind: ready, sessionId: "0123456789abcdef0123456789abcdef",
    payload: nativeCapabilitiesPayload([]))
  let stale = staleReady.validateReady()
  doAssert not stale.isOk
  doAssert stale.failure.kind == unsupportedVersion

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

block incompleteRequestEnvelopesAreRejected:
  let validRequest = ProtocolMessage(
    version: ProtocolVersion,
    kind: request,
    sessionId: "session",
    authenticationToken: "",
    requestId: 18,
    eventId: 0,
    methodName: "native.window.create",
    payload: "{}",
    error: "",
    timeoutMs: 5_000
  ).toJson.parseJson

  for missingKey in ["kind", "sessionId", "authenticationToken"]:
    var incomplete = validRequest.copy()
    incomplete.delete(missingKey)
    let decoded = ($incomplete).fromJson()
    doAssert not decoded.isOk
    doAssert decoded.failure.kind == invalidMessage

block summariesNeverExposeTokens:
  var message = helloMessage()
  message.sessionId = "session-identifier"
  let summary = message.logSummary
  doAssert ValidToken notin summary
  doAssert message.sessionId notin summary
  doAssert "<redacted>" == ValidToken.redactedToken
  doAssert ValidToken.secureEquals(ValidToken)
  doAssert not ValidToken.secureEquals(repeat("cd", 32))

block policyResponsesMustMatchTheAuthenticatedRequest:
  let response = ProtocolMessage(version: ProtocolVersion,
    kind: ProtocolMessageKind.response, sessionId: "session", requestId: 7,
    payload: "{\"allow\":false}")
  doAssert "session".validatePolicyResponse(7, response).isOk

  var wrongRequest = response
  wrongRequest.requestId = 8
  doAssert not "session".validatePolicyResponse(7, wrongRequest).isOk

  var reflectedToken = response
  reflectedToken.authenticationToken = ValidToken
  let tokenResult = "session".validatePolicyResponse(7, reflectedToken)
  doAssert not tokenResult.isOk
  doAssert tokenResult.failure.kind == authenticationFailed

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
  let unsafe = request.policyRequestJson.replace("file.zip", "../file.zip")
  doAssert not unsafe.parsePolicyRequest().isOk
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
