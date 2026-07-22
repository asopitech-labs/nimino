## Host-side M1 command adapter.  It owns the native object table but not the
## stdio transport or the Windows UI thread.

import std/[asyncfutures, json, os, strutils, tables, uri]

import nimino_native except success, successOf, failure, failureOf

import ../protocol/messages

type
  HostWebMessage* = object
    webViewId*: uint64
    message*: string

  HostNativeError* = object
    webViewId*: uint64
    error*: NativeError

  HostNewWindowRequested* = object
    webViewId*: uint64
    url*: string

  HostNavigationCompleted* = object
    webViewId*: uint64
    url*: string
    succeeded*: bool

  HostWindowResized* = object
    windowId*: uint64
    width*: int
    height*: int

  HostFileDrop* = object
    windowId*: uint64
    paths*: seq[string]

  HostDesktopAction* = object
    kind*: string
    itemId*: uint32
    notificationId*: string

  HostNavigationStarting* = object
    webViewId*: uint64
    url*: string

  HostDownloadEvent* = object
    webViewId*: uint64
    url*: string
    state*: NativeDownloadState
    progress*: float

  NavigationRules = object
    allow: seq[string]
    deny: seq[string]
    configured: bool

  HostActionKind* = enum
    noHostAction
    startUiLoop
    deferredResponse
    deferredBrowsingDataClear
    deferredCookieQuery
    deferredCookieMutation
    deferredFileDialog
    shutdownHost
    restartHostForProfileReset

  HostAction* = object
    kind*: HostActionKind
    payload*: string
    evaluation*: Future[NativeResultOf[string]]
    browsingDataClear*: Future[NativeResult]
    cookieQuery*: Future[NativeResultOf[seq[NativeCookie]]]
    cookieMutation*: Future[NativeResult]
    fileDialog*: Future[NativeResultOf[seq[string]]]

  HostAdapter* = ref object
    app*: NativeApp
    nextWindowId: uint64
    nextWebViewId: uint64
    windows: Table[uint64, NativeWindow]
    webViews: Table[uint64, NativeWebView]
    webViewWindowIds: Table[uint64, uint64]
    windowViewCounts: Table[uint64, int]
    windowUserAgents: Table[uint64, string]
    windowProxyUrls: Table[uint64, string]
    windowIncognito: Table[uint64, bool]
    windowZoomFactors: Table[uint64, float]
    windowIgnoreCertificateErrors: Table[uint64, bool]
    uiStartRequested: bool
    pendingMessages: seq[HostWebMessage]
    pendingErrors: seq[HostNativeError]
    pendingNewWindowRequests: seq[HostNewWindowRequested]
    pendingNavigationStarts: seq[HostNavigationStarting]
    pendingNavigationCompletions: seq[HostNavigationCompleted]
    pendingDownloadEvents: seq[HostDownloadEvent]
    pendingWindowResized: seq[HostWindowResized]
    pendingFileDrops: seq[HostFileDrop]
    pendingWindowClosed: seq[uint64]
    pendingDesktopActions: seq[HostDesktopAction]
    ## Optional synchronous decision hook owned by the transport layer.
    ## Returning false is the fail-closed default.
    policyDecision*: proc(request: PolicyRequest): bool {.closure.}
    customProtocolDecision*: proc(request: PolicyRequest): NativeCustomProtocolResponse {.closure.}
    navigationDecisionHook*: proc(webViewId: uint64; url: string): bool {.closure.}
    navigationRules: Table[uint64, NavigationRules]

proc suggestedDownloadName(url: string): string =
  try:
    let parsed = parseUri(url)
    let parts = splitFile(decodeUrl(parsed.path))
    let name = parts.name & parts.ext
    if name.len > 0 and name notin [".", ".."]:
      return name
  except CatchableError:
    discard
  "download"

proc newHostAdapter*(appId = ""): HostAdapter =
  new(result)
  result.app = if appId.len > 0:
    newNativeApp(NativeAppOptions(appId: appId))
  else:
    newNativeApp()
  result.nextWindowId = 1
  result.nextWebViewId = 1
  let adapterPointer = cast[pointer](result)
  discard result.app.onNotificationActivated(proc(notificationId: string) =
    let owner = cast[HostAdapter](adapterPointer)
    if owner != nil:
      owner.pendingDesktopActions.add(HostDesktopAction(
        kind: "notification", notificationId: notificationId)))

proc forgetWindow(adapter: HostAdapter; windowId: uint64) =
  var ownedWebViews: seq[uint64]
  for webViewId, ownerWindowId in adapter.webViewWindowIds.pairs:
    if ownerWindowId == windowId:
      ownedWebViews.add(webViewId)
  for webViewId in ownedWebViews:
    adapter.webViews.del(webViewId)
    adapter.webViewWindowIds.del(webViewId)
    adapter.navigationRules.del(webViewId)
  adapter.windows.del(windowId)
  adapter.windowViewCounts.del(windowId)
  adapter.windowUserAgents.del(windowId)
  adapter.windowProxyUrls.del(windowId)
  adapter.windowIncognito.del(windowId)
  adapter.windowZoomFactors.del(windowId)
  adapter.windowIgnoreCertificateErrors.del(windowId)

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

proc requiredBool(node: JsonNode; name: string): ProtocolResultOf[bool] =
  if not node.hasKey(name) or node[name].kind != JBool:
    return failureOf[bool](protocolError(invalidMessage, name & " must be a boolean"))
  successOf(node[name].getBool())

proc optionalBool(node: JsonNode; name: string; fallback: bool): ProtocolResultOf[bool] =
  if not node.hasKey(name):
    return successOf(fallback)
  node.requiredBool(name)

