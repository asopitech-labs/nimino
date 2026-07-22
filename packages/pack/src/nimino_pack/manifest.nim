import std/[json, os, sequtils, strutils, uri]

type
  PackErrorKind* = enum
    invalidManifest
    unsupportedFeature
    integrityFailure
    ioFailure

  PackError* = object
    kind*: PackErrorKind
    detail*: string

  PackResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: PackError

  PackWindowOptions* = object
    title*: string
    width*: int
    height*: int
    resizable*: bool
    fullscreen*: bool
    maximized*: bool
    alwaysOnTop*: bool
    hideWindowDecorations*: bool
    enableDragDrop*: bool
    minWidth*: int
    minHeight*: int
    hideTitleBar*: bool

  PackWebViewOptions* = object
    userAgent*: string
    proxyUrl*: string
    incognito*: bool
    zoomFactor*: float
    ignoreCertificateErrors*: bool
    darkMode*: bool
    disabledWebShortcuts*: bool
    enableFind*: bool
    wasm*: bool
    newWindow*: bool
    forceInternalNavigation*: bool
    internalUrlRegex*: string

  PackRuntimeOptions* = object
    showSystemTray*: bool
    startToTray*: bool
    hideOnClose*: bool
    multiWindow*: bool
    multiInstance*: bool
    activationShortcut*: string
    systemTrayIcon*: string

  PackPackageMetadata* = object
    ## Distribution-facing fields. They remain separate from the URL and
    ## window policy so installers can consume the same validated identity.
    version*: string
    description*: string
    publisher*: string
    homepage*: string
    categories*: seq[string]
    targets*: string
    installerLanguage*: string
    keepBinary*: bool
    bundle*: bool
    iterativeBuild*: bool
    debug*: bool
    multiArch*: bool
    install*: bool

  PackDeepLinkOptions* = object
    ## OS-level URL schemes owned by the packaged application.  These are
    ## deliberately separate from nimino-core's WebView custom resource
    ## protocol registration.
    schemes*: seq[string]

  PackManifest* = object
    name*: string
    id*: string
    url*: string
    ## Relative entry inside the generated bundle for local web assets.
    ## Remote URL manifests leave this empty.  Keeping the entry separate
    ## from `url` avoids embedding a machine-local absolute path in a bundle.
    localEntry*: string
    icon*: string
    profile*: string
    window*: PackWindowOptions
    webview*: PackWebViewOptions
    runtime*: PackRuntimeOptions
    package*: PackPackageMetadata
    deepLink*: PackDeepLinkOptions
    navigationAllow*: seq[string]
    navigationExternal*: seq[string]
    permissionsAllow*: seq[string]
    css*: seq[string]
    javascript*: seq[string]
    injectionFiles*: seq[string]
    useLocalFile*: bool
    safeDomains*: seq[string]

proc success*[T](value: T): PackResult[T] {.inline.} =
  PackResult[T](isOk: true, value: value)

proc failure*[T](kind: PackErrorKind; detail: string): PackResult[T] {.inline.} =
  PackResult[T](isOk: false, error: PackError(kind: kind, detail: detail))

proc unquote(value: string): string =
  let trimmed = value.strip()
  if trimmed.len >= 2 and trimmed[0] == '"' and trimmed[^1] == '"':
    return trimmed[1 .. ^2].replace("\\\"", "\"").replace("\\\\", "\\")
  trimmed

