import std/[json, os, strutils, uri]

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

  PackWebViewOptions* = object
    userAgent*: string
    proxyUrl*: string
    incognito*: bool
    zoomFactor*: float
    ignoreCertificateErrors*: bool

  PackRuntimeOptions* = object
    showSystemTray*: bool
    startToTray*: bool
    hideOnClose*: bool
    multiWindow*: bool
    multiInstance*: bool

  PackPackageMetadata* = object
    ## Distribution-facing fields. They remain separate from the URL and
    ## window policy so installers can consume the same validated identity.
    version*: string
    description*: string
    publisher*: string
    homepage*: string
    categories*: seq[string]

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

proc loadManifest*(path: string): PackResult[PackManifest] =
  if path.len == 0 or not fileExists(path):
    return failure[PackManifest](ioFailure, "manifest file does not exist")
  try:
    let source = readFile(path)
    if path.toLowerAscii().endsWith(".json"):
      let node = parseJson(source)
      if node.kind != JObject:
        return failure[PackManifest](invalidManifest, "JSON config must be an object")
      let getString = proc(key: string; fallback = ""): string =
        if node.hasKey(key) and node[key].kind == JString: node[key].getStr() else: fallback
      let getBool = proc(key: string; fallback: bool): bool =
        if node.hasKey(key) and node[key].kind == JBool: node[key].getBool() else: fallback
      let getInt = proc(key: string; fallback: int): int =
        if node.hasKey(key) and node[key].kind == JInt: node[key].getInt() else: fallback
      var manifest = PackManifest(
        name: getString("name"), id: getString("identifier", getString("id")),
        url: getString("url"), icon: getString("icon"), profile: getString("profile", "default"),
        window: PackWindowOptions(width: getInt("width", 1200), height: getInt("height", 800),
          resizable: getBool("resizable", true), fullscreen: getBool("fullscreen", false),
          maximized: getBool("maximize", getBool("maximized", false)),
          alwaysOnTop: getBool("always_on_top", getBool("alwaysOnTop", false)),
          hideWindowDecorations: getBool("hide_window_decorations", false),
          enableDragDrop: getBool("enable_drag_drop", false)),
        webview: PackWebViewOptions(userAgent: getString("user_agent", getString("userAgent")),
          proxyUrl: getString("proxy_url", getString("proxyUrl")),
          incognito: getBool("incognito", false), zoomFactor: getInt("zoom", 100).float / 100.0,
          ignoreCertificateErrors: getBool("ignore_certificate_errors", false)),
        runtime: PackRuntimeOptions(showSystemTray: getBool("show_system_tray", false),
          startToTray: getBool("start_to_tray", false), hideOnClose: getBool("hide_on_close", false),
          multiWindow: getBool("multi_window", true), multiInstance: getBool("multi_instance", false)),
        package: PackPackageMetadata(version: getString("app_version", "0.1.0"),
          description: getString("description"), publisher: getString("publisher", "Nimino"),
          homepage: getString("homepage", getString("url")), categories: @[
            "Network"]))
      if node.hasKey("title") and node["title"].kind == JString:
        manifest.window.title = node["title"].getStr()
      return manifest.validate()
    parse(source)
  except OSError:
    failure[PackManifest](ioFailure, "manifest file could not be read")