proc requiredMenuItems(node: JsonNode; name: string): ProtocolResultOf[seq[NativeMenuItem]] =
  if not node.hasKey(name) or node[name].kind != JArray:
    return failureOf[seq[NativeMenuItem]](protocolError(invalidMessage,
      name & " must be an array"))
  if node[name].len == 0:
    return failureOf[seq[NativeMenuItem]](protocolError(invalidMessage,
      name & " must not be empty"))
  var items: seq[NativeMenuItem]
  for entry in node[name].items:
    if entry.kind != JObject or not entry.hasKey("id") or
        not entry.hasKey("title") or not entry.hasKey("enabled") or
        entry["id"].kind != JInt or entry["title"].kind != JString or
        entry["enabled"].kind != JBool:
      return failureOf[seq[NativeMenuItem]](protocolError(invalidMessage,
        name & " contains a malformed item"))
    let id = entry["id"].getInt()
    let title = entry["title"].getStr()
    if id <= 0 or id > int64(high(uint32)) or title.len == 0 or '\0' in title:
      return failureOf[seq[NativeMenuItem]](protocolError(invalidMessage,
        name & " contains an invalid item"))
    for existing in items:
      if existing.id == uint32(id):
        return failureOf[seq[NativeMenuItem]](protocolError(invalidMessage,
          name & " contains duplicate item IDs"))
    items.add(NativeMenuItem(id: uint32(id), title: title,
      enabled: entry["enabled"].getBool()))
  successOf(items)

proc requiredInteger(node: JsonNode; name: string): ProtocolResultOf[int] =
  if not node.hasKey(name) or node[name].kind != JInt:
    return failureOf[int](protocolError(invalidMessage, name & " must be an integer"))
  let value = node[name].getInt()
  if value < low(int) or value > high(int):
    return failureOf[int](protocolError(invalidMessage, name & " is out of range"))
  successOf(int(value))

proc safeWindowsPathComponent(value: string): bool =
  if value.len == 0 or value == "." or value == "..":
    return false
  if value[^1] in {'.', ' '}:
    return false
  let device = value.toUpperAscii()
  if device in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4",
                "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2",
                "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
    return false
  for ch in value:
    if ch in {'/', '\\', ':', '*', '?', '"', '<', '>', '|'} or ord(ch) < 32:
      return false
  true

proc requiredId(node: JsonNode; name: string): ProtocolResultOf[uint64] =
  let encoded = node.requiredString(name)
  if not encoded.isOk:
    return failureOf[uint64](encoded.failure)
  try:
    successOf(uint64(parseUInt(encoded.value)))
  except CatchableError:
    failureOf[uint64](protocolError(invalidMessage, name & " must be an unsigned integer string"))

proc ruleMatches(pattern, url: string): bool {.inline.} =
  if pattern.len == 0:
    return false
  if pattern.endsWith("**"):
    return url.startsWith(pattern[0 ..< pattern.len - 2])
  pattern == url

proc navigationAllowed(rules: NavigationRules; url: string): bool {.inline.} =
  if not rules.configured:
    return true
  for pattern in rules.deny:
    if ruleMatches(pattern, url):
      return false
  for pattern in rules.allow:
    if ruleMatches(pattern, url):
      return true
  false

proc navigationDecision*(adapter: HostAdapter; webViewId: uint64; url: string): bool =
  ## Host-local policy hook used by the native callback and its deterministic
  ## unit tests. It never performs IPC or waits for the WSL client.
  if adapter.isNil:
    return false
  adapter.navigationRules.getOrDefault(webViewId).navigationAllowed(url)

proc stringArray(node: JsonNode; name: string): ProtocolResultOf[seq[string]] =
  if not node.hasKey(name) or node[name].kind != JArray:
    return failureOf[seq[string]](protocolError(invalidMessage, name & " must be an array"))
  var values: seq[string]
  for item in node[name].items:
    if item.kind != JString or item.getStr().len == 0:
      return failureOf[seq[string]](protocolError(invalidMessage,
        name & " must contain non-empty strings"))
    values.add(item.getStr())
  successOf(values)

proc encodedId(name: string; value: uint64): string =
  $(%*{name: $value})

proc nativeFailure(operation: string; nativeResult: NativeResult): ProtocolResultOf[HostAction] =
  let native = nativeResult.failure
  failureOf[HostAction](protocolNativeError(invalidMessage,
    operation & " failed: " & native.operation,
    $native.kind, native.operation, native.detail,
    native.platformCode))

proc nativeFailure[T](operation: string; nativeResult: NativeResultOf[T]): ProtocolResultOf[HostAction] =
  let native = nativeResult.failure
  failureOf[HostAction](protocolNativeError(invalidMessage,
    operation & " failed: " & native.operation,
    $native.kind, native.operation, native.detail,
    native.platformCode))

proc allWindowsHaveViews(adapter: HostAdapter): bool =
  for windowId, _ in adapter.windows:
    if adapter.windowViewCounts.getOrDefault(windowId) == 0:
      return false
  true