proc parseStringArray(value: string): PackResult[seq[string]] =
  let trimmed = value.strip()
  if trimmed.len < 2 or trimmed[0] != '[' or trimmed[^1] != ']':
    return failure[seq[string]](invalidManifest, "array value is required")
  let body = trimmed[1 .. ^2].strip()
  if body.len == 0:
    return success[seq[string]](@[])
  var values: seq[string]
  var itemStart = 0
  var quoted = false
  var escaped = false
  for index, character in body:
    if quoted and escaped:
      escaped = false
    elif quoted and character == '\\':
      escaped = true
    elif character == '"':
      quoted = not quoted
    elif character == ',' and not quoted:
      let parsed = unquote(body[itemStart ..< index])
      if parsed.len == 0:
        return failure[seq[string]](invalidManifest, "array items must be non-empty strings")
      values.add(parsed)
      itemStart = index + 1
  if quoted:
    return failure[seq[string]](invalidManifest, "unterminated array string")
  let last = unquote(body[itemStart .. ^1])
  if last.len == 0:
    return failure[seq[string]](invalidManifest, "array items must be non-empty strings")
  values.add(last)
  success(values)

proc parseBool(value: string): PackResult[bool] =
  case value.strip().toLowerAscii()
  of "true": success(true)
  of "false": success(false)
  else: failure[bool](invalidManifest, "expected boolean")

proc parsePositiveInt(value, field: string): PackResult[int] =
  try:
    let parsed = parseInt(value.strip())
    if parsed <= 0:
      return failure[int](invalidManifest, field & " must be positive")
    success(parsed)
  except ValueError:
    failure[int](invalidManifest, field & " must be an integer")

proc validMetadataText(value: string): bool

proc validateUrl(value: string): bool =
  try:
    let parsed = parseUri(value)
    if parsed.scheme.len == 0:
      return false
    for c in value:
      if c in {' ', '\t', '\r', '\n'} or ord(c) < 0x20 or ord(c) == 0x7f:
        return false
    let scheme = parsed.scheme.toLowerAscii()
    if scheme in ["http", "https"]:
      return parsed.hostname.len > 0
    if scheme == "file":
      return parsed.path.len > 0
    scheme == "data" and parsed.path.len > 0
  except CatchableError:
    false

proc validateProxyUrl(value: string): bool =
  if value.len == 0:
    return true
  try:
    let parsed = parseUri(value)
    parsed.scheme.toLowerAscii() in ["http", "https", "socks5"] and
      parsed.hostname.len > 0 and parsed.username.len == 0 and
      parsed.password.len == 0 and validMetadataText(value)
  except CatchableError:
    false

proc validPathComponent(value: string): bool =
  if value.len == 0 or value in [".", ".."] or value[^1] in {'.', ' '}:
    return false
  let upper = value.toUpperAscii()
  if upper in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4",
               "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2",
               "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]:
    return false
  for character in value:
    if character notin {'a'..'z', 'A'..'Z', '0'..'9', '-', '_', '.'}:
      return false
  true

proc validMetadataText(value: string): bool =
  for character in value:
    if ord(character) < 0x20 or ord(character) == 0x7f:
      return false
  true

proc validPackageVersion(value: string): bool =
  ## Keep the accepted release form aligned with SemVer's three numeric core
  ## components while allowing a conventional prerelease/build suffix.
  if value.len == 0 or not validMetadataText(value):
    return false
  var suffixAt = value.len
  for index, character in value:
    if character in {'-', '+'}:
      suffixAt = index
      break
  let core = value[0 ..< suffixAt]
  let components = core.split('.')
  if components.len != 3:
    return false
  for component in components:
    if component.len == 0:
      return false
    for character in component:
      if character notin {'0'..'9'}:
        return false
  if suffixAt < value.len:
    if suffixAt + 1 >= value.len:
      return false
    for character in value[suffixAt + 1 .. ^1]:
      if character notin {'a'..'z', 'A'..'Z', '0'..'9', '.', '-'}:
        return false
  true

proc validHomepage(value: string): bool =
  if value.len == 0:
    return true
  try:
    let parsed = parseUri(value)
    parsed.scheme.toLowerAscii() in ["http", "https"] and
      parsed.hostname.len > 0 and validMetadataText(value)
  except CatchableError:
    false

