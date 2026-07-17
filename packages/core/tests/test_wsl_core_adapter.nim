import std/[json, os]

import nimino_core

if paramCount() != 1:
  quit("usage: test-wsl-core-adapter <fake-host>", QuitFailure)

putEnv("NIMINO_WSL_HOST_EXE", paramStr(1))

var invoked = false
let created = newApp(id = "tech.asopi.wsl-core-test", name = "WSL core test")
doAssert created.isOk
let app = created.value
let window = app.newWindow(title = "WSL core test", width = 320, height = 200)
doAssert window.isOk
doAssert window.value.rpc.registerSync("system.version", proc(params: JsonNode): RpcResult =
  invoked = true
  rpcSuccess(%"1.0.0")
)
doAssert window.value.loadHtml("<main>WSL core protocol test</main>").isOk
doAssert app.run().isOk
doAssert invoked
