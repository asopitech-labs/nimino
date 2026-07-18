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
  sessionId: SessionId
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
    of "native.webview.loadHtml":
      doAssert output.writeMessageTo(message.response("{}")).isOk
      let payload = $(%*{"webViewId": "1", "url": "https://example.test/", "succeeded": true})
      doAssert output.writeMessageTo(event("native.webview.navigationCompleted", payload, nextEventId)).isOk
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
        for wire in [asyncRequest, completed, never]:
          let payload = $(%*{"webViewId": "1", "message": wire})
          doAssert output.writeMessageTo(event("native.webview.message", payload, nextEventId)).isOk
          inc nextEventId
      elif script.contains("async-one"):
        asyncReplySeen = true
      elif script.contains("timeout-one"):
        doAssert asyncReplySeen
        doAssert output.writeMessageTo(event("app.closed", "{}", nextEventId)).isOk
        inc nextEventId
    else:
      quit(QuitFailure)
  else:
    quit(QuitFailure)
