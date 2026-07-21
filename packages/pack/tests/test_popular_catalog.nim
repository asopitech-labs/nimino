import std/[base64, json, strutils]

import nimino_pack

const
  ShaA = "a".repeat(64)
  ShaB = "b".repeat(64)
  CommitA = "c".repeat(40)

proc entryJson(slug = "example-linux-amd64";
    packageFormat = "deb";
    repository = "https://github.com/asopitech-labs/nimino";
    signature = encode("\0".repeat(64))): JsonNode =
  %*{
    "slug": slug,
    "name": "Example",
    "appId": "app.nimino.example",
    "websiteUrl": "https://example.com",
    "version": "1.2.3",
    "target": "linux",
    "architecture": "amd64",
    "format": packageFormat,
    "artifact": {
      "url": "https://github.com/asopitech-labs/nimino/releases/download/v1.2.3/example.deb",
      "fileName": "example.deb",
      "sha256": ShaA,
      "size": 123
    },
    "signature": {
      "algorithm": "minisign-ed25519",
      "keyId": "nimino-release-test",
      "value": signature
    },
    "source": {
      "repository": repository,
      "commit": CommitA,
      "workflow": ".github/workflows/nimino-pack-online.yml",
      "runId": "123456789",
      "manifestSha256": ShaB,
      "sbomUrl": "https://github.com/asopitech-labs/nimino/releases/download/v1.2.3/example.cdx.json",
      "sbomSha256": ShaA
    }
  }

proc catalogJson(entries: seq[JsonNode]): string =
  $(%*{"schemaVersion": 1, "entries": entries})

let parsed = parsePopularPackageCatalog(catalogJson(@[entryJson()]))
doAssert parsed.isOk, parsed.error.detail
doAssert parsed.value.entries.len == 1
doAssert parsed.value.entries[0].slug == "example-linux-amd64"
doAssert parsed.value.entries[0].artifact.size == 123

let payload = popularPackageSignaturePayload(parsed.value.entries[0])
doAssert payload.startsWith("nimino-popular-package-v1\n")
doAssert "source.commit=" & CommitA & "\n" in payload
doAssert "signature.value" notin payload

var changedSource = parsed.value.entries[0]
changedSource.source.commit = "d".repeat(40)
doAssert popularPackageSignaturePayload(changedSource) != payload
var changedSignature = parsed.value.entries[0]
changedSignature.signature.value = encode("x".repeat(64))
doAssert popularPackageSignaturePayload(changedSignature) == payload

let duplicate = parsePopularPackageCatalog(catalogJson(@[entryJson(), entryJson()]))
doAssert not duplicate.isOk
doAssert duplicate.error.kind == invalidManifest
doAssert "duplicate" in duplicate.error.detail

let unsupported = parsePopularPackageCatalog(catalogJson(@[entryJson(packageFormat = "appimage")]))
doAssert not unsupported.isOk
doAssert unsupported.error.kind == unsupportedFeature

let untrusted = parsePopularPackageCatalog(catalogJson(@[
  entryJson(repository = "https://github.com/attacker/fork")]))
doAssert not untrusted.isOk
doAssert "source repository" in untrusted.error.detail

let invalidSignature = parsePopularPackageCatalog(catalogJson(@[
  entryJson(signature = "not-base64")]))
doAssert not invalidSignature.isOk
doAssert "signature" in invalidSignature.error.detail

var unknownField = entryJson()
unknownField["unexpected"] = %true
let unknown = parsePopularPackageCatalog(catalogJson(@[unknownField]))
doAssert not unknown.isOk
doAssert "unknown field" in unknown.error.detail

let emptyCatalog = parsePopularPackageCatalog(catalogJson(@[]))
doAssert emptyCatalog.isOk
doAssert emptyCatalog.value.entries.len == 0

echo "nimino-pack popular catalog tests passed"
