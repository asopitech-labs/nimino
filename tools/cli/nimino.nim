import std/[json, os]

import nimino_pack

proc usage() =
  stderr.writeLine("usage: nimino pack <manifest.toml>")
  quit(2)

proc manifestJson(manifest: PackManifest): JsonNode =
  %*{
    "name": manifest.name,
    "id": manifest.id,
    "url": manifest.url,
    "profile": manifest.profile,
    "window": {
      "width": manifest.window.width,
      "height": manifest.window.height,
      "resizable": manifest.window.resizable
    },
    "navigation": {
      "allow": manifest.navigationAllow,
      "external": manifest.navigationExternal
    },
    "permissions": {"allow": manifest.permissionsAllow},
    "injection": {
      "css": manifest.css,
      "javascript": manifest.javascript
    }
  }

if paramCount() != 2 or paramStr(1) != "pack":
  usage()
let loaded = loadManifest(paramStr(2))
if not loaded.isOk:
  stderr.writeLine("nimino pack: " & loaded.error.detail)
  quit(1)
echo manifestJson(loaded.value).pretty()
