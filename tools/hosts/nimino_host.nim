## Generic Nimino host used by packaged bundles and online builds.
## It intentionally depends on nimino-core only; packaging remains in nimino-pack.

import std/[json, os, re, sequtils, strutils, tables, uri]

import nimino_core
import ./[policy, web_compat]

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

proc emitInAppNotification(window: Window; notification: DesktopNotification) =
  let detail = $(%*{"id": notification.id, "title": notification.title,
    "body": notification.body, "icon": notification.icon})
  discard window.evalJavaScript(
    "window.dispatchEvent(new CustomEvent('nimino-notification',{detail:" & detail & "}));")

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
  let packageIcon = optionalString(manifest, "icon", "")
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
  let appUrl = if url.len > 0:
      url
    else:
      let localPath = (root / localEntry).absolutePath().normalizedPath().replace('\\', '/')
      let prefix = if localPath.len >= 2 and localPath[1] == ':': "file:///" else: "file://"
      prefix & encodeUrl(if prefix == "file:///": localPath[0 .. ^1] else: localPath, false)
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
  var injectionJavaScript = root.readInjection(injection.stringArray("javascript"))
  when defined(macosx):
    injectionJavaScript.add(macosWebCompatibilityScripts(
      newWindow = newWindow,
      forceInternalNavigation = forceInternalNavigation,
      internalUrlRegex = internalUrlRegex,
      appUrl = appUrl))
  when defined(windows) or defined(linux):
    injectionJavaScript.add(nonMacWebShortcutScripts(
      disabledWebShortcuts = disabledWebShortcuts))
  let minWidth = if windowNode.hasKey("minWidth") and windowNode["minWidth"].kind == JInt:
      windowNode["minWidth"].getInt() else: 0
  let minHeight = if windowNode.hasKey("minHeight") and windowNode["minHeight"].kind == JInt:
      windowNode["minHeight"].getInt() else: 0
  if minWidth < 0 or minHeight < 0:
    fail("window minimum size must not be negative")
  when not defined(macosx):
    if minWidth > 0 or minHeight > 0:
      fail("window minimum size is only supported by the macOS host")
  var hideTitleBar = windowNode.boolean("hideTitleBar", false)
  let initialAlwaysOnTop = windowNode.boolean("alwaysOnTop", false)
  var currentFullscreen = windowNode.boolean("fullscreen", false)
  when not defined(macosx):
    if hideTitleBar:
      ## Match Pake: this macOS-only decoration request is ignored when the
      ## same portable bundle is launched on Linux or Windows.
      hideTitleBar = false
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
    when defined(macosx):
      if not multiInstance and created.failure.kind == invalidState:
        ## The existing host owns the lock and has received a distributed
        ## activation request.  A second dock/process launch is successful
        ## from the user's perspective, just as it is in Pake/Tauri.
        quit(QuitSuccess)
    fail(created.failure.detail)
  let app = created.value
  when defined(windows):
    if packageIcon.len > 0:
      if packageIcon.contains('/') or packageIcon.contains('\\') or
          packageIcon in [".", ".."]:
        fail("manifest icon escapes the package root")
      let iconPath = root / packageIcon
      let configured = app.setWindowIcon(iconPath)
      if not configured.isOk:
        fail(configured.failure.detail)
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
    downloadDirectory: getHomeDir() / "Downloads",
    profile: profile,
    fullscreen: currentFullscreen,
    maximized: windowNode.boolean("maximized", false),
    alwaysOnTop: initialAlwaysOnTop,
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
    injectionJavaScript: injectionJavaScript))
  if not windowCreated.isOk:
    fail(windowCreated.failure.detail)
  let window = windowCreated.value
  ## Register before `run()` and retain the notification's web-facing click
  ## contract.  Native activation is delivered by macOS while the host is
  ## running; the page receives only JSON data, never interpolated source.
  when defined(windows) or defined(macosx):
    let activation = app.onNotificationActivated(proc(notificationId: string) =
      let detail = $(%*{"id": notificationId})
      discard window.evalJavaScript(
        "window.dispatchEvent(new CustomEvent('nimino-notification-activated',{detail:" &
        detail & "}));"))
    if not activation.isOk:
      fail(activation.failure.detail)
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
        if multiWindow:
          discard window.openPopup(NewWindowRequest(url: appUrl, focused: true), title = appName)
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
  if appUrl.len > 0:
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
        else: defaultNavigationDecision(appUrl, request.url))
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
      else: defaultNavigationDecision(appUrl, request.url)
    let popupDecision = popupLinkDisposition(
      allowed = decision == navigationAllow,
      external = decision == navigationExternal,
      newWindow = newWindow,
      authentication = isAuthenticationNavigation(request.url),
      blankPopup = request.url.toLowerAscii() == "about:blank")
    case popupDecision
    of popupLinkAllow:
      ## The request came from the WebView's user gesture.  Consume it by
      ## creating the popup explicitly; native backends never create one
      ## implicitly.
      let popup = window.openPopup(request, profile = profile)
      if not popup.isOk:
        fail("nimino-host: popup creation failed: " & popup.failure.detail)
      true
    of popupLinkExternal:
      discard window.openExternally(request.url)
      true
    of popupLinkDeny:
      true)
  if not popupConfigured.isOk:
    fail(popupConfigured.failure.detail)
  when defined(macosx):
    ## WKWebView does not return a child `WKWebView` to JavaScript when the
    ## host creates an application-owned NSWindow. Keep a narrowly scoped
    ## WindowProxy bridge for Pake-compatible Apple/blank authentication
    ## popups; every eventual redirect still goes through `Window.loadUrl`.
    var popupSequence = 0
    var managedPopups = initTable[string, Window]()
    let openPopupRpc = window.rpc.registerSync("app.openPopup",
      proc(params: JsonNode): RpcResult =
        if params.kind != JObject or not params.hasKey("url") or
            params["url"].kind != JString:
          return rpcFailure(rpcError(invalidRequest, "popup url is required"))
        let target = params["url"].getStr()
        if target.toLowerAscii() != "about:blank" and not isAuthenticationNavigation(target):
          return rpcFailure(rpcError(invalidRequest, "popup URL is not an authentication target"))
        let popup = window.openPopup(NewWindowRequest(url: target, focused: true),
          title = appName, profile = profile)
        if not popup.isOk:
          return rpcFailure(rpcError(handlerFailed, popup.failure.detail))
        inc popupSequence
        let popupId = "nimino-popup-" & $popupSequence
        managedPopups[popupId] = popup.value
        rpcSuccess(%*{"id": popupId})
    )
    if not openPopupRpc:
      fail("unable to register app.openPopup RPC")
    let navigatePopupRpc = window.rpc.registerSync("app.navigatePopup",
      proc(params: JsonNode): RpcResult =
        if params.kind != JObject or not params.hasKey("id") or not params.hasKey("url") or
            params["id"].kind != JString or params["url"].kind != JString:
          return rpcFailure(rpcError(invalidRequest, "popup id and url are required"))
        let popupId = params["id"].getStr()
        if not managedPopups.hasKey(popupId):
          return rpcFailure(rpcError(invalidRequest, "popup is no longer available"))
        let loaded = managedPopups[popupId].loadUrl(params["url"].getStr())
        if loaded.isOk: rpcSuccess(%*{"ok": true})
        else: rpcFailure(rpcError(handlerFailed, loaded.failure.detail))
    )
    if not navigatePopupRpc:
      fail("unable to register app.navigatePopup RPC")
    let closePopupRpc = window.rpc.registerSync("app.closePopup",
      proc(params: JsonNode): RpcResult =
        if params.kind != JObject or not params.hasKey("id") or params["id"].kind != JString:
          return rpcFailure(rpcError(invalidRequest, "popup id is required"))
        let popupId = params["id"].getStr()
        if not managedPopups.hasKey(popupId):
          return rpcSuccess(%*{"ok": true})
        let closed = managedPopups[popupId].close()
        managedPopups.del(popupId)
        if closed.isOk: rpcSuccess(%*{"ok": true})
        else: rpcFailure(rpcError(handlerFailed, closed.failure.detail))
    )
    if not closePopupRpc:
      fail("unable to register app.closePopup RPC")
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
    let notification = DesktopNotification(
      id: downloadNotificationId(downloadNotificationSequence, state),
      title: title,
      body: body)
    let sent = app.sendNotification(notification)
    if not sent.isOk:
      emitInAppNotification(window, notification)
    )
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
      let icon = if params.hasKey("icon"):
          if params["icon"].kind != JString:
            return rpcFailure(rpcError(invalidRequest, "icon must be a string"))
          params["icon"].getStr()
        else: ""
      let sent = app.sendNotification(DesktopNotification(
        id: params["id"].getStr(), title: params["title"].getStr(),
        body: params["body"].getStr(), icon: icon))
      if sent.isOk: rpcSuccess(%*{"ok": true})
      else:
        emitInAppNotification(window, DesktopNotification(
          id: params["id"].getStr(), title: params["title"].getStr(),
          body: params["body"].getStr(), icon: icon))
        rpcSuccess(%*{"ok": false, "fallback": true}))
  if not notificationRpc:
    fail("unable to register app.sendNotification RPC")
  let badgeRpc = window.rpc.registerSync("app.setDockBadge",
    proc(params: JsonNode): RpcResult =
      var label = ""
      if params.kind == JObject and params.hasKey("label") and
          params["label"].kind == JString:
        label = params["label"].getStr()
      elif params.kind == JObject and params.hasKey("count") and
          params["count"].kind == JInt:
        let count = params["count"].getInt()
        if count < 0:
          return rpcFailure(rpcError(invalidRequest, "badge count must not be negative"))
        label = $count
      elif params.kind == JObject and params.hasKey("count"):
        return rpcFailure(rpcError(invalidRequest, "badge count must be an integer"))
      elif params.kind != JObject:
        return rpcFailure(rpcError(invalidRequest, "badge parameters must be an object"))
      let updated = app.setDockBadge(label)
      if updated.isOk: rpcSuccess(%*{"ok": true})
      else: rpcFailure(rpcError(handlerFailed, updated.failure.detail)))
  if not badgeRpc:
    fail("unable to register app.setDockBadge RPC")
  when defined(windows) or defined(linux):
    let fullscreenRpc = window.rpc.registerSync("app.toggleFullscreen",
      proc(params: JsonNode): RpcResult =
        if params.kind != JObject:
          return rpcFailure(rpcError(invalidRequest,
            "fullscreen parameters must be an object"))
        currentFullscreen = not currentFullscreen
        let updated = window.setFullscreen(currentFullscreen)
        if updated.isOk:
          rpcSuccess(%*{"ok": true, "fullscreen": currentFullscreen})
        else:
          currentFullscreen = not currentFullscreen
          rpcFailure(rpcError(handlerFailed, updated.failure.detail)))
    if not fullscreenRpc:
      fail("unable to register app.toggleFullscreen RPC")
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
    var currentZoom = zoomFactor
    var currentAlwaysOnTop = initialAlwaysOnTop
    let appMenuGroup = appName
    var menuItems = @[
      DesktopMenuItem(id: 200, title: "About " & appName, enabled: true,
        group: appMenuGroup, predefined: "about"),
      DesktopMenuItem(id: 201, title: "Services", enabled: true,
        group: appMenuGroup, predefined: "services"),
      DesktopMenuItem(id: 202, title: "Hide", enabled: true,
        group: appMenuGroup, keyEquivalent: "cmd+h", predefined: "hide"),
      DesktopMenuItem(id: 203, title: "Hide Others", enabled: true,
        group: appMenuGroup, keyEquivalent: "cmd+alt+h", predefined: "hideOthers"),
      DesktopMenuItem(id: 204, title: "Show All", enabled: true,
        group: appMenuGroup, predefined: "showAll"),
      DesktopMenuItem(id: 205, title: "Quit " & appName, enabled: true,
        group: appMenuGroup, keyEquivalent: "cmd+q", predefined: "quit"),
      DesktopMenuItem(id: 210, title: "New Window", enabled: multiWindow,
        group: "File", keyEquivalent: "cmd+n"),
      DesktopMenuItem(id: 211, title: "Close Window", enabled: true,
        group: "File", keyEquivalent: "cmd+w", predefined: "closeWindow"),
      DesktopMenuItem(id: 212, title: "Clear Cache & Reload", enabled: true,
        group: "File", keyEquivalent: "cmd+shift+backspace"),
      DesktopMenuItem(id: 220, title: "Undo", enabled: true,
        group: "Edit", keyEquivalent: "cmd+z", predefined: "undo"),
      DesktopMenuItem(id: 221, title: "Redo", enabled: true,
        group: "Edit", keyEquivalent: "cmd+shift+z", predefined: "redo"),
      DesktopMenuItem(id: 222, title: "Cut", enabled: true,
        group: "Edit", keyEquivalent: "cmd+x", predefined: "cut"),
      DesktopMenuItem(id: 223, title: "Copy", enabled: true,
        group: "Edit", keyEquivalent: "cmd+c", predefined: "copy"),
      DesktopMenuItem(id: 224, title: "Paste", enabled: true,
        group: "Edit", keyEquivalent: "cmd+v", predefined: "paste"),
      DesktopMenuItem(id: 225, title: "Paste and Match Style", enabled: true,
        group: "Edit", keyEquivalent: "cmd+shift+option+v", predefined: "pasteAndMatchStyle"),
      DesktopMenuItem(id: 226, title: "Select All", enabled: true,
        group: "Edit", keyEquivalent: "cmd+a", predefined: "selectAll"),
      DesktopMenuItem(id: 227, title: "Find", enabled: enableFind,
        group: "Edit", keyEquivalent: "cmd+f"),
      DesktopMenuItem(id: 228, title: "Find Next", enabled: enableFind,
        group: "Edit", keyEquivalent: "cmd+g"),
      DesktopMenuItem(id: 229, title: "Find Previous", enabled: enableFind,
        group: "Edit", keyEquivalent: "cmd+shift+g"),
      DesktopMenuItem(id: 230, title: "Copy URL", enabled: true,
        group: "Edit", keyEquivalent: "cmd+l"),
      DesktopMenuItem(id: 231, title: "Reload", enabled: true,
        group: "View", keyEquivalent: "cmd+r"),
      DesktopMenuItem(id: 232, title: "Zoom In", enabled: true,
        group: "View", keyEquivalent: "cmd+="),
      DesktopMenuItem(id: 233, title: "Zoom Out", enabled: true,
        group: "View", keyEquivalent: "cmd+-"),
      DesktopMenuItem(id: 234, title: "Actual Size", enabled: true,
        group: "View", keyEquivalent: "cmd+0"),
      DesktopMenuItem(id: 235, title: "Fullscreen", enabled: true,
        group: "View"),
      DesktopMenuItem(id: 240, title: "Back", enabled: true,
        group: "Navigation", keyEquivalent: "cmd+["),
      DesktopMenuItem(id: 241, title: "Forward", enabled: true,
        group: "Navigation", keyEquivalent: "cmd+]"),
      DesktopMenuItem(id: 242, title: "Go Home", enabled: true,
        group: "Navigation", keyEquivalent: "cmd+shift+h"),
      DesktopMenuItem(id: 250, title: "Minimize", enabled: true,
        group: "Window", predefined: "minimize"),
      DesktopMenuItem(id: 251, title: "Maximize", enabled: true,
        group: "Window"),
      DesktopMenuItem(id: 252, title: "Toggle Always on Top", enabled: true,
        group: "Window"),
      DesktopMenuItem(id: 253, title: "Close Window", enabled: true,
        group: "Window", predefined: "closeWindow"),
      DesktopMenuItem(id: 260, title: "Nimino GitHub", enabled: true,
        group: "Help")]
    let menuConfigured = app.configureNativeMenu(appName, menuItems, proc(itemId: uint32) =
      case itemId
      of 210:
        if multiWindow:
          discard window.openPopup(NewWindowRequest(url: appUrl, focused: true), title = appName)
      of 212:
        discard window.clearWebViewProfileDataAndReload(
          {webViewCookies, webViewLocalStorage, webViewCache})
      of 227, 228, 229:
        if enableFind:
          let action = case itemId
            of 227: "open()"
            of 228: "next()"
            else: "previous()"
          discard window.evalJavaScript("window.nimino && window.nimino.findPanel && " &
            "window.nimino.findPanel." & action)
      of 230:
        discard window.evalJavaScript("navigator.clipboard.writeText(location.href)")
      of 231: discard window.reload()
      of 232:
        currentZoom = min(5.0, currentZoom + 0.1)
        discard window.setZoom(currentZoom)
      of 233:
        currentZoom = max(0.25, currentZoom - 0.1)
        discard window.setZoom(currentZoom)
      of 234:
        currentZoom = 1.0
        discard window.setZoom(currentZoom)
      of 235:
        currentFullscreen = not currentFullscreen
        discard window.setFullscreen(currentFullscreen)
      of 240: discard window.evalJavaScript("history.back()")
      of 241: discard window.evalJavaScript("history.forward()")
      of 242: discard window.loadUrl(appUrl)
      of 251: discard window.maximize()
      of 252:
        currentAlwaysOnTop = not currentAlwaysOnTop
        discard window.setAlwaysOnTop(currentAlwaysOnTop)
      of 260:
        discard window.openExternally("https://github.com/asopitech-labs/nimino")
      else: discard)
    if not menuConfigured.isOk:
      fail(menuConfigured.failure.detail)
  let running = app.run()
  if not running.isOk:
    fail(running.failure.detail)

when isMainModule:
  main()
