import std/asyncfutures

import nimino_native

var callbackApp: pointer
var evaluationFinished: bool
var messageReceived: bool

proc quitWhenComplete() {.gcsafe.} =
  if evaluationFinished and messageReceived:
    doAssert cast[NativeApp](callbackApp).quit().isOk

proc completeEvaluation(completed: Future[NativeResultOf[string]]) {.gcsafe.} =
  doAssert not completed.failed
  let result = completed.read()
  doAssert result.isOk
  doAssert result.value == "\"Nimino Linux eval\""
  evaluationFinished = true
  quitWhenComplete()

proc receiveMessage(message: string) {.gcsafe.} =
  doAssert message == "Nimino Linux message"
  messageReceived = true
  quitWhenComplete()

let app = newNativeApp()
callbackApp = cast[pointer](app)
let window = app.newWindow("Nimino Linux smoke", 320, 200)
doAssert window.isOk
let view = window.value.newWebView()
doAssert view.isOk
doAssert view.value.onMessage(receiveMessage).isOk
doAssert view.value.loadHtml("""
<main>Nimino Linux smoke</main>
<script>window.webkit.messageHandlers.nimino.postMessage('Nimino Linux message')</script>
""").isOk

let evaluated = view.value.evalJavaScript("'Nimino Linux eval'")
evaluated.addCallback(completeEvaluation)

doAssert app.run().isOk
doAssert evaluated.finished
doAssert messageReceived
echo "Linux native smoke passed"
