## Generic Nimino host used by packaged bundles and online builds.
## It intentionally depends on nimino-core only; packaging remains in nimino-pack.

import std/[json, os, sequtils, strutils, uri]

import nimino_core

proc fail(message: string; code = QuitFailure) {.noreturn.} =
  stderr.writeLine("nimino-host: " & message)
  quit(code)

proc requiredString(node: JsonNode; key: string): string =
  if node.kind != JObject or not node.hasKey(key) or node[key].kind != JString:
    fail("manifest field '" & key & "' must be a string")
  result = node[key].getStr()
  if result.len == 0:
    fail("manifest field '" & key & "' must not be empty")

proc optionalString(node: JsonNode; key, fallback: string): string =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JString:
    return node[key].getStr()
  fallback

proc stringArray(node: JsonNode; key: string): seq[string] =
  if node.kind != JObject or not node.hasKey(key):
    return @[]
  if node[key].kind != JArray:
    fail("manifest field '" & key & "' must be an array")
  for item in node[key].items:
    if item.kind != JString or item.getStr().len == 0:
      fail("manifest field '" & key & "' contains a non-string value")
    result.add(item.getStr())

proc integer(node: JsonNode; key: string; fallback: int): int =
  if node.kind == JObject and node.hasKey(key) and node[key].kind == JInt:
    let value = node[key].getInt()
    if value <= 0 or value > 10_000:
      fail("manifest window value '" & key & "' is out of range")
    return value
  fallback

proc boolean(node: JsonNode; key: string; fallback: bool): bool =
  if node.kind == JObject and node.hasKey(key):
    if node[key].kind != JBool:
      fail("manifest field '" & key & "' must be a boolean")
    return node[key].getBool()
  fallback

proc readInjection(root: string; names: seq[string]): seq[string] =
  for name in names:
    if name.contains('/') or name.contains('\\') or name in [".", ".."]:
      fail("injection path escapes the package root: " & name)
    let path = root / name
    if not fileExists(path):
      fail("injection file is missing: " & name)
    try:
      result.add(readFile(path))
    except OSError:
      fail("injection file cannot be read: " & name)

