import std/asyncfutures

import nimino_native

var callbackApp: pointer
var idleTicks: int
var evaluationFinished: bool
var messageReceived: bool
var navigationStarted: bool
var navigationCompleted: bool

proc quitWhenComplete() {.gcsafe.} =
  if idleTicks > 0 and evaluationFinished and messageReceived and
      navigationStarted and navigationCompleted:
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

proc receiveIdle() {.gcsafe.} =
  inc idleTicks
  quitWhenComplete()

proc receiveNavigationCompleted(url: string; succeeded: bool) {.gcsafe.} =
  doAssert succeeded
  navigationCompleted = true
  quitWhenComplete()

proc receiveNavigationStarting(url: string): bool {.gcsafe.} =
  navigationStarted = true
  true

let app = newNativeApp()
callbackApp = cast[pointer](app)
doAssert app.setIdleHandler(receiveIdle).isOk
let window = app.newWindow("Nimino Linux smoke", 320, 200)
doAssert window.isOk
doAssert window.value.setSize(640, 480).isOk
let view = window.value.newWebView()
doAssert view.isOk
doAssert view.value.onMessage(receiveMessage).isOk
doAssert view.value.onNavigationStarting(receiveNavigationStarting).isOk
doAssert view.value.onNavigationCompleted(receiveNavigationCompleted).isOk
doAssert view.value.loadUrl("data:text/html,%3Cmain%3ENimino%20Linux%20smoke%3C/main%3E%3Cscript%3Ewindow.webkit.messageHandlers.nimino.postMessage(%27Nimino%20Linux%20message%27)%3C/script%3E").isOk

let evaluated = view.value.evalJavaScript("'Nimino Linux eval'")
evaluated.addCallback(completeEvaluation)

doAssert app.run().isOk
doAssert evaluated.finished
doAssert idleTicks > 0
doAssert messageReceived
doAssert navigationStarted
doAssert navigationCompleted
echo "Linux native smoke passed"