proc validLocalEntry(value: string): bool =
  ## Local entries are resolved relative to the bundle root by nimino-host.
  ## Reject absolute paths, parent traversal and platform separators before
  ## they reach the generated manifest.
  if value.len == 0 or value.isAbsolute or value[0] in {'/', '\\'}:
    return false
  if value.contains('\\'):
    return false
  for component in value.split('/'):
    if component.len == 0 or component in [".", ".."]:
      return false
    if not validPathComponent(component):
      return false
  true

const ReservedDeepLinkSchemes = [
  "http", "https", "ws", "wss", "file", "data", "javascript", "about",
  "blob", "mailto", "tel", "sms", "urn"
]

proc validDeepLinkScheme*(value: string): bool =
  ## RFC 3986 scheme grammar: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ).
  ## Keep OS registration conservative and never claim a platform-owned scheme.
  if value.len == 0 or value.len > 63:
    return false
  let normalized = value.toLowerAscii()
  if normalized in ReservedDeepLinkSchemes:
    return false
  if value[0] notin {'a'..'z', 'A'..'Z'}:
    return false
  if value.len > 1:
    for character in value[1 .. ^1]:
      if character notin {'a'..'z', 'A'..'Z', '0'..'9', '+', '-', '.'}:
        return false
  true

const DesktopCategories = [
  "AudioVideo", "Audio", "Video", "Development", "Education", "Game",
  "Graphics", "Network", "Office", "Science", "Settings", "System",
  "Utility"
]

proc validate*(manifest: PackManifest): PackResult[PackManifest] =
  var normalized = manifest
  if normalized.package.version.len == 0:
    normalized.package.version = "0.1.0"
  if normalized.package.description.len == 0:
    normalized.package.description = normalized.name
  if normalized.package.categories.len == 0:
    normalized.package.categories = @["Network"]
  var invalidName = false
  for character in normalized.name:
    if ord(character) < 32:
      invalidName = true
  if normalized.name.len == 0 or normalized.id.len == 0 or
      normalized.name.strip().len == 0 or invalidName:
    return failure[PackManifest](invalidManifest, "name and id are required")
  for component in [normalized.id, normalized.profile]:
    if not validPathComponent(component):
      return failure[PackManifest](invalidManifest, "id and profile must be safe path components")
  if normalized.localEntry.len > 0:
    if normalized.url.len > 0:
      return failure[PackManifest](invalidManifest,
        "localEntry manifests must not also define url")
    if not validLocalEntry(normalized.localEntry):
      return failure[PackManifest](invalidManifest,
        "localEntry must be a safe relative bundle path")
  elif normalized.url.len == 0 or not validateUrl(normalized.url):
    return failure[PackManifest](invalidManifest,
      "url must use http, https, file, or data")
  for pattern in normalized.navigationAllow & normalized.navigationExternal:
    if pattern.len == 0 or pattern.find("://") <= 0:
      return failure[PackManifest](invalidManifest,
        "navigation URL patterns must include a scheme")
    for character in pattern:
      if ord(character) < 0x20 or character in {'\r', '\n'}:
        return failure[PackManifest](invalidManifest,
          "navigation URL patterns contain control characters")
  for permission in normalized.permissionsAllow:
    if permission notin ["microphone", "camera", "notifications", "geolocation",
                         "clipboard", "screenCapture"]:
      return failure[PackManifest](invalidManifest,
        "unknown permission: " & permission)
  if normalized.window.width <= 0 or normalized.window.height <= 0:
    return failure[PackManifest](invalidManifest, "window dimensions must be positive")
  if not validMetadataText(normalized.window.title):
    return failure[PackManifest](invalidManifest, "window.title must not contain control characters")
  if not validPackageVersion(normalized.package.version):
    return failure[PackManifest](invalidManifest,
      "package.version must use a semantic version such as 1.2.3")
  if not validMetadataText(normalized.package.description) or
      not validMetadataText(normalized.package.publisher):
    return failure[PackManifest](invalidManifest,
      "package description and publisher must not contain control characters")
  if not validHomepage(normalized.package.homepage):
      return failure[PackManifest](invalidManifest,
        "package.homepage must be an http or https URL")
  if not validMetadataText(normalized.webview.userAgent):
    return failure[PackManifest](invalidManifest,
      "webview.userAgent must not contain control characters")
  if not validateProxyUrl(normalized.webview.proxyUrl):
    return failure[PackManifest](invalidManifest,
      "webview.proxyUrl must be an http, https, or socks5 URL without credentials")
  if normalized.webview.zoomFactor <= 0.0 or normalized.webview.zoomFactor < 0.25 or
      normalized.webview.zoomFactor > 5.0:
    return failure[PackManifest](invalidManifest,
      "webview.zoomFactor must be between 0.25 and 5.0")
  for category in normalized.package.categories:
    if category notin DesktopCategories:
      return failure[PackManifest](invalidManifest,
        "unknown desktop category: " & category)
  var normalizedSchemes: seq[string]
  for scheme in normalized.deepLink.schemes:
    let normalizedScheme = scheme.toLowerAscii()
    if not validDeepLinkScheme(scheme):
      return failure[PackManifest](invalidManifest,
        "deepLink.schemes contains an invalid or reserved URL scheme: " & scheme)
    if normalizedScheme notin normalizedSchemes:
      normalizedSchemes.add(normalizedScheme)
  normalized.deepLink.schemes = normalizedSchemes
  success(normalized)

