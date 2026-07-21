## `niminoWsl` must not pretend that the Windows host can supply a WebView2
## NavigateToString base URL. The ordinary HTML path remains available.
import nimino_native

let app = newNativeApp()
let window = app.newWindow("WSL HTML base URL", 320, 200)
doAssert window.isOk
let view = window.value.newWebView()
doAssert view.isOk

let based = view.value.loadHtml("<main>WSL</main>",
  baseUrl = "https://example.test/assets/")
doAssert not based.isOk
doAssert based.failure.kind == unsupported
doAssert based.failure.operation == "webview.loadHtml"

doAssert view.value.loadHtml("<main>WSL</main>").isOk
