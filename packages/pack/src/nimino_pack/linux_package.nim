## Linux distribution archives built from the public nimino-pack bundle.
##
## This module deliberately consumes `nimino-linux-package.json` rather than
## re-parsing a TOML manifest.  The generated bundle is the contract between
## `nimino pack` and OS-specific package creation.

import std/[json, os, osproc, strutils, times]

import ./[manifest, flatpak]
import ./private/appimage_guardrails

type
  LinuxPackageFormat* = enum
    debPackage
    rpmPackage
    appImagePackage
    flatpakPackage

  LinuxPackageOptions* = object
    bundleDirectory*: string
    outputDirectory*: string
    format*: LinuxPackageFormat
    architecture*: string
    maintainer*: string
    license*: string

  LinuxBundleMetadata = object
    id: string
    name: string
    version: string
    description: string
    homepage: string
    desktopFile: string
    installRoot: string
    entryPoint: string
    manifest: string
    icon: string

proc noControlCharacters(value: string): bool =
  for character in value:
    if ord(character) < 0x20 or ord(character) == 0x7f:
      return false
  true

proc safePackageId(value: string): bool =
  if value.len == 0 or value in [".", ".."]:
    return false
  for character in value:
    if character notin {'a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_'}:
      return false
  true

proc safeFileName(value: string): bool =
  safePackageId(value) and value.find('/') < 0 and value.find('\\') < 0

proc validateLinuxHost(bundleDirectory: string): PackResult[bool] =
  let launcherPath = bundleDirectory / "run-nimino.sh"
  let launcher = try: readFile(launcherPath)
  except OSError:
    return failure[bool](ioFailure, "Linux package bundle launcher cannot be read")
  let marker = "exec \"$(dirname \"$0\")/"
  let start = launcher.find(marker)
  if start < 0:
    return failure[bool](invalidManifest,
      "Linux package launcher does not contain a validated host path")
  let hostStart = start + marker.len
  let hostEnd = launcher.find('"', hostStart)
  if hostEnd <= hostStart:
    return failure[bool](invalidManifest,
      "Linux package launcher host path is malformed")
  let hostName = launcher[hostStart ..< hostEnd]
  if not safeFileName(hostName) or not fileExists(bundleDirectory / hostName):
    return failure[bool](ioFailure,
      "Linux package bundle is missing the host executable referenced by launcher")
  success(true)

proc jsonString(node: JsonNode; key: string): PackResult[string] =
  if node.isNil or node.kind != JObject or not node.hasKey(key) or
      node[key].kind != JString:
    return failure[string](invalidManifest,
      "Linux package metadata requires string field: " & key)
  success(node[key].getStr())

proc expectedInstallRoot(id: string): string = "/opt/nimino/" & id

