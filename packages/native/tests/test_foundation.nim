import std/[asyncfutures, strutils]

import nimino_native

block nativeResultSuccess:
  let result = success()
  doAssert result.isOk

block nativeResultFailure:
  let expected = nativeError(unsupported, "window.create", 17, "not available")
  let result = failure(expected)
  doAssert not result.isOk
  doAssert result.failure.kind == unsupported
  doAssert result.failure.operation == "window.create"
  doAssert result.failure.platformCode == 17

block nativeResultOfSuccess:
  let result = successOf("Nimino")
  doAssert result.isOk
  doAssert result.value == "Nimino"

block nativeResultOfFailure:
  let expected = nativeError(webViewError, "webview.navigate")
  let result = failureOf[string](expected)
  doAssert not result.isOk
  doAssert result.failure.kind == webViewError

block capabilitiesAreExplicit:
  let available: CapabilitySet = {multipleWebViews}
  doAssert available.supports(multipleWebViews)
  doAssert not available.supports(systemTray)
  let app = newNativeApp()
  doAssert app.supports(webPermissionEvents)
  when defined(windows) or (defined(linux) and not defined(niminoWsl)) or defined(macosx):
    doAssert app.supports(multipleWebViews)
  else:
    doAssert not app.supports(multipleWebViews)

block systemTrayIsExplicitlyUnsupportedOffWindows:
  let app = newNativeApp()
  let configured = app.configureSystemTray([
    NativeMenuItem(id: 1, title: "Quit", enabled: true)
  ], proc(itemId: uint32) = discard)
  when defined(windows):
    doAssert configured.isOk
  elif defined(linux) and not defined(niminoWsl):
    if app.supports(systemTray):
      doAssert configured.isOk
      doAssert app.systemTraySupportDetail().contains("StatusNotifierItem")
    else:
      doAssert not configured.isOk
      doAssert configured.failure.kind == unsupported
      doAssert configured.failure.detail == app.systemTraySupportDetail()
      doAssert configured.failure.detail.len > 0
      let detail = configured.failure.detail.toLowerAscii()
      doAssert detail.contains("bus") or detail.contains("backend") or
        detail.contains("watcher")
  elif defined(macosx):
    doAssert app.supports(systemTray)
    doAssert configured.isOk
    doAssert app.systemTraySupportDetail().contains("NSStatusItem")
  else:
    doAssert not configured.isOk
    doAssert configured.failure.kind == unsupported

block nativeDesktopIntegrationCapabilitiesAndStatesAreExplicit:
  let app = newNativeApp()
  let identityApp = newNativeApp(NativeAppOptions(appId: "app.nimino.foundation"))
  doAssert not identityApp.isNil
  let items = [NativeMenuItem(id: 1, title: "Quit", enabled: true)]
  when defined(linux) and not defined(niminoWsl):
    doAssert app.supports(nativeMenu)
    doAssert app.supports(nativeNotification)
    doAssert app.configureNativeMenu("Nimino", items,
      proc(itemId: uint32) = discard).isOk
    let invalidNotification = app.sendNativeNotification(NativeNotification(
      id: "", title: "Nimino", body: "invalid"))
    doAssert not invalidNotification.isOk
    doAssert invalidNotification.failure.kind == invalidArgument
    let beforeRun = app.sendNativeNotification(NativeNotification(
      id: "foundation", title: "Nimino", body: "not running"))
    doAssert not beforeRun.isOk
    doAssert beforeRun.failure.kind == invalidState
  elif defined(windows):
    doAssert app.supports(nativeMenu)
    doAssert app.supports(nativeNotification)
    doAssert app.configureNativeMenu("Nimino", items,
      proc(itemId: uint32) = discard).isOk
    doAssert app.onNotificationActivated(proc(notificationId: string) = discard).isOk
    let notification = app.sendNativeNotification(NativeNotification(
      id: "foundation", title: "Nimino", body: "not running"))
    doAssert not notification.isOk
    doAssert notification.failure.kind == invalidState
  elif defined(macosx):
    doAssert app.supports(nativeMenu)
    doAssert app.supports(nativeNotification)
    doAssert app.configureNativeMenu("Nimino", items,
      proc(itemId: uint32) = discard).isOk
    let notification = app.sendNativeNotification(NativeNotification(
      id: "foundation", title: "Nimino", body: "not running"))
    doAssert not notification.isOk
    doAssert notification.failure.kind == invalidState
  else:
    doAssert not app.supports(nativeMenu)
    doAssert not app.supports(nativeNotification)
    let menu = app.configureNativeMenu("Nimino", items,
      proc(itemId: uint32) = discard)
    doAssert not menu.isOk
    doAssert menu.failure.kind == unsupported
    let notification = app.sendNativeNotification(NativeNotification(
      id: "foundation", title: "Nimino", body: "unsupported"))
    doAssert not notification.isOk
    doAssert notification.failure.kind == unsupported

