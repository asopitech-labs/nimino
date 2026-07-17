import std/json

import nimino_core

var testApp: App
var rpcResolved: bool
var rpcTimedOut: bool

proc completeTest(params: JsonNode): RpcResult =
  rpcResolved = true
  discard testApp.quit()
  rpcSuccess(newJNull())

proc timeoutTest(params: JsonNode): RpcResult =
  rpcTimedOut = true
  discard testApp.quit()
  rpcSuccess(newJNull())

let created = newApp(id = "tech.asopi.nimino.core-smoke", name = "Nimino core smoke")
doAssert created.isOk
testApp = created.value

let createdWindow = testApp.newWindow(title = "Nimino core RPC smoke", width = 320, height = 200)
doAssert createdWindow.isOk
let window = createdWindow.value

doAssert window.rpc.registerSync("system.version", proc(params: JsonNode): RpcResult =
  rpcSuccess(%"1.0.0")
)
doAssert window.rpc.registerSync("test.resolved", completeTest)
doAssert window.rpc.registerSync("test.timeout", timeoutTest)

doAssert window.loadHtml("""
<!doctype html>
<html><body>
<script>
window.nimino.invoke("system.version").then((value) => {
  if (value !== "1.0.0") throw new Error("unexpected version");
  window.nimino.notify("test.resolved", value);
});
</script>
</body></html>
""").isOk

## Fails deterministically instead of leaving a GUI test running if the core
## bootstrap does not establish the expected request/response bridge.
discard window.evalJavaScript("""
setTimeout(() => window.webkit.messageHandlers.nimino.postMessage(JSON.stringify({
  nimino: "rpc", kind: "notification", method: "test.timeout"
})), 3000); void 0;
""")

doAssert testApp.run().isOk
doAssert rpcResolved
doAssert not rpcTimedOut
echo "Linux core RPC smoke passed"
