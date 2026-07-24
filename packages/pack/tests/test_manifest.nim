import std/[json, os, strutils]
import nimino_pack

let parsed = parse("""
name = "Discord"
id = "app.nimino.discord"
url = "https://discord.com/app"
icon = "https://discord.com/icon.png"
profile = "default"

[window]
width = 1280
height = 900
resizable = true
fullscreen = true
maximized = true
always-on-top = true
hide-window-decorations = true
enable-drag-drop = true

[webview]
user-agent = "NiminoTest/1.0"
proxy-url = "socks5://proxy.example:1080"
incognito = false

[runtime]
show-system-tray = true
start-to-tray = true
hide-on-close = true
multi-window = true
multi-instance = false

[package]
version = "1.2.3"
description = "Discord desktop application"
publisher = "Nimino Labs"
homepage = "https://nimino.example/discord"
categories = ["Network", "Utility"]

[navigation]
allow = ["https://discord.com/**", "https://*.discord.com/**"]
external = ["https://support.discord.com/**"]

[permissions]
allow = ["microphone", "notifications"]

[injection]
css = ["custom.css"]
javascript = ["custom.js"]

[deepLink]
schemes = ["Nimino", "foo+bar", "nimino"]
""")
doAssert parsed.isOk
doAssert parsed.value.name == "Discord"
doAssert parsed.value.icon == "https://discord.com/icon.png"
doAssert parsed.value.window.width == 1280
doAssert parsed.value.window.fullscreen
doAssert parsed.value.window.maximized
doAssert parsed.value.window.enableDragDrop
doAssert parsed.value.webview.userAgent == "NiminoTest/1.0"
doAssert parsed.value.webview.proxyUrl == "socks5://proxy.example:1080"
doAssert parsed.value.runtime.startToTray
doAssert parsed.value.navigationAllow.len == 2
doAssert parsed.value.permissionsAllow == @["microphone", "notifications"]
doAssert parsed.value.package.version == "1.2.3"
doAssert parsed.value.package.categories == @["Network", "Utility"]
doAssert parsed.value.deepLink.schemes == @["nimino", "foo+bar"]

## Port Pake's config-file schema contract. The checked-in schema must expose
## exactly the JSON fields the strict loader accepts (apart from `$schema`,
## which is a JSON-Schema annotation rather than a property declaration).
let schema = parseJson(readFile("packages/pack/schema/nimino-pack.schema.json"))
doAssert schema.kind == JObject
doAssert schema["additionalProperties"].getBool == false
doAssert schema["properties"].kind == JObject
for key in JsonManifestKeys:
  if key != "$schema":
    doAssert schema["properties"].hasKey(key), "schema is missing " & key
for key, _ in schema["properties"].pairs:
  doAssert key in JsonManifestKeys, "schema exposes unsupported key " & key
doAssert schema["properties"]["zoom"]["minimum"].getInt == 25
doAssert schema["properties"]["zoom"]["maximum"].getInt == 500

## Pake's generated identifiers are stable, honor an explicit ID, and keep
## differently named wrappers for the same site in separate desktop/profile
## namespaces.
let workGmail = generateManifest("https://gmail.com", name = "Work Gmail")
let personalGmail = generateManifest("https://gmail.com", name = "Personal Gmail")
doAssert workGmail.isOk
doAssert personalGmail.isOk
doAssert workGmail.value.id != personalGmail.value.id
let explicitGmail = generateManifest("https://gmail.com", name = "Work Gmail",
  id = "com.example.work-gmail")
doAssert explicitGmail.isOk
doAssert explicitGmail.value.id == "com.example.work-gmail"
let digitLeadingIdentifier = generateManifest("https://gmail.com", id = "123.invalid")
doAssert not digitLeadingIdentifier.isOk
let numericHost = generateManifest("https://123.example.com", name = "123 Client")
doAssert numericHost.isOk
for segment in numericHost.value.id.split('.'):
  doAssert segment[0] in {'a'..'z', 'A'..'Z', '_'}

