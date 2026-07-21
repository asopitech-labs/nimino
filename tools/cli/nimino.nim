import std/[json, os, strutils]

import nimino_pack

proc usage() =
  stderr.writeLine("usage: nimino pack <manifest.toml> [--out <directory>] [--host <executable>]")
  stderr.writeLine("       nimino pack <url> --name <name> --id <id> [--out <directory>] [--host <executable>]")
  stderr.writeLine("       nimino package-linux <bundle> --format <deb|rpm|appimage|flatpak> --out <directory> [--arch <amd64|arm64>] [--maintainer <value>] [--license <value>]")
  stderr.writeLine("       nimino package-windows <bundle> --format <nsis|msi> --out <directory>")
  quit(2)

proc packageLinuxUsage() =
  usage()

proc runPackageLinux() =
  if paramCount() < 3:
    packageLinuxUsage()
  var options = LinuxPackageOptions(bundleDirectory: paramStr(2), architecture: "amd64")
  var hasFormat = false
  var index = 3
  while index <= paramCount():
    if index == paramCount(): packageLinuxUsage()
    let flag = paramStr(index)
    let value = paramStr(index + 1)
    case flag
    of "--format":
      case value.toLowerAscii()
      of "deb": options.format = debPackage
      of "rpm": options.format = rpmPackage
      of "appimage": options.format = appImagePackage
      of "flatpak": options.format = flatpakPackage
      else: packageLinuxUsage()
      hasFormat = true
    of "--out": options.outputDirectory = value
    of "--arch": options.architecture = value.toLowerAscii()
    of "--maintainer": options.maintainer = value
    of "--license": options.license = value
    else: packageLinuxUsage()
    index += 2
  if not hasFormat or options.outputDirectory.len == 0:
    packageLinuxUsage()
  let built = buildLinuxPackage(options)
  if not built.isOk:
    stderr.writeLine("nimino package-linux: " & built.error.detail)
    quit(1)
  echo built.value
  quit(0)

proc packageWindowsUsage() =
  usage()

proc runPackageWindows() =
  if paramCount() < 3:
    packageWindowsUsage()
  var options = WindowsPackageOptions(bundleDirectory: paramStr(2))
  var hasFormat = false
  var index = 3
  while index <= paramCount():
    if index == paramCount(): packageWindowsUsage()
    let flag = paramStr(index)
    let value = paramStr(index + 1)
    case flag
    of "--format":
      case value.toLowerAscii()
      of "nsis": options.format = nsisPackage
      of "msi": options.format = msiPackage
      else: packageWindowsUsage()
      hasFormat = true
    of "--out": options.outputDirectory = value
    else: packageWindowsUsage()
    index += 2
  if not hasFormat or options.outputDirectory.len == 0:
    packageWindowsUsage()
  let built = buildWindowsPackage(options)
  if not built.isOk:
    stderr.writeLine("nimino package-windows: " & built.error.detail)
    quit(1)
  echo built.value
  quit(0)

proc manifestJson(manifest: PackManifest): JsonNode =
  %*{
    "name": manifest.name,
    "id": manifest.id,
    "url": manifest.url,
    "icon": manifest.icon,
    "profile": manifest.profile,
    "package": {
      "version": manifest.package.version,
      "description": manifest.package.description,
      "publisher": manifest.package.publisher,
      "homepage": manifest.package.homepage,
      "categories": manifest.package.categories
    },
    "window": {
      "width": manifest.window.width,
      "height": manifest.window.height,
      "resizable": manifest.window.resizable
    },
    "navigation": {
      "allow": manifest.navigationAllow,
      "external": manifest.navigationExternal
    },
    "permissions": {"allow": manifest.permissionsAllow},
    "injection": {
      "css": manifest.css,
      "javascript": manifest.javascript
    }
  }

