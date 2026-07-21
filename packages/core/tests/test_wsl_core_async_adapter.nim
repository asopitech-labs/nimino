import std/[asyncfutures, json, os]

import nimino_core

if paramCount() != 1:
  quit("usage: test-wsl-core-async-adapter <fake-host>", QuitFailure)

putEnv("NIMINO_WSL_HOST_EXE", paramStr(1))

var pendingAsync: Future[RpcResult]
var profileDataClear: Future[CoreResult]
var unsupportedProfileDataClear: Future[CoreResult]
var asyncRequested = false
var asyncCompleted = false
var neverRequested = false
var closeRequested = false
var closedHandlerRan = false
var resizeWidth = 0
var resizeHeight = 0
var closingAsync: Future[RpcResult]
var desktopActionSeen = false
var fileDialogResult: Future[CoreResultOf[seq[string]]]

proc startAsync(params: JsonNode): Future[RpcResult] =
  asyncRequested = true
  pendingAsync = newFuture[RpcResult]("nimino.wsl.async-adapter")
  pendingAsync

proc completeAsync(params: JsonNode): RpcResult =
  doAssert pendingAsync != nil
  doAssert not pendingAsync.finished
  asyncCompleted = true
  pendingAsync.complete(rpcSuccess(%"complete"))
  rpcSuccess(newJNull())

proc neverCompletes(params: JsonNode): Future[RpcResult] =
  neverRequested = true
  newFuture[RpcResult]("nimino.wsl.timeout-adapter")

proc completeAfterWindowClosed(params: JsonNode): Future[RpcResult] =
  closeRequested = true
  closingAsync = newFuture[RpcResult]("nimino.wsl.close-adapter")
  closingAsync

let created = newApp(id = "tech.asopi.wsl-core-async-test", name = "WSL core async test")
doAssert created.isOk
let app = created.value
let createdWindow = app.newWindow(title = "WSL core async test", width = 320, height = 200)
doAssert createdWindow.isOk
let window = createdWindow.value
doAssert app.configureNativeMenu("File", @[
  DesktopMenuItem(id: 9, title: "Test", enabled: true)
], proc(itemId: uint32) =
  doAssert itemId == 9
  desktopActionSeen = true).isOk
doAssert app.configureSystemTray(@[
  DesktopMenuItem(id: 10, title: "Tray", enabled: true)
], proc(itemId: uint32) = discard).isOk
let extraView = window.newWebView()
doAssert extraView.isOk
var extraMessage = ""
doAssert extraView.value.onMessage(proc(message: string) = extraMessage = message).isOk
doAssert extraView.value.close().isOk

doAssert window.rpc.register("async.request", startAsync)
doAssert window.rpc.registerSync("async.complete", completeAsync)
doAssert window.rpc.register("never", neverCompletes)
doAssert window.rpc.register("close.delayed", completeAfterWindowClosed)
doAssert window.onClosed(proc() =
  ## The fake Windows host emits `native.window.closed` while this request is
  ## still pending. `processWslEvent` must close the registry before invoking
  ## this callback, so a late handler completion cannot reply to WebView.
  closedHandlerRan = true
  doAssert closingAsync != nil
  doAssert not closingAsync.finished
  doAssert not window.rpc.handleMessage("""{
    "nimino":"rpc", "kind":"request", "id":"after-close",
    "method":"close.delayed", "params":null
  }""")
  closingAsync.complete(rpcSuccess(%"late completion"))
).isOk
doAssert window.onResize(proc(width, height: int) =
  resizeWidth = width
  resizeHeight = height
).isOk
doAssert window.loadHtml("<main>WSL async adapter test</main>").isOk
doAssert app.onReady(proc() =
  doAssert app.sendNotification(DesktopNotification(
    id: "async-test", title: "Async test", body: "ready")).isOk
  fileDialogResult = window.openFileDialog(FileDialogOptions(
    title: "Choose a file", save: false, multiple: false))
  doAssert not fileDialogResult.finished
  profileDataClear = window.clearWebViewProfileData({webViewCookies, webViewCache})
  unsupportedProfileDataClear = window.clearWebViewProfileData({webViewLocalStorage})
  doAssert not profileDataClear.finished
  doAssert not unsupportedProfileDataClear.finished
).isOk

doAssert app.run().isOk
doAssert desktopActionSeen
doAssert asyncRequested
doAssert asyncCompleted
doAssert neverRequested
doAssert closeRequested
doAssert closedHandlerRan
doAssert resizeWidth == 640
doAssert resizeHeight == 480
doAssert closingAsync != nil
doAssert closingAsync.finished
doAssert closingAsync.read().isOk
doAssert profileDataClear != nil
doAssert profileDataClear.finished
doAssert profileDataClear.read().isOk
doAssert unsupportedProfileDataClear != nil
doAssert unsupportedProfileDataClear.finished
let unsupportedResult = unsupportedProfileDataClear.read()
doAssert not unsupportedResult.isOk
doAssert unsupportedResult.failure.kind == platformUnavailable
doAssert fileDialogResult != nil
doAssert fileDialogResult.finished
let chosen = fileDialogResult.read()
doAssert chosen.isOk
doAssert chosen.value == @["C:\\tmp\\chosen.txt"]
