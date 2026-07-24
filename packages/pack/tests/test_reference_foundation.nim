## Reference parity for Pake's `error` and `file-finding` unit suites.

import std/[os, strutils]
import nimino_pack

## Pake's user-error object keeps a stable classification and message. Nimino
## uses a typed result rather than exceptions, so assert both result branches
## and all public error categories instead of an `instanceof` convention.
let ok = success("bundle")
doAssert ok.isOk
doAssert ok.value == "bundle"
for kind in [invalidManifest, unsupportedFeature, integrityFailure, ioFailure]:
  let failed = failure[string](kind, "expected failure")
  doAssert not failed.isOk
  doAssert failed.error.kind == kind
  doAssert failed.error.detail == "expected failure"

let root = getTempDir() / "nimino-reference-artifact-discovery"
if dirExists(root): removeDir(root)
createDir(root)

let debA = root / "myapp_1.0.0_amd64.deb"
let debB = root / "myapp_1.0.0_arm64.deb"
let msiA = root / "app1.msi"
let msiB = root / "app2.msi"
let msiTen = root / "app10.msi"
let ignored = root / "other.txt"
for path in [debA, debB, msiA, msiB, msiTen, ignored]:
  writeFile(path, "artifact")
let app = root / "Nimino.app"
createDir(app)
createDir(root / "not-an-artifact.deb")

doAssert matchesArtifactPattern("test.deb", "test.deb")
doAssert matchesArtifactPattern("myapp_1.0.0_amd64.deb", "myapp_*.deb")
doAssert matchesArtifactPattern("app1.msi", "app?.msi")
doAssert not matchesArtifactPattern("app10.msi", "app?.msi")
doAssert not matchesArtifactPattern("package.rpm", "*.deb")
doAssert findArtifacts(root / "missing", "*.deb") == @[]
doAssert findArtifacts(root, "myapp_*.deb") == @[debA, debB]
doAssert findArtifacts(root, "app?.msi") == @[msiA, msiB]
doAssert findArtifacts(root, "Nimino.app") == @[app]
doAssert findArtifacts(root, "*.deb") == @[debA, debB]

let fallback = root / "bundle" / "dmg" / "fallback.dmg"
createDir(parentDir(fallback))
writeFile(fallback, "dmg")
doAssert findFirstExistingArtifact(@[root / "primary.dmg", fallback]) == fallback
let primary = root / "primary.dmg"
writeFile(primary, "dmg")
doAssert findFirstExistingArtifact(@[primary, fallback]) == primary
doAssert findFirstExistingArtifact(@[root / "missing.dmg"]).len == 0
let normalized = "src-tauri/target/../target/release/bundle".normalizedPath()
doAssert normalized.contains("target")

removeDir(root)
echo "nimino-pack reference foundation tests passed"
