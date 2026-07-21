import std/[os, strutils, uri]

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
    width*: int
    height*: int
    resizable*: bool

  PackPackageMetadata* = object
    ## Distribution-facing fields. They remain separate from the URL and
    ## window policy so installers can consume the same validated identity.
    version*: string
    description*: string
    publisher*: string
    homepage*: string
    categories*: seq[string]

  PackManifest* = object
    name*: string
    id*: string
    url*: string
    icon*: string
    profile*: string
    window*: PackWindowOptions
    package*: PackPackageMetadata
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
  if normalized.url.len == 0 or not validateUrl(normalized.url):
    return failure[PackManifest](invalidManifest, "url must use http, https, file, or data")
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
  for category in normalized.package.categories:
    if category notin DesktopCategories:
      return failure[PackManifest](invalidManifest,
        "unknown desktop category: " & category)
  success(normalized)

proc parse*(text: string): PackResult[PackManifest] =
  var manifest = PackManifest(
    profile: "default",
    window: PackWindowOptions(width: 1200, height: 800, resizable: true),
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
      of "icon": manifest.icon = unquote(value)
      of "profile": manifest.profile = unquote(value)
      else: return failure[PackManifest](invalidManifest, "unknown root key: " & key)
    of "window":
      case key
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
      else: return failure[PackManifest](invalidManifest, "unknown window key: " & key)
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
    of "navigation", "permissions", "injection":
      let parsed = parseStringArray(value)
      if not parsed.isOk: return failure[PackManifest](parsed.error.kind, parsed.error.detail)
      case section
      of "navigation":
        case key
        of "allow": manifest.navigationAllow = parsed.value
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
      else: return failure[PackManifest](invalidManifest, "unknown section: " & section)
    else:
      return failure[PackManifest](invalidManifest, "unknown section: " & section)
  manifest.validate()

proc loadManifest*(path: string): PackResult[PackManifest] =
  if path.len == 0 or not fileExists(path):
    return failure[PackManifest](ioFailure, "manifest file does not exist")
  try:
    parse(readFile(path))
  except OSError:
    failure[PackManifest](ioFailure, "manifest file could not be read")
