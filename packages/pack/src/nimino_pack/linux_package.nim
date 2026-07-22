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

proc copyAppImageFile(source, destination: string): PackResult[bool] =
  if not fileExists(source):
    return failure[bool](ioFailure, "AppImage dependency source is missing: " & source)
  try:
    let parent = parentDir(destination)
    if parent.len > 0 and not dirExists(parent):
      createDir(parent)
    copyFile(source, destination)
    setFilePermissions(destination, getFilePermissions(source))
    success(true)
  except OSError:
    failure[bool](ioFailure, "unable to copy AppImage dependency: " & source)

proc copyAppImageDirectory(source, destination: string): PackResult[bool] =
  if not dirExists(source):
    return failure[bool](ioFailure, "AppImage dependency directory is missing: " & source)
  try:
    createDir(destination)
    for path in walkDirRec(source):
      let relative = relativePath(path, source)
      let target = destination / relative
      if dirExists(path):
        createDir(target)
      else:
        let copied = copyAppImageFile(path, target)
        if not copied.isOk:
          return copied
    success(true)
  except OSError:
    failure[bool](ioFailure, "unable to copy AppImage dependency directory: " & source)

proc appImageCommandOutput(command: string; arguments: openArray[string]): PackResult[string] =
  var commandLine = command.shellQuote()
  for argument in arguments:
    commandLine.add(" " & argument.shellQuote())
  let executed = execCmdEx(commandLine)
  if executed.exitCode != 0:
    return failure[string](ioFailure,
      "AppImage dependency tool failed: " & extractFilename(command))
  success(executed.output.strip())

proc appImageCopyTree(lddtree, seed, destination: string): PackResult[bool] =
  let output = appImageCommandOutput(lddtree, ["--copy-to-tree", destination, seed])
  if not output.isOk:
    return failure[bool](output.error.kind, output.error.detail)
  success(true)

proc appImageSetRPath(patchelf, target, value: string): PackResult[bool] =
  let applied = patchelf.executeTool(["--set-rpath", value, target])
  if not applied.isOk:
    return failure[bool](applied.error.kind, applied.error.detail)
  success(true)

proc appImageAppRun(metadata: LinuxBundleMetadata): string =
  """#!/bin/sh
set -eu
APPDIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export LD_LIBRARY_PATH="$APPDIR/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export GSETTINGS_SCHEMA_DIR="$APPDIR/usr/share/glib-2.0/schemas"
export GIO_MODULE_DIR="$APPDIR/usr/lib/gio/modules"
export GDK_PIXBUF_MODULEDIR="$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders"
export GDK_PIXBUF_MODULE_FILE="$APPDIR/usr/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache"
export WEBKIT_EXEC_PATH="$APPDIR/usr/lib/webkitgtk-6.0"
exec "$APPDIR/usr/lib/nimino/""" & metadata.id & """/run-nimino.sh" "$@"
"""

proc appImageDesktop(metadata: LinuxBundleMetadata): string =
  "[Desktop Entry]\n" &
    "Type=Application\n" &
    "Name=" & metadata.name & "\n" &
    "Comment=" & metadata.description & "\n" &
    "Exec=run-nimino.sh\n" &
    "Icon=" & metadata.id & "\n" &
    "Terminal=false\n" &
    "Categories=Network;\n"

