## Linux StatusNotifierItem/dbusmenu registration smoke.
##
## The watcher runs in a separate process.  A same-process fake watcher cannot
## service a synchronous RegisterStatusNotifierItem call while the caller is
## blocked in g_dbus_connection_call_sync; keeping it separate exercises the
## real session-bus registration and teardown path.

when not defined(linux) or defined(niminoWsl):
  quit("Linux native test only")

import std/[os, osproc, times]
import nimino_native
import ../src/nimino_native/private/linux/ffi

const watcherXml = """
<node><interface name='org.freedesktop.StatusNotifierWatcher'>
  <method name='RegisterStatusNotifierItem'><arg type='s' direction='in'/></method>
</interface></node>"""

var receivedRegistration = false

proc watcherMethodCall(connection: ptr GDBusConnection; sender, objectPath,
                       interfaceName, methodName: cstring; parameters: ptr GVariant;
                       invocation: ptr GDBusMethodInvocation; userData: pointer) {.cdecl.} =
  if not methodName.isNil and $methodName == "RegisterStatusNotifierItem":
    receivedRegistration = true
    let marker = cast[cstring](userData)
    if not marker.isNil:
      try: writeFile($marker, "registered\n")
      except OSError: discard
  g_dbus_method_invocation_return_value(invocation, nil)

var watcherVTable = GDBusInterfaceVTable(
  methodCall: watcherMethodCall,
  getProperty: nil,
  setProperty: nil,
  padding: [nil, nil, nil, nil, nil, nil, nil, nil])

proc runWatcher(marker: string) =
  let connection = g_bus_get_sync(GBusTypeSession, nil, nil)
  doAssert connection != nil
  let request = g_dbus_connection_call_sync(connection,
    "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
    "RequestName", g_variant_new("(su)",
      "org.freedesktop.StatusNotifierWatcher", 0'u32), nil, 0, 1000, nil, nil)
  doAssert request != nil
  g_variant_unref(request)
  let markerCString = marker.cstring
  let node = g_dbus_node_info_new_for_xml(watcherXml, nil)
  doAssert node != nil
  let interfaceInfo = g_dbus_node_info_lookup_interface(node,
    "org.freedesktop.StatusNotifierWatcher")
  doAssert interfaceInfo != nil
  let watcherObject = g_dbus_connection_register_object(connection,
    "/StatusNotifierWatcher", interfaceInfo, addr watcherVTable,
    cast[pointer](markerCString), nil, nil)
  doAssert watcherObject != 0
  let stopMarker = marker & ".stop"
  let deadline = epochTime() + 15.0
  while not fileExists(stopMarker) and epochTime() < deadline:
    discard g_main_context_iteration(nil, 0)
    sleep(10)
  discard g_dbus_connection_unregister_object(connection, watcherObject)
  g_dbus_node_info_unref(node)
  g_object_unref(connection)

if paramCount() >= 1 and paramStr(1) == "--watcher":
  doAssert paramCount() == 2
  runWatcher(paramStr(2))
  quit(0)

let marker = getTempDir() / ("nimino-tray-smoke-" & $int(epochTime() * 1_000_000.0))
let watcher = startProcess(getAppFilename(), args = @[
  "--watcher", marker], options = {poUsePath})
try:
  var app: NativeApp
  var ready = false
  for _ in 0 ..< 100:
    app = newNativeApp(NativeAppOptions(appId: "app.nimino.tray.smoke"))
    if app.supports(systemTray):
      ready = true
      break
    sleep(50)
  doAssert ready
  doAssert app.configureSystemTray([
    NativeMenuItem(id: 1, title: "Quit", enabled: true)
  ], proc(itemId: uint32) = discard).isOk
  let window = app.newWindow("Tray smoke", 320, 200)
  doAssert window.isOk
  discard app.setIdleHandler(proc() = discard app.quit())
  let runResult = app.run()
  doAssert runResult.isOk
  writeFile(marker & ".stop", "stop\n")
  doAssert watcher.waitForExit(5000) == 0
  doAssert receivedRegistration or fileExists(marker)
finally:
  if watcher.running():
    try: watcher.terminate()
    except OSError: discard
  close(watcher)
  for path in [marker, marker & ".stop"]:
    if fileExists(path):
      try: removeFile(path)
      except OSError: discard
echo "Linux StatusNotifierItem/dbusmenu smoke passed"
