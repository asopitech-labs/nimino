import nimino_core

const Digest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

let lifecycle = newUpdateLifecycle("tech.asopi.update-test", "1.0.0")
let manifest = UpdateManifest(version: "1.1.0", url: "https://updates.example.test/nimino.exe",
  sha256: Digest, signature: "detached-signature", keyId: "release-2026")

doAssert validateUpdateManifest(manifest).isOk
doAssert lifecycle.checkForUpdate(manifest, proc(value: UpdateManifest): bool =
  value.keyId == "release-2026").value
doAssert lifecycle.state == updateAvailable
doAssert lifecycle.beginDownload().isOk
doAssert lifecycle.state == updateDownloading
doAssert lifecycle.markReady().isOk
doAssert lifecycle.state == updateReady

var unsigned = manifest
unsigned.signature = ""
doAssert not validateUpdateManifest(unsigned).isOk
doAssert not lifecycle.checkForUpdate(unsigned, proc(value: UpdateManifest): bool = true).isOk
doAssert lifecycle.state == updateFailed
doAssert lifecycle.cancelUpdate().isOk
doAssert lifecycle.state == updateIdle