## Port Pake's options-name suite. Dots are meaningful desktop-name text on
## macOS while leading dot/dash/space input must never become a bundle name.
doAssert validApplicationName("Vectorizer.AI")
doAssert not validApplicationName(".hidden")
doAssert not validApplicationName("-hidden")
doAssert not validApplicationName(" Hidden")
let dottedName = generateManifest("https://example.com", name = "Vectorizer.AI")
doAssert dottedName.isOk
doAssert dottedName.value.name == "Vectorizer.AI"
doAssert not generateManifest("https://example.com", name = ".hidden").isOk
doAssert not generateManifest("https://example.com", name = "-hidden").isOk
doAssert not generateManifest("https://example.com", name = " Hidden").isOk
let localNamesRoot = getTempDir() / "nimino-pack-local-names"
createDir(localNamesRoot)
let dottedLocal = localNamesRoot / "Vectorizer.AI.html"
let hiddenLocal = localNamesRoot / ".hidden.html"
writeFile(dottedLocal, "<!doctype html>")
writeFile(hiddenLocal, "<!doctype html>")
let dottedLocalManifest = generateLocalManifest(dottedLocal)
let hiddenLocalManifest = generateLocalManifest(hiddenLocal)
doAssert dottedLocalManifest.isOk
doAssert dottedLocalManifest.value.name == "Vectorizer.AI"
doAssert hiddenLocalManifest.isOk
doAssert hiddenLocalManifest.value.name == "Hidden"
removeFile(dottedLocal)
removeFile(hiddenLocal)
removeDir(localNamesRoot)

## Pake only emits start_to_tray when a system tray is enabled. Keep a
## portable Nimino manifest launchable instead of deferring this conflict to
## the platform host.
let startWithoutTray = parse("name = \"No tray\"\nid = \"app.no-tray\"\nurl = \"https://example.com\"\n[runtime]\nstart-to-tray = true")
doAssert startWithoutTray.isOk
doAssert not startWithoutTray.value.runtime.startToTray
let jsonStartWithoutTray = getTempDir() / "nimino-pack-start-without-tray.json"
writeFile(jsonStartWithoutTray, "{\"name\":\"No tray JSON\",\"id\":\"app.no-tray-json\",\"url\":\"https://example.com\",\"startToTray\":true}")
let loadedStartWithoutTray = loadManifest(jsonStartWithoutTray)
doAssert loadedStartWithoutTray.isOk
doAssert not loadedStartWithoutTray.value.runtime.startToTray
removeFile(jsonStartWithoutTray)

let local = parse("name = \"Local\"\nid = \"app.local\"\nlocal-entry = \"assets/index.html\"")
doAssert local.isOk
doAssert local.value.url.len == 0
doAssert local.value.localEntry == "assets/index.html"
let localWithUrl = parse("name = \"Invalid local\"\nid = \"app.invalid-local\"\nurl = \"https://example.com\"\nlocal-entry = \"index.html\"")
doAssert not localWithUrl.isOk
let unsafeLocal = parse("name = \"Unsafe local\"\nid = \"app.unsafe-local\"\nlocal-entry = \"../index.html\"")
doAssert not unsafeLocal.isOk

let metadataDefaults = parse("name = \"Defaults\"\nid = \"app.defaults\"\nurl = \"https://example.com\"")
doAssert metadataDefaults.isOk
doAssert metadataDefaults.value.package.version == "0.1.0"
doAssert metadataDefaults.value.package.description == "Defaults"
doAssert metadataDefaults.value.package.categories == @["Network"]
when defined(macosx):
  ## Pake keeps macOS apps resident by default. An explicit value must still
  ## override that platform default.
  doAssert metadataDefaults.value.runtime.hideOnClose
  let explicitClose = parse("name = \"Close\"\nid = \"app.close\"\nurl = \"https://example.com\"\n[runtime]\nhide-on-close = false")
  doAssert explicitClose.isOk
  doAssert not explicitClose.value.runtime.hideOnClose

let prereleaseVersion = parse("name = \"Release\"\nid = \"app.release\"\nurl = \"https://example.com\"\n[package]\nversion = \"2.0.0-rc.1\"")
doAssert prereleaseVersion.isOk
let invalidVersion = parse("name = \"Version\"\nid = \"app.version\"\nurl = \"https://example.com\"\n[package]\nversion = \"2.0\"")
doAssert not invalidVersion.isOk
let invalidCategory = parse("name = \"Category\"\nid = \"app.category\"\nurl = \"https://example.com\"\n[package]\ncategories = [\"Teleport\"]")
doAssert not invalidCategory.isOk
let invalidHomepage = parse("name = \"Homepage\"\nid = \"app.homepage\"\nurl = \"https://example.com\"\n[package]\nhomepage = \"file:///tmp/app\"")
doAssert not invalidHomepage.isOk
let invalidProxy = parse("name = \"Proxy\"\nid = \"app.proxy\"\nurl = \"https://example.com\"\n[webview]\nproxy-url = \"http://user:pass@proxy.example\"")
doAssert not invalidProxy.isOk

