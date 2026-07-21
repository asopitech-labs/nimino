## WSL never becomes a GTK desktop backend. Desktop integration remains owned
## by the Windows host, so these native APIs must fail explicitly rather than
## pretending that Linux GTK capabilities exist.
import nimino_native

let app = newNativeApp()
doAssert not app.supports(nativeMenu)
doAssert not app.supports(nativeNotification)

let menu = app.configureNativeMenu("Nimino", [
  NativeMenuItem(id: 1, title: "Quit", enabled: true)
], proc(itemId: uint32) = discard)
doAssert not menu.isOk
doAssert menu.failure.kind == unsupported

let notification = app.sendNativeNotification(NativeNotification(
  id: "wsl", title: "Nimino", body: "unsupported"
))
doAssert not notification.isOk
doAssert notification.failure.kind == unsupported
