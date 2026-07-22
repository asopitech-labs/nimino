import std/[base64, httpclient, json, os, sequtils, strutils, uri]

import nimino_pack

proc usage() =
  stderr.writeLine("usage: nimino pack <manifest.toml> [--out <directory>] [--host <executable>]")
  stderr.writeLine("       nimino pack --config <manifest.toml|config.json> [--out <directory>] [--host <executable>] [--targets <deb,rpm,appimage,flatpak,nsis,msi>]")
  stderr.writeLine("       nimino pack <url-or-local-path> [--use-local-file] [--name <name>] [--id <id>] [--profile <name>] [--title <title>] [--width <px>] [--height <px>] [--resizable <true|false>] [--fullscreen] [--maximize] [--always-on-top] [--hide-window-decorations] [--enable-drag-drop] [--user-agent <value>] [--proxy-url <url>] [--incognito] [--zoom <percent>] [--show-system-tray] [--start-to-tray] [--hide-on-close] [--multi-window <true|false>] [--multi-instance] [--icon <path-or-url>] [--deep-link <scheme>]... [--allow-permission <kind>]... [--inject-css <path>]... [--inject-js <path>]... [--allow-url <pattern>]... [--safe-domain <domain>]... [--external-url <pattern>]... [--out <directory>] [--host <executable>]")
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
    "localEntry": manifest.localEntry,
    "icon": manifest.icon,
    "profile": manifest.profile,
    "package": {
      "version": manifest.package.version,
      "description": manifest.package.description,
      "publisher": manifest.package.publisher,
      "homepage": manifest.package.homepage,
      "categories": manifest.package.categories,
      "targets": manifest.package.targets,
      "installerLanguage": manifest.package.installerLanguage,
      "keepBinary": manifest.package.keepBinary,
      "bundle": manifest.package.bundle,
      "iterativeBuild": manifest.package.iterativeBuild,
      "debug": manifest.package.debug,
      "multiArch": manifest.package.multiArch,
      "install": manifest.package.install
    },
    "deepLink": {"schemes": manifest.deepLink.schemes},
    "window": {
      "title": manifest.window.title,
      "width": manifest.window.width,
      "height": manifest.window.height,
      "resizable": manifest.window.resizable,
      "fullscreen": manifest.window.fullscreen,
      "maximized": manifest.window.maximized,
      "alwaysOnTop": manifest.window.alwaysOnTop,
      "hideWindowDecorations": manifest.window.hideWindowDecorations,
      "enableDragDrop": manifest.window.enableDragDrop,
      "minWidth": manifest.window.minWidth,
      "minHeight": manifest.window.minHeight,
      "hideTitleBar": manifest.window.hideTitleBar
    },
    "webview": {
      "userAgent": manifest.webview.userAgent,
      "proxyUrl": manifest.webview.proxyUrl,
      "incognito": manifest.webview.incognito,
      "zoom": int(manifest.webview.zoomFactor * 100.0),
      "ignoreCertificateErrors": manifest.webview.ignoreCertificateErrors,
      "darkMode": manifest.webview.darkMode,
      "disabledWebShortcuts": manifest.webview.disabledWebShortcuts,
      "enableFind": manifest.webview.enableFind,
      "wasm": manifest.webview.wasm,
      "newWindow": manifest.webview.newWindow,
      "forceInternalNavigation": manifest.webview.forceInternalNavigation,
      "internalUrlRegex": manifest.webview.internalUrlRegex
    },
    "runtime": {
      "showSystemTray": manifest.runtime.showSystemTray,
      "startToTray": manifest.runtime.startToTray,
      "hideOnClose": manifest.runtime.hideOnClose,
      "multiWindow": manifest.runtime.multiWindow,
      "multiInstance": manifest.runtime.multiInstance,
      "activationShortcut": manifest.runtime.activationShortcut,
      "systemTrayIcon": manifest.runtime.systemTrayIcon
    },
    "navigation": {
      "allow": manifest.navigationAllow,
      "external": manifest.navigationExternal
    },
    "permissions": {"allow": manifest.permissionsAllow},
    "injection": {
      "css": manifest.css,
      "javascript": manifest.javascript,
      "files": manifest.injectionFiles
    },
    "useLocalFile": manifest.useLocalFile,
    "safeDomains": manifest.safeDomains
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

