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
  let profile = optionalString(manifest, "profile", "default")
  let windowNode = if manifest.hasKey("window") and manifest["window"].kind == JObject:
      manifest["window"] else: newJObject()
  let navigation = if manifest.hasKey("navigation") and manifest["navigation"].kind == JObject:
      manifest["navigation"] else: newJObject()
  let injection = if manifest.hasKey("injection") and manifest["injection"].kind == JObject:
      manifest["injection"] else: newJObject()
  let deepLinkNode = if manifest.hasKey("deepLink") and manifest["deepLink"].kind == JObject:
      manifest["deepLink"] else: newJObject()
  let allowedDeepLinkSchemes = deepLinkNode.stringArray("schemes")
  let created = newApp(id = appId, name = appName)
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
    injectionCss: root.readInjection(injection.stringArray("css")),
    injectionJavaScript: root.readInjection(injection.stringArray("javascript"))))
  if not windowCreated.isOk:
    fail(windowCreated.failure.detail)
  let window = windowCreated.value
  let rules = window.setNavigationRules(NavigationRules(
    allow: navigation.stringArray("allow"),
    deny: navigation.stringArray("external")))
  if not rules.isOk:
    fail(rules.failure.detail)
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
  let loaded = if url.len > 0: window.loadUrl(url) else: CoreResult(isOk: true)
  if not loaded.isOk:
    fail(loaded.failure.detail)
  let running = app.run()
  if not running.isOk:
    fail(running.failure.detail)

when isMainModule:
  main()
