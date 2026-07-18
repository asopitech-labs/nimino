import std/[json, os]

import nimino_wsl

if paramCount() != 1:
  quit("usage: wsl-client-smoke <windows-host-executable>", QuitFailure)

let launched = launchHost(paramStr(1))
if not launched.isOk:
  stderr.writeLine("WSL client launch failed: " & launched.failure.detail)
  quit(QuitFailure)
let client = launched.value

let window = client.call("native.window.create",
  "{\"title\":\"WSL client smoke\",\"width\":800,\"height\":600}")
doAssert window.isOk
let windowId = parseJson(window.value.payload)["windowId"].getStr()

let view = client.call("native.webview.create", $(%*{"windowId": windowId}))
doAssert view.isOk
let webViewId = parseJson(view.value.payload)["webViewId"].getStr()
doAssert webViewId.len > 0

doAssert client.call("native.window.setTitle", $(%*{
  "windowId": windowId,
  "title": "WSL client smoke updated"
})).isOk
doAssert client.call("native.window.setSize", $(%*{
  "windowId": windowId,
  "width": 1_000,
  "height": 700
})).isOk
doAssert client.call("native.webview.loadUrl", $(%*{
  "webViewId": webViewId,
  "url": "about:blank"
})).isOk

let closed = client.close()
doAssert closed.isOk
echo "WSL client/host smoke passed"