proc handleWindowCreate(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let title = payload.requiredString("title")
  let width = payload.requiredPositiveInt("width")
  let height = payload.requiredPositiveInt("height")
  let appId = payload.requiredString("appId")
  let profile = payload.requiredString("profile")
  let fullscreen = payload.optionalBool("fullscreen", false)
  let maximized = payload.optionalBool("maximized", false)
  let alwaysOnTop = payload.optionalBool("alwaysOnTop", false)
  let hideWindowDecorations = payload.optionalBool("hideWindowDecorations", false)
  let userAgent = if payload.hasKey("userAgent") and payload["userAgent"].kind == JString:
      successOf(payload["userAgent"].getStr())
    else:
      successOf("")
  let proxyUrl = if payload.hasKey("proxyUrl") and payload["proxyUrl"].kind == JString:
      successOf(payload["proxyUrl"].getStr())
    elif payload.hasKey("proxyUrl"):
      failureOf[string](protocolError(invalidMessage, "proxyUrl must be a string"))
    else:
      successOf("")
  let incognito = payload.optionalBool("incognito", false)
  let ignoreCertificateErrors = payload.optionalBool("ignoreCertificateErrors", false)
  let zoomFactor = if payload.hasKey("zoomFactor"):
      if payload["zoomFactor"].kind in {JInt, JFloat}:
        let value = payload["zoomFactor"].getFloat()
        if value < 0.25 or value > 5.0:
          failureOf[float](protocolError(invalidMessage, "zoomFactor must be between 0.25 and 5.0"))
        else:
          successOf(value)
      else:
        failureOf[float](protocolError(invalidMessage, "zoomFactor must be a number"))
    else:
      successOf(1.0)
  let multiWindow = payload.optionalBool("multiWindow", true)
  let hideOnClose = payload.optionalBool("hideOnClose", false)
  let enableDragDrop = payload.optionalBool("enableDragDrop", false)
  if not title.isOk:
    return failureOf[HostAction](title.failure)
  if not width.isOk:
    return failureOf[HostAction](width.failure)
  if not height.isOk:
    return failureOf[HostAction](height.failure)
  if not appId.isOk:
    return failureOf[HostAction](appId.failure)
  if not profile.isOk:
    return failureOf[HostAction](profile.failure)
  if not fullscreen.isOk:
    return failureOf[HostAction](fullscreen.failure)
  if not maximized.isOk:
    return failureOf[HostAction](maximized.failure)
  if not alwaysOnTop.isOk:
    return failureOf[HostAction](alwaysOnTop.failure)
  if not hideWindowDecorations.isOk:
    return failureOf[HostAction](hideWindowDecorations.failure)
  if not userAgent.isOk:
    return failureOf[HostAction](userAgent.failure)
  if not proxyUrl.isOk:
    return failureOf[HostAction](proxyUrl.failure)
  if not incognito.isOk:
    return failureOf[HostAction](incognito.failure)
  if not ignoreCertificateErrors.isOk:
    return failureOf[HostAction](ignoreCertificateErrors.failure)
  if not zoomFactor.isOk:
    return failureOf[HostAction](zoomFactor.failure)
  if not multiWindow.isOk:
    return failureOf[HostAction](multiWindow.failure)
  if not hideOnClose.isOk:
    return failureOf[HostAction](hideOnClose.failure)
  if not enableDragDrop.isOk:
    return failureOf[HostAction](enableDragDrop.failure)
  if not safeWindowsPathComponent(appId.value) or not safeWindowsPathComponent(profile.value):
    return errorAction("appId/profile contains an unsafe path component")

  let localAppData = getEnv("LOCALAPPDATA")
  if localAppData.len == 0:
    return errorAction("LOCALAPPDATA is unavailable")
  let profilePath = localAppData / "Nimino" / "WSL" / appId.value / profile.value
  let created = adapter.app.newWindow(title.value, width.value, height.value, profilePath)
  if not created.isOk:
    return nativeFailure("native.window.create", created)

  if hideWindowDecorations.value:
    let configured = created.value.setDecorated(false)
    if not configured.isOk:
      discard created.value.close()
      return nativeFailure("native.window.setDecorated", configured)
  if fullscreen.value:
    let configured = created.value.setFullscreen(true)
    if not configured.isOk:
      discard created.value.close()
      return nativeFailure("native.window.setFullscreen", configured)
  if maximized.value:
    let configured = created.value.maximize()
    if not configured.isOk:
      discard created.value.close()
      return nativeFailure("native.window.maximize", configured)
  if alwaysOnTop.value:
    let configured = created.value.setAlwaysOnTop(true)
    if not configured.isOk:
      discard created.value.close()
      return nativeFailure("native.window.setAlwaysOnTop", configured)

  let windowId = adapter.nextWindowId
  inc adapter.nextWindowId
  let adapterPointer = cast[pointer](adapter)
  if enableDragDrop.value:
    let dropConfigured = created.value.onFileDrop(proc(paths: seq[string]) =
      let owner = cast[HostAdapter](adapterPointer)
      if owner != nil:
        owner.pendingFileDrops.add(HostFileDrop(windowId: windowId, paths: paths)))
    if not dropConfigured.isOk:
      discard created.value.close()
      return nativeFailure("native.window.onFileDrop", dropConfigured)
  let closeConfigured = created.value.onCloseRequested(proc(): bool =
    let owner = cast[HostAdapter](adapterPointer)
    if hideOnClose.value:
      discard created.value.hide()
      return false
    if owner.isNil or owner.policyDecision.isNil:
      return true
    owner.policyDecision(PolicyRequest(kind: closePolicy, windowId: windowId)))
  if not closeConfigured.isOk:
    return nativeFailure("native.window.onCloseRequested", closeConfigured)
  let closedConfigured = created.value.onClosed(proc() =
    let owner = cast[HostAdapter](adapterPointer)
    if not owner.isNil:
      owner.pendingWindowClosed.add(windowId))
  if not closedConfigured.isOk:
    return nativeFailure("native.window.onClosed", closedConfigured)
  let resizeConfigured = created.value.onResize(proc(width, height: int) =
    let owner = cast[HostAdapter](adapterPointer)
    if not owner.isNil:
      owner.pendingWindowResized.add(HostWindowResized(
        windowId: windowId, width: width, height: height)))
  if not resizeConfigured.isOk:
    return nativeFailure("native.window.onResize", resizeConfigured)
  adapter.windows[windowId] = created.value
  adapter.windowViewCounts[windowId] = 0
  adapter.windowUserAgents[windowId] = userAgent.value
  adapter.windowProxyUrls[windowId] = proxyUrl.value
  adapter.windowIncognito[windowId] = incognito.value
  adapter.windowZoomFactors[windowId] = zoomFactor.value
  adapter.windowIgnoreCertificateErrors[windowId] = ignoreCertificateErrors.value
  successOf(HostAction(kind: noHostAction, payload: encodedId("windowId", windowId)))

proc handleWindowSetTitle(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  let title = payload.requiredString("title")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not title.isOk:
    return failureOf[HostAction](title.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let updated = adapter.windows[windowId.value].setTitle(title.value)
  if not updated.isOk:
    return nativeFailure("native.window.setTitle", updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowSetSize(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  let width = payload.requiredPositiveInt("width")
  let height = payload.requiredPositiveInt("height")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not width.isOk:
    return failureOf[HostAction](width.failure)
  if not height.isOk:
    return failureOf[HostAction](height.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let updated = adapter.windows[windowId.value].setSize(width.value, height.value)
  if not updated.isOk:
    return nativeFailure("native.window.setSize", updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowClose(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let closed = adapter.windows[windowId.value].close()
  if not closed.isOk:
    return nativeFailure("native.window.close", closed)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc closeAllWindows*(adapter: HostAdapter): bool =
  ## Explicitly close every managed window before quitting the native app.
  ## This mirrors Tauri's managed WebviewWindow lifecycle and also ensures
  ## popup windows receive WM_CLOSE instead of relying on process termination.
  result = true
  var managedWindows: seq[NativeWindow]
  for window in adapter.windows.values:
    managedWindows.add(window)
  for window in managedWindows:
    let closed = window.close()
    if not closed.isOk and closed.failure.kind != invalidState:
      result = false

proc handleWindowVisibility(adapter: HostAdapter; payload: JsonNode; visible: bool): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let updated = if visible: adapter.windows[windowId.value].show()
                else: adapter.windows[windowId.value].hide()
  if not updated.isOk:
    return nativeFailure(if visible: "native.window.show" else: "native.window.hide", updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowState(adapter: HostAdapter; payload: JsonNode; operation: string): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let updated = case operation
    of "minimize": adapter.windows[windowId.value].minimize()
    of "maximize": adapter.windows[windowId.value].maximize()
    else: adapter.windows[windowId.value].restore()
  if not updated.isOk:
    return nativeFailure("native.window." & operation, updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowSetFullscreen(adapter: HostAdapter;
                               payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  let enabled = payload.requiredBool("enabled")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not enabled.isOk:
    return failureOf[HostAction](enabled.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let updated = adapter.windows[windowId.value].setFullscreen(enabled.value)
  if not updated.isOk:
    return nativeFailure("native.window.setFullscreen", updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowSetAlwaysOnTop(adapter: HostAdapter;
                                payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  let enabled = payload.requiredBool("enabled")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not enabled.isOk:
    return failureOf[HostAction](enabled.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let updated = adapter.windows[windowId.value].setAlwaysOnTop(enabled.value)
  if not updated.isOk:
    return nativeFailure("native.window.setAlwaysOnTop", updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowSetResizable(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let value = payload.requiredBool("resizable")
  if not value.isOk:
    return failureOf[HostAction](value.failure)
  let updated = adapter.windows[windowId.value].setResizable(value.value)
  if not updated.isOk:
    return nativeFailure("native.window.setResizable", updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowSetPosition(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk: return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value): return errorAction("unknown windowId")
  let x = payload.requiredInteger("x")
  let y = payload.requiredInteger("y")
  if not x.isOk: return failureOf[HostAction](x.failure)
  if not y.isOk: return failureOf[HostAction](y.failure)
  let updated = adapter.windows[windowId.value].setPosition(x.value, y.value)
  if not updated.isOk: return nativeFailure("native.window.setPosition", updated)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowFocus(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk: return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value): return errorAction("unknown windowId")
  let focused = adapter.windows[windowId.value].focus()
  if not focused.isOk: return nativeFailure("native.window.focus", focused)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc clearDirectoryContents(path: string): bool =
  if not dirExists(path):
    return true
  result = true
  for kind, entry in walkDir(path):
    case kind
    of pcFile, pcLinkToFile:
      try: removeFile(entry)
      except OSError: result = false
    of pcDir:
      if not clearDirectoryContents(entry): result = false
      try: removeDir(entry)
      except OSError: result = false
    else:
      discard

proc handleWindowClearCache(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk: return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value): return errorAction("unknown windowId")
  if adapter.windows[windowId.value].profilePath.len == 0:
    return errorAction("window profile path is unavailable")
  errorAction("WebView2 engine cache clearing is unsupported; ICoreWebView2Profile2 ClearBrowsingData is not implemented")

proc handleWindowClearDownloads(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk: return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value): return errorAction("unknown windowId")
  if adapter.windows[windowId.value].profilePath.len == 0:
    return errorAction("window profile path is unavailable")
  let downloads = adapter.windows[windowId.value].profilePath / "webview2" /
    "Default" / "Downloads"
  if not clearDirectoryContents(downloads):
    return errorAction("unable to clear WebView2 downloads")
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWindowOpenFileDialog(adapter: HostAdapter;
                                payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  let title = payload.requiredString("title")
  let save = payload.requiredBool("save")
  let multiple = payload.requiredBool("multiple")
  let suggestedName = payload.requiredString("suggestedName")
  if not title.isOk: return failureOf[HostAction](title.failure)
  if not save.isOk: return failureOf[HostAction](save.failure)
  if not multiple.isOk: return failureOf[HostAction](multiple.failure)
  if not suggestedName.isOk: return failureOf[HostAction](suggestedName.failure)
  if title.value.len == 0:
    return errorAction("title must not be empty")
  if multiple.value and save.value:
    return errorAction("save dialogs cannot select multiple files")
  let opened = adapter.windows[windowId.value].openFileDialog(NativeFileDialogOptions(
    title: title.value,
    save: save.value,
    multiple: multiple.value,
    suggestedName: suggestedName.value
  ))
  successOf(HostAction(kind: deferredFileDialog, fileDialog: opened))

proc handleActiveProfileReset(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  ## WebView2 owns files below its user-data folder while a controller is
  ## running.  Do not recursively delete an active profile: the official
  ## lifecycle requires the session and browser processes to end first.
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")
  errorAction("active WebView2 profile reset is unsupported; request app.restartForProfileReset")

proc handleRestartForProfileReset(adapter: HostAdapter): ProtocolResultOf[HostAction] =
  ## This operation deliberately does not delete profile files.  It creates a
  ## restart boundary so the next host lifecycle can reset a profile only after
  ## the previous WebView2 session and its browser processes have exited.
  if not adapter.uiStartRequested:
    return errorAction("profile reset restart requires an active UI session")
  successOf(HostAction(kind: restartHostForProfileReset,
    payload: $(%*{"restartRequired": true, "reason": "profileReset"})))

proc handleWebViewCreate(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let windowId = payload.requiredId("windowId")
  if not windowId.isOk:
    return failureOf[HostAction](windowId.failure)
  if not adapter.windows.hasKey(windowId.value):
    return errorAction("unknown windowId")

  let created = adapter.windows[windowId.value].newWebView(
    userAgent = adapter.windowUserAgents.getOrDefault(windowId.value, ""),
    proxyUrl = adapter.windowProxyUrls.getOrDefault(windowId.value, ""),
    incognito = adapter.windowIncognito.getOrDefault(windowId.value, false),
    ignoreCertificateErrors = adapter.windowIgnoreCertificateErrors.getOrDefault(windowId.value, false))
  if not created.isOk:
    return nativeFailure("native.webview.create", created)
  let zoomed = created.value.setZoom(adapter.windowZoomFactors.getOrDefault(windowId.value, 1.0))
  if not zoomed.isOk:
    return nativeFailure("native.webview.setZoom", zoomed)

  let webViewId = adapter.nextWebViewId
  inc adapter.nextWebViewId
  let adapterPointer = cast[pointer](adapter)
  let configured = created.value.onMessage(proc(message: string) =
    let owner = cast[HostAdapter](adapterPointer)
    if owner != nil:
      owner.pendingMessages.add(HostWebMessage(webViewId: webViewId, message: message))
  )
  if not configured.isOk:
    return nativeFailure("native.webview.onMessage", configured)
  let errorConfigured = created.value.onError(proc(error: NativeError) =
    let owner = cast[HostAdapter](adapterPointer)
    if owner != nil:
      owner.pendingErrors.add(HostNativeError(webViewId: webViewId, error: error))
  )
  if not errorConfigured.isOk:
    return nativeFailure("native.webview.onError", errorConfigured)
  let newWindowConfigured = created.value.onNewWindowRequested(proc(url: string): bool =
    let owner = cast[HostAdapter](adapterPointer)
    if owner != nil:
      owner.pendingNewWindowRequests.add(HostNewWindowRequested(
        webViewId: webViewId,
        url: url
      ))
    ## WSL cannot synchronously await the client policy while inside the
    ## native callback. Keep the request fail-closed and resolve it through
    ## the authenticated event stream.
    true
  )
  if not newWindowConfigured.isOk:
    return nativeFailure("native.webview.onNewWindowRequested", newWindowConfigured)
  let navigationStartingConfigured = created.value.onNavigationStarting(
    proc(url: string): bool =
      let owner = cast[HostAdapter](adapterPointer)
      if owner != nil:
        owner.pendingNavigationStarts.add(HostNavigationStarting(
          webViewId: webViewId,
          url: url
        ))
        if not owner.navigationDecisionHook.isNil:
          return owner.navigationDecisionHook(webViewId, url)
        return owner.navigationDecision(webViewId, url)
      true
  )
  if not navigationStartingConfigured.isOk:
    return nativeFailure("native.webview.onNavigationStarting", navigationStartingConfigured)
  let navigationConfigured = created.value.onNavigationCompleted(
    proc(url: string; succeeded: bool) =
      let owner = cast[HostAdapter](adapterPointer)
      if owner != nil:
        owner.pendingNavigationCompletions.add(HostNavigationCompleted(
          webViewId: webViewId,
          url: url,
          succeeded: succeeded
        ))
  )
  if not navigationConfigured.isOk:
    return nativeFailure("native.webview.onNavigationCompleted", navigationConfigured)
  let permissionConfigured = created.value.onPermissionRequested(proc(kind, url: string): bool =
    let owner = cast[HostAdapter](adapterPointer)
    let request = PolicyRequest(kind: permissionPolicy, webViewId: webViewId,
      permissionKind: kind, url: url)
    if owner != nil:
      if not owner.policyDecision.isNil:
        return owner.policyDecision(request)
    false
  )
  if not permissionConfigured.isOk:
    return nativeFailure("native.webview.onPermissionRequested", permissionConfigured)
  let downloadConfigured = created.value.onDownloadStarting(proc(url: string): bool =
    let owner = cast[HostAdapter](adapterPointer)
    let request = PolicyRequest(kind: downloadPolicy, webViewId: webViewId,
      url: url, suggestedName: suggestedDownloadName(url))
    if owner != nil:
      if not owner.policyDecision.isNil:
        return owner.policyDecision(request)
    false
  )
  if not downloadConfigured.isOk:
    return nativeFailure("native.webview.onDownloadStarting", downloadConfigured)
  let downloadPathConfigured = created.value.onDownloadPath(proc(url: string): string =
    let owner = cast[HostAdapter](adapterPointer)
    if owner.isNil or not owner.windows.hasKey(windowId.value):
      return ""
    let window = owner.windows[windowId.value]
    let destinationDirectory = window.profilePath / "downloads"
    try:
      createDir(destinationDirectory)
      destinationDirectory / suggestedDownloadName(url)
    except CatchableError:
      ""
  )
  if not downloadPathConfigured.isOk:
    return nativeFailure("native.webview.onDownloadPath", downloadPathConfigured)
  let downloadEventsConfigured = created.value.onDownloadEvent(
    proc(url: string; state: NativeDownloadState; progress: float) =
      let owner = cast[HostAdapter](adapterPointer)
      if owner != nil:
        owner.pendingDownloadEvents.add(HostDownloadEvent(
          webViewId: webViewId, url: url, state: state, progress: progress))
  )
  if not downloadEventsConfigured.isOk:
    return nativeFailure("native.webview.onDownloadEvent", downloadEventsConfigured)
  adapter.webViews[webViewId] = created.value
  adapter.webViewWindowIds[webViewId] = windowId.value
  inc adapter.windowViewCounts[windowId.value]
  successOf(HostAction(kind: noHostAction, payload: encodedId("webViewId", webViewId)))

proc handleWebViewClose(adapter: HostAdapter; payload: JsonNode): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  let windowId = adapter.webViewWindowIds[webViewId.value]
  let closed = adapter.webViews[webViewId.value].close()
  if not closed.isOk:
    return nativeFailure("native.webview.close", closed)
  adapter.webViews.del(webViewId.value)
  adapter.webViewWindowIds.del(webViewId.value)
  adapter.navigationRules.del(webViewId.value)
  if adapter.windowViewCounts.hasKey(windowId):
    dec adapter.windowViewCounts[windowId]
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWebViewSetDocumentStartScript(adapter: HostAdapter;
                                          payload: JsonNode): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  let script = payload.requiredString("script")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not script.isOk:
    return failureOf[HostAction](script.failure)
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  let configured = adapter.webViews[webViewId.value].setDocumentStartScript(script.value)
  if not configured.isOk:
    return nativeFailure("native.webview.setDocumentStartScript", configured)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWebViewSetDevToolsEnabled(adapter: HostAdapter;
                                     payload: JsonNode): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  let enabled = payload.requiredBool("enabled")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not enabled.isOk:
    return failureOf[HostAction](enabled.failure)
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  let configured = adapter.webViews[webViewId.value].setDevToolsEnabled(enabled.value)
  if not configured.isOk:
    return nativeFailure("native.webview.setDevToolsEnabled", configured)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleWebViewSetNavigationRules(adapter: HostAdapter;
                                     payload: JsonNode): ProtocolResultOf[HostAction] =
  if adapter.uiStartRequested:
    return errorAction("navigation rules are closed after the UI loop starts")
  let webViewId = payload.requiredId("webViewId")
  let allow = payload.stringArray("allow")
  let deny = payload.stringArray("deny")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not allow.isOk:
    return failureOf[HostAction](allow.failure)
  if not deny.isOk:
    return failureOf[HostAction](deny.failure)
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  adapter.navigationRules[webViewId.value] = NavigationRules(
    allow: allow.value, deny: deny.value, configured: true)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc takeMessages*(adapter: HostAdapter): seq[HostWebMessage] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingMessages
  adapter.pendingMessages.setLen(0)

proc takeErrors*(adapter: HostAdapter): seq[HostNativeError] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingErrors
  adapter.pendingErrors.setLen(0)

proc takeNewWindowRequests*(adapter: HostAdapter): seq[HostNewWindowRequested] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingNewWindowRequests
  adapter.pendingNewWindowRequests.setLen(0)

proc takeNavigationStarts*(adapter: HostAdapter): seq[HostNavigationStarting] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingNavigationStarts
  adapter.pendingNavigationStarts.setLen(0)

proc takeNavigationCompletions*(adapter: HostAdapter): seq[HostNavigationCompleted] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingNavigationCompletions
  adapter.pendingNavigationCompletions.setLen(0)

proc takeDownloadEvents*(adapter: HostAdapter): seq[HostDownloadEvent] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingDownloadEvents
  adapter.pendingDownloadEvents.setLen(0)

proc takeWindowClosed*(adapter: HostAdapter): seq[uint64] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingWindowClosed
  adapter.pendingWindowClosed.setLen(0)
  ## Closed callbacks run inside the native object's teardown stack.  Dropping
  ## the final managed references there can free ARC objects while their
  ## callback is still executing.  Reap ownership only after control returns
  ## to the host event flush.
  for windowId in result:
    adapter.forgetWindow(windowId)

proc takeWindowResized*(adapter: HostAdapter): seq[HostWindowResized] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingWindowResized
  adapter.pendingWindowResized.setLen(0)

proc takeFileDrops*(adapter: HostAdapter): seq[HostFileDrop] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingFileDrops
  adapter.pendingFileDrops.setLen(0)

proc takeDesktopActions*(adapter: HostAdapter): seq[HostDesktopAction] =
  if adapter.isNil:
    return @[]
  result = adapter.pendingDesktopActions
  adapter.pendingDesktopActions.setLen(0)


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
  if not adapter.allWindowsHaveViews():
    return errorAction("every window must have a WebView before the UI loop starts")

  let loaded =
    if operation == "native.webview.loadUrl":
      adapter.webViews[webViewId.value].loadUrl(content.value)
    else:
      adapter.webViews[webViewId.value].loadHtml(content.value)
  if not loaded.isOk:
    return nativeFailure(operation, loaded)

  if adapter.uiStartRequested:
    return successOf(HostAction(kind: noHostAction, payload: "{}"))
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

proc browsingDataKinds(payload: JsonNode): ProtocolResultOf[set[NativeBrowsingDataKind]] =
  let values = payload.stringArray("kinds")
  if not values.isOk:
    return failureOf[set[NativeBrowsingDataKind]](values.failure)
  if values.value.len == 0:
    return failureOf[set[NativeBrowsingDataKind]](protocolError(invalidMessage,
      "kinds must contain at least one value"))

  var kinds: set[NativeBrowsingDataKind]
  for value in values.value:
    let kind = case value
      of "cookies": nativeBrowsingCookies
      of "localStorage": nativeBrowsingLocalStorage
      of "cache": nativeBrowsingCache
      else:
        return failureOf[set[NativeBrowsingDataKind]](protocolError(invalidMessage,
          "kinds contains an unsupported browser data kind"))
    if kind in kinds:
      return failureOf[set[NativeBrowsingDataKind]](protocolError(invalidMessage,
        "kinds must not contain duplicates"))
    kinds.incl(kind)
  successOf(kinds)

proc handleClearBrowsingData(adapter: HostAdapter;
                             payload: JsonNode): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not adapter.uiStartRequested:
    return errorAction("browser data clearing requires the UI loop")
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  let kinds = payload.browsingDataKinds()
  if not kinds.isOk:
    return failureOf[HostAction](kinds.failure)

  ## Keep every native completion on the host UI loop.  Even a synchronously
  ## failed/finished Future follows this deferred path, so the client receives
  ## a single structured completion schema for success and unsupported cases.
  successOf(HostAction(
    kind: deferredBrowsingDataClear,
    browsingDataClear: adapter.webViews[webViewId.value].clearBrowsingData(kinds.value)
  ))

proc requiredNativeCookie(payload: JsonNode): ProtocolResultOf[NativeCookie] =
  for name in ["name", "value", "domain", "path"]:
    if not payload.hasKey(name) or payload[name].kind != JString:
      return failureOf[NativeCookie](protocolError(invalidMessage,
        "cookie." & name & " must be a string"))
  for name in ["secure", "httpOnly"]:
    if not payload.hasKey(name) or payload[name].kind != JBool:
      return failureOf[NativeCookie](protocolError(invalidMessage,
        "cookie." & name & " must be a boolean"))
  if not payload.hasKey("expires") or payload["expires"].kind != JInt:
    return failureOf[NativeCookie](protocolError(invalidMessage,
      "cookie.expires must be an integer"))
  let expires = payload["expires"].getBiggestInt()
  successOf(NativeCookie(
    name: payload["name"].getStr(),
    value: payload["value"].getStr(),
    domain: payload["domain"].getStr(),
    path: payload["path"].getStr(),
    secure: payload["secure"].getBool(),
    httpOnly: payload["httpOnly"].getBool(),
    expires: int64(expires)
  ))

proc handleGetCookies(adapter: HostAdapter;
                      payload: JsonNode): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  let url = payload.requiredString("url")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not url.isOk:
    return failureOf[HostAction](url.failure)
  if not adapter.uiStartRequested:
    return errorAction("cookie queries require the UI loop")
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  successOf(HostAction(kind: deferredCookieQuery,
    cookieQuery: adapter.webViews[webViewId.value].getCookies(url.value)))

proc handleMutateCookie(adapter: HostAdapter; payload: JsonNode;
                        delete: bool): ProtocolResultOf[HostAction] =
  let webViewId = payload.requiredId("webViewId")
  if not webViewId.isOk:
    return failureOf[HostAction](webViewId.failure)
  if not payload.hasKey("cookie") or payload["cookie"].kind != JObject:
    return errorAction("cookie must be an object")
  let cookie = payload["cookie"].requiredNativeCookie()
  if not cookie.isOk:
    return failureOf[HostAction](cookie.failure)
  if not adapter.uiStartRequested:
    return errorAction("cookie mutation requires the UI loop")
  if not adapter.webViews.hasKey(webViewId.value):
    return errorAction("unknown webViewId")
  let changed = if delete:
      adapter.webViews[webViewId.value].deleteCookie(cookie.value)
    else:
      adapter.webViews[webViewId.value].setCookie(cookie.value)
  successOf(HostAction(kind: deferredCookieMutation,
    cookieMutation: changed))

proc handleConfigureNativeMenu(adapter: HostAdapter;
                               payload: JsonNode): ProtocolResultOf[HostAction] =
  if adapter.uiStartRequested:
    return errorAction("native menu must be configured before the UI loop starts")
  let title = payload.requiredString("title")
  let items = payload.requiredMenuItems("items")
  if not title.isOk:
    return failureOf[HostAction](title.failure)
  if not items.isOk:
    return failureOf[HostAction](items.failure)
  let adapterPointer = cast[pointer](adapter)
  let configured = adapter.app.configureNativeMenu(title.value, items.value,
    proc(itemId: uint32) =
      let owner = cast[HostAdapter](adapterPointer)
      if owner != nil:
        owner.pendingDesktopActions.add(HostDesktopAction(kind: "menu", itemId: itemId)))
  if not configured.isOk:
    return nativeFailure("app.configureNativeMenu", configured)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleConfigureSystemTray(adapter: HostAdapter;
                               payload: JsonNode): ProtocolResultOf[HostAction] =
  if adapter.uiStartRequested:
    return errorAction("system tray must be configured before the UI loop starts")
  let items = payload.requiredMenuItems("items")
  if not items.isOk:
    return failureOf[HostAction](items.failure)
  let adapterPointer = cast[pointer](adapter)
  let configured = adapter.app.configureSystemTray(items.value,
    proc(itemId: uint32) =
      let owner = cast[HostAdapter](adapterPointer)
      if owner != nil:
        owner.pendingDesktopActions.add(HostDesktopAction(kind: "tray", itemId: itemId)))
  if not configured.isOk:
    return nativeFailure("app.configureSystemTray", configured)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleSendNativeNotification(adapter: HostAdapter;
                                  payload: JsonNode): ProtocolResultOf[HostAction] =
  let id = payload.requiredString("id")
  let title = payload.requiredString("title")
  let body = payload.requiredString("body")
  if not id.isOk:
    return failureOf[HostAction](id.failure)
  if not title.isOk:
    return failureOf[HostAction](title.failure)
  if not body.isOk:
    return failureOf[HostAction](body.failure)
  let sent = adapter.app.sendNativeNotification(NativeNotification(
    id: id.value, title: title.value, body: body.value))
  if not sent.isOk:
    return nativeFailure("app.sendNativeNotification", sent)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleRegisterCustomProtocol(adapter: HostAdapter;
                                  payload: JsonNode): ProtocolResultOf[HostAction] =
  let scheme = payload.requiredString("scheme")
  if not scheme.isOk:
    return failureOf[HostAction](scheme.failure)
  if adapter.customProtocolDecision.isNil:
    return errorAction("custom protocol decision relay is unavailable")
  let registered = adapter.app.registerCustomProtocol(scheme.value,
    proc(request: NativeCustomProtocolRequest): NativeCustomProtocolResponse =
      let owner = adapter
      let decision = owner.customProtocolDecision(PolicyRequest(
        kind: customProtocolPolicy,
        url: request.url,
        permissionKind: "",
        methodName: request.methodName,
        path: request.path))
      decision)
  if not registered.isOk:
    return nativeFailure("app.registerCustomProtocol", registered)
  successOf(HostAction(kind: noHostAction, payload: "{}"))

proc handleCapabilities(adapter: HostAdapter): ProtocolResultOf[HostAction] =
  var capabilities = newJArray()
  for capability in Capability:
    if adapter.app.supports(capability):
      capabilities.add(%($capability))
  successOf(HostAction(kind: noHostAction,
    payload: $(%*{"capabilities": capabilities})))

proc handleRequest*(adapter: HostAdapter; message: ProtocolMessage): ProtocolResultOf[HostAction] =
  if adapter.isNil:
    return errorAction("host adapter is unavailable")
  if message.kind != ProtocolMessageKind.request:
    return errorAction("expected request message")

  if message.methodName == "app.shutdown":
    return successOf(HostAction(kind: shutdownHost, payload: "{}"))
  if message.methodName == "app.restartForProfileReset":
    return adapter.handleRestartForProfileReset()
  if message.methodName == "app.capabilities":
    return adapter.handleCapabilities()

  let payload = message.payload.payloadObject()
  if not payload.isOk:
    return failureOf[HostAction](payload.failure)

  case message.methodName
  of "app.configureNativeMenu":
    adapter.handleConfigureNativeMenu(payload.value)
  of "app.configureSystemTray":
    adapter.handleConfigureSystemTray(payload.value)
  of "app.sendNativeNotification":
    adapter.handleSendNativeNotification(payload.value)
  of "app.registerCustomProtocol":
    adapter.handleRegisterCustomProtocol(payload.value)
  of "native.window.create":
    adapter.handleWindowCreate(payload.value)
  of "native.window.setTitle":
    adapter.handleWindowSetTitle(payload.value)
  of "native.window.setSize":
    adapter.handleWindowSetSize(payload.value)
  of "native.window.close":
    adapter.handleWindowClose(payload.value)
  of "native.window.show":
    adapter.handleWindowVisibility(payload.value, true)
  of "native.window.hide":
    adapter.handleWindowVisibility(payload.value, false)
  of "native.window.minimize":
    adapter.handleWindowState(payload.value, "minimize")
  of "native.window.maximize":
    adapter.handleWindowState(payload.value, "maximize")
  of "native.window.setFullscreen":
    adapter.handleWindowSetFullscreen(payload.value)
  of "native.window.setAlwaysOnTop":
    adapter.handleWindowSetAlwaysOnTop(payload.value)
  of "native.window.restore":
    adapter.handleWindowState(payload.value, "restore")
  of "native.window.setResizable":
    adapter.handleWindowSetResizable(payload.value)
  of "native.window.setPosition":
    adapter.handleWindowSetPosition(payload.value)
  of "native.window.clearCache":
    adapter.handleWindowClearCache(payload.value)
  of "native.window.clearDownloads":
    adapter.handleWindowClearDownloads(payload.value)
  of "native.window.openFileDialog":
    adapter.handleWindowOpenFileDialog(payload.value)
  of "native.window.resetProfile":
    adapter.handleActiveProfileReset(payload.value)
  of "native.window.focus":
    adapter.handleWindowFocus(payload.value)
  of "native.webview.create":
    adapter.handleWebViewCreate(payload.value)
  of "native.webview.close":
    adapter.handleWebViewClose(payload.value)
  of "native.webview.setDocumentStartScript":
    adapter.handleWebViewSetDocumentStartScript(payload.value)
  of "native.webview.setDevToolsEnabled":
    adapter.handleWebViewSetDevToolsEnabled(payload.value)
  of "native.webview.setNavigationRules":
    adapter.handleWebViewSetNavigationRules(payload.value)
  of "native.webview.loadUrl":
    adapter.handleLoadContent(payload.value, "url", message.methodName)
  of "native.webview.loadHtml":
    adapter.handleLoadContent(payload.value, "html", message.methodName)
  of "native.webview.evalJavaScript":
    adapter.handleEvalJavaScript(payload.value)
  of "native.webview.clearBrowsingData":
    adapter.handleClearBrowsingData(payload.value)
  of "native.webview.getCookies":
    adapter.handleGetCookies(payload.value)
  of "native.webview.setCookie":
    adapter.handleMutateCookie(payload.value, false)
  of "native.webview.deleteCookie":
    adapter.handleMutateCookie(payload.value, true)
  else:
    errorAction("method is not allowed")
