## macOS runtime regression coverage for Pake's link-guard Web API bridge.
## The test executes the same scripts that a generated host injects, then
## observes their explicit window-scoped RPC requests instead of assuming a
## notification was displayed by the operating system.

import std/[json, strutils, tables]

import nimino_core
import web_compat

var appPtr: pointer
var completed: bool
var badgeCalls: seq[string]
var notificationCalls: seq[string]
var popupUrls: seq[string]
var popupSequence: int
var managedPopups = initTable[string, Window]()
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
  multiWindow: true,
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
doAssert window.rpc.registerSync("app.openPopup", proc(params: JsonNode): RpcResult =
  if params.kind != JObject or not params.hasKey("url") or params["url"].kind != JString:
    return rpcFailure(rpcError(invalidRequest, "popup url is required"))
  let target = params["url"].getStr()
  popupUrls.add(target)
  let popup = window.openPopup(NewWindowRequest(url: target, focused: true), profile = "popup")
  if not popup.isOk:
    return rpcFailure(rpcError(handlerFailed, popup.failure.detail))
  inc popupSequence
  let popupId = "popup-" & $popupSequence
  managedPopups[popupId] = popup.value
  rpcSuccess(%*{"id": popupId})
)
doAssert window.rpc.registerSync("app.navigatePopup", proc(params: JsonNode): RpcResult =
  if params.kind != JObject or not params.hasKey("id") or not params.hasKey("url") or
      params["id"].kind != JString or params["url"].kind != JString or
      not managedPopups.hasKey(params["id"].getStr()):
    return rpcFailure(rpcError(invalidRequest, "popup id and url are required"))
  let target = params["url"].getStr()
  popupUrls.add(target)
  let loaded = managedPopups[params["id"].getStr()].loadUrl(target)
  if loaded.isOk: rpcSuccess(%*{"ok": true})
  else: rpcFailure(rpcError(handlerFailed, loaded.failure.detail))
)
doAssert window.rpc.registerSync("app.closePopup", proc(params: JsonNode): RpcResult =
  if params.kind != JObject or not params.hasKey("id") or params["id"].kind != JString:
    return rpcFailure(rpcError(invalidRequest, "popup id is required"))
  let popupId = params["id"].getStr()
  if managedPopups.hasKey(popupId):
    discard managedPopups[popupId].close()
    managedPopups.del(popupId)
  rpcSuccess(%*{"ok": true})
)

doAssert window.loadHtml("""
<!doctype html><title>Nimino Web Compatibility Smoke</title>
<base href="https://example.com/app">
<main>Web compatibility smoke</main>
<script>
(async () => {
  try {
    await navigator.setAppBadge(3.8);
    await navigator.setAppBadge();
    await navigator.setAppBadge(0);
    const notice = new Notification('Hello', {body: 'World', icon: '/icon.png'});
    const internal = document.createElement('a');
    internal.href = '/callback';
    internal.target = '_blank';
    internal.addEventListener('click', (event) => event.preventDefault());
    document.body.appendChild(internal);
    internal.click();
    const javascriptLink = document.createElement('a');
    javascriptLink.href = 'javascript:void(0)';
    javascriptLink.target = '_blank';
    javascriptLink.addEventListener('click', (event) => event.preventDefault());
    document.body.appendChild(javascriptLink);
    javascriptLink.click();
    const fragmentLink = document.createElement('a');
    fragmentLink.href = '#captcha-confirm';
    fragmentLink.target = '_blank';
    fragmentLink.addEventListener('click', (event) => event.preventDefault());
    document.body.appendChild(fragmentLink);
    fragmentLink.click();
    const blankPopup = window.open('about:blank', 'login', 'width=320,height=180');
    blankPopup.location.href = 'https://appleid.apple.com/auth/authorize';
    const applePopup = window.open('https://appleid.apple.com/auth/authorize', 'AppleAuthentication',
      'width=320,height=180');
    await new Promise((resolve) => setTimeout(resolve, 30));
    notice.close();
    await new Promise((resolve) => setTimeout(resolve, 0));
    window.nimino.notify('reference.webCompatComplete', {
      badgeApi: typeof navigator.setAppBadge === 'function' &&
        typeof navigator.clearAppBadge === 'function',
      notificationApi: typeof Notification === 'function' &&
        Notification.permission === 'granted',
      internalBlankRetargeted: internal.target === '_self',
      javascriptBypassed: javascriptLink.target === '_blank',
      fragmentBypassed: fragmentLink.target === '_blank',
      popupProxy: blankPopup && applePopup && blankPopup.closed === false && applePopup.closed === false,
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
doAssert completionPayload.contains("\"internalBlankRetargeted\":true")
doAssert completionPayload.contains("\"javascriptBypassed\":true")
doAssert completionPayload.contains("\"fragmentBypassed\":true")
doAssert completionPayload.contains("\"popupProxy\":true")
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
doAssert notificationCalls[0].contains("\"icon\":\"https://example.com/icon.png\"")
doAssert popupUrls == @[
  "about:blank",
  "https://appleid.apple.com/auth/authorize",
  "https://appleid.apple.com/auth/authorize"
]
echo "macOS web compatibility smoke passed"
