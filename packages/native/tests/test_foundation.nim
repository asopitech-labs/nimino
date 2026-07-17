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

block windowAndViewRemainSeparate:
  let app = newNativeApp()
  let window = app.newWindow("Foundation", 320, 200)
  doAssert window.isOk
  let view = window.value.newWebView()
  doAssert view.isOk
  doAssert view.value.loadUrl("about:blank").isOk
  doAssert view.value.loadHtml("<main>Foundation</main>").isOk
  doAssert window.value.setTitle("Foundation updated").isOk
  doAssert not window.value.newWebView().isOk
