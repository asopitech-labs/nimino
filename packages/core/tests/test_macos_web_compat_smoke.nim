## macOS runtime regression coverage for Pake's link-guard Web API bridge.
## The test executes the same scripts that a generated host injects, then
## observes their explicit window-scoped RPC requests instead of assuming a
## notification was displayed by the operating system.

import std/[json, strutils]

import nimino_core
import web_compat

var appPtr: pointer
var completed: bool
var badgeCalls: seq[string]
var notificationCalls: seq[string]
var completionPayload = ""

proc finish() {.gcsafe.} =
  if completed:
    {.cast(gcsafe).}:
      doAssert cast[App](appPtr).quit().isOk

let created = newApp(AppOptions(id: "tech.asopi.nimino.macos-web-compat-smoke",
  name: "Nimino macOS Web Compatibility Smoke", multiInstance: true))
doAssert created.isOk, created.failure.detail
let app = created.value
appPtr = cast[pointer](app)
let windowCreated = app.newWindow(CoreWindowOptions(
  title: "Nimino macOS Web Compatibility Smoke", width: 480, height: 280,
  injectionJavaScript: macosWebCompatibilityScripts()))
doAssert windowCreated.isOk, windowCreated.failure.detail
let window = windowCreated.value

doAssert window.rpc.registerSync("app.setDockBadge", proc(params: JsonNode): RpcResult =
  badgeCalls.add($params)
  rpcSuccess(%*{"ok": true})
)
doAssert window.rpc.registerSync("app.sendNotification", proc(params: JsonNode): RpcResult =
  notificationCalls.add($params)
  rpcSuccess(%*{"ok": true})
)
doAssert window.rpc.registerNotification("reference.webCompatComplete", proc(params: JsonNode) =
  completionPayload = $params
  completed = true
  finish()
)

doAssert window.loadHtml("""
<!doctype html><title>Nimino Web Compatibility Smoke</title>
<main>Web compatibility smoke</main>
<script>
(async () => {
  try {
    await navigator.setAppBadge(3.8);
    await navigator.setAppBadge();
    await navigator.setAppBadge(0);
    const notice = new Notification('Hello', {body: 'World', icon: '/icon.png'});
    await new Promise((resolve) => setTimeout(resolve, 0));
    notice.close();
    await new Promise((resolve) => setTimeout(resolve, 0));
    window.nimino.notify('reference.webCompatComplete', {
      badgeApi: typeof navigator.setAppBadge === 'function' &&
        typeof navigator.clearAppBadge === 'function',
      notificationApi: typeof Notification === 'function' &&
        Notification.permission === 'granted',
      title: notice.title,
      body: notice.body
    });
  } catch (error) {
    window.nimino.notify('reference.webCompatComplete', {error: String(error)});
  }
})();
</script>
""").isOk

doAssert app.run().isOk
doAssert completed
doAssert completionPayload.contains("\"badgeApi\":true")
doAssert completionPayload.contains("\"notificationApi\":true")
doAssert completionPayload.contains("\"title\":\"Hello\"")
doAssert completionPayload.contains("\"body\":\"World\"")
doAssert badgeCalls == @[
  "{\"count\":3}",
  "{\"label\":\"•\"}",
  "{\"label\":\"\"}",
  "{\"count\":1}",
  "{\"label\":\"\"}"
]
doAssert notificationCalls.len == 1
doAssert notificationCalls[0].contains("\"title\":\"Hello\"")
doAssert notificationCalls[0].contains("\"body\":\"World\"")
echo "macOS web compatibility smoke passed"