proc sbomJson(manifest: PackManifest): JsonNode =
  ## A deterministic CycloneDX inventory for the generated wrapper.  Runtime
  ## components are declared explicitly because Nimino does not bundle a
  ## browser engine; deployment tooling can replace their versions with the
  ## versions resolved by the target platform.
  %*{
    "bomFormat": "CycloneDX",
    "specVersion": "1.6",
    "serialNumber": "urn:nimino:" & manifest.id,
    "version": 1,
    "metadata": {"component": {
      "type": "application",
      "bom-ref": manifest.id,
      "name": manifest.name,
      "version": manifest.package.version
    }},
    "components": [
      {"type": "application", "bom-ref": "nimino-core",
       "name": "nimino-core", "version": "workspace"},
      {"type": "library", "bom-ref": "webview2-evergreen",
       "name": "Microsoft.Web.WebView2", "version": "evergreen"},
      {"type": "library", "bom-ref": "webkitgtk-6.0",
       "name": "WebKitGTK", "version": "6.0"}
    ]
  }

proc desktopEscape(value: string): string =
  ## Exec entries use desktop-entry escaping rather than shell quoting.
  for character in value:
    case character
    of '\\', ' ', '\t':
      result.add('\\')
      result.add(character)
    of '\n', '\r':
      result.add(' ')
    else:
      result.add(character)

proc desktopValueEscape(value: string): string =
  ## Desktop-entry string values are not shell fragments. Escape only the
  ## sequences defined by the desktop-entry specification.
  for character in value:
    case character
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(character)

proc powershellLiteral(value: string): string =
  "'" & value.replace("'", "''") & "'"

proc linuxInstallRoot(manifest: PackManifest): string =
  "/opt/nimino/" & manifest.id

proc windowsInstallRoot(manifest: PackManifest): string =
  "%LOCALAPPDATA%\\Nimino\\" & manifest.id

proc linuxMetadataJson(manifest: PackManifest; localIcon: string): JsonNode =
  let installRoot = manifest.linuxInstallRoot()
  result = %*{
    "schemaVersion": 1,
    "id": manifest.id,
    "name": manifest.name,
    "version": manifest.package.version,
    "description": manifest.package.description,
    "homepage": manifest.package.homepage,
    "categories": manifest.package.categories,
    "desktopFile": manifest.id & ".desktop",
    "installRoot": installRoot,
    "entryPoint": installRoot / "run-nimino.sh",
    "manifest": installRoot / "nimino-manifest.json",
    "icon": if localIcon.len > 0: installRoot / localIcon else: ""
  }

proc windowsMetadataJson(manifest: PackManifest; localIcon: string): JsonNode =
  result = %*{
    "schemaVersion": 1,
    "id": manifest.id,
    "displayName": manifest.name,
    "version": manifest.package.version,
    "publisher": manifest.package.publisher,
    "description": manifest.package.description,
    "homepage": manifest.package.homepage,
    "installScope": "perUser",
    "installRoot": manifest.windowsInstallRoot(),
    "entryPoint": "run-nimino.cmd",
    "uninstaller": "uninstall-windows.ps1",
    "startMenuShortcut": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Nimino\\" &
      manifest.id & ".lnk",
    "webViewRuntime": "evergreen",
    "displayIcon": localIcon
  }

proc desktopEntry(manifest: PackManifest; localIcon: string): string =
  let installRoot = manifest.linuxInstallRoot()
  let executable = installRoot / "run-nimino.sh"
  result = "[Desktop Entry]\nVersion=1.0\nType=Application\n" &
    "Name=" & desktopValueEscape(manifest.name) & "\n" &
    "Comment=" & desktopValueEscape(manifest.package.description) & "\n" &
    "Exec=" & desktopEscape(executable) & "\n" &
    "TryExec=" & desktopEscape(executable) & "\n" &
    "Terminal=false\nStartupNotify=true\n" &
    "Categories=" & manifest.package.categories.join(";") & ";\n" &
    "X-Nimino-Id=" & manifest.id & "\n" &
    "X-Nimino-Manifest=" & desktopValueEscape(installRoot / "nimino-manifest.json") & "\n"
  if localIcon.len > 0:
    result.add("Icon=" & desktopValueEscape(installRoot / localIcon) & "\n")

