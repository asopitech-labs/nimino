import std/[base64, os, osproc, streams, strutils]

import nimino_pack

proc run(tool: string; arguments: seq[string]): tuple[code: int, output: string] =
  let process = startProcess(tool, args = arguments,
    options = {poUsePath, poStdErrToStdOut})
  result.output = process.outputStream.readAll()
  result.code = process.waitForExit()
  process.close()

proc sha256(path: string): string =
  let checked = run("sha256sum", @["--", path])
  doAssert checked.code == 0, checked.output
  let fields = checked.output.splitWhitespace()
  doAssert fields.len > 0
  fields[0]

let root = getTempDir() / "nimino-popular-signature-test"
if dirExists(root):
  removeDir(root)
createDir(root)

let artifactPath = root / "Example_amd64.deb"
let sbomPath = root / "Example.cdx.json"
let payloadPath = root / "statement.txt"
let signaturePath = root / "statement.minisig"
let publicKeyPath = root / "release.pub"
let secretKeyPath = root / "release.key"
writeFile(artifactPath, "signed package\n")
writeFile(sbomPath, "{\"bomFormat\":\"CycloneDX\"}\n")

var entry = PopularPackageEntry(
  slug: "example-linux-amd64",
  name: "Example",
  appId: "app.nimino.example",
  websiteUrl: "https://example.com",
  version: "1.2.3",
  target: "linux",
  architecture: "amd64",
  format: "deb",
  artifact: PopularArtifact(
    url: "https://github.com/asopitech-labs/nimino/releases/download/v1.2.3/Example_amd64.deb",
    fileName: "Example_amd64.deb",
    sha256: sha256(artifactPath),
    size: getFileSize(artifactPath)),
  signature: PopularSignature(
    algorithm: PopularSignatureAlgorithm,
    keyId: "nimino-release-test",
    value: encode("pending")),
  source: PopularSource(
    repository: "https://github.com/asopitech-labs/nimino",
    commit: "c".repeat(40),
    workflow: ".github/workflows/nimino-site-release.yml",
    runId: "123456789",
    manifestSha256: "a".repeat(64),
    sbomUrl: "https://github.com/asopitech-labs/nimino/releases/download/v1.2.3/Example.cdx.json",
    sbomSha256: sha256(sbomPath)))

let generated = run("minisign",
  @["-G", "-W", "-p", publicKeyPath, "-s", secretKeyPath])
doAssert generated.code == 0, generated.output
writeFile(payloadPath, popularPackageSignaturePayload(entry))
let signed = run("minisign",
  @["-S", "-s", secretKeyPath, "-m", payloadPath, "-x", signaturePath, "-q"])
doAssert signed.code == 0, signed.output
entry.signature.value = encode(readFile(signaturePath))

let trustedKey = PopularTrustedKey(
  keyId: "nimino-release-test", publicKeyPath: publicKeyPath)
let verified = verifyPopularPackageRelease(entry, artifactPath, sbomPath, trustedKey)
doAssert verified.isOk, verified.error.detail

writeFile(artifactPath, "tampered package\n")
let tamperedArtifact = verifyPopularPackageRelease(
  entry, artifactPath, sbomPath, trustedKey)
doAssert not tamperedArtifact.isOk
doAssert tamperedArtifact.error.kind == integrityFailure
writeFile(artifactPath, "signed package\n")

writeFile(sbomPath, "{\"tampered\":true}\n")
let tamperedSbom = verifyPopularPackageRelease(
  entry, artifactPath, sbomPath, trustedKey)
doAssert not tamperedSbom.isOk
doAssert tamperedSbom.error.kind == integrityFailure
writeFile(sbomPath, "{\"bomFormat\":\"CycloneDX\"}\n")

let wrongKeyId = verifyPopularPackageRelease(entry, artifactPath, sbomPath,
  PopularTrustedKey(keyId: "attacker", publicKeyPath: publicKeyPath))
doAssert not wrongKeyId.isOk
doAssert wrongKeyId.error.kind == integrityFailure

var changedSource = entry
changedSource.source.commit = "d".repeat(40)
let replacedSource = verifyPopularPackageRelease(
  changedSource, artifactPath, sbomPath, trustedKey)
doAssert not replacedSource.isOk
doAssert replacedSource.error.kind == integrityFailure

removeDir(root)
echo "nimino-pack popular catalog signature tests passed"
