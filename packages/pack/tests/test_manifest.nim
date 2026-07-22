import std/os
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
writeFile(jsonPath, """
{"$schema":"https://example.invalid/schema.json","name":"JSON app","identifier":"app.json",
 "url":"https://example.com","width":1024,"height":768,"multiWindow":false,
 "safeDomain":"accounts.example.com,cdn.example.com","zoom":125,
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
removeFile(jsonPath)
writeFile(jsonPath, "{\"name\":\"JSON app\",\"id\":\"app.json\",\"url\":\"https://example.com\",\"unknown\":true}")
doAssert not loadManifest(jsonPath).isOk
removeFile(jsonPath)
writeFile(jsonPath, "{\"name\":\"JSON app\",\"id\":\"app.json\",\"url\":\"https://example.com\",\"width\":\"1024\"}")
doAssert not loadManifest(jsonPath).isOk
removeFile(jsonPath)

echo "nimino-pack manifest tests passed"
