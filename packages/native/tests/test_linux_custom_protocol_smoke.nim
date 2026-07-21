## Independent Linux custom-protocol harness.
## Production protocol callbacks live in the native backend; this executable
## only drives a real WebKitGTK request and enforces a bounded cleanup path.
import std/strutils
import nimino_native

var app: NativeApp
var received = false
var protocolCalled = false
var ticks = 0

proc idle() =
  inc ticks
  if ticks > 300:
    discard app.quit()

proc messageReceived(message: string) =
  if message == "custom:hello from nimino":
    received = true
    discard app.quit()
  elif message.startsWith("custom-error:"):
    discard app.quit()

app = newNativeApp()
doAssert app.supports(customProtocol)
doAssert app.registerCustomProtocol("nimino", proc(
    request: NativeCustomProtocolRequest): NativeCustomProtocolResponse =
  doAssert request.methodName == "GET"
  doAssert request.url.startsWith("nimino://")
  protocolCalled = true
  NativeCustomProtocolResponse(statusCode: 200, mimeType: "text/html",
    body: "<script>window.webkit.messageHandlers.nimino.postMessage('custom:hello from nimino')</script>")).isOk
doAssert app.setIdleHandler(idle).isOk

let window = app.newWindow("Nimino custom protocol", 640, 480)
doAssert window.isOk
let view = window.value.newWebView()
doAssert view.isOk
doAssert view.value.onMessage(messageReceived).isOk
doAssert view.value.loadUrl("nimino://app/hello.txt").isOk

doAssert app.run().isOk
doAssert protocolCalled, "custom protocol callback was not invoked before harness timeout"
doAssert received, "custom protocol response was not observed before harness timeout"
echo "Linux custom protocol smoke passed"
