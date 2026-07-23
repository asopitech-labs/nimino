## Compile-only contract target.  It is built as a Windows PE binary from the
## Docker development image and is never executed in the Linux test container.
import nimino_native

let app = newNativeApp()
let identityApp = newNativeApp(NativeAppOptions(appId: "app.nimino.windows-cross"))
let startupActivationApp = newNativeApp(NativeAppOptions(
  appId: "app.nimino.windows-cross-startup",
  initialNotificationId: "startup-payload"))
## The low-level option is used by launchers/tests to model a terminated
## process.  The real backend also accepts the same payload from its command
## line before `run()` and delivers it through this callback.
doAssert startupActivationApp.onNotificationActivated(proc(notificationId: string) = discard).isOk
let activatorClsid = windowsToastActivatorClsid("app.nimino.windows-cross-startup")
doAssert activatorClsid.data1 != 0
doAssert identityApp.supports(nativeNotification)
doAssert app.supports(systemTray)
doAssert app.supports(nativeMenu)
doAssert app.supports(nativeNotification)
doAssert app.onNotificationActivated(proc(notificationId: string) = discard).isOk
doAssert app.configureSystemTray([
  NativeMenuItem(id: 1, title: "Show Nimino", enabled: true),
  NativeMenuItem(id: 2, title: "Quit Nimino", enabled: true)
], proc(itemId: uint32) = discard).isOk
let nativeMenuApp = newNativeApp()
doAssert nativeMenuApp.configureNativeMenu("Nimino", [
  NativeMenuItem(id: 1, title: "Show Nimino", enabled: true),
  NativeMenuItem(id: 2, title: "Quit Nimino", enabled: true)
], proc(itemId: uint32) = discard).isOk
## Native menus and tray menus are independent Win32 surfaces; configuring one
## must not silently configure the other.
doAssert nativeMenuApp.configureSystemTray([
  NativeMenuItem(id: 3, title: "Tray Quit", enabled: true)
], proc(itemId: uint32) = discard).isOk
let notification = app.sendNativeNotification(NativeNotification(
  id: "windows-cross", title: "Nimino", body: "not running"))
doAssert not notification.isOk
doAssert notification.failure.kind == invalidState
let window = app.newWindow(title = "Nimino Windows M1", width = 800, height = 600)
doAssert window.isOk

let view = window.value.newWebView()
doAssert view.isOk
let configuredView = window.value.newWebView(
  proxyUrl = "http://127.0.0.1:8080", incognito = true)
doAssert configuredView.isOk
## Environment/controller options are construct-time settings; before app.run
## both setters remain valid and are consumed by the Windows startup path.
doAssert configuredView.value.setProxy("http://127.0.0.1:8081").isOk
doAssert configuredView.value.setIncognito(true).isOk
doAssert view.value.onMessage(proc(message: string) = discard).isOk
doAssert view.value.onError(proc(error: NativeError) = discard).isOk
doAssert view.value.onNewWindowRequested(proc(request: NativeNewWindowRequest): bool = true).isOk
doAssert view.value.onNavigationStarting(proc(url: string): bool = true).isOk
doAssert view.value.onNavigationCompleted(proc(url: string; succeeded: bool) = discard).isOk
doAssert view.value.setDocumentStartScript("globalThis.niminoDocumentStart = true;").isOk
let basedHtml = view.value.loadHtml("<main>Nimino Windows M1</main>",
  baseUrl = "https://example.test/assets/")
doAssert not basedHtml.isOk
doAssert basedHtml.failure.kind == unsupported
doAssert view.value.loadHtml("<main>Nimino Windows M1</main>").isOk
discard view.value.evalJavaScript("document.title")