proc toastActivatorClsid(appId: string): string =
  ## Keep this byte-for-byte aligned with nimino-native's private Win32
  ## derivation. It is an identity used by the Windows registry, not a trust
  ## boundary or cryptographic signature.
  var a = 2166136261'u32
  var b = 2246822519'u32
  var c = 3266489917'u32
  var d = 668265263'u32
  for index, character in appId:
    let value = uint32(ord(character) + index + 1)
    a = (a xor value) * 16777619'u32
    b = (b xor (value + a)) * 2246822519'u32
    c = (c xor (value + b)) * 3266489917'u32
    d = (d xor (value + c)) * 668265263'u32
  toHex(a, 8) & "-" & toHex(uint16(b shr 16), 4) & "-" &
    toHex(uint16(c shr 16), 4) & "-" &
    toHex(uint8(b and 0xff), 2) & toHex(uint8(b shr 8), 2) &
    "-" &
    toHex(uint8(c and 0xff), 2) & toHex(uint8(c shr 8), 2) &
    toHex(uint8(d and 0xff), 2) & toHex(uint8(d shr 8), 2) &
    toHex(uint8(d shr 16), 2) & toHex(uint8(d shr 24), 2)

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
    "icon": if localIcon.len > 0: installRoot / localIcon else: "",
    "deepLinkSchemes": manifest.deepLink.schemes
  }

proc windowsMetadataJson(manifest: PackManifest; localIcon, hostExecutable: string): JsonNode =
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
    "appUserModelId": manifest.id,
    "toastActivation": "inProcessOrComLocalServer",
    "toastActivatorClsid": manifest.id.toastActivatorClsid(),
    "hostExecutable": hostExecutable,
    "shortcutPropertiesScript": "register-windows-shortcut.ps1",
    "startMenuShortcut": "%APPDATA%\\Microsoft\\Windows\\Start Menu\\Programs\\Nimino\\" &
      manifest.id & ".lnk",
    "webViewRuntime": "evergreen",
    "displayIcon": localIcon,
    "deepLinkSchemes": manifest.deepLink.schemes
  }

proc windowsShortcutPropertiesScript(): string =
  ## Windows requires the AUMID on the Start-menu shortcut itself.  WScript.Shell
  ## can create the link but cannot write System.AppUserModel.ID, so this small
  ## PowerShell helper uses the documented IPropertyStore COM API.  It is kept
  ## as a generated artifact instead of adding a runtime dependency to Nimino.
  """# Generated by nimino-pack. Applies the AUMID to a Start-menu shortcut.
# System.AppUserModel.ID and System.AppUserModel.ToastActivatorCLSID are
# written through the documented PropertyStore keys.
param(
  [Parameter(Mandatory = $true)][string]$ShortcutPath,
  [Parameter(Mandatory = $true)][string]$AppUserModelId,
  [Parameter(Mandatory = $true)][string]$ToastActivatorClsid
)
$ErrorActionPreference = 'Stop'
$source = @'
using System;
using System.Runtime.InteropServices;

public static class NiminoShortcutProperties {
  [StructLayout(LayoutKind.Sequential, Pack = 4)]
  private struct PROPERTYKEY { public Guid fmtid; public uint pid; }

  [StructLayout(LayoutKind.Explicit)]
  private struct PROPVARIANT {
    [FieldOffset(0)] public ushort vt;
    [FieldOffset(8)] public IntPtr pointer;
  }

  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
   InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  private interface IPropertyStore {
    [PreserveSig] int GetCount(out uint count);
    [PreserveSig] int GetAt(uint index, out PROPERTYKEY key);
    [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
    [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
    [PreserveSig] int Commit();
  }

  [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
  private static extern int SHGetPropertyStoreFromParsingName(
    string path, IntPtr bindCtx, uint flags, ref Guid riid,
    [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);

  [DllImport("ole32.dll")]
  private static extern int PropVariantClear(ref PROPVARIANT value);

  public static void SetAppUserModelId(string path, string appUserModelId, string toastActivatorClsid) {
    Guid riid = typeof(IPropertyStore).GUID;
    IPropertyStore store;
    int hr = SHGetPropertyStoreFromParsingName(path, IntPtr.Zero, 2, ref riid, out store);
    if (hr < 0) Marshal.ThrowExceptionForHR(hr);
    var key = new PROPERTYKEY {
      fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5
    };
    var value = new PROPVARIANT {
      vt = 31, pointer = Marshal.StringToCoTaskMemUni(appUserModelId)
    };
    var activatorKey = new PROPERTYKEY {
      fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 26
    };
    var activatorGuid = Guid.Parse(toastActivatorClsid);
    var activatorPointer = Marshal.AllocCoTaskMem(16);
    Marshal.Copy(activatorGuid.ToByteArray(), 0, activatorPointer, 16);
    var activatorValue = new PROPVARIANT {
      vt = 72, pointer = activatorPointer
    };
    try {
      hr = store.SetValue(ref key, ref value);
      if (hr < 0) Marshal.ThrowExceptionForHR(hr);
      hr = store.SetValue(ref activatorKey, ref activatorValue);
      if (hr < 0) Marshal.ThrowExceptionForHR(hr);
      hr = store.Commit();
      if (hr < 0) Marshal.ThrowExceptionForHR(hr);
    } finally {
      PropVariantClear(ref value);
      PropVariantClear(ref activatorValue);
      Marshal.FinalReleaseComObject(store);
    }
  }
}
'@
Add-Type -TypeDefinition $source -Language CSharp
[NiminoShortcutProperties]::SetAppUserModelId($ShortcutPath, $AppUserModelId, $ToastActivatorClsid)
"""

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
  if manifest.deepLink.schemes.len > 0:
    result.add("MimeType=" & manifest.deepLink.schemes.mapIt("x-scheme-handler/" & it).join(";") & ";\n" &
      "X-Nimino-Deep-Link-Schemes=" & manifest.deepLink.schemes.join(";") & ";\n")
  if localIcon.len > 0:
    result.add("Icon=" & desktopValueEscape(installRoot / localIcon) & "\n")

