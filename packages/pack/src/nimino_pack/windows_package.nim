## Windows distribution installers built from a public nimino-pack bundle.
##
## NSIS is compiled on Linux by makensis, but the resulting installer must be
## executed and code-signed on Windows before release.

import std/[algorithm, json, os, osproc, strutils]

import ./manifest

const webView2AppGuid = "F3017226-FE2A-4295-8BDF-00C3A9A7E4C5"
const webView2BootstrapperUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"

type
  WindowsPackageFormat* = enum
    nsisPackage
    msiPackage

  WindowsPackageOptions* = object
    bundleDirectory*: string
    outputDirectory*: string
    format*: WindowsPackageFormat
    architecture*: string

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
    appUserModelId: string
    toastActivation: string
    toastActivatorClsid: string
    shortcutPropertiesScript: string
    startMenuShortcut: string
    webViewRuntime: string
    displayIcon: string
    hostExecutable: string
    deepLinkSchemes: seq[string]

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

proc validClsid(value: string): bool =
  if value.len != 36:
    return false
  for index, character in value:
    if index in [8, 13, 18, 23]:
      if character != '-':
        return false
    elif character notin {'0'..'9', 'a'..'f', 'A'..'F'}:
      return false
  true

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

proc jsonStringArray(node: JsonNode; key: string): PackResult[seq[string]] =
  if node.isNil or node.kind != JObject:
    return failure[seq[string]](invalidManifest,
      "Windows package metadata requires string array field: " & key)
  if not node.hasKey(key):
    ## Keep schemaVersion 1 bundles generated before deep-link support
    ## installable without registering any OS URL scheme.
    return success(newSeq[string]())
  if node[key].kind != JArray:
    return failure[seq[string]](invalidManifest,
      "Windows package metadata requires string array field: " & key)
  var values: seq[string]
  for item in node[key].items:
    if item.kind != JString or not validDeepLinkScheme(item.getStr()):
      return failure[seq[string]](invalidManifest,
        "Windows package metadata contains an invalid deep-link scheme")
    let value = item.getStr().toLowerAscii()
    if value notin values:
      values.add(value)
  success(values)

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
              "appUserModelId", "toastActivation", "toastActivatorClsid", "hostExecutable", "shortcutPropertiesScript",
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
    of "appUserModelId": metadata.appUserModelId = parsed.value
    of "toastActivation": metadata.toastActivation = parsed.value
    of "toastActivatorClsid": metadata.toastActivatorClsid = parsed.value
    of "hostExecutable": metadata.hostExecutable = parsed.value
    of "shortcutPropertiesScript": metadata.shortcutPropertiesScript = parsed.value
    of "startMenuShortcut": metadata.startMenuShortcut = parsed.value
    of "webViewRuntime": metadata.webViewRuntime = parsed.value
    of "displayIcon": metadata.displayIcon = parsed.value
    else: discard
  let deepLinks = node.jsonStringArray("deepLinkSchemes")
  if not deepLinks.isOk:
    return failure[WindowsBundleMetadata](deepLinks.error.kind, deepLinks.error.detail)
  metadata.deepLinkSchemes = deepLinks.value
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
      metadata.appUserModelId != metadata.id or
      metadata.toastActivation != "inProcessOrComLocalServer" or
      not validClsid(metadata.toastActivatorClsid) or
      not safeFileName(metadata.hostExecutable) or
      metadata.shortcutPropertiesScript != "register-windows-shortcut.ps1" or
      metadata.startMenuShortcut != metadata.id.expectedShortcut() or
      metadata.webViewRuntime != "evergreen":
    return failure[WindowsBundleMetadata](invalidManifest,
      "Windows package metadata does not match the Nimino per-user install layout")
  if not fileExists(bundleDirectory / metadata.hostExecutable):
    return failure[WindowsBundleMetadata](ioFailure,
      "Windows package bundle is missing a host executable")
  if metadata.displayIcon.len > 0 and
      (not safeFileName(metadata.displayIcon) or
       not fileExists(bundleDirectory / metadata.displayIcon)):
    return failure[WindowsBundleMetadata](invalidManifest,
      "Windows package metadata icon is missing or unsafe")
  if not fileExists(bundleDirectory / metadata.entryPoint) or
      not fileExists(bundleDirectory / metadata.shortcutPropertiesScript) or
      not fileExists(bundleDirectory / "nimino-manifest.json"):
    return failure[WindowsBundleMetadata](ioFailure,
      "Windows package bundle is missing a launcher, shortcut helper, or manifest")
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
    "!include LogicLib.nsh\n" &
    "RequestExecutionLevel user\n" &
    "SetCompressor /SOLID lzma\n" &
    "Name \"" & metadata.displayName.nsisString() & "\"\n" &
    "OutFile \"" & outputPath.nsisString() & "\"\n" &
    "InstallDir \"$LOCALAPPDATA\\Nimino\\" & metadata.id & "\"\n" &
    "InstallDirRegKey HKCU \"" & uninstallKey & "\" \"InstallLocation\"\n" &
    "Page directory\nPage instfiles\nUninstPage uninstConfirm\nUninstPage instfiles\n\n" &
    "Section \"Install\"\n" &
    "  ; Match Tauri's downloadBootstrapper mode: install Evergreen Runtime only when absent.\n" &
    "  ReadRegStr $4 HKLM \"SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{" &
      webView2AppGuid & "}\" \"pv\"\n" &
    "  StrCmp $4 \"\" 0 webview2_done\n" &
    "  ReadRegStr $4 HKLM \"SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{" &
      webView2AppGuid & "}\" \"pv\"\n" &
    "  StrCmp $4 \"\" 0 webview2_done\n" &
    "  ReadRegStr $4 HKCU \"SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{" &
      webView2AppGuid & "}\" \"pv\"\n" &
    "  StrCmp $4 \"\" 0 webview2_done\n" &
    "  Delete \"$TEMP\\MicrosoftEdgeWebView2Setup.exe\"\n" &
    "  NSISdl::download \"" & webView2BootstrapperUrl & "\" \"$TEMP\\MicrosoftEdgeWebView2Setup.exe\"\n" &
    "  Pop $0\n" &
    "  StrCmp $0 \"success\" 0 webview2_download_failed\n" &
    "  ExecWait '\"$TEMP\\MicrosoftEdgeWebView2Setup.exe\" /silent /install' $1\n" &
    "  StrCmp $1 \"0\" 0 webview2_install_failed\n" &
    "  Delete \"$TEMP\\MicrosoftEdgeWebView2Setup.exe\"\n" &
    "  Goto webview2_done\n" &
    "webview2_download_failed:\n" &
    "  Abort \"Unable to download the WebView2 Evergreen Runtime\"\n" &
    "webview2_install_failed:\n" &
    "  Abort \"Unable to install the WebView2 Evergreen Runtime\"\n" &
    "webview2_done:\n" &
    "  SetShellVarContext current\n" &
    "  SetOutPath \"$INSTDIR\"\n" &
    "  File /r \"" & source.nsisString() & "\"\n" &
    "  WriteUninstaller \"$INSTDIR\\uninstall.exe\"\n" &
    "  CreateDirectory \"$SMPROGRAMS\\Nimino\"\n" &
    "  CreateShortcut \"" & shortcut & "\" \"$INSTDIR\\" & metadata.entryPoint & "\"\n" &
    "  ExecWait '\"powershell.exe\" -NoProfile -ExecutionPolicy Bypass -File \"$INSTDIR\\" &
      metadata.shortcutPropertiesScript & "\" -ShortcutPath \"" & shortcut &
      "\" -AppUserModelId \"" & metadata.appUserModelId.nsisString() &
      "\" -ToastActivatorClsid \"" & metadata.toastActivatorClsid.nsisString() & "\"' $0\n" &
    "  StrCmp $0 \"0\" +2\n" &
    "  Abort \"Unable to configure Windows AppUserModelId shortcut property\"\n" &
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
  result.add("  WriteRegStr HKCU \"Software\\Classes\\CLSID\\{" &
    metadata.toastActivatorClsid & "}\\LocalServer32\" \"\" \"$\\\"$INSTDIR\\" &
    metadata.hostExecutable & "$\\\" -Embedding --manifest $\\\"$INSTDIR\\nimino-manifest.json$\\\"\"\n")
  for scheme in metadata.deepLinkSchemes:
    let schemeKey = "Software\\Classes\\" & scheme
    result.add("  WriteRegStr HKCU \"" & schemeKey & "\" \"\" \"URL:Nimino " &
      scheme.nsisString() & " Protocol\"\n" &
      "  WriteRegStr HKCU \"" & schemeKey & "\" \"URL Protocol\" \"\"\n" &
      "  WriteRegStr HKCU \"" & schemeKey & "\\shell\\open\\command\" \"\" \"$\\\"$INSTDIR\\" &
      metadata.entryPoint & "$\\\" $\\\"%1$\\\"\"\n")
  result.add("SectionEnd\n\n" &
    "Section \"Uninstall\"\n" &
    "  SetShellVarContext current\n" &
    "  Delete \"" & shortcut & "\"\n" &
    "  DeleteRegKey HKCU \"" & uninstallKey & "\"\n" &
    "  DeleteRegKey HKCU \"Software\\Classes\\CLSID\\{" & metadata.toastActivatorClsid & "}\"\n" &
    "  RMDir /r \"$INSTDIR\"\n")
  for scheme in metadata.deepLinkSchemes:
    result.add("  DeleteRegKey HKCU \"Software\\Classes\\" & scheme & "\"\n")
  result.add(
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

proc xmlAttribute(value: string): string =
  ## Escape a value inserted into a single-quoted WiX XML attribute.
  value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    .replace("'", "&apos;").replace("\"", "&quot;")

proc stableMsiGuid(seed: string): string =
  ## Derive a stable component/product GUID without adding a crypto dependency.
  ## The GUID is an identifier, not an authenticity mechanism; signed artifacts
  ## remain the release boundary.
  var first = 1469598103934665603'u64
  var second = 1099511628211'u64
  for index, character in seed:
    first = (first xor uint64(ord(character))) * 1099511628211'u64
    second = (second xor uint64(ord(character) + index + 1)) * 1469598103934665603'u64
  let left = toHex(first, 16)
  let right = toHex(second, 16)
  result = left[0..7] & "-" & left[8..11] & "-" & left[12..15] & "-" &
    right[0..3] & "-" & right[4..15]

proc msiVersion(value: string): PackResult[string] =
  let parts = value.split('.')
  if parts.len < 1 or parts.len > 4:
    return failure[string](invalidManifest, "MSI package version must contain one to four numeric components")
  for part in parts:
    if part.len == 0 or not part.allCharsInSet({'0'..'9'}) or
        parseInt(part) > 65535:
      return failure[string](invalidManifest, "MSI package version must contain numeric components <= 65535")
  success(value)

proc wixFileEntries(bundleDirectory: string): PackResult[seq[tuple[name, source: string]]] =
  var entries: seq[tuple[name, source: string]] = @[]
  try:
    for kind, path in walkDir(bundleDirectory, relative = false):
      if kind != pcFile:
        continue
      let name = path.lastPathPart()
      if not safeFileName(name):
        return failure[seq[tuple[name, source: string]]](invalidManifest,
          "Windows MSI bundle contains an unsafe top-level filename")
      entries.add((name, path))
  except OSError:
    return failure[seq[tuple[name, source: string]]](ioFailure,
      "Windows MSI bundle cannot be scanned")
  if entries.len == 0:
    return failure[seq[tuple[name, source: string]]](ioFailure,
      "Windows MSI bundle contains no files")
  entries.sort(proc(left, right: tuple[name, source: string]): int = cmp(left.name, right.name))
  success(entries)

proc wixSource(metadata: WindowsBundleMetadata; bundleDirectory, version: string;
               entries: seq[tuple[name, source: string]]): string =
  let productGuid = stableMsiGuid("product:" & metadata.id)
  result = "<?xml version='1.0' encoding='utf-8'?>\n" &
    "<Wix xmlns='http://schemas.microsoft.com/wix/2006/wi'>\n" &
    "  <Product Name='" & metadata.displayName.xmlAttribute() & "' Id='*' UpgradeCode='{" &
      productGuid & "}' Language='1033' Version='" & version & "' Manufacturer='" &
      metadata.publisher.xmlAttribute() & "'>\n" &
    "    <Package Id='*' Keywords='Installer' Description='" & metadata.description.xmlAttribute() &
      "' Manufacturer='" & metadata.publisher.xmlAttribute() &
      "' InstallerVersion='100' Languages='1033' Compressed='yes' SummaryCodepage='1252'\n" &
    "             InstallPrivileges='limited' InstallScope='perUser' />\n" &
    "    <MajorUpgrade Schedule='afterInstallInitialize' AllowDowngrades='no'\n" &
    "                  DowngradeErrorMessage='A newer version of this application is already installed.' />\n" &
    "    <Media Id='1' Cabinet='nimino.cab' EmbedCab='yes' />\n" &
    "    <!-- Match Pake/Tauri: bootstrap WebView2 only when the Evergreen Runtime is absent. -->\n" &
    "    <Property Id='WVRTINSTALLED'>\n" &
    "      <RegistrySearch Id='WVRTInstalledSystem64' Root='HKLM' Key='SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{" &
      webView2AppGuid & "}' Name='pv' Type='raw' Win64='yes' />\n" &
    "      <RegistrySearch Id='WVRTInstalledSystem32' Root='HKLM' Key='SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{" &
      webView2AppGuid & "}' Name='pv' Type='raw' Win64='no' />\n" &
    "      <RegistrySearch Id='WVRTInstalledUser' Root='HKCU' Key='SOFTWARE\\Microsoft\\EdgeUpdate\\Clients\\{" &
      webView2AppGuid & "}' Name='pv' Type='raw' />\n" &
    "    </Property>\n" &
    "    <Property Id='NIMINO_POWERSHELL'>[SystemFolder]WindowsPowerShell\\v1.0\\powershell.exe</Property>\n" &
    "    <CustomAction Id='DownloadAndInvokeBootstrapper' Property='NIMINO_POWERSHELL' Execute='deferred' " &
      "ExeCommand=\"-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command &quot;$$ErrorActionPreference='Stop'; " &
      "try { [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12 } catch {}; " &
      "Invoke-WebRequest -UseBasicParsing -Uri '" & webView2BootstrapperUrl & "' -OutFile (Join-Path $$env:TEMP 'MicrosoftEdgeWebView2Setup.exe'); " &
      "$$p=Start-Process -FilePath (Join-Path $$env:TEMP 'MicrosoftEdgeWebView2Setup.exe') -ArgumentList '/silent','/install' -Wait -PassThru; " &
      "if ($$p.ExitCode -ne 0) { exit $$p.ExitCode }&quot;\" Return='check' />\n" &
    "    <InstallExecuteSequence>\n" &
    "      <Custom Action='DownloadAndInvokeBootstrapper' Before='InstallFinalize'>NOT(REMOVE OR WVRTINSTALLED)</Custom>\n" &
    "    </InstallExecuteSequence>\n" &
    "    <Directory Id='TARGETDIR' Name='SourceDir'>\n" &
    "      <Directory Id='LocalAppDataFolder' Name='LocalAppData'>\n" &
    "        <Directory Id='NiminoFolder' Name='Nimino'>\n" &
    "          <Directory Id='INSTALLDIR' Name='" & metadata.id.xmlAttribute() & "'>\n"
  var references = ""
  for index, entry in entries:
    let componentId = "cmp" & $index
    let fileId = "fil" & $index
    let componentGuid = stableMsiGuid("component:" & metadata.id & ":" & entry.name)
    result.add("            <Component Id='" & componentId & "' Guid='{" & componentGuid & "}' Win64='yes'>\n" &
      "              <File Id='" & fileId & "' KeyPath='yes' Source='" & entry.source.xmlAttribute() & "' />\n" &
      "            </Component>\n")
    references.add("        <ComponentRef Id='" & componentId & "' />\n")
  for index, scheme in metadata.deepLinkSchemes:
    let componentId = "cmpDeepLink" & $index
    let componentGuid = stableMsiGuid("deep-link:" & metadata.id & ":" & scheme)
    let command = "&quot;[INSTALLDIR]" & metadata.entryPoint & "&quot; &quot;%1&quot;"
    result.add("            <Component Id='" & componentId & "' Guid='{" & componentGuid & "}' Win64='yes'>\n" &
      "              <RegistryKey Root='HKCU' Key='Software\\Classes\\" & scheme & "'>\n" &
      "                <RegistryValue Type='string' Value='URL:Nimino " & scheme & " Protocol' KeyPath='yes' />\n" &
      "                <RegistryValue Name='URL Protocol' Type='string' Value='' />\n" &
      "              </RegistryKey>\n" &
      "              <RegistryKey Root='HKCU' Key='Software\\Classes\\" & scheme & "\\shell\\open\\command'>\n" &
      "                <RegistryValue Type='string' Value='" & command & "' />\n" &
      "              </RegistryKey>\n" &
      "            </Component>\n")
    references.add("        <ComponentRef Id='" & componentId & "' />\n")
  let toastComponentId = "cmpToastActivator"
  let toastComponentGuid = stableMsiGuid("toast-activator:" & metadata.id)
  let toastCommand = "&quot;[INSTALLDIR]" & metadata.hostExecutable &
    "&quot; -Embedding --manifest &quot;[INSTALLDIR]nimino-manifest.json&quot;"
  result.add("            <Component Id='" & toastComponentId & "' Guid='{" &
    toastComponentGuid & "}' Win64='yes'>\n" &
    "              <RegistryKey Root='HKCU' Key='Software\\Classes\\CLSID\\{" &
    metadata.toastActivatorClsid & "}\\LocalServer32'>\n" &
    "                <RegistryValue Type='string' Value='" & toastCommand &
    "' KeyPath='yes' />\n" &
    "              </RegistryKey>\n" &
    "            </Component>\n")
  references.add("        <ComponentRef Id='" & toastComponentId & "' />\n")
  let shortcutComponentId = "cmpStartMenuShortcut"
  let shortcutComponentGuid = stableMsiGuid("start-menu:" & metadata.id)
  let shortcutName = metadata.displayName.xmlAttribute()
  let uninstallKey = "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" & metadata.id
  result.add("          </Directory>\n" &
    "        </Directory>\n" &
    "      </Directory>\n" &
    "      <Directory Id='ProgramMenuFolder'>\n" &
    "        <Directory Id='NiminoProgramsFolder' Name='Nimino'>\n" &
    "          <Component Id='" & shortcutComponentId & "' Guid='{" & shortcutComponentGuid & "}'>\n" &
    "            <Shortcut Id='StartMenuShortcut' Name='" & shortcutName &
      "' Target='[INSTALLDIR]" & metadata.entryPoint.xmlAttribute() &
      "' WorkingDirectory='INSTALLDIR' />\n" &
    "            <RemoveFolder Id='RemoveNiminoProgramsFolder' On='uninstall' />\n" &
    "            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='DisplayName' Type='string' Value='" & shortcutName & "' KeyPath='yes' />\n" &
    "            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='DisplayVersion' Type='string' Value='" & metadata.version.xmlAttribute() & "' />\n" &
    "            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='InstallLocation' Type='string' Value='[INSTALLDIR]' />\n" &
    "            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='UninstallString' Type='string' Value='&quot;[SystemFolder]msiexec.exe&quot; /x [ProductCode]' />\n" &
    "            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='NoModify' Type='integer' Value='1' />\n" &
    "            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='NoRepair' Type='integer' Value='1' />\n"
  )
  if metadata.publisher.len > 0:
    result.add("            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='Publisher' Type='string' Value='" & metadata.publisher.xmlAttribute() & "' />\n")
  if metadata.homepage.len > 0:
    result.add("            <RegistryValue Root='HKCU' Key='" & uninstallKey &
      "' Name='URLInfoAbout' Type='string' Value='" & metadata.homepage.xmlAttribute() & "' />\n")
  result.add("          </Component>\n" &
    "        </Directory>\n" &
    "      </Directory>\n" &
    "    </Directory>\n" &
    "    <Feature Id='Complete' Level='1' Title='" & metadata.displayName.xmlAttribute() & "'>\n" &
    references &
    "        <ComponentRef Id='" & shortcutComponentId & "' />\n" &
    "    </Feature>\n" &
    "  </Product>\n" &
    "</Wix>\n")

proc buildMsi(options: WindowsPackageOptions; metadata: WindowsBundleMetadata): PackResult[string] =
  let tool = findExe("wixl")
  if tool.len == 0:
    return failure[string](unsupportedFeature,
      "MSI package generation requires wixl (msitools) in the Docker image")
  let version = metadata.version.msiVersion()
  if not version.isOk:
    return failure[string](version.error.kind, version.error.detail)
  let entries = options.bundleDirectory.wixFileEntries()
  if not entries.isOk:
    return failure[string](entries.error.kind, entries.error.detail)
  let outputName = metadata.id & "-" & metadata.version & ".msi"
  let scriptName = metadata.id & "-" & metadata.version & ".wxs"
  let outputPath = options.outputDirectory / outputName
  let scriptPath = options.outputDirectory / scriptName
  if fileExists(outputPath) or fileExists(scriptPath):
    return failure[string](ioFailure, "Windows MSI package output already exists")
  try:
    writeFile(scriptPath, metadata.wixSource(options.bundleDirectory, version.value, entries.value))
  except OSError:
    return failure[string](ioFailure, "unable to write WiX MSI descriptor")
  let built = tool.executeTool(["-o", outputPath, "--arch", "x64", scriptPath])
  try:
    removeFile(scriptPath)
  except OSError:
    discard
  if not built.isOk:
    return failure[string](built.error.kind, built.error.detail)
  if not fileExists(outputPath) or getFileSize(outputPath) == 0:
    return failure[string](ioFailure, "wixl did not produce the expected MSI package")
  success(outputPath)

proc buildWindowsPackage*(options: WindowsPackageOptions): PackResult[string] =
  if options.architecture.len > 0 and options.architecture notin ["x64", "amd64"]:
    return failure[string](unsupportedFeature,
      "Windows ARM64 packaging requires an ARM64 host executable and signer; the Linux pack builder currently supports x64 only")
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
    return options.buildMsi(metadata.value)
