## Compile-only contract target.  It is built as a Windows PE binary from the
## Docker development image and is never executed in the Linux test container.
import nimino_native

let app = newNativeApp()
let window = app.newWindow(title = "Nimino Windows M1", width = 800, height = 600)
doAssert window.isOk

let view = window.value.newWebView()
doAssert view.isOk
doAssert view.value.loadHtml("<main>Nimino Windows M1</main>").isOk
