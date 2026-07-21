## Strict, fail-closed catalog and release verification for Popular Packages.
##
## A detached minisign signature covers the canonical catalog statement, not
## only the artifact bytes.  The statement binds the artifact checksum to its
## website, release URL, source commit, workflow run, manifest, and SBOM.
import std/[base64, json, os, osproc, streams, strutils, tempfiles, uri]

import ./manifest

type
  PopularCatalogPolicy* = object
    repository*: string
    workflow*: string

  PopularArtifact* = object
    url*: string
    fileName*: string
    sha256*: string
    size*: BiggestInt

  PopularSignature* = object
    algorithm*: string
    keyId*: string
    value*: string

  PopularSource* = object
    repository*: string
    commit*: string
    workflow*: string
    runId*: string
    manifestSha256*: string
    sbomUrl*: string
    sbomSha256*: string

  PopularPackageEntry* = object
    slug*: string
    name*: string
    appId*: string
    websiteUrl*: string
    version*: string
    target*: string
    architecture*: string
    format*: string
    artifact*: PopularArtifact
    signature*: PopularSignature
    source*: PopularSource

  PopularPackageCatalog* = object
    schemaVersion*: int
    entries*: seq[PopularPackageEntry]

  PopularTrustedKey* = object
    keyId*: string
    publicKeyPath*: string

const
  PopularCatalogSchemaVersion* = 1
  PopularSignatureAlgorithm* = "minisign-ed25519"

proc defaultPopularCatalogPolicy*(): PopularCatalogPolicy =
  PopularCatalogPolicy(
    repository: "https://github.com/asopitech-labs/nimino",
    workflow: ".github/workflows/nimino-pack-online.yml")

proc hasOnlyFields(node: JsonNode; fields: openArray[string];
    context: string): PackResult[bool] =
  if node.kind != JObject:
    return failure[bool](invalidManifest, context & " must be an object")
  for key, _ in node:
    if key notin fields:
      return failure[bool](invalidManifest,
        context & " contains unknown field: " & key)
  for field in fields:
    if not node.hasKey(field):
      return failure[bool](invalidManifest,
        context & " is missing field: " & field)
  success(true)

proc stringField(node: JsonNode; field, context: string): PackResult[string] =
  if node[field].kind != JString or node[field].getStr().len == 0:
    return failure[string](invalidManifest,
      context & "." & field & " must be a non-empty string")
  let value = node[field].getStr()
  if '\n' in value or '\r' in value or '\0' in value:
    return failure[string](invalidManifest,
      context & "." & field & " contains a control character")
  success(value)

proc integerField(node: JsonNode; field, context: string): PackResult[BiggestInt] =
  if node[field].kind != JInt:
    return failure[BiggestInt](invalidManifest,
      context & "." & field & " must be an integer")
  success(node[field].getBiggestInt())

proc isSha256(value: string): bool =
  value.len == 64 and value.allCharsInSet({'0' .. '9', 'a' .. 'f'})

proc isSafeId(value: string; allowUppercase = false): bool =
  if value.len == 0:
    return false
  let letters = if allowUppercase: {'a' .. 'z', 'A' .. 'Z'} else: {'a' .. 'z'}
  value.allCharsInSet(letters + {'0' .. '9', '.', '_', '-'})

proc isReleaseVersion(value: string): bool =
  var coreEnd = value.len
  for index, character in value:
    if character in {'-', '+'}:
      coreEnd = index
      break
  let core = value[0 ..< coreEnd]
  let parts = core.split('.')
  if parts.len != 3:
    return false
  for part in parts:
    if part.len == 0 or not part.allCharsInSet({'0' .. '9'}):
      return false
  if coreEnd < value.len:
    let suffix = value[coreEnd .. ^1]
    if suffix.len < 2 or not suffix.allCharsInSet(
        {'a' .. 'z', 'A' .. 'Z', '0' .. '9', '.', '-', '+'}):
      return false
  true

proc isHttpsUrl(value: string): bool =
  try:
    let parsed = parseUri(value)
    parsed.scheme == "https" and parsed.hostname.len > 0 and
      parsed.username.len == 0 and parsed.password.len == 0
  except ValueError:
    false