proc main() =
  ## Toast activation of a terminated Win32 process is forwarded by the
  ## generated launcher as an additional argument.  Keep the manifest option
  ## mandatory, but accept and preserve the activation payload so the native
  ## layer can deliver it through `onNotificationActivated`.
  var manifestArgument = ""
  var activationArguments: seq[string]
  var skipActivationPayload = false
  var index = 1
  while index <= paramCount():
    let argument = paramStr(index)
    if argument == "--manifest":
      skipActivationPayload = false
      if index == paramCount():
        fail("--manifest requires a path", QuitFailure)
      manifestArgument = paramStr(index + 1)
      inc index
    elif argument in ["--nimino-notification", "-Embedding", "--embedding",
                      "-ToastActivated", "--toastactivated"]:
      ## COM local-server and the explicit notification fallback are host
      ## control arguments, not deep-link URLs.  The payload for the fallback
      ## is consumed here by the native startup notification parser.
      skipActivationPayload = argument == "--nimino-notification"
    elif skipActivationPayload:
      skipActivationPayload = false
    elif not argument.startsWith("-"):
      activationArguments.add(argument)
    inc index
  if manifestArgument.len == 0:
    fail("usage: nimino-host --manifest <nimino-manifest.json>", QuitFailure)
  let manifestPath = absolutePath(manifestArgument)
  if not fileExists(manifestPath):
    fail("manifest does not exist: " & manifestPath)
  let root = parentDir(manifestPath)
  let manifest = try:
    parseJson(readFile(manifestPath))
  except CatchableError:
    fail("manifest is not valid JSON: " & manifestPath)
    nil
  let appId = requiredString(manifest, "id")
  let appName = requiredString(manifest, "name")
  let url = optionalString(manifest, "url", "")
  let localEntry = optionalString(manifest, "localEntry", "")
  if url.len == 0 and localEntry.len == 0:
    fail("manifest must define url or localEntry")
  if localEntry.len > 0:
    if localEntry.isAbsolute or localEntry[0] in {'/', '\\'} or
        localEntry.contains('\\'):
      fail("manifest localEntry must be a relative path")
    for part in localEntry.split('/'):
      if part.len == 0 or part in [".", ".."]:
        fail("manifest localEntry escapes the package root")
    if not fileExists(root / localEntry):
      fail("manifest localEntry is missing: " & localEntry)
  let profile = optionalString(manifest, "profile", "default")
  let windowNode = if manifest.hasKey("window") and manifest["window"].kind == JObject:
      manifest["window"] else: newJObject()
  let runtime = if manifest.hasKey("runtime") and manifest["runtime"].kind == JObject:
      manifest["runtime"] else: newJObject()
  let webview = if manifest.hasKey("webview") and manifest["webview"].kind == JObject:
      manifest["webview"] else: newJObject()
  let navigation = if manifest.hasKey("navigation") and manifest["navigation"].kind == JObject:
      manifest["navigation"] else: newJObject()
  let permissions = if manifest.hasKey("permissions") and manifest["permissions"].kind == JObject:
      manifest["permissions"] else: newJObject()
  let injection = if manifest.hasKey("injection") and manifest["injection"].kind == JObject:
      manifest["injection"] else: newJObject()
  let deepLinkNode = if manifest.hasKey("deepLink") and manifest["deepLink"].kind == JObject:
      manifest["deepLink"] else: newJObject()
  let allowedDeepLinkSchemes = deepLinkNode.stringArray("schemes")
  let allowedPermissions = permissions.stringArray("allow")
  let showSystemTray = runtime.boolean("showSystemTray", false)
  let startToTray = runtime.boolean("startToTray", false)
  let hideOnClose = runtime.boolean("hideOnClose", false)
  let multiWindow = runtime.boolean("multiWindow", true)
  let multiInstance = runtime.boolean("multiInstance", false)
  let userAgent = optionalString(webview, "userAgent", "")
  let proxyUrl = optionalString(webview, "proxyUrl", "")
  let incognito = webview.boolean("incognito", false)
  for permission in allowedPermissions:
    if permission notin ["microphone", "camera", "notifications", "geolocation",
                         "clipboard", "screenCapture"]:
      fail("manifest contains an unknown permission: " & permission)
  let created = newApp(AppOptions(id: appId, name: appName,
    multiInstance: multiInstance))
  if not created.isOk:
    fail(created.failure.detail)
  let app = created.value
  ## Register before `run()` so both in-process WinRT activation and the
  ## terminated-process command-line activation path are delivered.  The
  ## generic host has no application-specific handler, therefore it reports
  ## the event to stderr for diagnostics while library consumers install
  ## their own callback through nimino-core.
  when defined(windows):
    let activation = app.onNotificationActivated(proc(notificationId: string) =
      stderr.writeLine("nimino-host: notification activated: " & notificationId))
    if not activation.isOk:
      fail(activation.failure.detail)
  let windowCreated = app.newWindow(CoreWindowOptions(
    title: appName,
    width: windowNode.integer("width", 1200),
    height: windowNode.integer("height", 800),
    profile: profile,
    fullscreen: windowNode.boolean("fullscreen", false),
    maximized: windowNode.boolean("maximized", false),
    alwaysOnTop: windowNode.boolean("alwaysOnTop", false),
    hideWindowDecorations: windowNode.boolean("hideWindowDecorations", false),
    enableDragDrop: windowNode.boolean("enableDragDrop", false),
    userAgent: userAgent,
    proxyUrl: proxyUrl,
    incognito: incognito,
    multiWindow: multiWindow,
    hideOnClose: hideOnClose,
    injectionCss: root.readInjection(injection.stringArray("css")),
    injectionJavaScript: root.readInjection(injection.stringArray("javascript"))))
  if not windowCreated.isOk:
    fail(windowCreated.failure.detail)
  let window = windowCreated.value
  if hideOnClose:
    let closeConfigured = window.onCloseRequested(proc(): bool =
      discard window.hide()
      false)
    if not closeConfigured.isOk:
      fail(closeConfigured.failure.detail)
  if showSystemTray:
    let trayConfigured = app.configureSystemTray([
      DesktopMenuItem(id: 1, title: "Show", enabled: true),
      DesktopMenuItem(id: 2, title: "Quit", enabled: true)
    ], proc(itemId: uint32) =
      case itemId
      of 1: discard window.show()
      of 2: discard app.quit()
      else: discard)
    if not trayConfigured.isOk:
      fail(trayConfigured.failure.detail)
  if startToTray:
    if not showSystemTray:
      fail("runtime.startToTray requires runtime.showSystemTray")
    let hidden = window.hide()
    if not hidden.isOk:
      fail(hidden.failure.detail)
  let allowPatterns = navigation.stringArray("allow")
  let externalPatterns = navigation.stringArray("external")
  ## URL-only bundles do not carry a site-specific allow-list.  Use the core
  ## runtime policy instead: same-site navigation and generic OAuth/SSO
  ## redirects stay in the WebView, while unrelated top-level destinations
  ## open externally.  An explicit manifest list remains an override.
  if url.len > 0:
    let policyConfigured = if allowPatterns.len > 0 or externalPatterns.len > 0:
      window.setNavigationPolicy(proc(request: NavigationRequest): NavigationDecision =
        if externalPatterns.anyIt(matchesNavigationPattern(it, request.url)):
          navigationExternal
        elif allowPatterns.anyIt(matchesNavigationPattern(it, request.url)):
          navigationAllow
        else:
          navigationDeny)
    else:
      window.setNavigationPolicy(proc(request: NavigationRequest): NavigationDecision =
        defaultNavigationDecision(url, request.url))
    if not policyConfigured.isOk:
      fail(policyConfigured.failure.detail)
  let popupConfigured = window.onNewWindow(proc(request: NewWindowRequest): bool =
    let decision = if allowPatterns.len > 0 or externalPatterns.len > 0:
      if externalPatterns.anyIt(matchesNavigationPattern(it, request.url)):
        navigationExternal
      elif allowPatterns.anyIt(matchesNavigationPattern(it, request.url)):
        navigationAllow
      else:
        navigationDeny
    else:
      defaultNavigationDecision(url, request.url)
    case decision
    of navigationAllow:
      ## The request came from the WebView's user gesture.  Consume it by
      ## creating the popup explicitly; native backends never create one
      ## implicitly.
      let popup = window.openPopup(NewWindowRequest(url: request.url), profile = profile)
      if not popup.isOk:
        fail("nimino-host: popup creation failed: " & popup.failure.detail)
      true
    of navigationExternal:
      discard window.openExternally(request.url)
      true
    of navigationDeny:
      true)
  if not popupConfigured.isOk:
    fail(popupConfigured.failure.detail)
  let permissionConfigured = window.onPermission(proc(request: PermissionRequest): PermissionDecision =
    let requested = case request.kind
      of microphone: "microphone"
      of camera: "camera"
      of notifications: "notifications"
      of geolocation: "geolocation"
      of clipboard: "clipboard"
      of screenCapture: "screenCapture"
    if requested in allowedPermissions: permissionGrant else: permissionDeny)
  if not permissionConfigured.isOk:
    fail(permissionConfigured.failure.detail)
  let resizable = window.setResizable(windowNode.boolean("resizable", true))
  if not resizable.isOk:
    fail(resizable.failure.detail)
  for activation in activationArguments:
    let parsed = try: parseUri(activation)
    except CatchableError:
      fail("deep-link activation is malformed")
    let scheme = parsed.scheme.toLowerAscii()
    if scheme.len == 0 or scheme notin allowedDeepLinkSchemes.mapIt(it.toLowerAscii()):
      fail("deep-link activation scheme is not declared by the manifest")
    let delivered = app.deliverDeepLink(activation)
    if not delivered.isOk:
      fail(delivered.failure.detail)
  let loaded = if localEntry.len > 0:
      let assets = window.loadAssets(root)
      if not assets.isOk:
        assets
      else:
        window.loadEntry(localEntry)
    elif url.len > 0:
      window.loadUrl(url)
    else:
      CoreResult(isOk: true)
  if not loaded.isOk:
    fail(loaded.failure.detail)
  let running = app.run()
  if not running.isOk:
    fail(running.failure.detail)

when isMainModule:
  main()
