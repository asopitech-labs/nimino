import std/[os, strutils, uri]

type
  PackErrorKind* = enum
    invalidManifest
    unsupportedFeature
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

  PackManifest* = object
    name*: string
    id*: string
    url*: string
    icon*: string
    profile*: string
    window*: PackWindowOptions
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
  for item in body.split(','):
    let parsed = unquote(item)
    if parsed.len == 0:
      return failure[seq[string]](invalidManifest, "array items must be non-empty strings")
    values.add(parsed)
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
    parsed.scheme in ["http", "https", "file", "data"] and parsed.scheme.len > 0
  except CatchableError:
    false

proc validate*(manifest: PackManifest): PackResult[PackManifest] =
  if manifest.name.len == 0 or manifest.id.len == 0:
    return failure[PackManifest](invalidManifest, "name and id are required")
  for component in [manifest.id, manifest.profile]:
    if component.len == 0 or component in [".", ".."] or component.contains('/') or
        component.contains('\\') or component.contains('\0'):
      return failure[PackManifest](invalidManifest, "id and profile must be safe path components")
  if manifest.url.len == 0 or not validateUrl(manifest.url):
    return failure[PackManifest](invalidManifest, "url must use http, https, file, or data")
  if manifest.window.width <= 0 or manifest.window.height <= 0:
    return failure[PackManifest](invalidManifest, "window dimensions must be positive")
  success(manifest)

proc parse*(text: string): PackResult[PackManifest] =
  var manifest = PackManifest(
    profile: "default",
    window: PackWindowOptions(width: 1200, height: 800, resizable: true))
  var section = ""
  for rawLine in text.splitLines():
    var line = rawLine.strip()
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
