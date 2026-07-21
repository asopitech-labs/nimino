## Windows distribution installers built from a public nimino-pack bundle.
##
## NSIS is compiled on Linux by makensis, but the resulting installer must be
## executed and code-signed on Windows before release.

import std/[json, os, osproc, strutils]

import ./manifest

type
  WindowsPackageFormat* = enum
    nsisPackage
    msiPackage

  WindowsPackageOptions* = object
    bundleDirectory*: string
    outputDirectory*: string
    format*: WindowsPackageFormat

  WindowsBundleMetadata = object
    id: string
    displayName: string
    version: string
    publisher: string
    description: string
    homepage: string
    installScope: string
    installRoot: string
    entryPoint: string
    uninstaller: string
    startMenuShortcut: string
    webViewRuntime: string
    displayIcon: string

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

proc validateWindowsHost(bundleDirectory: string): PackResult[bool] =
  var found = false
  try:
    for path in walkDirRec(bundleDirectory):
      if parentDir(path) == bundleDirectory and
          path.toLowerAscii().endsWith(".exe") and fileExists(path):
        found = true
        break
  except OSError:
    return failure[bool](ioFailure, "Windows package bundle cannot be scanned")
  if not found:
    return failure[bool](ioFailure,
      "Windows package bundle is missing a host executable")
  success(true)

proc jsonString(node: JsonNode; key: string): PackResult[string] =
  if node.isNil or node.kind != JObject or not node.hasKey(key) or
      node[key].kind != JString:
    return failure[string](invalidManifest,
      "Windows package metadata requires string field: " & key)
  success(node[key].getStr())

proc expectedInstallRoot(id: string): string =
  "%LOCALAPPDATA%\\Nimino\\" & id

proc expectedShortcut(id: string): string =
  "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Nimino\\" & id & ".lnk"

proc readWindowsBundleMetadata(bundleDirectory: string): PackResult[WindowsBundleMetadata] =
  if bundleDirectory.len == 0 or not dirExists(bundleDirectory):
    return failure[WindowsBundleMetadata](ioFailure,
      "Windows package bundle directory does not exist")
  let metadataPath = bundleDirectory / "nimino-windows-installer.json"
  if not fileExists(metadataPath):
    return failure[WindowsBundleMetadata](ioFailure,
      "Windows package bundle is missing nimino-windows-installer.json")
  let node = try:
    parseJson(readFile(metadataPath))
  except CatchableError:
    return failure[WindowsBundleMetadata](invalidManifest,
      "Windows package metadata is not valid JSON")
  if node.kind != JObject or not node.hasKey("schemaVersion") or
      node["schemaVersion"].kind != JInt or node["schemaVersion"].getInt() != 1:
    return failure[WindowsBundleMetadata](invalidManifest,
      "Windows package metadata schemaVersion must be 1")
  var metadata: WindowsBundleMetadata
  for key in ["id", "displayName", "version", "publisher", "description", "homepage",
              "installScope", "installRoot", "entryPoint", "uninstaller",
              "startMenuShortcut", "webViewRuntime", "displayIcon"]:
    let parsed = node.jsonString(key)
    if not parsed.isOk:
      return failure[WindowsBundleMetadata](parsed.error.kind, parsed.error.detail)
    case key
    of "id": metadata.id = parsed.value
    of "displayName": metadata.displayName = parsed.value
    of "version": metadata.version = parsed.value
    of "publisher": metadata.publisher = parsed.value
    of "description": metadata.description = parsed.value
    of "homepage": metadata.homepage = parsed.value
    of "installScope": metadata.installScope = parsed.value
    of "installRoot": metadata.installRoot = parsed.value
    of "entryPoint": metadata.entryPoint = parsed.value
    of "uninstaller": metadata.uninstaller = parsed.value
    of "startMenuShortcut": metadata.startMenuShortcut = parsed.value
    of "webViewRuntime": metadata.webViewRuntime = parsed.value
    of "displayIcon": metadata.displayIcon = parsed.value
    else: discard
  if not safePackageId(metadata.id) or
      not noControlCharacters(metadata.displayName) or
      not noControlCharacters(metadata.version) or
      not noControlCharacters(metadata.publisher) or
      not noControlCharacters(metadata.description) or
      not noControlCharacters(metadata.homepage):
    return failure[WindowsBundleMetadata](invalidManifest,
      "Windows package metadata contains unsafe text")
  if metadata.installScope != "perUser" or
      metadata.installRoot != metadata.id.expectedInstallRoot() or
      metadata.entryPoint != "run-nimino.cmd" or
      metadata.uninstaller != "uninstall-windows.ps1" or
      metadata.startMenuShortcut != metadata.id.expectedShortcut() or
      metadata.webViewRuntime != "evergreen":
    return failure[WindowsBundleMetadata](invalidManifest,
      "Windows package metadata does not match the Nimino per-user install layout")
  if metadata.displayIcon.len > 0 and
      (not safeFileName(metadata.displayIcon) or
       not fileExists(bundleDirectory / metadata.displayIcon)):
    return failure[WindowsBundleMetadata](invalidManifest,
      "Windows package metadata icon is missing or unsafe")
  if not fileExists(bundleDirectory / metadata.entryPoint) or
      not fileExists(bundleDirectory / "nimino-manifest.json"):
    return failure[WindowsBundleMetadata](ioFailure,
      "Windows package bundle is missing a launcher or manifest")
  let host = bundleDirectory.validateWindowsHost()
  if not host.isOk:
    return failure[WindowsBundleMetadata](host.error.kind, host.error.detail)
  success(metadata)

proc shellQuote(value: string): string =
  "'" & value.replace("'", "'\"'\"'") & "'"

