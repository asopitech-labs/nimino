## Generic Nimino host used by packaged bundles and online builds.
## It intentionally depends on nimino-core only; packaging remains in nimino-pack.

import std/[json, os, re, sequtils, strutils, uri]

import nimino_core
import ./policy

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
    when defined(macosx):
      ## A macOS .app uses the host binary itself as CFBundleExecutable.  The
      ## manifest is adjacent in Contents/Resources, so no shell launcher or
      ## extra command-line contract is needed for LaunchServices.
      let executable = absolutePath(getAppFilename())
      manifestArgument = parentDir(parentDir(executable)) / "Resources" /
        "nimino-manifest.json"
    else:
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
  proc deepLinkAllowed(value: string): bool =
    try:
      let parsed = parseUri(value)
      parsed.scheme.len > 0 and parsed.scheme.toLowerAscii() in
        allowedDeepLinkSchemes.mapIt(it.toLowerAscii()) and
        value.find({'\r', '\n', '\0'}) < 0
    except CatchableError:
      false
  let allowedPermissions = permissions.stringArray("allow")
  let showSystemTray = runtime.boolean("showSystemTray", false)
  let systemTrayIcon = optionalString(runtime, "systemTrayIcon", "")
  let activationShortcut = optionalString(runtime, "activationShortcut", "")
  let startToTray = runtime.boolean("startToTray", false)
  let hideOnClose = runtime.boolean("hideOnClose", false)
  let multiWindow = runtime.boolean("multiWindow", true)
  let multiInstance = runtime.boolean("multiInstance", false)
  let userAgent = optionalString(webview, "userAgent", "")
  let proxyUrl = optionalString(webview, "proxyUrl", "")
  let incognito = webview.boolean("incognito", false)
  let enableWasm = webview.boolean("wasm", false)
  let newWindow = webview.boolean("newWindow", false)
  let darkMode = webview.boolean("darkMode", false)
  let disabledWebShortcuts = webview.boolean("disabledWebShortcuts", false)
  let enableFind = webview.boolean("enableFind", false)
  let forceInternalNavigation = webview.boolean("forceInternalNavigation", false)
  let internalUrlRegex = optionalString(webview, "internalUrlRegex", "")
  let minWidth = if windowNode.hasKey("minWidth") and windowNode["minWidth"].kind == JInt:
      windowNode["minWidth"].getInt() else: 0
  let minHeight = if windowNode.hasKey("minHeight") and windowNode["minHeight"].kind == JInt:
      windowNode["minHeight"].getInt() else: 0
  if minWidth < 0 or minHeight < 0:
    fail("window minimum size must not be negative")
  when not defined(macosx):
    if minWidth > 0 or minHeight > 0:
      fail("window minimum size is only supported by the macOS host")
  let hideTitleBar = windowNode.boolean("hideTitleBar", false)
  when not defined(macosx):
    if hideTitleBar:
      fail("window.hideTitleBar is only supported by the macOS host")
  var internalRegex: Regex
  if internalUrlRegex.len > 0:
    try:
      internalRegex = re(internalUrlRegex)
    except CatchableError:
      fail("webview.internalUrlRegex is not a valid regular expression")
  let zoomFactor = if webview.hasKey("zoom") and webview["zoom"].kind in {JInt, JFloat}:
      webview["zoom"].getFloat() / 100.0
    else: 1.0
  if zoomFactor < 0.25 or zoomFactor > 5.0:
    fail("manifest webview.zoom must be between 25 and 500")
  let ignoreCertificateErrors = webview.boolean("ignoreCertificateErrors", false)
  for permission in allowedPermissions:
    if permission notin ["microphone", "camera", "notifications", "geolocation",
                         "clipboard", "screenCapture"]:
      fail("manifest contains an unknown permission: " & permission)
  when defined(macosx):
    for permission in allowedPermissions:
      if permission notin ["microphone", "camera"]:
        fail("macOS host only supports microphone and camera permissions")
  let packageVersion = if manifest.hasKey("package") and manifest["package"].kind == JObject:
      optionalString(manifest["package"], "version", NiminoCoreVersion)
    else: NiminoCoreVersion
  let created = newApp(AppOptions(id: appId, name: appName, version: packageVersion,
    multiInstance: multiInstance))
  if not created.isOk:
    fail(created.failure.detail)
  let app = created.value
  when defined(macosx):
    if systemTrayIcon.len > 0:
      let iconPath = if fileExists(systemTrayIcon): systemTrayIcon
        elif fileExists(root / systemTrayIcon): root / systemTrayIcon
        elif fileExists(root / extractFilename(systemTrayIcon)): root / extractFilename(systemTrayIcon)
        else: ""
      if iconPath.len == 0:
        fail("runtime.systemTrayIcon does not identify a packaged icon: " & systemTrayIcon)
      let trayIconConfigured = app.setSystemTrayIcon(iconPath)
      if not trayIconConfigured.isOk:
        fail(trayIconConfigured.failure.detail)
  ## Register before `run()` so both in-process WinRT activation and the
  ## terminated-process command-line activation path are delivered.  The
  ## generic host has no application-specific handler, therefore it reports
  ## the event to stderr for diagnostics while library consumers install
  ## their own callback through nimino-core.
  when defined(windows) or defined(macosx):
    let activation = app.onNotificationActivated(proc(notificationId: string) =
      stderr.writeLine("nimino-host: notification activated: " & notificationId))
    if not activation.isOk:
      fail(activation.failure.detail)
  when defined(macosx):
    let deepLink = app.onDeepLink(proc(url: string) =
      if deepLinkAllowed(url):
        stderr.writeLine("nimino-host: deep link activated: " & url)
      else:
        stderr.writeLine("nimino-host: ignored undeclared deep link: " & url))
    if not deepLink.isOk:
      fail(deepLink.failure.detail)
  let windowCreated = app.newWindow(CoreWindowOptions(
    title: optionalString(windowNode, "title", appName),
    width: windowNode.integer("width", 1200),
    height: windowNode.integer("height", 800),
    minWidth: minWidth,
    minHeight: minHeight,
    profile: profile,
    fullscreen: windowNode.boolean("fullscreen", false),
    maximized: windowNode.boolean("maximized", false),
    alwaysOnTop: windowNode.boolean("alwaysOnTop", false),
    hideWindowDecorations: windowNode.boolean("hideWindowDecorations", false),
    hideTitleBar: hideTitleBar,
    enableDragDrop: windowNode.boolean("enableDragDrop", false),
    userAgent: userAgent,
    proxyUrl: proxyUrl,
    incognito: incognito,
    enableWasm: enableWasm,
    darkMode: darkMode,
    disabledWebShortcuts: disabledWebShortcuts,
    enableFind: enableFind,
    zoomFactor: zoomFactor,
    ignoreCertificateErrors: ignoreCertificateErrors,
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
      DesktopMenuItem(id: 1, title: "New Window", enabled: multiWindow),
      DesktopMenuItem(id: 2, title: "Hide", enabled: true),
      DesktopMenuItem(id: 3, title: "Show", enabled: true),
      DesktopMenuItem(id: 4, title: "Quit", enabled: true)
    ], proc(itemId: uint32) =
      case itemId
      of 0:
        ## Cocoa sends action 0 for a left-click on the status item. Match
        ## Pake's toggle behavior while keeping the menu commands explicit.
        if not window.isVisible:
          discard window.show()
          discard window.focus()
        else:
          discard window.hide()
      of 1:
        if multiWindow and url.len > 0:
          discard window.openPopup(NewWindowRequest(url: url, focused: true), title = appName)
      of 2: discard window.hide()
      of 3:
        discard window.show()
        discard window.focus()
      of 4: discard app.quit()
      else: discard)
    if not trayConfigured.isOk:
      fail(trayConfigured.failure.detail)
  if startToTray:
    if not showSystemTray:
      fail("runtime.startToTray requires runtime.showSystemTray")
    let hidden = window.hide()
    if not hidden.isOk:
      fail(hidden.failure.detail)
  when defined(macosx):
    if activationShortcut.len > 0:
      let shortcutConfigured = app.setActivationShortcut(activationShortcut, proc() =
        if window.isVisible:
          discard window.hide()
        else:
          discard window.show()
          discard window.focus())
      if not shortcutConfigured.isOk:
        fail(shortcutConfigured.failure.detail)
  let allowPatterns = navigation.stringArray("allow")
  let externalPatterns = navigation.stringArray("external")
  ## URL-only bundles do not carry a site-specific allow-list.  Use the core
  ## runtime policy instead: same-site navigation and generic OAuth/SSO
  ## redirects stay in the WebView, while unrelated top-level destinations
  ## open externally.  An explicit manifest list remains an override.
  proc isForcedInternalNavigation(target: string): bool =
    if not forceInternalNavigation and internalUrlRegex.len == 0:
      return false
    if internalUrlRegex.len > 0:
      return target.match(internalRegex)
    true
  if url.len > 0:
    let policyConfigured = if allowPatterns.len > 0 or externalPatterns.len > 0:
      window.setNavigationPolicy(proc(request: NavigationRequest): NavigationDecision =
        if isForcedInternalNavigation(request.url):
          navigationAllow
        elif externalPatterns.anyIt(matchesNavigationPattern(it, request.url)):
          navigationExternal
        elif allowPatterns.anyIt(matchesNavigationPattern(it, request.url)):
          navigationAllow
        else:
          navigationDeny)
    else:
      window.setNavigationPolicy(proc(request: NavigationRequest): NavigationDecision =
        if isForcedInternalNavigation(request.url): navigationAllow
        else: defaultNavigationDecision(url, request.url))
    if not policyConfigured.isOk:
      fail(policyConfigured.failure.detail)
  let popupConfigured = window.onNewWindow(proc(request: NewWindowRequest): bool =
    let decision = if allowPatterns.len > 0 or externalPatterns.len > 0:
      if isForcedInternalNavigation(request.url):
        navigationAllow
      elif externalPatterns.anyIt(matchesNavigationPattern(it, request.url)):
        navigationExternal
      elif allowPatterns.anyIt(matchesNavigationPattern(it, request.url)):
        navigationAllow
      else:
        navigationDeny
    else:
      if isForcedInternalNavigation(request.url): navigationAllow
      else: defaultNavigationDecision(url, request.url)
    let popupDecision = if decision == navigationAllow and not newWindow and
        not isAuthenticationNavigation(request.url):
        navigationExternal
      else:
        decision
    case popupDecision
    of navigationAllow:
      ## The request came from the WebView's user gesture.  Consume it by
      ## creating the popup explicitly; native backends never create one
      ## implicitly.
      let popup = window.openPopup(request, profile = profile)
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
  ## Pake accepts browser downloads by default.  Core deliberately denies an
  ## unhandled request, so the generated host must install an explicit policy
  ## instead of relying on a native backend default.
  let downloadPolicy = window.onDownload(proc(request: DownloadRequest): DownloadDecision =
    discard request
    downloadAllow)
  if not downloadPolicy.isOk:
    fail(downloadPolicy.failure.detail)
  var downloadNotificationSequence = 0
  let downloadEvents = window.onDownloadEvent(proc(event: DownloadEvent) =
    let label = safeDownloadLabel(event.request.suggestedName)
    var title = "Download"
    var body = ""
    var state = "event"
    case event.state
    of downloadStarted:
      title = "Download started"
      body = label
      state = "started"
    of downloadCompleted:
      title = "Download complete"
      body = label
      state = "completed"
    of downloadFailed:
      title = "Download failed"
      body = label
      state = "failed"
    of downloadCancelled:
      title = "Download cancelled"
      body = label
      state = "cancelled"
    of downloadProgress:
      return
    discard app.sendNotification(DesktopNotification(
      id: downloadNotificationId(downloadNotificationSequence, state),
      title: title,
      body: body)))
  if not downloadEvents.isOk:
    fail(downloadEvents.failure.detail)
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
  let notificationRpc = window.rpc.registerSync("app.sendNotification",
    proc(params: JsonNode): RpcResult =
      if params.kind != JObject or not params.hasKey("id") or
          not params.hasKey("title") or not params.hasKey("body") or
          params["id"].kind != JString or params["title"].kind != JString or
          params["body"].kind != JString:
        return rpcFailure(rpcError(invalidRequest, "id, title, and body are required"))
      let sent = app.sendNotification(DesktopNotification(
        id: params["id"].getStr(), title: params["title"].getStr(),
        body: params["body"].getStr()))
      if sent.isOk: rpcSuccess(%*{"ok": true})
      else: rpcFailure(rpcError(handlerFailed, sent.failure.detail)))
  if not notificationRpc:
    fail("unable to register app.sendNotification RPC")
  if windowNode.boolean("enableDragDrop", false):
    let fileDropConfigured = window.onFileDrop(proc(paths: seq[string]) =
      var encoded = newJArray()
      for path in paths:
        encoded.add(%path)
      ## The generated host has no application callback surface, so expose
      ## native drops to the loaded page as a stable DOM event.
      discard window.evalJavaScript(
        "window.dispatchEvent(new CustomEvent('nimino-file-drop',{detail:" &
        $encoded & "}));"))
    if not fileDropConfigured.isOk:
      fail(fileDropConfigured.failure.detail)
  let resizable = window.setResizable(windowNode.boolean("resizable", true))
  if not resizable.isOk:
    fail(resizable.failure.detail)
  for activation in activationArguments:
    if not deepLinkAllowed(activation):
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
  when defined(macosx):
    var menuItems = @[
      DesktopMenuItem(id: 100, title: "Show", enabled: true),
      DesktopMenuItem(id: 101, title: "Hide", enabled: true),
      DesktopMenuItem(id: 102, title: "Reload", enabled: true),
      DesktopMenuItem(id: 103, title: "Find", enabled: enableFind),
      DesktopMenuItem(id: 104, title: "Quit", enabled: true)]
    if multiWindow:
      menuItems.insert(DesktopMenuItem(id: 105, title: "New Window", enabled: true), 0)
    let menuConfigured = app.configureNativeMenu(appName, menuItems, proc(itemId: uint32) =
      case itemId
      of 100: discard window.show()
      of 101: discard window.hide()
      of 102: discard window.reload()
      of 103:
        if enableFind:
          discard window.evalJavaScript(
            "(() => { const q = prompt('Find'); if (q) window.nimino.find(q); })()")
      of 104: discard app.quit()
      of 105:
        if multiWindow and url.len > 0:
          discard window.openPopup(NewWindowRequest(url: url, focused: true), title = appName)
      else: discard)
    if not menuConfigured.isOk:
      fail(menuConfigured.failure.detail)
  let running = app.run()
  if not running.isOk:
    fail(running.failure.detail)

when isMainModule:
  main()