proc parse*(text: string): PackResult[PackManifest] =
  var manifest = PackManifest(
    profile: "default",
    window: PackWindowOptions(width: 1200, height: 800, resizable: true),
    webview: PackWebViewOptions(zoomFactor: 1.0),
    package: PackPackageMetadata(version: "0.1.0", categories: @["Network"]))
  var section = ""
  for rawLine in text.splitLines():
    var line = rawLine.strip()
    var quoted = false
    var escaped = false
    var commentAt = -1
    for index, character in line:
      if quoted and escaped:
        escaped = false
      elif quoted and character == '\\':
        escaped = true
      elif character == '"':
        quoted = not quoted
      elif character == '#' and not quoted:
        commentAt = index
        break
    if commentAt >= 0:
      line = line[0 ..< commentAt].strip()
    if line.len == 0 or line[0] == '#':
      continue
    if line.startsWith('[') and line.endsWith(']'):
      section = line[1 .. ^2].strip().toLowerAscii()
      continue
    let separator = line.find('=')
    if separator <= 0:
      return failure[PackManifest](invalidManifest, "expected key = value")
    let key = line[0 ..< separator].strip().toLowerAscii()
    let value = line[separator + 1 .. ^1].strip()
    case section
    of "":
      case key
      of "name": manifest.name = unquote(value)
      of "id": manifest.id = unquote(value)
      of "url": manifest.url = unquote(value)
      of "local-entry", "localentry": manifest.localEntry = unquote(value)
      of "icon": manifest.icon = unquote(value)
      of "profile": manifest.profile = unquote(value)
      else: return failure[PackManifest](invalidManifest, "unknown root key: " & key)
    of "window":
      case key
      of "title": manifest.window.title = unquote(value)
      of "width":
        let parsed = parsePositiveInt(value, "window.width")
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.width = parsed.value
      of "height":
        let parsed = parsePositiveInt(value, "window.height")
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.height = parsed.value
      of "resizable":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.resizable = parsed.value
      of "fullscreen":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.fullscreen = parsed.value
      of "maximized":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.maximized = parsed.value
      of "always-on-top", "alwaysontop":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.alwaysOnTop = parsed.value
      of "hide-window-decorations", "hidewindowdecorations":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.hideWindowDecorations = parsed.value
      of "enable-drag-drop", "enabledragdrop":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.window.enableDragDrop = parsed.value
      else: return failure[PackManifest](invalidManifest, "unknown window key: " & key)
    of "webview":
      case key
      of "user-agent", "useragent": manifest.webview.userAgent = unquote(value)
      of "proxy-url", "proxyurl": manifest.webview.proxyUrl = unquote(value)
      of "incognito":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.webview.incognito = parsed.value
      of "zoom", "zoom-percent":
        try:
          manifest.webview.zoomFactor = parseFloat(value.strip()) / 100.0
        except ValueError:
          return failure[PackManifest](invalidManifest, "webview.zoom must be a number")
      of "ignore-certificate-errors", "ignorecertificateerrors":
        let parsed = parseBool(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.webview.ignoreCertificateErrors = parsed.value
      else: return failure[PackManifest](invalidManifest, "unknown webview key: " & key)
    of "runtime":
      let parsed = parseBool(value)
      if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
      case key
      of "show-system-tray": manifest.runtime.showSystemTray = parsed.value
      of "start-to-tray": manifest.runtime.startToTray = parsed.value
      of "hide-on-close": manifest.runtime.hideOnClose = parsed.value
      of "multi-window": manifest.runtime.multiWindow = parsed.value
      of "multi-instance": manifest.runtime.multiInstance = parsed.value
      else: return failure[PackManifest](invalidManifest, "unknown runtime key: " & key)
    of "package":
      case key
      of "version": manifest.package.version = unquote(value)
      of "description": manifest.package.description = unquote(value)
      of "publisher": manifest.package.publisher = unquote(value)
      of "homepage": manifest.package.homepage = unquote(value)
      of "categories":
        let parsed = parseStringArray(value)
        if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
        manifest.package.categories = parsed.value
      else: return failure[PackManifest](invalidManifest, "unknown package key: " & key)
    of "navigation", "permissions", "injection", "deeplink", "deep-link":
      let parsed = parseStringArray(value)
      if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
      case section
      of "navigation":
        case key
        of "allow": manifest.navigationAllow = parsed.value
        of "safe-domain":
          for domain in parsed.value:
            manifest.navigationAllow.add("https://" & domain & "/**")
        of "external": manifest.navigationExternal = parsed.value
        else: return failure[PackManifest](invalidManifest, "unknown key: " & section & "." & key)
      of "permissions":
        if key != "allow":
          return failure[PackManifest](invalidManifest, "unknown key: " & section & "." & key)
        manifest.permissionsAllow = parsed.value
      of "injection":
        case key
        of "css": manifest.css = parsed.value
        of "javascript": manifest.javascript = parsed.value
        else: return failure[PackManifest](invalidManifest, "unknown key: " & section & "." & key)
      of "deeplink", "deep-link":
        if key != "schemes":
          return failure[PackManifest](invalidManifest, "unknown key: " & section & "." & key)
        manifest.deepLink.schemes = parsed.value
      else: return failure[PackManifest](invalidManifest, "unknown section: " & section)
    else:
      return failure[PackManifest](invalidManifest, "unknown section: " & section)
  manifest.validate()

proc jsonString(node: JsonNode; keys: openArray[string]; fallback: string): PackResult[string] =
  for key in keys:
    if node.hasKey(key):
      if node[key].kind != JString:
        return failure[string](invalidManifest, key & " must be a string")
      return success(node[key].getStr())
  success(fallback)

proc jsonBool(node: JsonNode; keys: openArray[string]; fallback: bool): PackResult[bool] =
  for key in keys:
    if node.hasKey(key):
      if node[key].kind != JBool:
        return failure[bool](invalidManifest, key & " must be a boolean")
      return success(node[key].getBool())
  success(fallback)

proc jsonInt(node: JsonNode; keys: openArray[string]; fallback: int): PackResult[int] =
  for key in keys:
    if node.hasKey(key):
      if node[key].kind != JInt:
        return failure[int](invalidManifest, key & " must be an integer")
      return success(node[key].getInt())
  success(fallback)

proc jsonFloat(node: JsonNode; keys: openArray[string]; fallback: float): PackResult[float] =
  for key in keys:
    if node.hasKey(key):
      if node[key].kind notin {JInt, JFloat}:
        return failure[float](invalidManifest, key & " must be a number")
      return success(node[key].getFloat())
  success(fallback)

proc jsonStringArray(node: JsonNode; keys: openArray[string]): PackResult[seq[string]] =
  for key in keys:
    if node.hasKey(key):
      if node[key].kind != JArray:
        return failure[seq[string]](invalidManifest, key & " must be an array of strings")
      var values: seq[string]
      for item in node[key].items:
        if item.kind != JString or item.getStr().len == 0:
          return failure[seq[string]](invalidManifest,
            key & " must contain only non-empty strings")
        values.add(item.getStr())
      return success(values)
  success(newSeq[string]())

const JsonManifestKeys = [
  "$schema", "url", "name", "identifier", "id", "title", "icon", "width", "height", "resizable",
  "useLocalFile", "use_local_file", "fullscreen", "hideTitleBar", "hide_title_bar",
  "hideWindowDecorations", "hide_window_decorations", "multiArch", "multi_arch", "inject",
  "debug", "proxyUrl", "proxy_url", "userAgent", "user_agent", "targets", "appVersion",
  "app_version", "alwaysOnTop", "always_on_top", "maximize", "maximized", "darkMode",
  "dark_mode", "disabledWebShortcuts", "disabled_web_shortcuts", "activationShortcut",
  "activation_shortcut", "showSystemTray", "show_system_tray", "systemTrayIcon",
  "system_tray_icon", "hideOnClose", "hide_on_close", "incognito", "wasm", "enableDragDrop",
  "enable_drag_drop", "keepBinary", "keep_binary", "bundle", "multiInstance", "multi_instance",
  "multiWindow", "multi_window", "startToTray", "start_to_tray", "forceInternalNavigation",
  "force_internal_navigation", "internalUrlRegex", "internal_url_regex", "safeDomain",
  "safe_domain", "enableFind", "enable_find", "installerLanguage", "installer_language", "zoom",
  "minWidth", "min_width", "minHeight", "min_height", "ignoreCertificateErrors",
  "ignore_certificate_errors", "iterativeBuild", "iterative_build", "newWindow", "new_window",
  "install", "camera", "microphone", "profile", "description", "publisher", "homepage",
  "categories", "permissions", "deepLink", "deep_link", "css", "javascript", "injection"
]

proc loadManifest*(path: string): PackResult[PackManifest] =
  if path.len == 0 or not fileExists(path):
    return failure[PackManifest](ioFailure, "manifest file does not exist")
  try:
    let source = readFile(path)
    if path.toLowerAscii().endsWith(".json"):
      let node = parseJson(source)
      if node.kind != JObject:
        return failure[PackManifest](invalidManifest, "JSON config must be an object")
      for key, _ in node.pairs:
        if key notin JsonManifestKeys:
          return failure[PackManifest](invalidManifest, "unknown JSON key: " & key)
      if node.hasKey("$schema") and node["$schema"].kind != JString:
        return failure[PackManifest](invalidManifest, "$schema must be a string")
      let name = jsonString(node, ["name"], "")
      let identifier = jsonString(node, ["identifier", "id"], "")
      let url = jsonString(node, ["url"], "")
      let profile = jsonString(node, ["profile"], "default")
      let title = jsonString(node, ["title"], "")
      let icon = jsonString(node, ["icon"], "")
      let width = jsonInt(node, ["width"], 1200)
      let height = jsonInt(node, ["height"], 800)
      let resizable = jsonBool(node, ["resizable"], true)
      let fullscreen = jsonBool(node, ["fullscreen"], false)
      let maximized = jsonBool(node, ["maximize", "maximized"], false)
      let alwaysOnTop = jsonBool(node, ["alwaysOnTop", "always_on_top"], false)
      let hideWindowDecorations = jsonBool(node,
        ["hideWindowDecorations", "hide_window_decorations"], false)
      let enableDragDrop = jsonBool(node, ["enableDragDrop", "enable_drag_drop"], false)
      let minWidth = jsonInt(node, ["minWidth", "min_width"], 0)
      let minHeight = jsonInt(node, ["minHeight", "min_height"], 0)
      let hideTitleBar = jsonBool(node, ["hideTitleBar", "hide_title_bar"], false)
      let userAgent = jsonString(node, ["userAgent", "user_agent"], "")
      let proxyUrl = jsonString(node, ["proxyUrl", "proxy_url"], "")
      let incognito = jsonBool(node, ["incognito"], false)
      let zoom = jsonFloat(node, ["zoom"], 100.0)
      let ignoreCertificateErrors = jsonBool(node,
        ["ignoreCertificateErrors", "ignore_certificate_errors"], false)
      let showSystemTray = jsonBool(node, ["showSystemTray", "show_system_tray"], false)
      let startToTray = jsonBool(node, ["startToTray", "start_to_tray"], false)
      let hideOnClose = jsonBool(node, ["hideOnClose", "hide_on_close"], false)
      let multiWindow = jsonBool(node, ["multiWindow", "multi_window"], false)
      let multiInstance = jsonBool(node, ["multiInstance", "multi_instance"], false)
      let activationShortcut = jsonString(node,
        ["activationShortcut", "activation_shortcut"], "")
      let systemTrayIcon = jsonString(node, ["systemTrayIcon", "system_tray_icon"], "")
      let darkMode = jsonBool(node, ["darkMode", "dark_mode"], false)
      let disabledWebShortcuts = jsonBool(node, ["disabledWebShortcuts", "disabled_web_shortcuts"], false)
      let enableFind = jsonBool(node, ["enableFind", "enable_find"], false)
      let wasm = jsonBool(node, ["wasm"], false)
      let newWindow = jsonBool(node, ["newWindow", "new_window"], false)
      let forceInternalNavigation = jsonBool(node,
        ["forceInternalNavigation", "force_internal_navigation"], false)
      let internalUrlRegex = jsonString(node, ["internalUrlRegex", "internal_url_regex"], "")
      let safeDomain = jsonString(node, ["safeDomain", "safe_domain"], "")
      let targets = jsonString(node, ["targets"], "")
      let appVersion = jsonString(node, ["appVersion", "app_version"], "0.1.0")
      let description = jsonString(node, ["description"], "")
      let publisher = jsonString(node, ["publisher"], "Nimino")
      let homepage = jsonString(node, ["homepage"], url.value)
      let categories = jsonStringArray(node, ["categories"])
      let inject = jsonStringArray(node, ["inject"])
      let css = jsonStringArray(node, ["css"])
      let javascript = jsonStringArray(node, ["javascript"])
      let permissions = jsonStringArray(node, ["permissions"])
      let deepLinks = jsonStringArray(node, ["deepLink", "deep_link"])
      template ensureJson(parsed: untyped) =
        if not parsed.isOk:
          return failure[PackManifest](parsed.error.kind, parsed.error.detail)
      ensureJson(name)
      ensureJson(identifier)
      ensureJson(url)
      ensureJson(profile)
      ensureJson(title)
      ensureJson(icon)
      ensureJson(width)
      ensureJson(height)
      ensureJson(resizable)
      ensureJson(fullscreen)
      ensureJson(maximized)
      ensureJson(alwaysOnTop)
      ensureJson(hideWindowDecorations)
      ensureJson(enableDragDrop)
      ensureJson(minWidth)
      ensureJson(minHeight)
      ensureJson(hideTitleBar)
      ensureJson(userAgent)
      ensureJson(proxyUrl)
      ensureJson(incognito)
      ensureJson(zoom)
      ensureJson(ignoreCertificateErrors)
      ensureJson(showSystemTray)
      ensureJson(startToTray)
      ensureJson(hideOnClose)
      ensureJson(multiWindow)
      ensureJson(multiInstance)
      ensureJson(activationShortcut)
      ensureJson(systemTrayIcon)
      ensureJson(darkMode)
      ensureJson(disabledWebShortcuts)
      ensureJson(enableFind)
      ensureJson(wasm)
      ensureJson(newWindow)
      ensureJson(forceInternalNavigation)
      ensureJson(internalUrlRegex)
      ensureJson(safeDomain)
      ensureJson(targets)
      ensureJson(appVersion)
      ensureJson(description)
      ensureJson(publisher)
      ensureJson(homepage)
      ensureJson(categories)
      ensureJson(inject)
      ensureJson(css)
      ensureJson(javascript)
      ensureJson(permissions)
      ensureJson(deepLinks)
      var allow: seq[string]
      let useLocalFile = jsonBool(node, ["useLocalFile", "use_local_file"], false)
      let keepBinary = jsonBool(node, ["keepBinary", "keep_binary"], false)
      let bundle = jsonBool(node, ["bundle"], true)
      let iterativeBuild = jsonBool(node, ["iterativeBuild", "iterative_build"], false)
      let debug = jsonBool(node, ["debug"], false)
      let multiArch = jsonBool(node, ["multiArch", "multi_arch"], false)
      let install = jsonBool(node, ["install"], false)
      ensureJson(useLocalFile)
      ensureJson(keepBinary)
      ensureJson(bundle)
      ensureJson(iterativeBuild)
      ensureJson(debug)
      ensureJson(multiArch)
      ensureJson(install)
      if safeDomain.value.len > 0:
        for domain in safeDomain.value.split(','):
          let trimmed = domain.strip()
          if trimmed.len > 0:
            allow.add("https://" & trimmed & "/**")
      var manifest = PackManifest(
        name: name.value, id: identifier.value, url: url.value, icon: icon.value,
        profile: profile.value, window: PackWindowOptions(title: title.value,
          width: width.value, height: height.value, resizable: resizable.value,
          fullscreen: fullscreen.value, maximized: maximized.value,
          alwaysOnTop: alwaysOnTop.value, hideWindowDecorations: hideWindowDecorations.value,
          enableDragDrop: enableDragDrop.value, minWidth: minWidth.value,
          minHeight: minHeight.value, hideTitleBar: hideTitleBar.value),
        webview: PackWebViewOptions(userAgent: userAgent.value, proxyUrl: proxyUrl.value,
          incognito: incognito.value, zoomFactor: zoom.value / 100.0,
          ignoreCertificateErrors: ignoreCertificateErrors.value, darkMode: darkMode.value,
          disabledWebShortcuts: disabledWebShortcuts.value, enableFind: enableFind.value,
          wasm: wasm.value, newWindow: newWindow.value,
          forceInternalNavigation: forceInternalNavigation.value,
          internalUrlRegex: internalUrlRegex.value),
        runtime: PackRuntimeOptions(showSystemTray: showSystemTray.value,
          startToTray: startToTray.value, hideOnClose: hideOnClose.value,
          multiWindow: multiWindow.value, multiInstance: multiInstance.value,
          activationShortcut: activationShortcut.value, systemTrayIcon: systemTrayIcon.value),
        package: PackPackageMetadata(version: appVersion.value, description: description.value,
          publisher: publisher.value, homepage: homepage.value,
          categories: if categories.value.len == 0: @[
            "Network"] else: categories.value, targets: targets.value,
          installerLanguage: "en-US", keepBinary: keepBinary.value, bundle: bundle.value,
          iterativeBuild: iterativeBuild.value, debug: debug.value, multiArch: multiArch.value,
          install: install.value), navigationAllow: allow,
        permissionsAllow: permissions.value, css: css.value, javascript: javascript.value,
        deepLink: PackDeepLinkOptions(schemes: deepLinks.value), injectionFiles: inject.value,
        useLocalFile: useLocalFile.value, safeDomains: if safeDomain.value.len == 0: @[] else:
          safeDomain.value.split(',').mapIt(it.strip()))
      return manifest.validate()
    parse(source)
  except OSError:
    failure[PackManifest](ioFailure, "manifest file could not be read")