proc windowsInstallScript(manifest: PackManifest; localIcon, hostExecutable: string): string =
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
    "$hostExecutable = Join-Path $target " & powershellLiteral(hostExecutable) & "\n" &
    "if (-not (Test-Path -LiteralPath $hostExecutable)) { throw 'host executable is missing from bundle' }\n" &
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
    "$shortcutProperties = Join-Path $target 'register-windows-shortcut.ps1'\n" &
    "if (-not (Test-Path -LiteralPath $shortcutProperties)) { throw 'shortcut property helper is missing from bundle' }\n" &
    "& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $shortcutProperties -ShortcutPath $shortcutPath -AppUserModelId " &
      powershellLiteral(manifest.id) & " -ToastActivatorClsid " &
      powershellLiteral(manifest.id.toastActivatorClsid()) & "\n" &
    "if ($LASTEXITCODE -ne 0) { throw 'unable to configure Windows AppUserModelId shortcut property' }\n" &
    "$uninstallKey = " & powershellLiteral(uninstallKey) & "\n" &
    "New-Item -Force -Path $uninstallKey | Out-Null\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'DisplayName' -Value " &
      powershellLiteral(manifest.name) & " | Out-Null\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'DisplayVersion' -Value " &
      powershellLiteral(manifest.package.version) & " | Out-Null\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'InstallLocation' -Value $target | Out-Null\n" &
    "$uninstallCommand = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"' + (Join-Path $target 'uninstall-windows.ps1') + '\"'\n" &
    "New-ItemProperty -Force -LiteralPath $uninstallKey -Name 'UninstallString' -Value $uninstallCommand | Out-Null\n")
  result.add("$toastClsid = " & powershellLiteral(manifest.id.toastActivatorClsid()) & "\n" &
    "$toastKey = 'HKCU:\\Software\\Classes\\CLSID\\{' + $toastClsid + '}'\n" &
    "$toastServer = Join-Path $toastKey 'LocalServer32'\n" &
    "New-Item -Force -Path $toastServer | Out-Null\n" &
    "$hostExecutable = Join-Path $target " & powershellLiteral(hostExecutable) & "\n" &
    "$toastCommand = '" & '"' & "' + $hostExecutable + '" & '"' & " -Embedding --manifest \"' + (Join-Path $target 'nimino-manifest.json') + '\"'\n" &
    "New-ItemProperty -Force -LiteralPath $toastServer -Name '(default)' -Value $toastCommand | Out-Null\n")
  for scheme in manifest.deepLink.schemes:
    let key = "HKCU:\\Software\\Classes\\" & scheme
    result.add("$deepLinkKey = " & powershellLiteral(key) & "\n" &
      "New-Item -Force -Path $deepLinkKey | Out-Null\n" &
      "New-ItemProperty -Force -LiteralPath $deepLinkKey -Name '(default)' -Value " &
        powershellLiteral("URL:Nimino " & scheme & " Protocol") & " | Out-Null\n" &
      "New-ItemProperty -Force -LiteralPath $deepLinkKey -Name 'URL Protocol' -Value '' | Out-Null\n" &
      "New-Item -Force -Path (Join-Path $deepLinkKey 'shell\\open\\command') | Out-Null\n" &
      "New-ItemProperty -Force -LiteralPath (Join-Path $deepLinkKey 'shell\\open\\command') -Name '(default)' -Value " &
        "('" & '"' & "' + $launcher + '" & '"' & "' \"%1\"') | Out-Null\n")
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