proc validateEntry(entry: PopularPackageEntry; policy: PopularCatalogPolicy):
    PackResult[PopularPackageEntry] =
  if not isSafeId(entry.slug) or entry.slug.startsWith("-") or entry.slug.endsWith("-"):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package slug is unsafe")
  if entry.name.len == 0 or not isSafeId(entry.appId) or '.' notin entry.appId:
    return failure[PopularPackageEntry](invalidManifest,
      "popular package name or appId is invalid")
  if not isHttpsUrl(entry.websiteUrl):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package websiteUrl must use HTTPS")
  if not isReleaseVersion(entry.version):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package version must be SemVer")
  let supportedTarget =
    entry.architecture == "amd64" and
    ((entry.target == "linux" and entry.format in ["deb", "rpm"]) or
     (entry.target == "windows" and entry.format == "nsis"))
  if not supportedTarget:
    return failure[PopularPackageEntry](unsupportedFeature,
      "popular package target, architecture, or format is unsupported")
  if not isSafeId(entry.artifact.fileName, allowUppercase = true) or
      entry.artifact.fileName in [".", ".."]:
    return failure[PopularPackageEntry](invalidManifest,
      "popular package artifact fileName is unsafe")
  if entry.artifact.size <= 0 or not isSha256(entry.artifact.sha256):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package artifact size or SHA-256 is invalid")
  let releasePrefix = policy.repository & "/releases/download/"
  if not isHttpsUrl(entry.artifact.url) or
      not entry.artifact.url.startsWith(releasePrefix) or
      not entry.artifact.url.endsWith("/" & entry.artifact.fileName):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package artifact URL is outside the trusted release origin")
  if entry.signature.algorithm != PopularSignatureAlgorithm or
      not isSafeId(entry.signature.keyId, allowUppercase = true):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package signature algorithm or keyId is invalid")
  try:
    let decoded = decode(entry.signature.value)
    if decoded.len == 0 or decoded.len > 4096 or
        encode(decoded) != entry.signature.value:
      return failure[PopularPackageEntry](invalidManifest,
        "popular package signature is invalid")
  except ValueError:
    return failure[PopularPackageEntry](invalidManifest,
      "popular package signature is not valid base64")
  if entry.source.repository != policy.repository:
    return failure[PopularPackageEntry](invalidManifest,
      "popular package source repository is not trusted")
  if entry.source.workflow != policy.workflow:
    return failure[PopularPackageEntry](invalidManifest,
      "popular package source workflow is not trusted")
  if entry.source.commit.len != 40 or
      not entry.source.commit.allCharsInSet({'0' .. '9', 'a' .. 'f'}):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package source commit is invalid")
  if entry.source.runId.len == 0 or
      not entry.source.runId.allCharsInSet({'0' .. '9'}):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package source runId is invalid")
  if not isSha256(entry.source.manifestSha256) or
      not isSha256(entry.source.sbomSha256):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package source checksums are invalid")
  if not isHttpsUrl(entry.source.sbomUrl) or
      not entry.source.sbomUrl.startsWith(releasePrefix) or
      not entry.source.sbomUrl.endsWith(".cdx.json"):
    return failure[PopularPackageEntry](invalidManifest,
      "popular package SBOM URL is outside the trusted release origin")
  success(entry)

proc parseEntry(node: JsonNode; policy: PopularCatalogPolicy):
    PackResult[PopularPackageEntry] =
  let top = hasOnlyFields(node,
    ["slug", "name", "appId", "websiteUrl", "version", "target",
     "architecture", "format", "artifact", "signature", "source"],
    "popular package entry")
  if not top.isOk:
    return failure[PopularPackageEntry](top.error.kind, top.error.detail)
  for field in ["slug", "name", "appId", "websiteUrl", "version", "target",
                "architecture", "format"]:
    let checked = stringField(node, field, "popular package entry")
    if not checked.isOk:
      return failure[PopularPackageEntry](checked.error.kind, checked.error.detail)
  let artifactFields = hasOnlyFields(node["artifact"],
    ["url", "fileName", "sha256", "size"], "popular package artifact")
  if not artifactFields.isOk:
    return failure[PopularPackageEntry](artifactFields.error.kind, artifactFields.error.detail)
  for field in ["url", "fileName", "sha256"]:
    let checked = stringField(node["artifact"], field, "popular package artifact")
    if not checked.isOk:
      return failure[PopularPackageEntry](checked.error.kind, checked.error.detail)
  let artifactSize = integerField(node["artifact"], "size", "popular package artifact")
  if not artifactSize.isOk:
    return failure[PopularPackageEntry](artifactSize.error.kind, artifactSize.error.detail)
  let signatureFields = hasOnlyFields(node["signature"],
    ["algorithm", "keyId", "value"], "popular package signature")
  if not signatureFields.isOk:
    return failure[PopularPackageEntry](signatureFields.error.kind, signatureFields.error.detail)
  for field in ["algorithm", "keyId", "value"]:
    let checked = stringField(node["signature"], field, "popular package signature")
    if not checked.isOk:
      return failure[PopularPackageEntry](checked.error.kind, checked.error.detail)
  let sourceFields = hasOnlyFields(node["source"],
    ["repository", "commit", "workflow", "runId", "manifestSha256",
     "sbomUrl", "sbomSha256"], "popular package source")
  if not sourceFields.isOk:
    return failure[PopularPackageEntry](sourceFields.error.kind, sourceFields.error.detail)
  for field in ["repository", "commit", "workflow", "runId", "manifestSha256",
                "sbomUrl", "sbomSha256"]:
    let checked = stringField(node["source"], field, "popular package source")
    if not checked.isOk:
      return failure[PopularPackageEntry](checked.error.kind, checked.error.detail)
  let entry = PopularPackageEntry(
    slug: node["slug"].getStr(), name: node["name"].getStr(),
    appId: node["appId"].getStr(), websiteUrl: node["websiteUrl"].getStr(),
    version: node["version"].getStr(), target: node["target"].getStr(),
    architecture: node["architecture"].getStr(), format: node["format"].getStr(),
    artifact: PopularArtifact(
      url: node["artifact"]["url"].getStr(),
      fileName: node["artifact"]["fileName"].getStr(),
      sha256: node["artifact"]["sha256"].getStr(), size: artifactSize.value),
    signature: PopularSignature(
      algorithm: node["signature"]["algorithm"].getStr(),
      keyId: node["signature"]["keyId"].getStr(),
      value: node["signature"]["value"].getStr()),
    source: PopularSource(
      repository: node["source"]["repository"].getStr(),
      commit: node["source"]["commit"].getStr(),
      workflow: node["source"]["workflow"].getStr(),
      runId: node["source"]["runId"].getStr(),
      manifestSha256: node["source"]["manifestSha256"].getStr(),
      sbomUrl: node["source"]["sbomUrl"].getStr(),
      sbomSha256: node["source"]["sbomSha256"].getStr()))
  validateEntry(entry, policy)