proc readLinuxBundleMetadata(bundleDirectory: string): PackResult[LinuxBundleMetadata] =
  if bundleDirectory.len == 0 or not dirExists(bundleDirectory):
    return failure[LinuxBundleMetadata](ioFailure,
      "Linux package bundle directory does not exist")
  let metadataPath = bundleDirectory / "nimino-linux-package.json"
  if not fileExists(metadataPath):
    return failure[LinuxBundleMetadata](ioFailure,
      "Linux package bundle is missing nimino-linux-package.json")
  let node = try:
    parseJson(readFile(metadataPath))
  except CatchableError:
    return failure[LinuxBundleMetadata](invalidManifest,
      "Linux package metadata is not valid JSON")
  if node.kind != JObject or not node.hasKey("schemaVersion") or
      node["schemaVersion"].kind != JInt or node["schemaVersion"].getInt() != 1:
    return failure[LinuxBundleMetadata](invalidManifest,
      "Linux package metadata schemaVersion must be 1")
  var metadata: LinuxBundleMetadata
  for key in ["id", "name", "version", "description", "homepage", "desktopFile",
              "installRoot", "entryPoint", "manifest", "icon"]:
    let parsed = node.jsonString(key)
    if not parsed.isOk:
      return failure[LinuxBundleMetadata](parsed.error.kind, parsed.error.detail)
    case key
    of "id": metadata.id = parsed.value
    of "name": metadata.name = parsed.value
    of "version": metadata.version = parsed.value
    of "description": metadata.description = parsed.value
    of "homepage": metadata.homepage = parsed.value
    of "desktopFile": metadata.desktopFile = parsed.value
    of "installRoot": metadata.installRoot = parsed.value
    of "entryPoint": metadata.entryPoint = parsed.value
    of "manifest": metadata.manifest = parsed.value
    of "icon": metadata.icon = parsed.value
    else: discard
  if not safePackageId(metadata.id) or not noControlCharacters(metadata.name) or
      not noControlCharacters(metadata.version) or not noControlCharacters(metadata.description) or
      not noControlCharacters(metadata.homepage):
    return failure[LinuxBundleMetadata](invalidManifest,
      "Linux package metadata contains unsafe text")
  let installRoot = metadata.id.expectedInstallRoot()
  if metadata.installRoot != installRoot or metadata.entryPoint != installRoot / "run-nimino.sh" or
      metadata.manifest != installRoot / "nimino-manifest.json" or
      metadata.desktopFile != metadata.id & ".desktop" or not safeFileName(metadata.desktopFile):
    return failure[LinuxBundleMetadata](invalidManifest,
      "Linux package metadata does not match the Nimino install layout")
  if metadata.icon.len > 0:
    let iconName = extractFilename(metadata.icon)
    if not safeFileName(iconName) or metadata.icon != installRoot / iconName or
        not fileExists(bundleDirectory / iconName):
      return failure[LinuxBundleMetadata](invalidManifest,
        "Linux package metadata icon is missing or unsafe")
  if not fileExists(bundleDirectory / metadata.desktopFile) or
      not fileExists(bundleDirectory / "run-nimino.sh") or
      not fileExists(bundleDirectory / "nimino-manifest.json"):
    return failure[LinuxBundleMetadata](ioFailure,
      "Linux package bundle is missing a desktop entry, launcher, or manifest")
  let host = bundleDirectory.validateLinuxHost()
  if not host.isOk:
    return failure[LinuxBundleMetadata](host.error.kind, host.error.detail)
  success(metadata)

proc shellQuote(value: string): string =
  "'" & value.replace("'", "'\"'\"'") & "'"

proc executeTool(command: string; arguments: openArray[string]): PackResult[bool] =
  var commandLine = command.shellQuote()
  for argument in arguments:
    commandLine.add(" " & argument.shellQuote())
  let executed = execCmdEx(commandLine)
  if executed.exitCode != 0:
    var detail = "Linux package tool failed: " & extractFilename(command)
    let output = executed.output.strip()
    if output.len > 0:
      detail.add(": " & output)
    return failure[bool](ioFailure, detail)
  success(true)

proc ensureDirectory(path: string): PackResult[bool] =
  if dirExists(path):
    return success(true)
  try:
    createDir(path)
    success(true)
  except OSError:
    failure[bool](ioFailure, "unable to create package output directory")

proc temporaryDirectory(id: string): string =
  let prefix = "nimino-pack-" & id & "-" & $(int64(epochTime() * 1_000_000.0))
  result = getTempDir() / prefix
  var suffix = 0
  while dirExists(result):
    inc suffix
    result = getTempDir() / (prefix & "-" & $suffix)

proc preserveBundlePermissions(sourceDirectory, destinationDirectory: string): PackResult[bool] =
  ## copyDir copies content but not the executable mode needed by the generated
  ## launcher and host binary. Preserve the source bundle's regular-file modes.
  try:
    for sourcePath in walkDirRec(sourceDirectory):
      let relative = relativePath(sourcePath, sourceDirectory)
      setFilePermissions(destinationDirectory / relative, getFilePermissions(sourcePath))
    success(true)
  except OSError:
    failure[bool](ioFailure, "unable to preserve Linux package file permissions")

proc stageBundle(bundleDirectory, packageRoot: string;
                 metadata: LinuxBundleMetadata): PackResult[bool] =
  let optDirectory = packageRoot / "opt"
  let niminoDirectory = optDirectory / "nimino"
  let applicationDirectory = niminoDirectory / metadata.id
  let shareDirectory = packageRoot / "usr" / "share"
  let desktopDirectory = shareDirectory / "applications"
  try:
    createDir(packageRoot)
    createDir(optDirectory)
    createDir(niminoDirectory)
    copyDir(bundleDirectory, applicationDirectory)
    let permissions = bundleDirectory.preserveBundlePermissions(applicationDirectory)
    if not permissions.isOk:
      return permissions
    createDir(packageRoot / "usr")
    createDir(shareDirectory)
    createDir(desktopDirectory)
    copyFile(bundleDirectory / metadata.desktopFile,
      desktopDirectory / metadata.desktopFile)
    success(true)
  except OSError:
    failure[bool](ioFailure, "unable to stage Linux package bundle")

