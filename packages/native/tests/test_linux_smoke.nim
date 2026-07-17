import std/asyncfutures

import nimino_native

var callbackApp: pointer

proc completeEvaluation(completed: Future[NativeResultOf[string]]) {.gcsafe.} =
  doAssert not completed.failed
  let result = completed.read()
  doAssert result.isOk
  doAssert result.value == "\"Nimino Linux eval\""
  doAssert cast[NativeApp](callbackApp).quit().isOk

let app = newNativeApp()
callbackApp = cast[pointer](app)
let window = app.newWindow("Nimino Linux smoke", 320, 200)
doAssert window.isOk
let view = window.value.newWebView()
doAssert view.isOk
doAssert view.value.loadHtml("<main>Nimino Linux smoke</main>").isOk

let evaluated = view.value.evalJavaScript("'Nimino Linux eval'")
evaluated.addCallback(completeEvaluation)

doAssert app.run().isOk
doAssert evaluated.finished
echo "Linux native smoke passed"
