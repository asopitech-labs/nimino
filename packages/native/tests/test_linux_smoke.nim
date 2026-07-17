import nimino_native

let app = newNativeApp()
let window = app.newWindow("Nimino Linux smoke", 320, 200)
doAssert window.isOk
let view = window.value.newWebView()
doAssert view.isOk
doAssert view.value.loadUrl("about:blank").isOk

# Calling quit before run makes the activate callback create the native Window and
# WebView, then close it. This exercises creation, URL loading, and cleanup without
# leaving a GUI test process open.
doAssert app.quit().isOk
doAssert app.run().isOk
echo "Linux native smoke passed"