proc validateDesktopEntry(bundleDirectory: string;
                          metadata: LinuxBundleMetadata): PackResult[bool] =
  let validator = findExe("desktop-file-validate")
  if validator.len == 0:
    return failure[bool](unsupportedFeature,
      "Linux package generation requires desktop-file-validate in the Docker image")
  let validated = validator.executeTool([bundleDirectory / metadata.desktopFile])
  if not validated.isOk:
    return failure[bool](invalidManifest, "Linux desktop metadata validation failed")
  success(true)

proc debArchitecture(architecture: string): PackResult[string] =
  if architecture in ["amd64", "arm64"]:
    return success(architecture)
  failure[string](invalidManifest,
    "Linux package architecture must be amd64 or arm64")

proc rpmArchitecture(architecture: string): string =
  if architecture == "amd64": "x86_64" else: "aarch64"

proc rpmVersionSupported(version: string): bool =
  let components = version.split('.')
  if components.len != 3:
    return false
  for component in components:
    if component.len == 0:
      return false
    for character in component:
      if character notin {'0'..'9'}:
        return false
  true

proc rpmSpec(metadata: LinuxBundleMetadata; stagedRoot, rpmArchitecture,
             license: string): string =
  let escapedDescription = metadata.description.replace("%", "%%")
  result = "Name: " & metadata.id & "\n" &
    "Version: " & metadata.version & "\n" &
    "Release: 1%{?dist}\n" &
    "Summary: " & escapedDescription & "\n" &
    "License: " & license.replace("%", "%%") & "\n" &
    "BuildArch: " & rpmArchitecture & "\n"
  if metadata.homepage.len > 0:
    result.add("URL: " & metadata.homepage.replace("%", "%%") & "\n")
  result.add("\n%description\n" & escapedDescription & "\n\n" &
    "%install\nrm -rf %{buildroot}\nmkdir -p %{buildroot}\ncp -a " &
    stagedRoot.shellQuote() & "/. %{buildroot}/\n\n%files\n" &
    "/opt/nimino/" & metadata.id & "\n" &
    "/usr/share/applications/" & metadata.desktopFile & "\n")

proc buildDeb(options: LinuxPackageOptions; metadata: LinuxBundleMetadata;
              workDirectory, debArchitecture: string): PackResult[string] =
  let tool = findExe("dpkg-deb")
  if tool.len == 0:
    return failure[string](unsupportedFeature,
      "Debian package generation requires dpkg-deb in the Docker image")
  if options.maintainer.len == 0 or not noControlCharacters(options.maintainer):
    return failure[string](invalidManifest,
      "Debian package generation requires a control-character-free --maintainer")
  let packageRoot = workDirectory / "deb-root"
  let staged = options.bundleDirectory.stageBundle(packageRoot, metadata)
  if not staged.isOk:
    return failure[string](staged.error.kind, staged.error.detail)
  try:
    createDir(packageRoot / "DEBIAN")
    var control = "Package: " & metadata.id & "\n" &
      "Version: " & metadata.version & "\n" &
      "Section: utils\nPriority: optional\nArchitecture: " & debArchitecture & "\n" &
      "Maintainer: " & options.maintainer & "\n" &
      "Description: " & metadata.description & "\n"
    if metadata.homepage.len > 0:
      control.add("Homepage: " & metadata.homepage & "\n")
    writeFile(packageRoot / "DEBIAN" / "control", control)
  except OSError:
    return failure[string](ioFailure, "unable to write Debian package control metadata")
  let outputPath = options.outputDirectory /
    (metadata.id & "_" & metadata.version & "_" & debArchitecture & ".deb")
  if fileExists(outputPath):
    return failure[string](ioFailure, "Linux package output already exists")
  let built = tool.executeTool(["--build", packageRoot, outputPath])
  if not built.isOk:
    return failure[string](built.error.kind, built.error.detail)
  success(outputPath)

