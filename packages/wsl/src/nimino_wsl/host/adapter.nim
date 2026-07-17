## Host-side M1 command adapter.  It owns the native object table but not the
## stdio transport or the Windows UI thread.

import std/[asyncfutures, json, strutils, tables]

import nimino_native except success, successOf, failure, failureOf

import ../protocol/messages

type
  HostActionKind* = enum
    noHostAction
    startUiLoop
    deferredResponse
    shutdownHost

  HostAction* = object
    kind*: HostActionKind
    payload*: string
    evaluation*: Future[NativeResultOf[string]]

  HostAdapter* = ref object
    app*: NativeApp
    nextWindowId: uint64
    nextWebViewId: uint64
    windows: Table[uint64, NativeWindow]
    webViews: Table[uint64, NativeWebView]
    windowViewCounts: Table[uint64, int]
    uiStartRequested: bool

proc newHostAdapter*(): HostAdapter =
  HostAdapter(app: newNativeApp(), nextWindowId: 1, nextWebViewId: 1)

proc errorAction(detail: string): ProtocolResultOf[HostAction] {.inline.} =
  failureOf[HostAction](protocolError(invalidMessage, detail))

proc payloadObject(payload: string): ProtocolResultOf[JsonNode] =
  try:
    let node = parseJson(payload)
    if node.kind != JObject:
      return failureOf[JsonNode](protocolError(invalidMessage, "payload must be an object"))
    successOf(node)
  except CatchableError:
    failureOf[JsonNode](protocolError(invalidMessage, "payload is not valid JSON"))

proc requiredString(node: JsonNode; name: string): ProtocolResultOf[string] =
  if not node.hasKey(name) or node[name].kind != JString:
    return failureOf[string](protocolError(invalidMessage, name & " must be a string"))
  successOf(node[name].getStr())

proc requiredPositiveInt(node: JsonNode; name: string): ProtocolResultOf[int] =
  if not node.hasKey(name) or node[name].kind notin {JInt}:
    return failureOf[int](protocolError(invalidMessage, name & " must be an integer"))
  let value = node[name].getInt()
  if value <= 0 or value > high(int):
    return failureOf[int](protocolError(invalidMessage, name & " is out of range"))
  successOf(int(value))

proc requiredId(node: JsonNode; name: string): ProtocolResultOf[uint64] =
  let encoded = node.requiredString(name)
  if not encoded.isOk:
    return failureOf[uint64](encoded.failure)
  try:
    successOf(uint64(parseUInt(encoded.value)))
  except CatchableError:
    failureOf[uint64](protocolError(invalidMessage, name & " must be an unsigned integer string"))

proc encodedId(name: string; value: uint64): string =
  $(%*{name: $value})

proc nativeFailure(operation: string; nativeResult: NativeResult): ProtocolResultOf[HostAction] =
  failureOf[HostAction](protocolError(invalidMessage,
    operation & " failed: " & nativeResult.failure.operation))

proc nativeFailure[T](operation: string; nativeResult: NativeResultOf[T]): ProtocolResultOf[HostAction] =
  failureOf[HostAction](protocolError(invalidMessage,
    operation & " failed: " & nativeResult.failure.operation))

proc allWindowsHaveViews(adapter: HostAdapter): bool =
  for windowId, _ in adapter.windows:
    if adapter.windowViewCounts.getOrDefault(windowId) == 0:
      return false
  true

proc handleWindowCreate(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  if adapter.uiStartRequested:
    return errorAction("window creation is closed after the UI loop starts")
  let title = payload.requiredString("title")
  let width = payload.requiredPositiveInt("width")
  let height = payload.requiredPositiveInt("height")
  if not title.isOk:
    return failureOf[HostAction](title.failure)
  if not width.isOk:
    return failureOf[HostAction](width.failure)
  if not height.isOk:
    return failureOf[HostAction](height.failure)

  let created = adapter.app.newWindow(title.value, width.value, height.value)
  if not created.isOk:
    return nativeFailure("native.window.create", created)

  let windowId = adapter.nextWindowId
  inc adapter.nextWindowId
  adapter.windows[windowId] = created.value
  adapter.windowViewCounts[windowId] = 0
  successOf(HostAction(kind: noHostAction, payload: encodedId("windowId", windowId)))

proc handleWebViewCreate(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  if adapter.uiStartRequested:
    return errorAction("webview creation is closed after the UI loop starts")
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")

  let created = adapter.windows[windowId.value].newWebView()
  if not created.isOk:
    return nativeFailure("native.webview.create", created)

  let webViewId = adapter.nextWebViewId
  inc adapter.nextWebViewId
  adapter.webViews[webViewId] = created.value
  inc adapter.windowViewCounts[windowId.value]
  successOf(HostAction(kind: noHostAction, payload: encodedId("webViewId", webViewId)))

proc handleLoadContent(adapter: HostAdapter; payload: JsonNode;
                       contentField, operation: string): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  let content = payload.requiredString(contentField)
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not content.isOk:
    return failureOf[HostAction](content.failure)
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  if adapter.uiStartRequested:
    return errorAction("content loading is closed after the UI loop starts")
  if not adapter.allWindowsHaveViews():
    return errorAction("every window must have a WebView before the UI loop starts")

  let loaded =
    if operation == "native.webview.loadUrl":
      adapter.webViews[webViewId.value].loadUrl(content.value)
    else:
      adapter.webViews[webViewId.value].loadHtml(content.value)
  if not loaded.isOk:
    return nativeFailure(operation, loaded)

  adapter.uiStartRequested = true
  successOf(HostAction(kind: startUiLoop, payload: "{}"))

proc handleEvalJavaScript(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  let script = payload.requiredString("script")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not script.isOk:
    return failureOf[HostAction](script.failure)
  if not adapter.uiStartRequested:
    return errorAction("JavaScript evaluation requires the UI loop")
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")

  successOf(HostAction(
    kind: deferredResponse,
    evaluation: adapter.webViews[webViewId.value].evalJavaScript(script.value)
  ))

proc handleRequest*(adapter: HostAdapter; message: ProtocolMessage): ProtocolResultOf[HostAction] =
  if adapter.isNil:
    return errorAction("host adapter is unavailable")
  if message.kind != ProtocolMessageKind.request:
    return errorAction("expected request message")

  if message.methodName == "app.shutdown":
    return successOf(HostAction(kind: shutdownHost, payload: "{}"))

  let payload = message.payload.payloadObject()
  if not payload.isOk:
    return failureOf[HostAction](payload.failure)

  case message.methodName
  of "native.window.create":
    adapter.handleWindowCreate(payload.value)
  of "native.webview.create":
    adapter.handleWebViewCreate(payload.value)
  of "native.webview.loadUrl":
    adapter.handleLoadContent(payload.value, "url", message.methodName)
  of "native.webview.loadHtml":
    adapter.handleLoadContent(payload.value, "html", message.methodName)
  of "native.webview.evalJavaScript":
    adapter.handleEvalJavaScript(payload.value)
  else:
    errorAction("method is not allowed")
