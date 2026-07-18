import std/[json, os, uri]

import nimino_core

if paramCount() != 1:
  quit("usage: wsl-core-rpc-url-client-smoke <windows-host-executable>", QuitFailure)

putEnv("NIMINO_WSL_HOST_EXE", paramStr(1))

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

let created = newApp(id = "tech.asopi.wsl-core-rpc-url-smoke", name = "WSL core URL smoke")
doAssert created.isOk
testApp = created.value
let createdWindow = testApp.newWindow(title = "WSL core URL RPC smoke", width = 800, height = 600)
doAssert createdWindow.isOk
let window = createdWindow.value

doAssert window.rpc.registerSync("system.version", proc(params: JsonNode): RpcResult =
  rpcSuccess(%"1.0.0")
)
doAssert window.rpc.registerSync("test.resolved", resolved)
doAssert window.rpc.registerSync("test.missingBridge", missingBridge)

let document = """
<!doctype html><script>
const report = (method) => chrome.webview.postMessage(JSON.stringify({
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
doAssert window.loadUrl(url).isOk

doAssert testApp.run().isOk
doAssert rpcResolved
doAssert not bridgeMissing
echo "WSL core URL document-start RPC smoke passed"