proc parsePopularPackageCatalog*(content: string;
    policy = defaultPopularCatalogPolicy()): PackResult[PopularPackageCatalog] =
  var root: JsonNode
  try:
    root = parseJson(content)
  except JsonParsingError:
    return failure[PopularPackageCatalog](invalidManifest,
      "popular package catalog is not valid JSON")
  let rootFields = hasOnlyFields(root, ["schemaVersion", "entries"],
    "popular package catalog")
  if not rootFields.isOk:
    return failure[PopularPackageCatalog](rootFields.error.kind, rootFields.error.detail)
  if root["schemaVersion"].kind != JInt or
      root["schemaVersion"].getInt() != PopularCatalogSchemaVersion:
    return failure[PopularPackageCatalog](unsupportedFeature,
      "popular package catalog schemaVersion is unsupported")
  if root["entries"].kind != JArray:
    return failure[PopularPackageCatalog](invalidManifest,
      "popular package catalog entries must be an array")
  var catalog = PopularPackageCatalog(schemaVersion: PopularCatalogSchemaVersion)
  for node in root["entries"]:
    let parsed = parseEntry(node, policy)
    if not parsed.isOk:
      return failure[PopularPackageCatalog](parsed.error.kind, parsed.error.detail)
    for existing in catalog.entries:
      if existing.slug == parsed.value.slug:
        return failure[PopularPackageCatalog](invalidManifest,
          "popular package catalog contains duplicate slug: " & parsed.value.slug)
    catalog.entries.add(parsed.value)
  success(catalog)

proc loadPopularPackageCatalog*(path: string;
    policy = defaultPopularCatalogPolicy()): PackResult[PopularPackageCatalog] =
  if path.len == 0 or not fileExists(path):
    return failure[PopularPackageCatalog](ioFailure,
      "popular package catalog file does not exist")
  try:
    parsePopularPackageCatalog(readFile(path), policy)
  except OSError:
    failure[PopularPackageCatalog](ioFailure,
      "popular package catalog file could not be read")

proc findPopularPackage*(catalog: PopularPackageCatalog; slug: string):
    PackResult[PopularPackageEntry] =
  for entry in catalog.entries:
    if entry.slug == slug:
      return success(entry)
  failure[PopularPackageEntry](invalidManifest,
    "popular package entry does not exist: " & slug)