proc windowsUninstallScript(manifest: PackManifest; hostExecutable: string): string =
  let uninstallKey = "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\" & manifest.id
  result = "# Generated by nimino-pack.\n" &
    "$ErrorActionPreference = 'Stop'\n" &
    "$target = $PSScriptRoot\n" &
    "$toastClsid = " & powershellLiteral(manifest.id.toastActivatorClsid()) & "\n" &
    "$toastClsidKey = 'HKCU:\\Software\\Classes\\CLSID\\{' + $toastClsid + '}'\n" &
    "if (Test-Path -LiteralPath $toastClsidKey) { Remove-Item -LiteralPath $toastClsidKey -Recurse -Force }\n" &
    "$programs = [Environment]::GetFolderPath('Programs')\n" &
    "$shortcutPath = Join-Path (Join-Path $programs 'Nimino') " &
      powershellLiteral(manifest.id & ".lnk") & "\n" &
    "if (Test-Path -LiteralPath $shortcutPath) { Remove-Item -LiteralPath $shortcutPath -Force }\n" &
    "$uninstallKey = " & powershellLiteral(uninstallKey) & "\n" &
    "if (Test-Path -LiteralPath $uninstallKey) { Remove-Item -LiteralPath $uninstallKey -Recurse -Force }\n" &
    "$toastKey = 'HKCU:\\Software\\Classes\\CLSID\\{" & manifest.id.toastActivatorClsid() & "}'\n" &
    "$toastCommand = '" & '"' & "' + (Join-Path $target " & powershellLiteral(hostExecutable) &
      ") + '" & '"' & " -Embedding --manifest \"' + (Join-Path $target 'nimino-manifest.json') + '\"'\n" &
    "if (Test-Path -LiteralPath (Join-Path $toastKey 'LocalServer32')) {\n" &
    "  $registered = (Get-ItemProperty -LiteralPath (Join-Path $toastKey 'LocalServer32') -Name '(default)').'(default)'\n" &
    "  if ($registered -eq $toastCommand) { Remove-Item -LiteralPath $toastKey -Recurse -Force }\n" &
    "}\n" &
    "Remove-Item -LiteralPath $target -Recurse -Force\n"
  for scheme in manifest.deepLink.schemes:
    let key = "HKCU:\\Software\\Classes\\" & scheme
    result.add("$deepLinkKey = " & powershellLiteral(key) & "\n" &
      "$deepLinkCommand = '\"' + (Join-Path $target 'run-nimino.cmd') + '\" \"%1\"'\n" &
      "if (Test-Path -LiteralPath (Join-Path $deepLinkKey 'shell\\open\\command')) {\n" &
      "  $registered = (Get-ItemProperty -LiteralPath (Join-Path $deepLinkKey 'shell\\open\\command') -Name '(default)').'(default)'\n" &
      "  if ($registered -eq $deepLinkCommand) { Remove-Item -LiteralPath $deepLinkKey -Recurse -Force }\n" &
      "}\n")

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

proc stageLocalTree(source, destination: string): bool =
  ## Copy a static web tree while preserving its relative layout.  Symlinks
  ## are rejected so a bundle cannot accidentally capture files outside the
  ## requested source tree.
  let sourceRoot = absolutePath(source).normalizedPath()
  try:
    for kind, path in walkDir(sourceRoot, relative = false):
      let relative = relativePath(path, sourceRoot).replace('\\', '/')
      if relative == ".." or relative.startsWith("../") or relative.isAbsolute:
        stderr.writeLine("nimino pack: local asset escapes source root: " & path)
        return false
      let target = destination / relative
      case kind
      of pcDir:
        createDir(target)
        if not stageLocalTree(path, target):
          return false
      of pcFile:
        createDir(parentDir(target))
        if not copyGenerated(path, target):
          return false
      of pcLinkToFile, pcLinkToDir:
        stderr.writeLine("nimino pack: symbolic links are not allowed in local assets: " & path)
        return false
      else:
        stderr.writeLine("nimino pack: unsupported local asset: " & path)
        return false
    true
  except OSError:
    stderr.writeLine("nimino pack: unable to stage local assets from " & source)
    false

