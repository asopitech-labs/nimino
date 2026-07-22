## Deterministic Flatpak build-context generation.
##
## The repository does not embed flatpak-builder or a Flatpak runtime.  This
## module therefore produces a validated manifest plus a copied `bundle/`
## source directory.  A release pipeline can run flatpak-builder against that
## context without re-parsing the Nimino manifest or inventing permissions.

import std/[json, os, strutils]

import ./manifest

type
  FlatpakManifestOptions* = object
    bundleDirectory*: string
    outputDirectory*: string
    runtime*: string
    runtimeVersion*: string
    sdk*: string

proc safeFlatpakId(value: string): bool =
  if value.len == 0 or value[0] == '.' or value[^1] == '.':
    return false
  for part in value.split('.'):
    if part.len == 0:
      return false
    for character in part:
      if character notin {'a'..'z', 'A'..'Z', '0'..'9', '-', '_'}:
        return false
  true

proc buildFlatpakManifest*(options: FlatpakManifestOptions): PackResult[string] =
  if options.bundleDirectory.len == 0 or not dirExists(options.bundleDirectory):
    return failure[string](ioFailure, "Flatpak bundle directory does not exist")
  let metadataPath = options.bundleDirectory / "nimino-linux-package.json"
  let manifestPath = options.bundleDirectory / "nimino-manifest.json"
  if not fileExists(metadataPath) or not fileExists(manifestPath):
    return failure[string](ioFailure,
      "Flatpak bundle is missing Nimino package metadata")
  let metadata = try:
    parseJson(readFile(metadataPath))
  except CatchableError:
    return failure[string](invalidManifest,
      "Flatpak Linux package metadata is not valid JSON")
  if metadata.kind != JObject or not metadata.hasKey("id") or
      not metadata.hasKey("version") or metadata["id"].kind != JString or
      metadata["version"].kind != JString:
    return failure[string](invalidManifest,
      "Flatpak Linux package metadata requires id and version")
  let appId = metadata["id"].getStr()
  let version = metadata["version"].getStr()
  var unsafeVersion = version.len == 0 or version.len > 64
  for character in version:
    if character in {'\n', '\r', '\0'}:
      unsafeVersion = true
  if not safeFlatpakId(appId) or unsafeVersion:
    return failure[string](invalidManifest, "Flatpak app id or version is unsafe")
  let runtime = if options.runtime.len > 0: options.runtime else: "org.gnome.Platform"
  let runtimeVersion = if options.runtimeVersion.len > 0: options.runtimeVersion else: "49"
  let sdk = if options.sdk.len > 0: options.sdk else: "org.gnome.Sdk"
  if not safeFlatpakId(runtime) or not safeFlatpakId(sdk) or runtimeVersion.len == 0:
    return failure[string](invalidManifest, "Flatpak runtime metadata is unsafe")
  if options.outputDirectory.len == 0:
    return failure[string](invalidManifest, "Flatpak output directory is required")
  try:
    if not dirExists(options.outputDirectory):
      createDir(options.outputDirectory)
    let context = options.outputDirectory / (appId & "-" & version & "-flatpak")
    if dirExists(context):
      return failure[string](ioFailure, "Flatpak output already exists")
    createDir(context)
    copyDir(options.bundleDirectory, context / "bundle")
    let node = %*{
      "app-id": appId,
      "runtime": runtime,
      "runtime-version": runtimeVersion,
      "sdk": sdk,
      "branch": "stable",
      "command": "run-nimino.sh",
      "finish-args": [
        "--share=network",
        "--socket=wayland",
        "--socket=fallback-x11",
        "--device=dri"
      ],
      "modules": [{
        "name": "nimino-bundle",
        "buildsystem": "simple",
        "build-commands": [
          "install -Dm755 run-nimino.sh /app/bin/run-nimino.sh",
          "install -Dm644 " & appId & ".desktop /app/share/applications/" & appId & ".desktop",
          "sed -i -e 's#^Exec=.*#Exec=/app/bin/run-nimino.sh#' -e 's#^TryExec=.*#TryExec=/app/bin/run-nimino.sh#' /app/share/applications/" & appId & ".desktop",
          "install -d /app/lib/nimino",
          "cp -a . /app/lib/nimino"
        ],
        "sources": [{"type": "dir", "path": "bundle"}]
      }]
    }
    let outputPath = context / (appId & ".flatpak.json")
    writeFile(outputPath, node.pretty() & "\n")
    success(outputPath)
  except OSError:
    failure[string](ioFailure, "unable to create Flatpak build context")
