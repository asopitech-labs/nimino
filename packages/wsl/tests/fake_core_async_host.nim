## GUIなしでWSL coreの非同期RPC期限切れを検証する一回限りのprotocol host。

import std/[json, os, streams, strutils]

import ../src/nimino_wsl/client/transport
import ../src/nimino_wsl/protocol/[authentication, messages, versioning]

const SessionId = "fedcba9876543210fedcba9876543210"

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

let token = getEnv("NIMINO_WSL_HOST_TOKEN")
if not token.isValidAuthenticationToken:
  quit(QuitFailure)

let input = newFileStream(stdin)
let output = newFileStream(stdout)
if input.isNil or output.isNil:
  quit(QuitFailure)

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
var rpcRequestsSent = false
var asyncReplySeen = false
while true:
  let incoming = input.readMessageFrom()
  if not incoming.isOk:
    quit(QuitFailure)
  let message = incoming.value
  if message.sessionId != SessionId:
    quit(QuitFailure)

  case message.kind
  of shutdown:
    doAssert output.writeMessageTo(message.response("{}")).isOk
    break
  of request:
    case message.methodName
    of "native.window.create":
      doAssert output.writeMessageTo(message.response("{\"windowId\":\"1\"}")).isOk
    of "native.webview.create":
      doAssert output.writeMessageTo(message.response("{\"webViewId\":\"1\"}")).isOk
    of "native.webview.setDevToolsEnabled":
      doAssert output.writeMessageTo(message.response("{}")).isOk
    of "native.webview.loadHtml":
      doAssert output.writeMessageTo(message.response("{}")).isOk
      let payload = $(%*{"webViewId": "1", "url": "https://example.test/", "succeeded": true})
      doAssert output.writeMessageTo(event("native.webview.navigationCompleted", payload, nextEventId)).isOk
      inc nextEventId
      ## Headless harness: emulate the document-start bridge without a real
      ## WebView, so the async RPC/timeout contract can run deterministically.
      rpcRequestsSent = true
      let asyncRequest = $(%*{
        "nimino": "rpc", "kind": "request", "id": "async-one",
        "method": "async.request", "params": newJNull(), "timeoutMs": 1_000
      })
      let completed = $(%*{
        "nimino": "rpc", "kind": "notification", "method": "async.complete",
        "params": newJNull()
      })
      let never = $(%*{
        "nimino": "rpc", "kind": "request", "id": "timeout-one",
        "method": "never", "params": newJNull(), "timeoutMs": 40
      })
      let delayedClose = $(%*{
        "nimino": "rpc", "kind": "request", "id": "close-one",
        "method": "close.delayed", "params": newJNull(), "timeoutMs": 1_000
      })
      for wire in [asyncRequest, completed, never, delayedClose]:
        let messagePayload = $(%*{"webViewId": "1", "message": wire})
        doAssert output.writeMessageTo(event("native.webview.message", messagePayload,
          nextEventId)).isOk
        inc nextEventId
    of "native.webview.evalJavaScript":
      doAssert output.writeMessageTo(message.response("{\"result\":\"null\"}")).isOk
      let script = parseJson(message.payload)["script"].getStr()
      if script.contains("__niminoRpcV1") and not rpcRequestsSent:
        rpcRequestsSent = true
        let asyncRequest = $(%*{
          "nimino": "rpc", "kind": "request", "id": "async-one",
          "method": "async.request", "params": newJNull(), "timeoutMs": 1_000
        })
        let completed = $(%*{
          "nimino": "rpc", "kind": "notification", "method": "async.complete",
          "params": newJNull()
        })
        let never = $(%*{
          "nimino": "rpc", "kind": "request", "id": "timeout-one",
          "method": "never", "params": newJNull(), "timeoutMs": 40
        })
        let delayedClose = $(%*{
          "nimino": "rpc", "kind": "request", "id": "close-one",
          "method": "close.delayed", "params": newJNull(), "timeoutMs": 1_000
        })
        for wire in [asyncRequest, completed, never, delayedClose]:
          let payload = $(%*{"webViewId": "1", "message": wire})
          doAssert output.writeMessageTo(event("native.webview.message", payload, nextEventId)).isOk
          inc nextEventId
      elif script.contains("async-one"):
        asyncReplySeen = true
      elif script.contains("timeout-one"):
        doAssert asyncReplySeen
        doAssert output.writeMessageTo(event("native.window.resized",
          "{\"windowId\":\"1\",\"width\":640,\"height\":480}", nextEventId)).isOk
        inc nextEventId
        ## Model the Windows host's native close callback while a registered
        ## Nim handler still owns a delayed Future. The next `app.closed`
        ## event gives the client a deterministic shutdown without WebView2.
        doAssert output.writeMessageTo(event("native.window.closed",
          "{\"windowId\":\"1\"}", nextEventId)).isOk
        inc nextEventId
        doAssert output.writeMessageTo(event("app.closed", "{}", nextEventId)).isOk
        inc nextEventId
      elif script.contains("close-one"):
        ## A closed Window must not evaluate a cancellation or late-success
        ## response into a WebView that the host has already destroyed.
        quit(QuitFailure)
    of "native.webview.clearBrowsingData":
      let payload = parseJson(message.payload)
      doAssert payload["webViewId"].getStr() == "1"
      doAssert payload["kinds"].kind == JArray
      if payload["kinds"].len == 2:
        doAssert payload["kinds"][0].getStr() == "cookies"
        doAssert payload["kinds"][1].getStr() == "cache"
        doAssert output.writeMessageTo(message.response("{\"ok\":true}")).isOk
      else:
        doAssert payload["kinds"].len == 1
        doAssert payload["kinds"][0].getStr() == "localStorage"
        doAssert output.writeMessageTo(message.response(
          "{\"ok\":false,\"kind\":\"unsupported\",\"operation\":\"webview.clearBrowsingData\",\"platformCode\":0,\"detail\":\"Profile2 unavailable\"}")).isOk
    else:
      quit(QuitFailure)
  else:
    quit(QuitFailure)