proc iconExtension(contentType, sourceName: string): string =
  let mime = contentType.toLowerAscii().split(';')[0].strip()
  case mime
  of "image/png": ".png"
  of "image/jpeg", "image/jpg": ".jpg"
  of "image/gif": ".gif"
  of "image/svg+xml": ".svg"
  of "image/x-icon", "image/vnd.microsoft.icon": ".ico"
  else:
    let extension = splitFile(sourceName).ext.toLowerAscii()
    if extension in [".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".webp"]:
      extension
    else: ".png"

proc safeIconName(candidate, extension: string): string =
  var stem = splitFile(candidate).name
  if stem.len == 0:
    stem = "icon"
  result = ""
  for character in stem:
    if character.isAlphaNumeric or character in {'-', '_'}:
      result.add(character)
    elif result.len == 0 or result[^1] != '-':
      result.add('-')
  result = result.strip(chars = {'-'})
  if result.len == 0:
    result = "icon"
  result &= extension

proc fetchRemoteIcon(url, destination: string): bool =
  ## Fetch only bounded image payloads.  The pack command is synchronous, so
  ## a bounded timeout prevents a dead icon host from hanging packaging.
  let lower = url.toLowerAscii()
  if lower.startsWith("data:"):
    let comma = url.find(',')
    if comma <= 5:
      stderr.writeLine("nimino pack: malformed data icon URL")
      return false
    let header = url[5 ..< comma]
    let body = url[comma + 1 .. ^1]
    try:
      let bytes = if header.toLowerAscii().contains(";base64"):
          decode(body)
        else:
          decodeUrl(body)
      if bytes.len == 0 or bytes.len > 8 * 1024 * 1024:
        stderr.writeLine("nimino pack: icon payload is empty or too large")
        return false
      writeFile(destination, bytes)
      return true
    except CatchableError:
      stderr.writeLine("nimino pack: unable to decode data icon URL")
      return false
  if not (lower.startsWith("http://") or lower.startsWith("https://")):
    return false
  try:
    var client = newHttpClient(timeout = 15_000)
    let response = client.get(url)
    if response.code.int < 200 or response.code.int >= 300:
      stderr.writeLine("nimino pack: remote icon returned HTTP " & $response.code.int)
      return false
    if response.body.len == 0 or response.body.len > 8 * 1024 * 1024:
      stderr.writeLine("nimino pack: remote icon payload is empty or too large")
      return false
    writeFile(destination, response.body)
    true
  except CatchableError:
    stderr.writeLine("nimino pack: unable to download remote icon")
    false

proc parseCliBool(value: string): bool =
  case value.toLowerAscii()
  of "true", "1", "yes": result = true
  of "false", "0", "no": result = false
  else: usage()

proc packBooleanFlag(flag: string): bool =
  flag in ["--resizable", "--fullscreen", "--maximize", "--always-on-top",
           "--hide-window-decorations", "--incognito", "--show-system-tray",
           "--enable-drag-drop",
           "--start-to-tray", "--hide-on-close", "--multi-window",
           "--multi-instance", "--use-local-file", "--json"]

proc applyManifestCliOverride(manifest: var PackManifest; flag, value: string) =
  case flag
  of "--name": manifest.name = value
  of "--title": manifest.window.title = value
  of "--id": manifest.id = value
  of "--profile": manifest.profile = value
  of "--width":
    try: manifest.window.width = parseInt(value)
    except ValueError: usage()
  of "--height":
    try: manifest.window.height = parseInt(value)
    except ValueError: usage()
  of "--resizable": manifest.window.resizable = parseCliBool(value)
  of "--fullscreen": manifest.window.fullscreen = parseCliBool(value)
  of "--maximize": manifest.window.maximized = parseCliBool(value)
  of "--always-on-top": manifest.window.alwaysOnTop = parseCliBool(value)
  of "--hide-window-decorations": manifest.window.hideWindowDecorations = parseCliBool(value)
  of "--enable-drag-drop": manifest.window.enableDragDrop = parseCliBool(value)
  of "--user-agent": manifest.webview.userAgent = value
  of "--proxy-url": manifest.webview.proxyUrl = value
  of "--incognito": manifest.webview.incognito = parseCliBool(value)
  of "--zoom":
    try: manifest.webview.zoomFactor = parseInt(value).float / 100.0
    except ValueError: usage()
  of "--ignore-certificate-errors":
    manifest.webview.ignoreCertificateErrors = parseCliBool(value)
  of "--show-system-tray": manifest.runtime.showSystemTray = parseCliBool(value)
  of "--start-to-tray": manifest.runtime.startToTray = parseCliBool(value)
  of "--hide-on-close": manifest.runtime.hideOnClose = parseCliBool(value)
  of "--multi-window": manifest.runtime.multiWindow = parseCliBool(value)
  of "--multi-instance": manifest.runtime.multiInstance = parseCliBool(value)
  of "--use-local-file": manifest.useLocalFile = parseCliBool(value)
  of "--icon": manifest.icon = value
  of "--deep-link": manifest.deepLink.schemes.add(value)
  of "--allow-permission": manifest.permissionsAllow.add(value)
  of "--inject-css": manifest.css.add(value)
  of "--inject-js": manifest.javascript.add(value)
  of "--allow-url": manifest.navigationAllow.add(value)
  of "--safe-domain":
    manifest.safeDomains.add(value)
    manifest.navigationAllow.add("https://" & value & "/**")
  of "--external-url": manifest.navigationExternal.add(value)
  else: discard

if paramCount() >= 1 and paramStr(1) == "package-linux":
  runPackageLinux()
if paramCount() >= 1 and paramStr(1) == "package-windows":
  runPackageWindows()
if paramCount() < 2 or paramStr(1) != "pack":
  usage()
var loaded: PackResult[PackManifest]
var optionStart = 3
var source = paramStr(2)
if source == "--config":
  if paramCount() < 3:
    usage()
  source = paramStr(3)
  optionStart = 4
let sourceIsUrl = source.toLowerAscii().startsWith("http://") or
  source.toLowerAscii().startsWith("https://")
let sourceIsManifest = fileExists(source) and
  (source.toLowerAscii().endsWith(".toml") or source.toLowerAscii().endsWith(".json"))
let sourceIsLocal = (fileExists(source) or dirExists(source)) and not sourceIsManifest
var localSourcePath = ""
var localUseLocalFile = false
if sourceIsUrl or sourceIsLocal:
  var name = ""
  var title = ""
  var id = ""
  var profile = "default"
  var icon = ""
  var width = 1200
  var height = 800
  var resizable = true
  var fullscreen = false
  var maximized = false
  var alwaysOnTop = false
  var hideWindowDecorations = false
  var enableDragDrop = false
  var userAgent = ""
  var proxyUrl = ""
  var incognito = false
  var zoom = 100
  var ignoreCertificateErrors = false
  var showSystemTray = false
  var startToTray = false
  var hideOnClose = false
  var multiWindow = true
  var multiInstance = false
  var useLocalFile = false
  var permissionsAllow: seq[string]
  var css: seq[string]
  var javascript: seq[string]
  var navigationAllow: seq[string]
  var navigationExternal: seq[string]
  var deepLinkSchemes: seq[string]
  var index = optionStart
  while index <= paramCount():
    let flag = paramStr(index)
    let hasValue = index < paramCount() and not paramStr(index + 1).startsWith("--")
    if not hasValue and not packBooleanFlag(flag):
      usage()
    let value = if hasValue: paramStr(index + 1) else: "true"
    case flag
    of "--name": name = value
    of "--title": title = value
    of "--id": id = value
    of "--profile": profile = value
    of "--width":
      try: width = parseInt(value)
      except ValueError: usage()
    of "--height":
      try: height = parseInt(value)
      except ValueError: usage()
    of "--resizable": resizable = parseCliBool(value)
    of "--fullscreen": fullscreen = parseCliBool(value)
    of "--maximize": maximized = parseCliBool(value)
    of "--always-on-top": alwaysOnTop = parseCliBool(value)
    of "--hide-window-decorations": hideWindowDecorations = parseCliBool(value)
    of "--enable-drag-drop": enableDragDrop = parseCliBool(value)
    of "--user-agent": userAgent = value
    of "--proxy-url": proxyUrl = value
    of "--incognito": incognito = parseCliBool(value)
    of "--zoom":
      try: zoom = parseInt(value)
      except ValueError: usage()
      if zoom < 25 or zoom > 500: usage()
    of "--ignore-certificate-errors": ignoreCertificateErrors = parseCliBool(value)
    of "--show-system-tray": showSystemTray = parseCliBool(value)
    of "--start-to-tray": startToTray = parseCliBool(value)
    of "--hide-on-close": hideOnClose = parseCliBool(value)
    of "--multi-window": multiWindow = parseCliBool(value)
    of "--multi-instance": multiInstance = parseCliBool(value)
    of "--use-local-file": useLocalFile = parseCliBool(value)
    of "--icon": icon = value
    of "--deep-link": deepLinkSchemes.add(value)
    of "--allow-permission": permissionsAllow.add(value)
    of "--inject-css": css.add(value)
    of "--inject-js": javascript.add(value)
    of "--allow-url": navigationAllow.add(value)
    of "--safe-domain": navigationAllow.add("https://" & value & "/**")
    of "--external-url": navigationExternal.add(value)
    of "--json": discard
    of "--out", "--host", "--targets": discard
    else: usage()
    if hasValue: index += 2 else: inc index
  if sourceIsLocal:
    localSourcePath = source
    localUseLocalFile = useLocalFile
    loaded = generateLocalManifest(source, name = name, id = id, profile = profile, title = title,
      icon = icon, width = width,
      height = height, resizable = resizable, fullscreen = fullscreen,
      maximized = maximized, alwaysOnTop = alwaysOnTop,
      hideWindowDecorations = hideWindowDecorations, userAgent = userAgent,
      enableDragDrop = enableDragDrop,
      proxyUrl = proxyUrl, incognito = incognito, zoom = zoom,
      ignoreCertificateErrors = ignoreCertificateErrors,
      showSystemTray = showSystemTray, startToTray = startToTray,
      hideOnClose = hideOnClose, multiWindow = multiWindow,
      multiInstance = multiInstance, permissionsAllow = permissionsAllow,
      css = css, javascript = javascript, navigationAllow = navigationAllow,
      navigationExternal = navigationExternal)
  else:
    loaded = generateManifest(source, name = name, id = id, profile = profile, title = title,
      icon = icon, deepLinkSchemes = deepLinkSchemes, width = width,
      height = height, resizable = resizable, fullscreen = fullscreen,
      maximized = maximized, alwaysOnTop = alwaysOnTop,
      hideWindowDecorations = hideWindowDecorations, userAgent = userAgent,
      enableDragDrop = enableDragDrop,
      proxyUrl = proxyUrl, incognito = incognito, zoom = zoom,
      ignoreCertificateErrors = ignoreCertificateErrors,
      showSystemTray = showSystemTray, startToTray = startToTray,
      hideOnClose = hideOnClose, multiWindow = multiWindow,
      multiInstance = multiInstance, permissionsAllow = permissionsAllow,
      css = css, javascript = javascript, navigationAllow = navigationAllow,
      navigationExternal = navigationExternal)
else:
  loaded = loadManifest(source)
if not loaded.isOk:
  stderr.writeLine("nimino pack: " & loaded.error.detail)
  quit(1)
var output = manifestJson(loaded.value).pretty()
var outputDirectory = ""
var hostPath = ""
var jsonOutput = false
var targets: seq[string]
var index = optionStart
while index <= paramCount():
  let flag = paramStr(index)
  let hasValue = index < paramCount() and not paramStr(index + 1).startsWith("--")
  if not hasValue and not packBooleanFlag(flag): usage()
  case flag
  of "--out":
    if not hasValue: usage()
    outputDirectory = paramStr(index + 1)
  of "--host":
    if not hasValue: usage()
    hostPath = paramStr(index + 1)
  of "--targets":
    if not hasValue: usage()
    for target in paramStr(index + 1).split(','):
      if target.strip().len > 0: targets.add(target.strip().toLowerAscii())
  of "--config", "--name", "--id", "--profile", "--title", "--width", "--height", "--resizable",
     "--fullscreen", "--maximize", "--always-on-top", "--hide-window-decorations",
     "--enable-drag-drop",
     "--user-agent", "--proxy-url", "--incognito", "--zoom", "--ignore-certificate-errors", "--show-system-tray",
     "--start-to-tray", "--hide-on-close", "--multi-window", "--multi-instance",
     "--icon", "--deep-link", "--allow-permission", "--inject-css", "--inject-js", "--allow-url", "--safe-domain", "--external-url",
     "--use-local-file":
    if not sourceIsUrl and not sourceIsLocal:
      if not hasValue and not packBooleanFlag(flag): usage()
      let value = if hasValue: paramStr(index + 1) else: "true"
      applyManifestCliOverride(loaded.value, flag, value)
  of "--json":
    jsonOutput = true
  else: usage()
  if hasValue: index += 2 else: inc index
let validatedLoaded = loaded.value.validate()
if not validatedLoaded.isOk:
  stderr.writeLine("nimino pack: " & validatedLoaded.error.detail)
  quit(1)
loaded = validatedLoaded
if hostPath.len > 0 and not fileExists(hostPath):
  stderr.writeLine("nimino pack: host executable does not exist")
  quit(1)
if outputDirectory.len == 0:
  echo output
else:
  if hostPath.len == 0:
    stderr.writeLine("nimino pack: --host is required when --out is used; bundles must carry their host executable")
    quit(1)
  let directory = outputDirectory
  if directory.len == 0:
    usage()
  let sourceManifest = loaded.value
  let sourceIconIsRemote = sourceManifest.icon.toLowerAscii().startsWith("http://") or
    sourceManifest.icon.toLowerAscii().startsWith("https://") or
    sourceManifest.icon.toLowerAscii().startsWith("data:")
  if sourceManifest.icon.len > 0 and not sourceIconIsRemote and not fileExists(sourceManifest.icon):
    stderr.writeLine("nimino pack: local icon does not exist")
    quit(1)
  for injected in sourceManifest.css & sourceManifest.javascript:
    if not fileExists(injected):
      stderr.writeLine("nimino pack: injected file does not exist: " & injected)
      quit(1)
  if localSourcePath.len > 0:
    let sourceAbsolute = absolutePath(localSourcePath).normalizedPath()
    let stageRoot = if dirExists(sourceAbsolute): sourceAbsolute
      elif localUseLocalFile: parentDir(sourceAbsolute)
      else: sourceAbsolute
    let outputAbsolute = absolutePath(directory).normalizedPath()
    let relativeOutput = relativePath(outputAbsolute, stageRoot).replace('\\', '/')
    if relativeOutput == "." or
        (relativeOutput != ".." and not relativeOutput.startsWith("../")):
      stderr.writeLine("nimino pack: output directory must not be inside local source assets")
      quit(1)
  try:
    createDir(directory)
  except OSError:
    stderr.writeLine("nimino pack: unable to create output directory")
    quit(1)
  var packaged = sourceManifest
  if localSourcePath.len > 0:
    let sourceRoot = absolutePath(localSourcePath).normalizedPath()
    let assetsRoot = directory / "assets"
    try:
      createDir(assetsRoot)
    except OSError:
      stderr.writeLine("nimino pack: unable to create local assets directory")
      quit(1)
    if dirExists(sourceRoot):
      if not stageLocalTree(sourceRoot, assetsRoot):
        quit(1)
    elif localUseLocalFile:
      if not stageLocalTree(parentDir(sourceRoot), assetsRoot):
        quit(1)
    elif not copyGenerated(sourceRoot, assetsRoot / extractFilename(sourceRoot)):
      quit(1)
    packaged.localEntry = "assets/" & packaged.localEntry
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
  let iconIsRemote = packaged.icon.toLowerAscii().startsWith("http://") or
    packaged.icon.toLowerAscii().startsWith("https://") or
    packaged.icon.toLowerAscii().startsWith("data:")
  if iconIsRemote:
    let parsed = if packaged.icon.toLowerAscii().startsWith("data:"):
        parseUri("https://nimino.invalid/icon.png")
      else:
        parseUri(packaged.icon)
    let candidate = if parsed.path.len > 0: extractFilename(parsed.path) else: "icon"
    let iconName = safeIconName(candidate, iconExtension("", candidate))
    if fileExists(directory / iconName):
      stderr.writeLine("nimino pack: icon filename collides with generated assets: " & iconName)
      quit(1)
    if not fetchRemoteIcon(packaged.icon, directory / iconName):
      quit(1)
    packaged.icon = iconName
    localIconName = iconName
  elif packaged.icon.len > 0 and fileExists(packaged.icon):
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
  if not writeGenerated(launcherPath, "#!/bin/sh\n# Generated by nimino-pack.\nexec \"$(dirname \"$0\")/" & hostName & "\" --manifest \"$(dirname \"$0\")/nimino-manifest.json\" \"$@\"\n"):
    quit(1)
  setFilePermissions(launcherPath, {fpUserExec, fpUserRead, fpUserWrite,
    fpGroupExec, fpGroupRead, fpOthersExec, fpOthersRead})
  let windowsLauncherPath = directory / "run-nimino.cmd"
  let windowsHostName = if hostPath.len == 0: "nimino-host.exe" else: hostName
  if not writeGenerated(windowsLauncherPath, "@echo off\r\nrem Generated by nimino-pack.\r\n\"%~dp0" & cmdEscape(windowsHostName) & "\" --manifest \"%~dp0nimino-manifest.json\" %*\r\n"):
    quit(1)
  let shortcutPropertiesPath = directory / "register-windows-shortcut.ps1"
  if not writeGenerated(shortcutPropertiesPath, windowsShortcutPropertiesScript()):
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
      windowsMetadataJson(packaged, localIconName, windowsHostName).pretty() & "\n"):
    quit(1)
  let installScriptPath = directory / "install-windows.ps1"
  if not writeGenerated(installScriptPath,
      windowsInstallScript(packaged, localIconName, windowsHostName)):
    quit(1)
  let uninstallScriptPath = directory / "uninstall-windows.ps1"
  if not writeGenerated(uninstallScriptPath, windowsUninstallScript(packaged, windowsHostName)):
    quit(1)
  var artifacts = newJArray()
  if targets.len > 0:
    let packageDirectory = directory / "packages"
    try: createDir(packageDirectory)
    except OSError:
      stderr.writeLine("nimino pack: unable to create package output directory")
      quit(1)
    for target in targets:
      var artifact: PackResult[string]
      case target
      of "deb", "rpm", "appimage", "flatpak":
        let format = case target
          of "deb": debPackage
          of "rpm": rpmPackage
          of "appimage": appImagePackage
          else: flatpakPackage
        artifact = buildLinuxPackage(LinuxPackageOptions(bundleDirectory: directory,
          outputDirectory: packageDirectory, format: format, architecture: "amd64",
          maintainer: packaged.package.publisher, license: "Proprietary"))
      of "nsis", "msi":
        let format = if target == "nsis": nsisPackage else: msiPackage
        artifact = buildWindowsPackage(WindowsPackageOptions(bundleDirectory: directory,
          outputDirectory: packageDirectory, format: format))
      else:
        stderr.writeLine("nimino pack: unsupported target: " & target)
        quit(1)
      if not artifact.isOk:
        stderr.writeLine("nimino pack: " & artifact.error.detail)
        quit(1)
      artifacts.add(%artifact.value)
  if jsonOutput:
    echo (%*{"manifest": manifestPath, "directory": directory,
      "localEntry": packaged.localEntry, "artifacts": artifacts}).pretty()
  else:
    echo manifestPath
