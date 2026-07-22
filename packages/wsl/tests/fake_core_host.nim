## GUIなしでcore WSL adapterのevent経路を検証する一回限りのprotocol host。

import std/[json, os, streams, strutils]

import ../src/nimino_wsl/client/transport
import ../src/nimino_wsl/protocol/[authentication, messages, versioning]

const SessionId = "0123456789abcdef0123456789abcdef"

proc response(request: ProtocolMessage; payload = ""): ProtocolMessage =
  ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.response,
    sessionId: SessionId,
    requestId: request.requestId,
    payload: payload
  )

proc event(methodName, payload: string; eventId: uint64): ProtocolMessage =
  ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.event,
    sessionId: SessionId,
    eventId: eventId,
    methodName: methodName,
    payload: payload
  )

proc policyRequest(requestId: uint64; payload: string): ProtocolMessage =
  ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.request,
    sessionId: SessionId,
    requestId: requestId,
    methodName: "native.webview.policyRequested",
    payload: payload,
    timeoutMs: 5_000
  )

let token = getEnv("NIMINO_WSL_HOST_TOKEN")
if not token.isValidAuthenticationToken:
  quit(QuitFailure)

let input = newFileStream(stdin)
let output = newFileStream(stdout)
if input.isNil or output.isNil:
  quit(QuitFailure)

let structuredError = getEnv("NIMINO_TEST_STRUCTURED_ERROR") == "1"

let hello = input.readMessageFrom()
if not hello.isOk or not hello.value.validateHello().isOk or
    not token.secureEquals(hello.value.authenticationToken):
  quit(QuitFailure)
doAssert output.writeMessageTo(ProtocolMessage(
  version: ProtocolVersion,
  kind: ready,
  sessionId: SessionId,
  payload: nativeCapabilitiesPayload(["webPermissionEvents",
    WebViewProfileDataClearCapability])
)).isOk