proc buildRpm(options: LinuxPackageOptions; metadata: LinuxBundleMetadata;
              workDirectory, debArchitecture: string): PackResult[string] =
  let tool = findExe("rpmbuild")
  if tool.len == 0:
    return failure[string](unsupportedFeature,
      "RPM package generation requires rpmbuild in the Docker image")
  if options.license.len == 0 or not noControlCharacters(options.license):
    return failure[string](invalidManifest,
      "RPM package generation requires a control-character-free --license")
  if not metadata.version.rpmVersionSupported():
    return failure[string](invalidManifest,
      "RPM package generation currently requires a release version such as 1.2.3")
  let packageRoot = workDirectory / "rpm-root"
  let staged = options.bundleDirectory.stageBundle(packageRoot, metadata)
  if not staged.isOk:
    return failure[string](staged.error.kind, staged.error.detail)
  let topDirectory = workDirectory / "rpmbuild"
  let rpmArchitecture = debArchitecture.rpmArchitecture()
  try:
    for directory in [topDirectory, topDirectory / "BUILD", topDirectory / "BUILDROOT",
                      topDirectory / "RPMS", topDirectory / "SOURCES", topDirectory / "SPECS",
                      topDirectory / "SRPMS"]:
      if not dirExists(directory): createDir(directory)
    writeFile(topDirectory / "SPECS" / (metadata.id & ".spec"),
      metadata.rpmSpec(packageRoot, rpmArchitecture, options.license))
  except OSError:
    return failure[string](ioFailure, "unable to write RPM package specification")
  let built = tool.executeTool([
    "--target", rpmArchitecture,
    "--define", "_topdir " & topDirectory,
    "--define", "_build_id_links none",
    "-bb", topDirectory / "SPECS" / (metadata.id & ".spec")
  ])
  if not built.isOk:
    return failure[string](built.error.kind, built.error.detail)
  let expected = topDirectory / "RPMS" / rpmArchitecture /
    (metadata.id & "-" & metadata.version & "-1." & rpmArchitecture & ".rpm")
  if not fileExists(expected):
    return failure[string](ioFailure, "RPM package tool did not produce the expected archive")
  let outputPath = options.outputDirectory / extractFilename(expected)
  if fileExists(outputPath):
    return failure[string](ioFailure, "Linux package output already exists")
  try:
    copyFile(expected, outputPath)
    success(outputPath)
  except OSError:
    failure[string](ioFailure, "unable to copy RPM package output")

proc buildAppImage(options: LinuxPackageOptions; metadata: LinuxBundleMetadata;
                   workDirectory, debArchitecture: string): PackResult[string] =
  ## Do not reinstate the former appimagetool-only path here.  An AppDir that
  ## merely contains the Nimino host is structurally valid but cannot launch
  ## on a system without GTK/WebKitGTK.  The dependency closure and WebKitGTK
  ## helper relocation must be implemented and verified as one unit before
  ## this branch is allowed to return success.
  discard options
  discard workDirectory
  if debArchitecture != "amd64":
    return failure[string](unsupportedFeature,
      "AppImage package generation currently supports amd64 only")
  if metadata.icon.len == 0:
    return failure[string](invalidManifest,
      "AppImage package generation requires a local icon in the bundle")
  let environment = validateAppImageBuildEnvironment()
  if not environment.isOk:
    return failure[string](environment.error.kind, environment.error.detail)
  failure[string](unsupportedFeature, AppImageIncompleteClosureError)

proc buildLinuxPackage*(options: LinuxPackageOptions): PackResult[string] =
  let metadata = options.bundleDirectory.readLinuxBundleMetadata()
  if not metadata.isOk:
    return failure[string](metadata.error.kind, metadata.error.detail)
  let architecture = options.architecture.debArchitecture()
  if not architecture.isOk:
    return failure[string](architecture.error.kind, architecture.error.detail)
  let output = options.outputDirectory.ensureDirectory()
  if not output.isOk:
    return failure[string](output.error.kind, output.error.detail)
  let desktop = options.bundleDirectory.validateDesktopEntry(metadata.value)
  if not desktop.isOk:
    return failure[string](desktop.error.kind, desktop.error.detail)
  let workDirectory = metadata.value.id.temporaryDirectory()
  try:
    case options.format
    of debPackage:
      return options.buildDeb(metadata.value, workDirectory, architecture.value)
    of rpmPackage:
      return options.buildRpm(metadata.value, workDirectory, architecture.value)
    of appImagePackage:
      return options.buildAppImage(metadata.value, workDirectory, architecture.value)
    of flatpakPackage:
      let built = buildFlatpakManifest(FlatpakManifestOptions(
        bundleDirectory: options.bundleDirectory,
        outputDirectory: options.outputDirectory))
      if not built.isOk:
        return failure[string](built.error.kind, built.error.detail)
      return built
  finally:
    if dirExists(workDirectory):
      try: removeDir(workDirectory)
      except OSError: discard
