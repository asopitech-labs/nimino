import std/asyncfutures

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
  doAssert not app.supports(multipleWebViews)

block systemTrayIsExplicitlyUnsupportedOffWindows:
  let app = newNativeApp()
  let configured = app.configureSystemTray([
    NativeMenuItem(id: 1, title: "Quit", enabled: true)
  ], proc(itemId: uint32) = discard)
  when defined(windows):
    doAssert configured.isOk
  else:
    doAssert not configured.isOk
    doAssert configured.failure.kind == unsupported

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
  doAssert view.value.onNewWindowRequested(proc(url: string) = discard).isOk
  doAssert view.value.onNavigationStarting(proc(url: string): bool = true).isOk
  doAssert view.value.onNavigationCompleted(proc(url: string; succeeded: bool) = discard).isOk
  doAssert window.value.onCloseRequested(proc(): bool = true).isOk
  doAssert window.value.onClosed(proc() = discard).isOk
  doAssert not window.value.newWebView().isOk

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
  when defined(linux) and not defined(niminoWsl):
    doAssert result.failure.kind == invalidState
  else:
    doAssert result.failure.kind == unsupported