block windowAndViewRemainSeparate:
  let app = newNativeApp()
  let window = app.newWindow("Foundation", 320, 200)
  doAssert window.isOk
  let view = window.value.newWebView()
  doAssert view.isOk
  var notified = false
  doAssert view.value.onError(proc(error: NativeError) =
    notified = true
    doAssert error.kind == webViewError
    doAssert error.operation == "webview.loadUrl"
  ).isOk
  doAssert not view.value.loadUrl("").isOk
  doAssert not view.value.loadUrl("https://example.com/has space").isOk
  doAssert notified
  doAssert view.value.loadUrl("about:blank").isOk
  let emptyScript = view.value.evalJavaScript("")
  doAssert emptyScript.finished
  doAssert not emptyScript.read().isOk
  doAssert view.value.loadHtml("<main>Foundation</main>").isOk
  doAssert window.value.setTitle("Foundation updated").isOk
  doAssert view.value.onNewWindowRequested(proc(url: string): bool = true).isOk
  doAssert view.value.onNavigationStarting(proc(url: string): bool = true).isOk
  doAssert view.value.onNavigationCompleted(proc(url: string; succeeded: bool) = discard).isOk
  doAssert window.value.onCloseRequested(proc(): bool = true).isOk
  doAssert window.value.onClosed(proc() = discard).isOk
  when defined(windows) or (defined(linux) and not defined(niminoWsl)) or defined(macosx):
    let secondView = window.value.newWebView()
    doAssert secondView.isOk
    doAssert secondView.value.close().isOk
    doAssert secondView.value.isClosed()
  else:
    doAssert not window.value.newWebView().isOk

block lifecycleStateQueriesAreExplicit:
  let app = newNativeApp()
  let window = app.newWindow("Lifecycle", 320, 200)
  doAssert window.isOk
  doAssert not window.value.isReady()
  doAssert not window.value.isClosed()
  let view = window.value.newWebView()
  doAssert view.isOk
  doAssert not view.value.isReady()
  doAssert not view.value.isClosed()

block webViewSessionOptionsAreCapturedBeforeRun:
  let app = newNativeApp()
  let window = app.newWindow("Session options", 320, 200)
  doAssert window.isOk
  let view = window.value.newWebView(userAgent = "NiminoTest/1.0",
    proxyUrl = "http://proxy.example:8080", incognito = true)
  doAssert view.isOk
  doAssert view.value.setUserAgent("NiminoTest/2.0").isOk
  doAssert view.value.setProxy("http://proxy.example:8081").isOk
  doAssert view.value.setIncognito(false).isOk

block nativeWindowControlCapabilitiesAreExplicit:
  let app = newNativeApp()
  let window = app.newWindow("Window controls", 320, 200)
  doAssert window.isOk
  when defined(windows):
    doAssert window.value.supports(maximize)
    doAssert window.value.supports(fullscreen)
    doAssert window.value.supports(alwaysOnTop)
  elif defined(linux) and not defined(niminoWsl):
    doAssert window.value.supports(maximize)
    doAssert window.value.supports(fullscreen)
    doAssert not window.value.supports(alwaysOnTop)
    let topmost = window.value.setAlwaysOnTop(true)
    doAssert not topmost.isOk
    doAssert topmost.failure.kind == unsupported
  elif defined(macosx):
    doAssert window.value.supports(maximize)
    doAssert window.value.supports(fullscreen)
    doAssert window.value.supports(alwaysOnTop)
  else:
    doAssert not window.value.supports(maximize)
    doAssert not window.value.supports(fullscreen)
    doAssert not window.value.supports(alwaysOnTop)

block uiDispatchContractIsExplicit:
  let app = newNativeApp()
  doAssert not app.postToUi(nil).isOk
  when defined(niminoWsl):
    doAssert not app.postToUi(proc() = discard).isOk
  else:
    doAssert app.postToUi(proc() = discard).isOk

block htmlBaseUrlIsValidatedBeforeNativeCreation:
  let app = newNativeApp()
  let window = app.newWindow("HTML base URL", 320, 200)
  doAssert window.isOk
  let view = window.value.newWebView()
  doAssert view.isOk
  var malformedBaseNotified = false
  doAssert view.value.onError(proc(error: NativeError) =
    malformedBaseNotified = true
    doAssert error.kind == invalidArgument
    doAssert error.operation == "webview.loadHtml"
  ).isOk
  let malformedBase = view.value.loadHtml("<main>Foundation</main>",
    baseUrl = "https://example.test/assets/\n")
  doAssert not malformedBase.isOk
  doAssert malformedBase.failure.kind == invalidArgument
  doAssert malformedBaseNotified
  when defined(linux) and not defined(niminoWsl):
    doAssert view.value.loadHtml("<main>Foundation</main>",
      baseUrl = "https://example.test/assets/").isOk
  elif defined(macosx):
    doAssert view.value.loadHtml("<main>Foundation</main>",
      baseUrl = "https://example.test/assets/").isOk
  else:
    let based = view.value.loadHtml("<main>Foundation</main>",
      baseUrl = "https://example.test/assets/")
    doAssert not based.isOk
    doAssert based.failure.kind == unsupported

block documentStartScriptIsConfiguredBeforeNativeCreation:
  let app = newNativeApp()
  let window = app.newWindow("Document start", 320, 200)
  doAssert window.isOk
  let view = window.value.newWebView()
  doAssert view.isOk
  doAssert view.value.setDocumentStartScript("globalThis.niminoDocumentStart = true;").isOk
  doAssert view.value.setDocumentStartScript("globalThis.niminoDocumentStart = 'updated';").isOk

block javascriptEvaluationRejectsInvalidView:
  let view = NativeWebView(nil)
  let evaluation = view.evalJavaScript("document.title")
  doAssert evaluation.finished
  let result = evaluation.read()
  doAssert not result.isOk
  doAssert result.failure.kind == invalidState

block liveBrowserDataClearingRequiresAReadyNativeWebView:
  let app = newNativeApp()
  let window = app.newWindow("Browser data", 320, 200)
  doAssert window.isOk
  let view = window.value.newWebView()
  doAssert view.isOk
  let cleared = view.value.clearBrowsingData({nativeBrowsingCookies})
  doAssert cleared.finished
  let result = cleared.read()
  doAssert not result.isOk
  when defined(linux) and not defined(niminoWsl) or defined(macosx):
    doAssert result.failure.kind == invalidState
  else:
    doAssert result.failure.kind == unsupported