proc buildAppImage(options: LinuxPackageOptions; metadata: LinuxBundleMetadata;
                   workDirectory, debArchitecture: string): PackResult[string] =
  if debArchitecture != "amd64":
    return failure[string](unsupportedFeature,
      "AppImage package generation currently supports amd64 only")
  if metadata.icon.len == 0:
    return failure[string](invalidManifest,
      "AppImage package generation requires a local icon in the bundle")
  let environment = validateAppImageBuildEnvironment()
  if not environment.isOk:
    return failure[string](environment.error.kind, environment.error.detail)
  let appImageTool = findExe("appimagetool")
  let linuxDeploy = findExe("linuxdeploy")
  let patchelf = findExe("patchelf")
  let lddtree = findExe("lddtree")
  let appDir = workDirectory / (metadata.id & ".AppDir")
  let bundleRoot = appDir / "usr" / "lib" / "nimino" / metadata.id
  let hostValidation = options.bundleDirectory.validateLinuxHost()
  if not hostValidation.isOk:
    return failure[string](hostValidation.error.kind, hostValidation.error.detail)
  let launcher = options.bundleDirectory / "run-nimino.sh"
  let launcherText = try: readFile(launcher)
  except OSError:
    return failure[string](ioFailure, "Linux AppImage launcher cannot be read")
  let marker = "exec \"$(dirname \"$0\")/"
  let markerStart = launcherText.find(marker)
  if markerStart < 0:
    return failure[string](invalidManifest, "Linux AppImage launcher host path is malformed")
  let hostStart = markerStart + marker.len
  let hostEnd = launcherText.find('"', hostStart)
  if hostEnd <= hostStart:
    return failure[string](invalidManifest, "Linux AppImage launcher host path is malformed")
  let hostName = launcherText[hostStart ..< hostEnd]
  let appHost = bundleRoot / hostName
  try:
    createDir(appDir / "usr" / "lib" / "nimino")
    copyDir(options.bundleDirectory, bundleRoot)
    discard options.bundleDirectory.preserveBundlePermissions(bundleRoot)
  except OSError:
    return failure[string](ioFailure, "unable to stage AppImage bundle")

  let copiedTree = appImageCopyTree(lddtree, appHost, appDir / "usr")
  if not copiedTree.isOk:
    return failure[string](copiedTree.error.kind, copiedTree.error.detail)
  let gtkLib = appImagePkgConfigVariable("gtk4", "libdir")
  let webKitLib = appImagePkgConfigVariable("webkitgtk-6.0", "libdir")
  let schemas = appImagePkgConfigVariable("gio-2.0", "schemasdir")
  let gioModules = appImagePkgConfigVariable("gio-2.0", "giomoduledir")
  let pixbufModules = appImagePkgConfigVariable("gdk-pixbuf-2.0", "gdk_pixbuf_moduledir")
  for inspected in [gtkLib, webKitLib, schemas, gioModules, pixbufModules]:
    if not inspected.isOk:
      return failure[string](inspected.error.kind, inspected.error.detail)
  for library in AppImageRequiredRuntimeLibraries:
    let source = (if library == AppImageRequiredRuntimeLibraries[0]: gtkLib.value else: webKitLib.value) / library
    let copied = copyAppImageFile(source, appDir / "usr" / "lib" / library)
    if not copied.isOk:
      return failure[string](copied.error.kind, copied.error.detail)
    let deployed = linuxDeploy.executeTool(["--appdir", appDir, "--library", source])
    if not deployed.isOk:
      return failure[string](deployed.error.kind, deployed.error.detail)
  let webKitRoot = webKitLib.value / "webkitgtk-6.0"
  let webKitDestination = appDir / "usr" / "lib" / "webkitgtk-6.0"
  for relative in AppImageRequiredWebKitAssets:
    let copied = copyAppImageFile(webKitRoot / relative, webKitDestination / relative)
    if not copied.isOk:
      return failure[string](copied.error.kind, copied.error.detail)
  let schemaCopy = copyAppImageDirectory(schemas.value, appDir / "usr" / "share" / "glib-2.0" / "schemas")
  let gioCopy = copyAppImageDirectory(gioModules.value, appDir / "usr" / "lib" / "gio" / "modules")
  let pixbufCopy = copyAppImageDirectory(pixbufModules.value,
    appDir / "usr" / "lib" / "gdk-pixbuf-2.0" / "2.10.0" / "loaders")
  for copied in [schemaCopy, gioCopy, pixbufCopy]:
    if not copied.isOk:
      return failure[string](copied.error.kind, copied.error.detail)
  let compiledSchemas = findExe("glib-compile-schemas").executeTool([
    appDir / "usr" / "share" / "glib-2.0" / "schemas"])
  let queriedGio = findExe("gio-querymodules").executeTool([
    appDir / "usr" / "lib" / "gio" / "modules"])
  if not compiledSchemas.isOk or not queriedGio.isOk:
    return failure[string](ioFailure, "AppImage runtime metadata compilation failed")
  var loaders: seq[string]
  for path in walkDirRec(appDir / "usr" / "lib" / "gdk-pixbuf-2.0" / "2.10.0" / "loaders"):
    if fileExists(path): loaders.add(path)
  if loaders.len == 0:
    return failure[string](ioFailure, "AppImage GdkPixbuf loader closure is empty")
  let loaderOutput = appImageCommandOutput(findExe("gdk-pixbuf-query-loaders"), loaders)
  if not loaderOutput.isOk:
    return failure[string](loaderOutput.error.kind, loaderOutput.error.detail)
  try:
    writeFile(appDir / "usr" / "lib" / "gdk-pixbuf-2.0" / "2.10.0" / "loaders.cache",
      loaderOutput.value)
    writeFile(appDir / "AppRun", metadata.appImageAppRun())
    setFilePermissions(appDir / "AppRun", {fpUserExec, fpUserRead, fpUserWrite,
      fpGroupExec, fpGroupRead, fpOthersExec, fpOthersRead})
    createDir(appDir / "usr" / "share" / "applications")
    writeFile(appDir / "usr" / "share" / "applications" / metadata.desktopFile,
      metadata.appImageDesktop())
    let iconExtension = splitFile(metadata.icon).ext
    createDir(appDir / "usr" / "share" / "icons" / "hicolor" / "128x128" / "apps")
    copyFile(options.bundleDirectory / metadata.icon,
      appDir / "usr" / "share" / "icons" / "hicolor" / "128x128" / (metadata.id & iconExtension))
  except OSError as error:
    return failure[string](ioFailure,
      "unable to write AppImage runtime metadata: " & error.msg)
  let hostRPath = appImageSetRPath(patchelf, appHost, "$ORIGIN/../..:$ORIGIN/../../lib")
  if not hostRPath.isOk:
    return failure[string](hostRPath.error.kind, hostRPath.error.detail)
  for relative in AppImageRequiredWebKitAssets:
    if not relative.endsWith(".so"):
      let helperRPath = appImageSetRPath(patchelf, webKitDestination / relative, "$ORIGIN/..")
      if not helperRPath.isOk:
        return failure[string](helperRPath.error.kind, helperRPath.error.detail)
  for relative in AppImageRequiredWebKitAssets:
    let seed = webKitDestination / relative
    let report = appImageCommandOutput(lddtree, ["-l", seed])
    if not report.isOk:
      return failure[string](report.error.kind, report.error.detail)
    let checked = validateAppImageDependencyReport(report.value, 0,
      [extractFilename(seed)])
    if not checked.isOk:
      return failure[string](checked.error.kind,
        checked.error.detail & " (copied seed: " & relative & ")")
  let outputPath = options.outputDirectory / (metadata.id & "-" & metadata.version & "-x86_64.AppImage")
  let built = appImageTool.executeTool([appDir, outputPath])
  if not built.isOk:
    return failure[string](built.error.kind, built.error.detail)
  if not fileExists(outputPath) or getFileSize(outputPath) == 0:
    return failure[string](ioFailure, "appimagetool did not produce the expected AppImage")
  success(outputPath)

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
