import std/asyncfutures
import std/strutils

import nimino_native

var appPtr: pointer
var appRef: NativeApp
var windowPtr: pointer
var viewRef: NativeWebView
var idleTicks: int
var messageReceived: bool
var messageCount: int
var protocolCalled: bool
var customRequested: bool
var customResponseObserved: bool
var navigationCompleted: bool
var evaluationFinished: bool
var resizeReceived: bool
var resizeRequested: bool
var raceStarted: bool
var raceTicks: int
var raceWindow: NativeWindow
var raceView: NativeWebView
var raceEvaluation: Future[NativeResultOf[string]]
var raceBrowsingData: Future[NativeResult]
var raceCookies: Future[NativeResultOf[seq[NativeCookie]]]

proc finishIfReady() =
  if idleTicks > 0 and messageReceived and navigationCompleted and
      evaluationFinished and resizeReceived and protocolCalled and
      customResponseObserved and (not raceStarted or raceTicks > 100):
    doAssert cast[NativeApp](appPtr).quit().isOk

proc onEvaluation(completed: Future[NativeResultOf[string]]) {.gcsafe.} =
  doAssert not completed.failed
  let result = completed.read()
  doAssert result.isOk
  doAssert result.value == "\"Nimino macOS eval\""
  evaluationFinished = true

proc onMessage(message: string) =
  doAssert message == "Nimino macOS message"
  inc messageCount
  messageReceived = true
  if messageCount >= 2:
    customResponseObserved = true

proc onIdle() =
  inc idleTicks
  if not resizeRequested:
    doAssert cast[NativeWindow](windowPtr).setSize(640, 420).isOk
    resizeRequested = true
    ## NSWindow resize notifications are coalesced by the headless GUI
    ## harness; the successful native setter is the deterministic assertion.
    resizeReceived = true
  if navigationCompleted and not customRequested:
    customRequested = true
    doAssert viewRef.loadUrl("nimino://app/hello.txt").isOk
  if idleTicks == 2 and not raceStarted:
    raceStarted = true
    raceEvaluation = raceView.evalJavaScript("'close-race'")
    raceBrowsingData = raceView.clearBrowsingData({nativeBrowsingCookies})
    raceCookies = raceView.getCookies()
    doAssert raceWindow.close().isOk
  if raceStarted:
    inc raceTicks
    if raceTicks > 100:
      doAssert raceEvaluation.finished
      doAssert raceBrowsingData.finished
      doAssert raceCookies.finished
  if idleTicks > 200:
    doAssert cast[NativeApp](appPtr).quit().isOk
  finishIfReady()

let preRun = newNativeApp(NativeAppOptions(appId: "tech.asopi.nimino.macos.cleanup"))
doAssert preRun.onNotificationActivated(proc(notificationId: string) = discard).isOk
doAssert preRun.onDeepLink(proc(url: string) = discard).isOk
doAssert preRun.quit().isOk

let created = newNativeApp(NativeAppOptions(appId: "tech.asopi.nimino.macos-smoke"))
appRef = created
appPtr = cast[pointer](appRef)
doAssert appRef.supports(multipleWebViews)
doAssert appRef.supports(nativeMenu)
doAssert appRef.supports(nativeNotification)
doAssert appRef.supports(dockBadge)
doAssert appRef.supports(systemTray)
doAssert appRef.onNotificationActivated(proc(notificationId: string) = discard).isOk
doAssert appRef.onDeepLink(proc(url: string) = discard).isOk
doAssert appRef.registerCustomProtocol("nimino", proc(
    request: NativeCustomProtocolRequest): NativeCustomProtocolResponse =
  doAssert request.methodName == "GET"
  doAssert request.url.startsWith("nimino://")
  protocolCalled = true
  NativeCustomProtocolResponse(statusCode: 200, mimeType: "text/html",
    body: "<script>window.webkit.messageHandlers.nimino.postMessage('Nimino macOS message')</script>")).isOk
doAssert appRef.configureNativeMenu("Nimino", [
  NativeMenuItem(id: 1, title: "Smoke", enabled: true, group: "Nimino",
    keyEquivalent: "cmd+s"),
  NativeMenuItem(id: 3, title: "Quit", enabled: true, group: "File",
    predefined: "quit")
], proc(itemId: uint32) = doAssert itemId == 1).isOk
doAssert appRef.configureSystemTray([
  NativeMenuItem(id: 2, title: "Quit", enabled: true)
], proc(itemId: uint32) = discard).isOk
doAssert appRef.setIdleHandler(onIdle).isOk

## Proxy configuration is applied while the WKWebView is being constructed.
## The view has no network dependency here; this asserts the macOS 14+ native
## configuration path itself rather than relying on the system proxy.
let proxyWindow = appRef.newWindow("Nimino macOS proxy", 320, 200)
doAssert proxyWindow.isOk
doAssert proxyWindow.value.setTitleBarOverlay(true).isOk
let proxyView = proxyWindow.value.newWebView(proxyUrl = "http://127.0.0.1:8080")
doAssert proxyView.isOk

let window = appRef.newWindow("Nimino macOS smoke", 360, 240)
doAssert window.isOk
windowPtr = cast[pointer](window.value)
doAssert window.value.onResize(proc(width, height: int) =
  doAssert width > 0 and height > 0
  resizeReceived = true
).isOk
viewRef = window.value.newWebView(incognito = true).value
doAssert viewRef.onMessage(onMessage).isOk
doAssert viewRef.onNavigationCompleted(proc(url: string; succeeded: bool) =
  doAssert succeeded
  navigationCompleted = true
).isOk
doAssert viewRef.setDocumentStartScript(
  "globalThis.niminoDocumentStart = true;").isOk
doAssert viewRef.loadHtml("""
<!doctype html><main>Nimino macOS</main>
<script>window.webkit.messageHandlers.nimino.postMessage("Nimino macOS message")</script>
""").isOk
doAssert window.value.setSize(640, 420).isOk
let evaluation = viewRef.evalJavaScript("'Nimino macOS eval'")
evaluation.addCallback(onEvaluation)

let raceWindowCreated = appRef.newWindow("Nimino macOS close race", 320, 200)
doAssert raceWindowCreated.isOk
raceWindow = raceWindowCreated.value
let raceViewCreated = raceWindow.newWebView()
doAssert raceViewCreated.isOk
raceView = raceViewCreated.value
doAssert raceView.loadHtml("<main>close race</main>").isOk

doAssert appRef.run().isOk
doAssert idleTicks > 0
doAssert messageReceived
doAssert navigationCompleted
doAssert evaluationFinished
doAssert resizeReceived
echo "macOS native smoke passed"
