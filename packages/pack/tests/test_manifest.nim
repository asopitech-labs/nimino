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
doAssert parsed.value.navigationAllow.len == 2
doAssert parsed.value.permissionsAllow == @["microphone", "notifications"]
doAssert parsed.value.package.version == "1.2.3"
doAssert parsed.value.package.categories == @["Network", "Utility"]
doAssert parsed.value.deepLink.schemes == @["nimino", "foo+bar"]

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

echo "nimino-pack manifest tests passed"