proc executeTool(command: string; arguments: openArray[string]): PackResult[bool] =
  var commandLine = command.shellQuote()
  for argument in arguments:
    commandLine.add(" " & argument.shellQuote())
  let executed = execCmdEx(commandLine)
  if executed.exitCode != 0:
    var detail = "Windows package tool failed: " & extractFilename(command)
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

proc nsisString(value: string): string =
  ## Values are inserted into quoted NSIS strings, never as code fragments.
  value.replace("$", "$$").replace("\"", "$\\\"")

proc nsisScript(metadata: WindowsBundleMetadata; bundleDirectory, outputPath: string): string =
  let uninstallKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" & metadata.id
  let shortcut = "$SMPROGRAMS\\Nimino\\" & metadata.id & ".lnk"
  let source = bundleDirectory / "*"
  result = "Unicode true\n" &
    "RequestExecutionLevel user\n" &
    "SetCompressor /SOLID lzma\n" &
    "Name \"" & metadata.displayName.nsisString() & "\"\n" &
    "OutFile \"" & outputPath.nsisString() & "\"\n" &
    "InstallDir \"$LOCALAPPDATA\\Nimino\\" & metadata.id & "\"\n" &
    "InstallDirRegKey HKCU \"" & uninstallKey & "\" \"InstallLocation\"\n" &
    "Page directory\nPage instfiles\nUninstPage uninstConfirm\nUninstPage instfiles\n\n" &
    "Section \"Install\"\n" &
    "  SetShellVarContext current\n" &
    "  SetOutPath \"$INSTDIR\"\n" &
    "  File /r \"" & source.nsisString() & "\"\n" &
    "  WriteUninstaller \"$INSTDIR\\uninstall.exe\"\n" &
    "  CreateDirectory \"$SMPROGRAMS\\Nimino\"\n" &
    "  CreateShortcut \"" & shortcut & "\" \"$INSTDIR\\" & metadata.entryPoint & "\"\n" &
    "  WriteRegStr HKCU \"" & uninstallKey & "\" \"DisplayName\" \"" &
      metadata.displayName.nsisString() & "\"\n" &
    "  WriteRegStr HKCU \"" & uninstallKey & "\" \"DisplayVersion\" \"" &
      metadata.version.nsisString() & "\"\n" &
    "  WriteRegStr HKCU \"" & uninstallKey & "\" \"InstallLocation\" \"$INSTDIR\"\n" &
    "  WriteRegStr HKCU \"" & uninstallKey & "\" \"UninstallString\" \"$\\\"$INSTDIR\\uninstall.exe$\\\"\"\n" &
    "  WriteRegDWORD HKCU \"" & uninstallKey & "\" \"NoModify\" 1\n" &
    "  WriteRegDWORD HKCU \"" & uninstallKey & "\" \"NoRepair\" 1\n"
  if metadata.publisher.len > 0:
    result.add("  WriteRegStr HKCU \"" & uninstallKey & "\" \"Publisher\" \"" &
      metadata.publisher.nsisString() & "\"\n")
  if metadata.homepage.len > 0:
    result.add("  WriteRegStr HKCU \"" & uninstallKey & "\" \"URLInfoAbout\" \"" &
      metadata.homepage.nsisString() & "\"\n")
  if metadata.displayIcon.len > 0:
    result.add("  WriteRegStr HKCU \"" & uninstallKey & "\" \"DisplayIcon\" \"$INSTDIR\\" &
      metadata.displayIcon & "\"\n")
  result.add("SectionEnd\n\n" &
    "Section \"Uninstall\"\n" &
    "  SetShellVarContext current\n" &
    "  Delete \"" & shortcut & "\"\n" &
    "  DeleteRegKey HKCU \"" & uninstallKey & "\"\n" &
    "  RMDir /r \"$INSTDIR\"\n" &
    "  RMDir \"$SMPROGRAMS\\Nimino\"\n" &
    "SectionEnd\n")

proc buildNsis(options: WindowsPackageOptions; metadata: WindowsBundleMetadata): PackResult[string] =
  let tool = findExe("makensis")
  if tool.len == 0:
    return failure[string](unsupportedFeature,
      "NSIS package generation requires makensis in the Docker image")
  let outputName = metadata.id & "-" & metadata.version & "-setup.exe"
  let scriptName = metadata.id & "-" & metadata.version & "-setup.nsi"
  let outputPath = options.outputDirectory / outputName
  let scriptPath = options.outputDirectory / scriptName
  if fileExists(outputPath) or fileExists(scriptPath):
    return failure[string](ioFailure, "Windows package output already exists")
  try:
    writeFile(scriptPath, metadata.nsisScript(options.bundleDirectory, outputPath))
  except OSError:
    return failure[string](ioFailure, "unable to write NSIS installer script")
  let built = tool.executeTool([scriptPath])
  if not built.isOk:
    return failure[string](built.error.kind, built.error.detail)
  if not fileExists(outputPath) or getFileSize(outputPath) == 0:
    return failure[string](ioFailure, "NSIS did not produce the expected installer")
  success(outputPath)

proc buildWindowsPackage*(options: WindowsPackageOptions): PackResult[string] =
  let metadata = options.bundleDirectory.readWindowsBundleMetadata()
  if not metadata.isOk:
    return failure[string](metadata.error.kind, metadata.error.detail)
  let output = options.outputDirectory.ensureDirectory()
  if not output.isOk:
    return failure[string](output.error.kind, output.error.detail)
  case options.format
  of nsisPackage:
    return options.buildNsis(metadata.value)
  of msiPackage:
    return failure[string](unsupportedFeature,
      "MSI package generation is unavailable: a fixed WiX toolchain and Windows Installer validation are not configured")
