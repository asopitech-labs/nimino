import std/[asyncfutures, json, os]

import nimino_core

if paramCount() != 1:
  quit("usage: test-wsl-core-async-adapter <fake-host>", QuitFailure)

putEnv("NIMINO_WSL_HOST_EXE", paramStr(1))

var pendingAsync: Future[RpcResult]
var asyncRequested = false
var asyncCompleted = false
var neverRequested = false

proc startAsync(params: JsonNode): Future[RpcResult] =
  asyncRequested = true
  pendingAsync = newFuture[RpcResult]("nimino.wsl.async-adapter")
  pendingAsync

proc completeAsync(params: JsonNode): RpcResult =
  doAssert pendingAsync != nil
  doAssert not pendingAsync.finished
  asyncCompleted = true
  pendingAsync.complete(rpcSuccess(%"complete"))
  rpcSuccess(newJNull())

proc neverCompletes(params: JsonNode): Future[RpcResult] =
  neverRequested = true
  newFuture[RpcResult]("nimino.wsl.timeout-adapter")

let created = newApp(id = "tech.asopi.wsl-core-async-test", name = "WSL core async test")
doAssert created.isOk
let app = created.value
let createdWindow = app.newWindow(title = "WSL core async test", width = 320, height = 200)
doAssert createdWindow.isOk
let window = createdWindow.value

doAssert window.rpc.register("async.request", startAsync)
doAssert window.rpc.registerSync("async.complete", completeAsync)
doAssert window.rpc.register("never", neverCompletes)
doAssert window.loadHtml("<main>WSL async adapter test</main>").isOk

doAssert app.run().isOk
doAssert asyncRequested
doAssert asyncCompleted
doAssert neverRequested
