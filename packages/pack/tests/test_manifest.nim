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

[navigation]
allow = ["https://discord.com/**", "https://*.discord.com/**"]
external = ["https://support.discord.com/**"]

[permissions]
allow = ["microphone", "notifications"]

[injection]
css = ["custom.css"]
javascript = ["custom.js"]
""")
doAssert parsed.isOk
doAssert parsed.value.name == "Discord"
doAssert parsed.value.icon == "https://discord.com/icon.png"
doAssert parsed.value.window.width == 1280
doAssert parsed.value.navigationAllow.len == 2
doAssert parsed.value.permissionsAllow == @["microphone", "notifications"]

let commaValue = parse("name = \"Comma\"\nid = \"app.comma\"\nurl = \"https://example.com\"\n[navigation]\nallow = [\"https://example.com/a,b\", \"https://example.com/c\"]")
doAssert commaValue.isOk
doAssert commaValue.value.navigationAllow[0] == "https://example.com/a,b"

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

echo "nimino-pack manifest tests passed"