proc popularPackageSignaturePayload*(entry: PopularPackageEntry): string =
  "nimino-popular-package-v1\n" &
    "slug=" & entry.slug & "\n" &
    "name=" & entry.name & "\n" &
    "appId=" & entry.appId & "\n" &
    "websiteUrl=" & entry.websiteUrl & "\n" &
    "version=" & entry.version & "\n" &
    "target=" & entry.target & "\n" &
    "architecture=" & entry.architecture & "\n" &
    "format=" & entry.format & "\n" &
    "artifact.url=" & entry.artifact.url & "\n" &
    "artifact.fileName=" & entry.artifact.fileName & "\n" &
    "artifact.sha256=" & entry.artifact.sha256 & "\n" &
    "artifact.size=" & $entry.artifact.size & "\n" &
    "signature.algorithm=" & entry.signature.algorithm & "\n" &
    "signature.keyId=" & entry.signature.keyId & "\n" &
    "source.repository=" & entry.source.repository & "\n" &
    "source.commit=" & entry.source.commit & "\n" &
    "source.workflow=" & entry.source.workflow & "\n" &
    "source.runId=" & entry.source.runId & "\n" &
    "source.manifestSha256=" & entry.source.manifestSha256 & "\n" &
    "source.sbomUrl=" & entry.source.sbomUrl & "\n" &
    "source.sbomSha256=" & entry.source.sbomSha256 & "\n"

proc runTool(tool: string; arguments: seq[string]): tuple[exitCode: int, output: string] =
  let process = startProcess(tool, args = arguments,
    options = {poUsePath, poStdErrToStdOut})
  result.output = process.outputStream.readAll()
  result.exitCode = process.waitForExit()
  process.close()

proc sha256File(path: string): PackResult[string] =
  let tool = findExe("sha256sum")
  if tool.len == 0:
    return failure[string](unsupportedFeature,
      "popular package verification requires sha256sum")
  try:
    let executed = runTool(tool, @["--", path])
    if executed.exitCode != 0:
      return failure[string](ioFailure,
        "popular package checksum tool failed")
    let fields = executed.output.splitWhitespace()
    if fields.len == 0 or not isSha256(fields[0].toLowerAscii()):
      return failure[string](ioFailure,
        "popular package checksum tool returned invalid output")
    success(fields[0].toLowerAscii())
  except OSError:
    failure[string](ioFailure, "popular package checksum tool could not start")

proc verifyPopularPackageRelease*(entry: PopularPackageEntry; artifactPath,
    sbomPath: string; trustedKey: PopularTrustedKey;
    policy = defaultPopularCatalogPolicy()): PackResult[bool] =
  let checked = validateEntry(entry, policy)
  if not checked.isOk:
    return failure[bool](checked.error.kind, checked.error.detail)
  if trustedKey.keyId != entry.signature.keyId:
    return failure[bool](integrityFailure,
      "popular package signature keyId is not trusted")
  if not fileExists(trustedKey.publicKeyPath):
    return failure[bool](ioFailure,
      "popular package trusted public key does not exist")
  if not fileExists(artifactPath) or not fileExists(sbomPath):
    return failure[bool](ioFailure,
      "popular package artifact or SBOM does not exist")
  try:
    if getFileSize(artifactPath) != entry.artifact.size:
      return failure[bool](integrityFailure,
        "popular package artifact size does not match catalog")
  except OSError:
    return failure[bool](ioFailure,
      "popular package artifact size could not be read")
  let artifactHash = sha256File(artifactPath)
  if not artifactHash.isOk:
    return failure[bool](artifactHash.error.kind, artifactHash.error.detail)
  if artifactHash.value != entry.artifact.sha256:
    return failure[bool](integrityFailure,
      "popular package artifact SHA-256 does not match catalog")
  let sbomHash = sha256File(sbomPath)
  if not sbomHash.isOk:
    return failure[bool](sbomHash.error.kind, sbomHash.error.detail)
  if sbomHash.value != entry.source.sbomSha256:
    return failure[bool](integrityFailure,
      "popular package SBOM SHA-256 does not match catalog")
  let minisign = findExe("minisign")
  if minisign.len == 0:
    return failure[bool](unsupportedFeature,
      "popular package verification requires minisign")
  var tempDirectory = ""
  try:
    tempDirectory = createTempDir("nimino-popular-", ".verify")
    let payloadPath = tempDirectory / "statement.txt"
    let signaturePath = tempDirectory / "statement.minisig"
    writeFile(payloadPath, popularPackageSignaturePayload(entry))
    writeFile(signaturePath, decode(entry.signature.value))
    let verified = runTool(minisign,
      @["-V", "-m", payloadPath, "-x", signaturePath,
        "-p", trustedKey.publicKeyPath, "-q"])
    if verified.exitCode != 0:
      return failure[bool](integrityFailure,
        "popular package signature verification failed")
    success(true)
  except ValueError:
    failure[bool](invalidManifest,
      "popular package signature is not valid base64")
  except OSError:
    failure[bool](ioFailure,
      "popular package signature verification could not run")
  finally:
    if tempDirectory.len > 0 and dirExists(tempDirectory):
      try:
        removeFile(tempDirectory / "statement.txt")
        removeFile(tempDirectory / "statement.minisig")
        removeDir(tempDirectory)
      except OSError:
        discard
