## Compile-only contract target.  It is built as a Windows PE binary from the
## Docker development image and is never executed in the Linux test container.
import nimino_native

let app = newNativeApp()
let window = app.newWindow(title = "Nimino Windows M1", width = 800, height = 600)
doAssert window.isOk

let view = window.value.newWebView()
doAssert view.isOk
doAssert view.value.onMessage(proc(message: string) = discard).isOk
doAssert view.value.onError(proc(error: NativeError) = discard).isOk
doAssert view.value.onNavigationStarting(proc(url: string): bool = true).isOk
doAssert view.value.onNavigationCompleted(proc(url: string; succeeded: bool) = discard).isOk
doAssert view.value.loadHtml("<main>Nimino Windows M1</main>").isOk
discard view.value.evalJavaScript("document.title")