var nextEventId = 1'u64
var customProtocolRegistered = false
var customProtocolResponseReceived = false
const CustomProtocolRequestId = 900'u64
while true:
  let incoming = input.readMessageFrom()
  if not incoming.isOk:
    quit(QuitFailure)
  let incomingMessage = incoming.value
  if incomingMessage.sessionId != SessionId:
    quit(QuitFailure)

  case incomingMessage.kind
  of shutdown:
    doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
    break
  of request:
    case incomingMessage.methodName
    of "app.capabilities":
      ## The fake host intentionally omits autostart.  Core must report a
      ## capability-checked unsupported result rather than writing startup
      ## files from WSL.
      doAssert output.writeMessageTo(incomingMessage.response(
        nativeCapabilitiesPayload(["webPermissionEvents"]))).isOk
    of "native.window.create":
      let payload = parseJson(incomingMessage.payload)
      doAssert payload["proxyUrl"].getStr() == "http://127.0.0.1:8080"
      doAssert payload["incognito"].getBool()
      doAssert payload["enableDragDrop"].getBool()
      doAssert payload["zoomFactor"].getFloat() == 1.25
      doAssert payload["ignoreCertificateErrors"].getBool()
      doAssert output.writeMessageTo(incomingMessage.response("{\"windowId\":\"1\"}")).isOk
    of "native.window.setSize", "native.window.setPosition",
       "native.window.show", "native.window.hide":
      doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
    of "native.webview.setZoom":
      doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
    of "native.webview.create":
      doAssert output.writeMessageTo(incomingMessage.response("{\"webViewId\":\"1\"}")).isOk
    of "native.webview.setDevToolsEnabled":
      doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
    of "app.registerCustomProtocol":
      let payload = parseJson(incomingMessage.payload)
      doAssert payload["scheme"].getStr() == "nimino"
      customProtocolRegistered = true
      doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
    of "native.window.setTitle":
      if structuredError:
        doAssert output.writeMessageTo(ProtocolMessage(
          version: ProtocolVersion,
          kind: ProtocolMessageKind.response,
          sessionId: SessionId,
          requestId: incomingMessage.requestId,
          error: "native.window.setTitle failed",
          errorKind: "osError",
          errorOperation: "window.setTitle",
          errorPlatformCode: 5,
          errorDetail: "SetWindowTextW failed"
        )).isOk
      else:
        doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
    of "native.webview.loadHtml", "native.webview.loadUrl":
      doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
      let dropped = $(%*{"windowId": "1", "paths": ["/tmp/dropped.txt"]})
      doAssert output.writeMessageTo(event("native.window.fileDrop", dropped,
        nextEventId)).isOk
      inc nextEventId
      let payload = $(%*{"webViewId": "1", "url": "https://example.test/", "succeeded": true})
      doAssert output.writeMessageTo(event("native.webview.navigationCompleted", payload, nextEventId)).isOk
      inc nextEventId
      if customProtocolRegistered:
        let customRequest = $(%*{
          "kind": "customProtocol",
          "windowId": "0",
          "webViewId": "0",
          "permissionKind": "",
          "url": "nimino://app/hello.txt",
          "method": "GET",
          "path": "/hello.txt"
        })
        doAssert output.writeMessageTo(policyRequest(CustomProtocolRequestId,
          customRequest)).isOk
      else:
        let wire = $(%*{
          "nimino": "rpc",
          "kind": "request",
          "id": "one",
          "method": "system.version",
          "params": newJNull(),
          "timeoutMs": 1_000
        })
        let messagePayload = $(%*{"webViewId": "1", "message": wire})
        doAssert output.writeMessageTo(event("native.webview.message", messagePayload,
          nextEventId)).isOk
        inc nextEventId
    of "native.webview.evalJavaScript":
      doAssert output.writeMessageTo(incomingMessage.response("{\"result\":\"null\"}")).isOk
      let script = parseJson(incomingMessage.payload)["script"].getStr()
      if script.contains("__niminoRpcV1"):
        let wire = $(%*{
          "nimino": "rpc",
          "kind": "request",
          "id": "one",
          "method": "system.version",
          "params": newJNull(),
          "timeoutMs": 1_000
        })
        let payload = $(%*{"webViewId": "1", "message": wire})
        doAssert output.writeMessageTo(event("native.webview.message", payload, nextEventId)).isOk
        inc nextEventId
      else:
        if not customProtocolRegistered or customProtocolResponseReceived:
          doAssert output.writeMessageTo(event("app.closed", "{}", nextEventId)).isOk
          break
    of "app.shutdown":
      doAssert output.writeMessageTo(incomingMessage.response("{}")).isOk
      break
    else:
      quit(QuitFailure)
  of response:
    if incomingMessage.requestId == CustomProtocolRequestId:
      doAssert incomingMessage.error.len == 0
      let customResponse = incomingMessage.payload.parsePolicyResponse()
      doAssert customResponse.isOk
      doAssert customResponse.value.allow
      doAssert customResponse.value.statusCode == 201
      doAssert customResponse.value.mimeType == "text/plain; charset=utf-8"
      doAssert customResponse.value.body == "hello from WSL core"
      customProtocolResponseReceived = true
      let wire = $(%*{
        "nimino": "rpc",
        "kind": "request",
        "id": "one",
        "method": "system.version",
        "params": newJNull(),
        "timeoutMs": 1_000
      })
      let messagePayload = $(%*{"webViewId": "1", "message": wire})
      doAssert output.writeMessageTo(event("native.webview.message", messagePayload,
        nextEventId)).isOk
      inc nextEventId
    else:
      ## The Core RPC handler has answered the synthetic request.  End the
      ## harness run deterministically instead of waiting for a real WebView.
      doAssert output.writeMessageTo(event("app.closed", "{}", nextEventId)).isOk
      break
  else:
    quit(QuitFailure)
