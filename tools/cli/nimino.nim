import std/[json, os, strutils]

import nimino_pack

proc usage() =
  stderr.writeLine("usage: nimino pack <manifest.toml> [--out <directory>] [--host <executable>]")
  stderr.writeLine("       nimino pack <url> --name <name> --id <id> [--out <directory>] [--host <executable>]")
  quit(2)

proc manifestJson(manifest: PackManifest): JsonNode =
  %*{
    "name": manifest.name,
    "id": manifest.id,
    "url": manifest.url,
    "icon": manifest.icon,
    "profile": manifest.profile,
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

proc desktopEscape(value: string): string =
  ## Exec entries use desktop-entry escaping rather than shell quoting.
  for character in value:
    case character
    of '\\', ' ', '\t':
      result.add('\\')
      result.add(character)

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
    of '\n', '\r':
      result.add(' ')
    else:
      result.add(character)

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
    of "--out", "--host": index += 1
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
  try:
    createDir(directory)
  except OSError:
    stderr.writeLine("nimino pack: unable to create output directory")
    quit(1)
  var packaged = loaded.value
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
  let iconIsRemote = packaged.icon.toLowerAscii().startsWith("http://") or
    packaged.icon.toLowerAscii().startsWith("https://") or
    packaged.icon.toLowerAscii().startsWith("data:")
  if packaged.icon.len > 0 and not iconIsRemote and not fileExists(packaged.icon):
    stderr.writeLine("nimino pack: local icon does not exist")
    quit(1)
  if packaged.icon.len > 0 and fileExists(packaged.icon):
    let iconName = extractFilename(packaged.icon)
    if iconName.len == 0 or iconName in [".", ".."]:
      stderr.writeLine("nimino pack: icon path has no usable filename")
      quit(1)
    if not copyGenerated(packaged.icon, directory / iconName):
      quit(1)
    packaged.icon = iconName
  packageFiles(packaged.css)
  packageFiles(packaged.javascript)
  output = manifestJson(packaged).pretty()
  let manifestPath = directory / "nimino-manifest.json"
  if not writeGenerated(manifestPath, output & "\n"):
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
  let desktopPath = directory / "nimino.desktop"
  if not writeGenerated(desktopPath, "[Desktop Entry]\nType=Application\nName=" & loaded.value.name &
      "\nExec=" & desktopEscape(directory / "run-nimino.sh") &
      "\nTerminal=false\nCategories=Utility;\n"):
    quit(1)
  let installScriptPath = directory / "install-windows.ps1"
  if not writeGenerated(installScriptPath, "# Generated by nimino-pack.\n$target = Join-Path $env:LOCALAPPDATA 'Nimino\\" & loaded.value.id & "'\nNew-Item -ItemType Directory -Force -Path $target | Out-Null\nCopy-Item -Recurse -Force (Join-Path $PSScriptRoot '*') $target\nWrite-Host \"Installed Nimino app at $target\"\n"):
    quit(1)
  echo manifestPath