proc windowsInstallScript(manifest: PackManifest; localIcon: string): string =
  let installRelative = "Nimino\\" & manifest.id
  let shortcutName = manifest.id & ".lnk"
  let uninstallKey = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" & manifest.id
  result = "# Generated by nimino-pack. Per-user installer metadata only.\n" &
    "$ErrorActionPreference = 'Stop'\n" &
    "$source = $PSScriptRoot\n" &
    "$target = Join-Path $env:LOCALAPPDATA " & powershellLiteral(installRelative) & "\n" &
    "if ([IO.Path]::GetFullPath($source) -eq [IO.Path]::GetFullPath($target)) { throw 'bundle is already installed' }\n" &
    "New-Item -ItemType Directory -Force -Path $target | Out-Null\n" &
    "Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $target -Recurse -Force\n" &
    "$launcher = Join-Path $target 'run-nimino.cmd'\n" &
    "if (-not (Test-Path -LiteralPath $launcher)) { throw 'run-nimino.cmd is missing from bundle' }\n" &
    "$programs = [Environment]::GetFolderPath('Programs')\n" &
    "$shortcutDirectory = Join-Path $programs 'Nimino'\n" &
    "New-Item -ItemType Directory -Force -Path $shortcutDirectory | Out-Null\n" &
    "$shortcutPath = Join-Path $shortcutDirectory " & powershellLiteral(shortcutName) & "\n" &
    "$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)\n" &
    "$shortcut.TargetPath = $launcher\n" &
    "$shortcut.WorkingDirectory = $target\n" &
    "$shortcut.Description = " & powershellLiteral(manifest.package.description) & "\n"
  if localIcon.len > 0:
    result.add("$shortcut.IconLocation = Join-Path $target " & powershellLiteral(localIcon) & "\n")
  result.add("$shortcut.Save()\n" &
    "$uninstallKey = " & powershellLiteral(uninstallKey) & "\n" &
    "New-Item -Force -Path $uninstallKey | Out-Null\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'DisplayName' -Value " &
      powershellLiteral(manifest.name) & " | Out-Null\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'DisplayVersion' -Value " &
      powershellLiteral(manifest.package.version) & " | Out-Null\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'InstallLocation' -Value $target | Out-Null\n" &
    "$uninstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"' + (Join-Path $target 'uninstall-windows.ps1') + '\"'\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'UninstallString' -Value $uninstallCommand | Out-Null\n")
  if manifest.package.publisher.len > 0:
    result.add("New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'Publisher' -Value " &
      powershellLiteral(manifest.package.publisher) & " | Out-Null\n")
  if manifest.package.homepage.len > 0:
    result.add("New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'URLInfoAbout' -Value " &
      powershellLiteral(manifest.package.homepage) & " | Out-Null\n")
  if localIcon.len > 0:
    result.add("New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'DisplayIcon' -Value " &
      "(Join-Path $target " & powershellLiteral(localIcon) & ") | Out-Null\n")
  result.add("Write-Host " & powershellLiteral("Installed " & manifest.name & " at ") & " $target\n")

proc windowsUninstallScript(manifest: PackManifest): string =
  let uninstallKey = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" & manifest.id
  result = "# Generated by nimino-pack.\n" &
    "$ErrorActionPreference = 'Stop'\n" &
    "$target = $PSScriptRoot\n" &
    "$programs = [Environment]::GetFolderPath('Programs')\n" &
    "$shortcutPath = Join-Path (Join-Path $programs 'Nimino') " &
      powershellLiteral(manifest.id & ".lnk") & "\n" &
    "if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }\n" &
    "$uninstallKey = " & powershellLiteral(uninstallKey) & "\n" &
    "if (Test-Path -LiteralPath $uninstallKey) { Remove-Item -LiteralPath $uninstallKey -Recurse -Force }\n" &
    "Remove-Item -LiteralPath $target -Recurse -Force\n"

