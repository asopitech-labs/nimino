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
var notificationRequested: bool
var baseDocumentCompleted: bool
var baseUrlResolved: bool
var urlRequested: bool
var uiTaskExecuted: bool

const BaseUrl = "https://example.invalid/assets/"
const BaseUrlMessage = "Nimino Linux base:https://example.invalid/assets/images/logo.svg"
const UrlSmokeDocument = "data:text/html,%3Cmain%3ENimino%20Linux%20smoke%3C/main%3E%3Cscript%3Ewindow.webkit.messageHandlers.nimino.postMessage(%27Nimino%20Linux%20message%27)%3C/script%3E"

proc quitWhenComplete() =
  if idleTicks > 0 and evaluationFinished and messageReceived and
      navigationStarted and navigationCompleted and browsingDataFinished and
      notificationRequested and baseDocumentCompleted and baseUrlResolved and
      urlRequested and uiTaskExecuted:
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
  case message
  of BaseUrlMessage:
    baseUrlResolved = true
  of "Nimino Linux message":
    messageReceived = true
  else:
    doAssert false

proc receiveIdle() =
  inc idleTicks
  if not notificationRequested:
    let notification = cast[NativeApp](callbackApp).sendNativeNotification(
      NativeNotification(
        id: "linux-native-smoke",
        title: "Nimino Linux smoke",
        body: "GTK/GIO notification request"
      ))
    ## GIO does not report whether the desktop shell ultimately shows it, but
    ## this proves the in-process GNotification API request succeeds.
    doAssert notification.isOk
    notificationRequested = true
  if baseDocumentCompleted and baseUrlResolved and not urlRequested:
    urlRequested = true
    doAssert cast[NativeWebView](callbackView).loadUrl(UrlSmokeDocument).isOk
  if navigationCompleted and not browsingDataFinished and not browsingDataClearInFlight:
    beginNextBrowsingDataClear()
  quitWhenComplete()

proc receiveNavigationCompleted(url: string; succeeded: bool) =
  doAssert succeeded
  if urlRequested:
    navigationCompleted = true
  else:
    baseDocumentCompleted = true

proc receiveNavigationStarting(url: string): bool =
  if urlRequested:
    navigationStarted = true
  true

let app = newNativeApp()
callbackApp = cast[pointer](app)
doAssert app.supports(nativeMenu)
doAssert app.supports(nativeNotification)
doAssert app.configureNativeMenu("Nimino", [
  NativeMenuItem(id: 1, title: "Smoke command", enabled: true)
], proc(itemId: uint32) =
  doAssert itemId == 1
).isOk
doAssert app.setIdleHandler(receiveIdle).isOk
doAssert app.postToUi(proc() = uiTaskExecuted = true).isOk
let window = app.newWindow("Nimino Linux smoke", 320, 200)
doAssert window.isOk
doAssert window.value.setSize(640, 480).isOk
let view = window.value.newWebView()
doAssert view.isOk
callbackView = cast[pointer](view.value)
doAssert view.value.onMessage(receiveMessage).isOk
doAssert view.value.onNavigationStarting(receiveNavigationStarting).isOk
doAssert view.value.onNavigationCompleted(receiveNavigationCompleted).isOk
doAssert view.value.loadHtml("""
<!doctype html>
<main>Nimino Linux HTML base smoke</main>
<a id="asset" href="images/logo.svg">asset</a>
<script>
window.webkit.messageHandlers.nimino.postMessage(
  "Nimino Linux base:" + document.getElementById("asset").href
)
</script>
""", baseUrl = BaseUrl).isOk

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
doAssert notificationRequested
doAssert baseDocumentCompleted
doAssert baseUrlResolved
doAssert urlRequested
echo "Linux native smoke passed"