let commaValue = parse("name = \"Comma\"\nid = \"app.comma\"\nurl = \"https://example.com\"\n[navigation]\nallow = [\"https://example.com/a,b\", \"https://example.com/c\"]")
doAssert commaValue.isOk
doAssert commaValue.value.navigationAllow[0] == "https://example.com/a,b"
let comments = parse("name = \"Comments\" # app name\nid = \"app.comments\" # id\nurl = \"https://example.com/#app\" # fragment\n")
doAssert comments.isOk
doAssert comments.value.url == "https://example.com/#app"

let invalid = parse("name = \"No URL\"\nid = \"app.example\"")
doAssert not invalid.isOk
doAssert invalid.error.kind == invalidManifest

let unsafe = parse("name = \"Unsafe\"\nid = \"../escape\"\nurl = \"https://example.com\"")
doAssert not unsafe.isOk
doAssert unsafe.error.kind == invalidManifest

let reserved = parse("name = \"Reserved\"\nid = \"CON\"\nurl = \"https://example.com\"")
doAssert not reserved.isOk
let trailing = parse("name = \"Trailing\"\nid = \"app.example.\"\nurl = \"https://example.com\"")
doAssert not trailing.isOk
let controlName = validate(PackManifest(name: "Bad" & chr(1) & "Name",
  id: "app.example", url: "https://example.com", profile: "default",
  window: PackWindowOptions(width: 800, height: 600, resizable: true)))
doAssert not controlName.isOk
let unknownPermission = parse("name = \"Permission\"\nid = \"app.permission\"\nurl = \"https://example.com\"\n[permissions]\nallow = [\"teleport\"]")
doAssert not unknownPermission.isOk
let uppercaseScheme = parse("name = \"Upper\"\nid = \"app.upper\"\nurl = \"HTTPS://example.com\"")
doAssert uppercaseScheme.isOk
let whitespaceUrl = parse("name = \"Whitespace\"\nid = \"app.whitespace\"\nurl = \"https://example.com/a b\"")
doAssert not whitespaceUrl.isOk
let missingHost = parse("name = \"Missing host\"\nid = \"app.missing\"\nurl = \"https:\"")
doAssert not missingHost.isOk
let invalidNavigation = parse("name = \"Navigation\"\nid = \"app.nav\"\nurl = \"https://example.com\"\n[navigation]\nallow = [\"example.com\"]")
doAssert not invalidNavigation.isOk
let invalidDeepLink = parse("name = \"Deep link\"\nid = \"app.deep\"\nurl = \"https://example.com\"\n[deepLink]\nschemes = [\"https\"]")
doAssert not invalidDeepLink.isOk
let invalidDeepLinkName = parse("name = \"Deep link\"\nid = \"app.deep-name\"\nurl = \"https://example.com\"\n[deepLink]\nschemes = [\"9invalid\"]")
doAssert not invalidDeepLinkName.isOk

let jsonPath = getTempDir() / "nimino-pack-manifest.json"
## Port the configuration-file failure contract from Pake.  JSON manifests are
## the portable CLI/config-file surface, so malformed, missing, unknown and
## wrongly typed values must fail before a bundle is generated.
let missingJsonPath = getTempDir() / "nimino-pack-missing-manifest.json"
if fileExists(missingJsonPath):
  removeFile(missingJsonPath)
let missingJson = loadManifest(missingJsonPath)
doAssert not missingJson.isOk
doAssert missingJson.error.kind == ioFailure
writeFile(jsonPath, "{ malformed")
let brokenJson = loadManifest(jsonPath)
doAssert not brokenJson.isOk
doAssert brokenJson.error.kind == invalidManifest
removeFile(jsonPath)

writeFile(jsonPath, """
{"$schema":"https://example.invalid/schema.json","name":"JSON app","identifier":"app.json",
 "url":"https://example.com","width":1024,"height":768,"multiWindow":false,
 "safeDomain":" accounts.example.com, ,cdn.example.com ","zoom":125,
 "inject":["custom.css","custom.js"],"appVersion":"2.3.4","newWindow":true}
""")
let jsonManifest = loadManifest(jsonPath)
doAssert jsonManifest.isOk
doAssert jsonManifest.value.window.width == 1024
doAssert jsonManifest.value.webview.zoomFactor == 1.25
doAssert jsonManifest.value.webview.newWindow
doAssert jsonManifest.value.package.version == "2.3.4"
doAssert jsonManifest.value.safeDomains == @[
  "accounts.example.com", "cdn.example.com"]