proc cmdEscape(value: string): string =
  for character in value:
    if character == '%':
      result.add("%%")
      continue
    if character in {'^', '&', '|', '<', '>', '(', ')', '!'}:
      result.add('^')
    result.add(character)

proc writeGenerated(path, content: string): bool =
  try:
    writeFile(path, content)
    true
  except OSError:
    stderr.writeLine("nimino pack: unable to write " & path)
    false

proc copyGenerated(source, destination: string): bool =
  try:
    copyFile(source, destination)
    true
  except OSError:
    stderr.writeLine("nimino pack: unable to copy " & source)
    false

if paramCount() >= 1 and paramStr(1) == "package-linux":
  runPackageLinux()
if paramCount() >= 1 and paramStr(1) == "package-windows":
  runPackageWindows()
if paramCount() < 2 or paramStr(1) != "pack":
  usage()
var loaded: PackResult[PackManifest]
let source = paramStr(2)
let sourceIsUrl = source.toLowerAscii().startsWith("http://") or
  source.toLowerAscii().startsWith("https://")
if sourceIsUrl:
  var name = ""
  var id = ""
  var profile = "default"
  var icon = ""
  var index = 3
  while index <= paramCount():
    if index == paramCount():
      usage()
    let flag = paramStr(index)
    let value = paramStr(index + 1)
    case flag
    of "--name": name = value
    of "--id": id = value
    of "--profile": profile = value
    of "--icon": icon = value
    of "--out", "--host": discard
    else: usage()
    index += 2
  if name.len == 0 or id.len == 0:
    usage()
  loaded = validate(PackManifest(
    name: name,
    id: id,
    url: source,
    icon: icon,
    profile: profile,
    window: PackWindowOptions(width: 1200, height: 800, resizable: true)))
else:
  loaded = loadManifest(source)
if not loaded.isOk:
  stderr.writeLine("nimino pack: " & loaded.error.detail)
  quit(1)
var output = manifestJson(loaded.value).pretty()
var outputDirectory = ""
var hostPath = ""
var index = 3
while index <= paramCount():
  if index == paramCount(): usage()
  case paramStr(index)
  of "--out": outputDirectory = paramStr(index + 1)
  of "--host": hostPath = paramStr(index + 1)
  of "--name", "--id", "--profile", "--icon":
    if not sourceIsUrl: usage()
  else: usage()
  index += 2
if hostPath.len > 0 and not fileExists(hostPath):
  stderr.writeLine("nimino pack: host executable does not exist")
  quit(1)
if outputDirectory.len == 0:
  echo output
