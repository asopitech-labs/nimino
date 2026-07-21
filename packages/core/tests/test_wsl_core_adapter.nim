import std/[asyncfutures, json, os]

import nimino_core

if paramCount() != 1:
  quit("usage: test-wsl-core-adapter <fake-host>", QuitFailure)

putEnv("NIMINO_WSL_HOST_EXE", paramStr(1))
putEnv("NIMINO_TEST_STRUCTURED_ERROR", "1")

var invoked = false
let created = newApp(id = "tech.asopi.wsl-core-test", name = "WSL core test")
doAssert created.isOk
let app = created.value
var customProtocolInvoked = false
let customProtocol = app.registerCustomProtocol("nimino", proc(
    request: CustomProtocolRequest): CustomProtocolResponse =
  customProtocolInvoked = true
  doAssert request.methodName == "GET"
  doAssert request.url == "nimino://app/hello.txt"
  doAssert request.path == "/hello.txt"
  CustomProtocolResponse(statusCode: 201,
    mimeType: "text/plain; charset=utf-8", body: "hello from WSL core"))
doAssert customProtocol.isOk
let window = app.newWindow(title = "WSL core test", width = 320, height = 200)
doAssert window.isOk
let structuredFailure = window.value.setTitle("structured error")
doAssert not structuredFailure.isOk
doAssert structuredFailure.failure.kind == osError
doAssert structuredFailure.failure.operation == "window.setTitle"
doAssert structuredFailure.failure.platformCode == 5
doAssert structuredFailure.failure.detail == "SetWindowTextW failed"
let browserData = window.value.clearWebViewProfileData({webViewCookies})
doAssert browserData.finished
let browserDataResult = browserData.read()
doAssert not browserDataResult.isOk
## The host advertises the relay.  Calling before app.run is still invalid:
## browser data must be cleared while the Windows host UI session is active.
doAssert browserDataResult.failure.kind == invalidState
doAssert window.value.rpc.registerSync("system.version", proc(params: JsonNode): RpcResult =
  invoked = true
  rpcSuccess(%"1.0.0")
)
doAssert window.value.loadHtml("<main>WSL core protocol test</main>").isOk
doAssert app.run().isOk
doAssert invoked
doAssert customProtocolInvoked
