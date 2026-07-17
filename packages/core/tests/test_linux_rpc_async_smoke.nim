import std/[asyncfutures, json]

import nimino_core

var testApp: App
var pendingAsync: Future[RpcResult]
var asyncResolved: bool
var timeoutReceived: bool
var fallbackTriggered: bool

proc finishIfComplete() =
  if asyncResolved and timeoutReceived:
    discard testApp.quit()

proc startAsync(params: JsonNode): Future[RpcResult] =
  pendingAsync = newFuture[RpcResult]("nimino.core.async-smoke")
  pendingAsync

proc neverCompletes(params: JsonNode): Future[RpcResult] =
  newFuture[RpcResult]("nimino.core.timeout-smoke")

proc completeAsync(params: JsonNode): RpcResult =
  doAssert pendingAsync != nil
  doAssert not pendingAsync.finished
  pendingAsync.complete(rpcSuccess(%"async complete"))
  rpcSuccess(newJNull())

proc receiveAsyncResolved(params: JsonNode): RpcResult =
  asyncResolved = true
  finishIfComplete()
  rpcSuccess(newJNull())

proc receiveTimeout(params: JsonNode): RpcResult =
  doAssert params.kind == JObject
  doAssert params["code"].getStr() == "timeout"
  timeoutReceived = true
  finishIfComplete()
  rpcSuccess(newJNull())

proc failFallback(params: JsonNode): RpcResult =
  fallbackTriggered = true
  discard testApp.quit()
  rpcSuccess(newJNull())

let created = newApp(id = "tech.asopi.nimino.core-async-smoke", name = "Nimino core async smoke")
doAssert created.isOk
testApp = created.value
let createdWindow = testApp.newWindow(title = "Nimino core async RPC smoke", width = 320, height = 200)
doAssert createdWindow.isOk
let window = createdWindow.value

doAssert window.rpc.register("async.request", startAsync)
doAssert window.rpc.register("never", neverCompletes)
doAssert window.rpc.registerSync("async.complete", completeAsync)
doAssert window.rpc.registerSync("test.asyncResolved", receiveAsyncResolved)
doAssert window.rpc.registerSync("test.timeout", receiveTimeout)
doAssert window.rpc.registerSync("test.failed", failFallback)

doAssert window.loadHtml("""
<!doctype html>
<html><body>
<script>
const receiveFromNative = window.nimino.__receiveFromNative;
window.nimino.__receiveFromNative = (message) => {
  receiveFromNative(message);
  if (message && message.id === "timeout-one" && message.ok === false) {
    window.nimino.notify("test.timeout", { code: message.error.code });
  }
};
window.nimino.invoke("async.request").then((value) => {
  if (value !== "async complete") throw new Error("unexpected async result");
  window.nimino.notify("test.asyncResolved");
});
setTimeout(() => window.nimino.notify("async.complete"), 25);
setTimeout(() => window.webkit.messageHandlers.nimino.postMessage(JSON.stringify({
  nimino: "rpc", kind: "request", id: "timeout-one", method: "never", timeoutMs: 40
})), 50);
setTimeout(() => window.nimino.notify("test.failed"), 3000);
</script>
</body></html>
""").isOk

doAssert testApp.run().isOk
doAssert asyncResolved
doAssert timeoutReceived
doAssert not fallbackTriggered
echo "Linux core async RPC smoke passed"
