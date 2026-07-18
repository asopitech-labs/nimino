import std/[json, uri]

import nimino_core

var testApp: App
var rpcResolved: bool
var bridgeMissing: bool

proc resolved(params: JsonNode): RpcResult =
  rpcResolved = true
  discard testApp.quit()
  rpcSuccess(newJNull())

proc missingBridge(params: JsonNode): RpcResult =
  bridgeMissing = true
  discard testApp.quit()
  rpcSuccess(newJNull())

let created = newApp(id = "tech.asopi.nimino.core-url-smoke", name = "Nimino core URL smoke")
doAssert created.isOk
testApp = created.value
let createdWindow = testApp.newWindow(title = "Nimino core URL RPC smoke", width = 320, height = 200)
doAssert createdWindow.isOk
let window = createdWindow.value

doAssert window.rpc.registerSync("system.version", proc(params: JsonNode): RpcResult =
  rpcSuccess(%"1.0.0")
)
doAssert window.rpc.registerSync("test.resolved", resolved)
doAssert window.rpc.registerSync("test.missingBridge", missingBridge)

let document = """
<!doctype html><script>
const report = (method) => window.webkit.messageHandlers.nimino.postMessage(JSON.stringify({
  nimino: "rpc", kind: "notification", method
}));
if (!window.nimino || typeof window.nimino.invoke !== "function") {
  report("test.missingBridge");
} else {
  window.nimino.invoke("system.version").then((value) => {
    if (value !== "1.0.0") throw new Error("unexpected version");
    report("test.resolved");
  });
}
</script>
"""
let url = "data:text/html," & encodeUrl(document, false)
## `about:blank` must not consume the document-start slot: its inherited
## origin cannot be authorized by a URL equality check.
doAssert window.loadUrl("about:blank").isOk
doAssert window.loadUrl(url).isOk

doAssert testApp.run().isOk
doAssert rpcResolved
doAssert not bridgeMissing
echo "Linux core URL document-start RPC smoke passed"
