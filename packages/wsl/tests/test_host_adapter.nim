import std/[asyncfutures, json, os, strutils]

import nimino_wsl

proc requestMessage(methodName, payload: string): ProtocolMessage =
  ProtocolMessage(
    version: ProtocolVersion,
    kind: request,
    sessionId: "session",
    requestId: 1,
    methodName: methodName,
    payload: payload
  )

putEnv("LOCALAPPDATA", getTempDir() / "nimino-host-adapter")

block createsWindowViewAndUrlBeforeStartingUi:
  let adapter = newHostAdapter()
  let window = adapter.handleRequest(requestMessage("native.window.create",
    "{\"title\":\"WSL\",\"width\":800,\"height\":600,\"appId\":\"app.test\",\"profile\":\"default\"}"))
  doAssert window.isOk
  let windowId = parseJson(window.value.payload)["windowId"].getStr()

  let view = adapter.handleRequest(requestMessage("native.webview.create",
    $(%*{"windowId": windowId})))
  doAssert view.isOk
  let webViewId = parseJson(view.value.payload)["webViewId"].getStr()

  let script = adapter.handleRequest(requestMessage("native.webview.setDocumentStartScript",
    $(%*{"webViewId": webViewId, "script": "globalThis.niminoTest = true;"})))
  doAssert script.isOk

  let loaded = adapter.handleRequest(requestMessage("native.webview.loadUrl",
    $(%*{"webViewId": webViewId, "url": "https://example.com"})))
  doAssert loaded.isOk
  doAssert loaded.value.kind == startUiLoop

block navigationRulesAreEvaluatedOnHostWithoutIpcWait:
  let adapter = newHostAdapter()
  let window = adapter.handleRequest(requestMessage("native.window.create",
    "{\"title\":\"Policy\",\"width\":800,\"height\":600,\"appId\":\"app.test\",\"profile\":\"default\"}"))
  doAssert window.isOk
  let windowId = parseJson(window.value.payload)["windowId"].getStr()
  let view = adapter.handleRequest(requestMessage("native.webview.create",
    $(%*{"windowId": windowId})))
  doAssert view.isOk
  let webViewId = parseJson(view.value.payload)["webViewId"].getStr()
  let configured = adapter.handleRequest(requestMessage("native.webview.setNavigationRules",
    $(%*{"webViewId": webViewId, "allow": ["https://example.com/**"],
      "deny": ["https://example.com/private/**"]})))
  doAssert configured.isOk
  doAssert adapter.navigationDecision(uint64(parseUInt(webViewId)),
    "https://example.com/docs/start")
  doAssert not adapter.navigationDecision(uint64(parseUInt(webViewId)),
    "https://example.com/private/token")
  doAssert not adapter.navigationDecision(uint64(parseUInt(webViewId)),
    "https://other.example/")
  let invalid = adapter.handleRequest(requestMessage("native.webview.setNavigationRules",
    $(%*{"webViewId": webViewId, "allow": [""], "deny": []})))
  doAssert not invalid.isOk

block rejectsUnknownObjectsAndLateMutation:
  let adapter = newHostAdapter()
  let unknown = adapter.handleRequest(requestMessage("native.webview.create", "{\"windowId\":\"42\"}"))
  doAssert not unknown.isOk

  let denied = adapter.handleRequest(requestMessage("forbidden", "{}"))
  doAssert not denied.isOk

block updatesWindowTitleAndSize:
  let adapter = newHostAdapter()
  let window = adapter.handleRequest(requestMessage("native.window.create",
    "{\"title\":\"Initial\",\"width\":320,\"height\":200,\"appId\":\"app.test\",\"profile\":\"default\"}"))
  doAssert window.isOk
  let windowId = parseJson(window.value.payload)["windowId"].getStr()

  let title = adapter.handleRequest(requestMessage("native.window.setTitle",
    $(%*{"windowId": windowId, "title": "Updated"})))
  doAssert title.isOk

  let size = adapter.handleRequest(requestMessage("native.window.setSize",
    $(%*{"windowId": windowId, "width": 640, "height": 480})))
  doAssert size.isOk

block shutdownDoesNotNeedPayload:
  let adapter = newHostAdapter()
  let stopped = adapter.handleRequest(requestMessage("app.shutdown", ""))
  doAssert stopped.isOk
  doAssert stopped.value.kind == shutdownHost

block htmlLoadStartsTheUiLoop:
  let adapter = newHostAdapter()
  let window = adapter.handleRequest(requestMessage("native.window.create",
    "{\"title\":\"HTML\",\"width\":320,\"height\":200,\"appId\":\"app.test\",\"profile\":\"default\"}"))
  doAssert window.isOk
  let windowId = parseJson(window.value.payload)["windowId"].getStr()
  let view = adapter.handleRequest(requestMessage("native.webview.create",
    $(%*{"windowId": windowId})))
  doAssert view.isOk
  let webViewId = parseJson(view.value.payload)["webViewId"].getStr()
  let loaded = adapter.handleRequest(requestMessage("native.webview.loadHtml",
    $(%*{"webViewId": webViewId, "html": "<main>HTML</main>"})))
  doAssert loaded.isOk
  doAssert loaded.value.kind == startUiLoop

  let evaluated = adapter.handleRequest(requestMessage("native.webview.evalJavaScript",
    $(%*{"webViewId": webViewId, "script": "document.title"})))
  doAssert evaluated.isOk
  doAssert evaluated.value.kind == deferredResponse
  doAssert not evaluated.value.evaluation.finished

  let navigated = adapter.handleRequest(requestMessage("native.webview.loadUrl",
    $(%*{"webViewId": webViewId, "url": "about:blank"})))
  doAssert navigated.isOk
  doAssert navigated.value.kind == noHostAction
