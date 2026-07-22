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
  let clearedCache = adapter.handleRequest(requestMessage("native.window.clearCache",
    $(%*{"windowId": windowId})))
  doAssert not clearedCache.isOk
  doAssert "WebView2 engine cache clearing is unsupported" in clearedCache.failure.detail
  let clearedDownloads = adapter.handleRequest(requestMessage("native.window.clearDownloads",
    $(%*{"windowId": windowId})))
  doAssert clearedDownloads.isOk
  let webViewId = parseJson(view.value.payload)["webViewId"].getStr()

  let script = adapter.handleRequest(requestMessage("native.webview.setDocumentStartScript",
    $(%*{"webViewId": webViewId, "script": "globalThis.niminoTest = true;"})))
  doAssert script.isOk
  let devTools = adapter.handleRequest(requestMessage("native.webview.setDevToolsEnabled",
    $(%*{"webViewId": webViewId, "enabled": false})))
  doAssert devTools.isOk

  let loaded = adapter.handleRequest(requestMessage("native.webview.loadUrl",
    $(%*{"webViewId": webViewId, "url": "https://example.com"})))
  doAssert loaded.isOk
  doAssert loaded.value.kind == startUiLoop

  ## A user-initiated popup may be created after the first view starts.
  let popup = adapter.handleRequest(requestMessage("native.window.create",
    "{\"title\":\"Popup\",\"width\":400,\"height\":300,\"appId\":\"app.test\",\"profile\":\"popup\"}"))
  doAssert popup.isOk
  let popupId = parseJson(popup.value.payload)["windowId"].getStr()
  let popupView = adapter.handleRequest(requestMessage("native.webview.create",
    $(%*{"windowId": popupId})))
  doAssert popupView.isOk
  let popupViewId = parseJson(popupView.value.payload)["webViewId"].getStr()
  when not defined(niminoWsl):
    let closedPopupView = adapter.handleRequest(requestMessage("native.webview.close",
      $(%*{"webViewId": popupViewId})))
    doAssert closedPopupView.isOk

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

block activeProfileResetIsExplicitlyRefusedAndRestartIsRequestedSeparately:
  let adapter = newHostAdapter()
  let window = adapter.handleRequest(requestMessage("native.window.create",
    "{\"title\":\"Reset\",\"width\":320,\"height\":200,\"appId\":\"app.test\",\"profile\":\"default\"}"))
  doAssert window.isOk
  let windowId = parseJson(window.value.payload)["windowId"].getStr()
  let view = adapter.handleRequest(requestMessage("native.webview.create",
    $(%*{"windowId": windowId})))
  doAssert view.isOk
  let webViewId = parseJson(view.value.payload)["webViewId"].getStr()
  let started = adapter.handleRequest(requestMessage("native.webview.loadHtml",
    $(%*{"webViewId": webViewId, "html": "<main>reset</main>"})))
  doAssert started.isOk
  doAssert started.value.kind == startUiLoop

  let reset = adapter.handleRequest(requestMessage("native.window.resetProfile",
    $(%*{"windowId": windowId})))
  doAssert not reset.isOk
  doAssert "active WebView2 profile reset is unsupported" in reset.failure.detail

  let restart = adapter.handleRequest(requestMessage("app.restartForProfileReset", ""))
  doAssert restart.isOk
  doAssert restart.value.kind == restartHostForProfileReset
  let payload = parseJson(restart.value.payload)
  doAssert payload["restartRequired"].getBool
  doAssert payload["reason"].getStr == "profileReset"

block profileResetRestartCannotBeRequestedBeforeTheUiSession:
  let adapter = newHostAdapter()
  let restart = adapter.handleRequest(requestMessage("app.restartForProfileReset", ""))
  doAssert not restart.isOk
  doAssert "requires an active UI session" in restart.failure.detail

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

  let invalidKinds = adapter.handleRequest(requestMessage("native.webview.clearBrowsingData",
    $(%*{"webViewId": webViewId, "kinds": ["cookies", "cookies"]})))
  doAssert not invalidKinds.isOk
  doAssert "must not contain duplicates" in invalidKinds.failure.detail

  let cleared = adapter.handleRequest(requestMessage("native.webview.clearBrowsingData",
    $(%*{"webViewId": webViewId, "kinds": ["cookies", "cache"]})))
  doAssert cleared.isOk
  doAssert cleared.value.kind == deferredBrowsingDataClear
  ## This unit test runs on the Linux backend. The completed Future proves the
  ## relay preserves the native unsupported result for the host main to encode.
  doAssert cleared.value.browsingDataClear.finished
  let clearResult = cleared.value.browsingDataClear.read()
  doAssert not clearResult.isOk
  doAssert $clearResult.failure.kind == "unsupported"

  let queriedCookies = adapter.handleRequest(requestMessage(
    "native.webview.getCookies", $(%*{
      "webViewId": webViewId, "url": "https://example.com/"
    })))
  doAssert queriedCookies.isOk
  doAssert queriedCookies.value.kind == deferredCookieQuery
  doAssert queriedCookies.value.cookieQuery.finished
  doAssert not queriedCookies.value.cookieQuery.read().isOk

  let cookie = %*{
    "name": "sid", "value": "abc", "domain": "example.com", "path": "/",
    "secure": true, "httpOnly": true, "expires": 0
  }
  let setCookie = adapter.handleRequest(requestMessage(
    "native.webview.setCookie", $(%*{
      "webViewId": webViewId, "cookie": cookie
    })))
  doAssert setCookie.isOk
  doAssert setCookie.value.kind == deferredCookieMutation
  doAssert setCookie.value.cookieMutation.finished
  doAssert not setCookie.value.cookieMutation.read().isOk
  let deleteCookie = adapter.handleRequest(requestMessage(
    "native.webview.deleteCookie", $(%*{
      "webViewId": webViewId, "cookie": cookie
    })))
  doAssert deleteCookie.isOk
  doAssert deleteCookie.value.kind == deferredCookieMutation
  let malformedCookie = adapter.handleRequest(requestMessage(
    "native.webview.setCookie", $(%*{
      "webViewId": webViewId, "cookie": {"name": "sid"}
    })))
  doAssert not malformedCookie.isOk

  let evaluated = adapter.handleRequest(requestMessage("native.webview.evalJavaScript",
    $(%*{"webViewId": webViewId, "script": "document.title"})))
  doAssert evaluated.isOk
  doAssert evaluated.value.kind == deferredResponse
  doAssert not evaluated.value.evaluation.finished

  let navigated = adapter.handleRequest(requestMessage("native.webview.loadUrl",
    $(%*{"webViewId": webViewId, "url": "about:blank"})))
  doAssert navigated.isOk
  doAssert navigated.value.kind == noHostAction
