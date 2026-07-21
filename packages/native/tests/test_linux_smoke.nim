import std/asyncfutures

import nimino_native

var callbackApp: pointer
var callbackView: pointer
var idleTicks: int
var evaluationFinished: bool
var messageReceived: bool
var navigationStarted: bool
var navigationCompleted: bool
var browsingDataClearInFlight: bool
var browsingDataClearStep: int
var browsingDataFinished: bool

proc quitWhenComplete() =
  if idleTicks > 0 and evaluationFinished and messageReceived and
      navigationStarted and navigationCompleted and browsingDataFinished:
    doAssert cast[NativeApp](callbackApp).quit().isOk

proc completeEvaluation(completed: Future[NativeResultOf[string]]) {.gcsafe.} =
  doAssert not completed.failed
  let result = completed.read()
  doAssert result.isOk
  doAssert result.value == "\"Nimino Linux eval\""
  evaluationFinished = true

proc completeBrowsingData(completed: Future[NativeResult]) {.gcsafe.} =
  doAssert not completed.failed
  doAssert completed.read().isOk
  browsingDataClearInFlight = false
  inc browsingDataClearStep
  if browsingDataClearStep == 3:
    browsingDataFinished = true

proc beginNextBrowsingDataClear() =
  let view = cast[NativeWebView](callbackView)
  let kinds =
    case browsingDataClearStep
    of 0: {nativeBrowsingCookies}
    of 1: {nativeBrowsingLocalStorage}
    of 2: {nativeBrowsingCache}
    else: return
  browsingDataClearInFlight = true
  let cleared = view.clearBrowsingData(kinds)
  cleared.addCallback(completeBrowsingData)

proc receiveMessage(message: string) =
  doAssert message == "Nimino Linux message"
  messageReceived = true

proc receiveIdle() =
  inc idleTicks
  if navigationCompleted and not browsingDataFinished and not browsingDataClearInFlight:
    beginNextBrowsingDataClear()
  quitWhenComplete()

proc receiveNavigationCompleted(url: string; succeeded: bool) =
  doAssert succeeded
  navigationCompleted = true

proc receiveNavigationStarting(url: string): bool =
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
callbackView = cast[pointer](view.value)
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
doAssert browsingDataClearStep == 3
doAssert browsingDataFinished
echo "Linux native smoke passed"