doAssert jsonManifest.value.navigationAllow == @[
  "https://accounts.example.com/**", "https://*.accounts.example.com/**",
  "http://accounts.example.com/**", "http://*.accounts.example.com/**",
  "https://cdn.example.com/**", "https://*.cdn.example.com/**",
  "http://cdn.example.com/**", "http://*.cdn.example.com/**"]
removeFile(jsonPath)

writeFile(jsonPath, """
{"name":"JSON aliases","id":"app.json-aliases","url":"https://example.com",
 "hide_title_bar":true,"min_width":640,"minHeight":480,
 "user_agent":"Nimino Config Test","proxy_url":"socks5://proxy.example:1080",
 "disabled_web_shortcuts":true,"enable_find":true,
 "activation_shortcut":"CmdOrCtrl+Shift+Space","show_system_tray":true,
 "start_to_tray":true,"system_tray_icon":"tray.icns","hide_on_close":false,
 "app_version":"1.2.3","keep_binary":true,"iterative_build":true,
 "new_window":true,"permissions":["camera","microphone"],
 "deep_link":["nimino-config"],"css":["theme.css"],"javascript":["boot.js"],
 "inject":["custom.css","custom.js"]}
""")
let jsonAliases = loadManifest(jsonPath)
doAssert jsonAliases.isOk
doAssert jsonAliases.value.window.hideTitleBar
doAssert jsonAliases.value.window.minWidth == 640
doAssert jsonAliases.value.window.minHeight == 480
doAssert jsonAliases.value.webview.userAgent == "Nimino Config Test"
doAssert jsonAliases.value.webview.proxyUrl == "socks5://proxy.example:1080"
doAssert jsonAliases.value.webview.disabledWebShortcuts
doAssert jsonAliases.value.webview.enableFind
doAssert jsonAliases.value.webview.newWindow
doAssert jsonAliases.value.runtime.showSystemTray
doAssert jsonAliases.value.runtime.startToTray
doAssert not jsonAliases.value.runtime.hideOnClose
doAssert jsonAliases.value.runtime.activationShortcut == "CmdOrCtrl+Shift+Space"
doAssert jsonAliases.value.runtime.systemTrayIcon == "tray.icns"
doAssert jsonAliases.value.package.version == "1.2.3"
doAssert jsonAliases.value.package.keepBinary
doAssert jsonAliases.value.package.iterativeBuild
doAssert jsonAliases.value.permissionsAllow == @["camera", "microphone"]
doAssert jsonAliases.value.deepLink.schemes == @["nimino-config"]
doAssert jsonAliases.value.css == @["theme.css"]
doAssert jsonAliases.value.javascript == @["boot.js"]
doAssert jsonAliases.value.injectionFiles == @["custom.css", "custom.js"]
removeFile(jsonPath)

when defined(macosx):
  writeFile(jsonPath, "{\"name\":\"JSON defaults\",\"id\":\"app.json-defaults\",\"url\":\"https://example.com\"}")
  let jsonDefaults = loadManifest(jsonPath)
  doAssert jsonDefaults.isOk
  doAssert jsonDefaults.value.runtime.hideOnClose
  removeFile(jsonPath)
writeFile(jsonPath, "{\"name\":\"JSON app\",\"id\":\"app.json\",\"url\":\"https://example.com\",\"unknown\":true}")
doAssert not loadManifest(jsonPath).isOk
removeFile(jsonPath)
writeFile(jsonPath, "{\"name\":\"JSON app\",\"id\":\"app.json\",\"url\":\"https://example.com\",\"width\":\"1024\"}")
doAssert not loadManifest(jsonPath).isOk
removeFile(jsonPath)
writeFile(jsonPath, "{\"name\":\"JSON app\",\"id\":\"app.json\",\"url\":\"https://example.com\",\"zoom\":\"100\"}")
doAssert not loadManifest(jsonPath).isOk
removeFile(jsonPath)
writeFile(jsonPath, "{\"name\":\"JSON app\",\"id\":\"app.json\",\"url\":\"https://example.com\",\"inject\":\"custom.css\"}")
doAssert not loadManifest(jsonPath).isOk
removeFile(jsonPath)
writeFile(jsonPath, "{\"name\":\"JSON app\",\"id\":\"app.json\",\"url\":\"https://example.com\",\"multiWindow\":\"true\"}")
doAssert not loadManifest(jsonPath).isOk
removeFile(jsonPath)

echo "nimino-pack manifest tests passed"