else:
  let directory = outputDirectory
  if directory.len == 0:
    usage()
  let sourceManifest = loaded.value
  let iconIsRemote = sourceManifest.icon.toLowerAscii().startsWith("http://") or
    sourceManifest.icon.toLowerAscii().startsWith("https://") or
    sourceManifest.icon.toLowerAscii().startsWith("data:")
  if sourceManifest.icon.len > 0 and not iconIsRemote and not fileExists(sourceManifest.icon):
    stderr.writeLine("nimino pack: local icon does not exist")
    quit(1)
  for injected in sourceManifest.css & sourceManifest.javascript:
    if not fileExists(injected):
      stderr.writeLine("nimino pack: injected file does not exist: " & injected)
      quit(1)
  try:
    createDir(directory)
  except OSError:
    stderr.writeLine("nimino pack: unable to create output directory")
    quit(1)
  var packaged = sourceManifest
  proc packageFiles(paths: var seq[string]) =
    var packagedNames: seq[string]
    for index in 0 ..< paths.len:
      if not fileExists(paths[index]):
        stderr.writeLine("nimino pack: injected file does not exist: " & paths[index])
        quit(1)
      let fileName = extractFilename(paths[index])
      if fileName.len == 0 or fileName in [".", ".."]:
        stderr.writeLine("nimino pack: injected file path has no usable filename")
        quit(1)
      if fileName in packagedNames:
        stderr.writeLine("nimino pack: duplicate injected filename: " & fileName)
        quit(1)
      if fileExists(directory / fileName):
        stderr.writeLine("nimino pack: output filename collision: " & fileName)
        quit(1)
      packagedNames.add(fileName)
      if not copyGenerated(paths[index], directory / fileName):
        quit(1)
      paths[index] = fileName
  var localIconName = ""
  if packaged.icon.len > 0 and fileExists(packaged.icon):
    let iconName = extractFilename(packaged.icon)
    if iconName.len == 0 or iconName in [".", ".."]:
      stderr.writeLine("nimino pack: icon path has no usable filename")
      quit(1)
    if not copyGenerated(packaged.icon, directory / iconName):
      quit(1)
    packaged.icon = iconName
    localIconName = iconName
  packageFiles(packaged.css)
  packageFiles(packaged.javascript)
  output = manifestJson(packaged).pretty()
  let manifestPath = directory / "nimino-manifest.json"
  if not writeGenerated(manifestPath, output & "\n"):
    quit(1)
  let sbomPath = directory / "nimino-sbom.cdx.json"
  if not writeGenerated(sbomPath, packaged.sbomJson().pretty() & "\n"):
    quit(1)
  let launcherPath = directory / "run-nimino.sh"
  let hostName = if hostPath.len > 0:
                   extractFilename(hostPath)
                 else: "nimino-host"
  if hostPath.len > 0:
    if not copyGenerated(hostPath, directory / hostName):
      quit(1)
    setFilePermissions(directory / hostName, {fpUserExec, fpUserRead, fpUserWrite,
      fpGroupExec, fpGroupRead, fpOthersExec, fpOthersRead})
  if not writeGenerated(launcherPath, "#!/bin/sh\n# Generated by nimino-pack.\nexec \"$(dirname \"$0\")/" & hostName & "\" --manifest \"$(dirname \"$0\")/nimino-manifest.json\"\n"):
    quit(1)
  setFilePermissions(launcherPath, {fpUserExec, fpUserRead, fpUserWrite,
    fpGroupExec, fpGroupRead, fpOthersExec, fpOthersRead})
  let windowsLauncherPath = directory / "run-nimino.cmd"
  let windowsHostName = if hostPath.len == 0: "nimino-host.exe" else: hostName
  if not writeGenerated(windowsLauncherPath, "@echo off\r\nrem Generated by nimino-pack.\r\n\"%~dp0" & cmdEscape(windowsHostName) & "\" --manifest \"%~dp0nimino-manifest.json\"\r\n"):
    quit(1)
  let linuxMetadataPath = directory / "nimino-linux-package.json"
  if not writeGenerated(linuxMetadataPath,
      linuxMetadataJson(packaged, localIconName).pretty() & "\n"):
    quit(1)
  let desktopPath = directory / (packaged.id & ".desktop")
  if not writeGenerated(desktopPath, desktopEntry(packaged, localIconName)):
    quit(1)
  let windowsMetadataPath = directory / "nimino-windows-installer.json"
  if not writeGenerated(windowsMetadataPath,
      windowsMetadataJson(packaged, localIconName).pretty() & "\n"):
    quit(1)
  let installScriptPath = directory / "install-windows.ps1"
  if not writeGenerated(installScriptPath,
      windowsInstallScript(packaged, localIconName)):
    quit(1)
  let uninstallScriptPath = directory / "uninstall-windows.ps1"
  if not writeGenerated(uninstallScriptPath, windowsUninstallScript(packaged)):
    quit(1)
  echo manifestPath
