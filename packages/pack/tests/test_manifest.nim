import nimino_pack

let parsed = parse("""
name = "Discord"
id = "app.nimino.discord"
url = "https://discord.com/app"
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
doAssert parsed.value.window.width == 1280
doAssert parsed.value.navigationAllow.len == 2
doAssert parsed.value.permissionsAllow == @["microphone", "notifications"]

let invalid = parse("name = \"No URL\"\nid = \"app.example\"")
doAssert not invalid.isOk
doAssert invalid.error.kind == invalidManifest

echo "nimino-pack manifest tests passed"
