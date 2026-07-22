#!/bin/sh
set -eu

nimino="${1:-/tmp/nimino}"
root=/tmp/nimino-pack-windows-test

rm -rf "$root"
mkdir -p "$root/out"
printf '%s\n' \
  'name = "Windows Demo"' \
  'id = "app.nimino.windows-demo"' \
  'url = "https://example.com"' \
  "icon = \"$root/icon.ico\"" \
  '' \
  '[package]' \
  'version = "1.2.3"' \
  'description = "Nimino Windows package test"' \
  'publisher = "Nimino Tests"' \
  'homepage = "https://nimino.example/windows-demo"' \
  '' \
  '[deepLink]' \
  'schemes = ["nimino", "foo+bar"]' \
  > "$root/input.toml"
printf 'not-a-real-icon\n' > "$root/icon.ico"
printf 'MZfake-windows-host\n' > "$root/nimino-host.exe"

"$nimino" pack "$root/input.toml" --out "$root/bundle" --host "$root/nimino-host.exe"
"$nimino" package-windows "$root/bundle" --format nsis --out "$root/out"
"$nimino" package-windows "$root/bundle" --format msi --out "$root/out/msi"

setup="$root/out/app.nimino.windows-demo-1.2.3-setup.exe"
script="$root/out/app.nimino.windows-demo-1.2.3-setup.nsi"
test -s "$setup"
test -s "$script"
test -s "$root/bundle/register-windows-shortcut.ps1"
grep -F '%*' "$root/bundle/run-nimino.cmd"
grep -F 'System.AppUserModel.ID' "$root/bundle/register-windows-shortcut.ps1"
grep -q '"appUserModelId": "app.nimino.windows-demo"' "$root/bundle/nimino-windows-installer.json"
grep -Eq '"toastActivatorClsid": "[0-9A-Fa-f-]{36}"' "$root/bundle/nimino-windows-installer.json"
grep -q '"toastActivation": "inProcessOrComLocalServer"' "$root/bundle/nimino-windows-installer.json"
grep -q '"hostExecutable": "nimino-host.exe"' "$root/bundle/nimino-windows-installer.json"
grep -q 'SetAppUserModelId' "$root/bundle/register-windows-shortcut.ps1"
grep -q 'ToastActivatorClsid' "$root/bundle/register-windows-shortcut.ps1"
grep -q 'LASTEXITCODE' "$root/bundle/install-windows.ps1"
grep -q 'Software.*Classes.*nimino' "$root/bundle/install-windows.ps1"
grep -q 'Software.*Classes.*foo+bar' "$root/bundle/install-windows.ps1"
grep -q 'URL Protocol' "$root/bundle/install-windows.ps1"
test "$(od -An -tx1 -N2 "$setup" | tr -d '[:space:]')" = '4d5a'
grep -Fx 'RequestExecutionLevel user' "$script"
grep -Fx 'InstallDir "$LOCALAPPDATA\Nimino\app.nimino.windows-demo"' "$script"
grep -Fx '  File /r "/tmp/nimino-pack-windows-test/bundle/*"' "$script"
grep -Fx '  WriteUninstaller "$INSTDIR\uninstall.exe"' "$script"
grep -Fx '  CreateShortcut "$SMPROGRAMS\Nimino\app.nimino.windows-demo.lnk" "$INSTDIR\run-nimino.cmd"' "$script"
grep -F 'register-windows-shortcut.ps1' "$script"
grep -F 'LocalServer32' "$script"
grep -F -- '-Embedding --manifest' "$script"
grep -F 'Software\Classes\nimino' "$script"
grep -F 'Software\Classes\foo+bar' "$script"
grep -F 'shell\open\command' "$script"
grep -F 'CLSID\{' "$script"
grep -F 'nimino-host.exe$\" -Embedding' "$script"
grep -Fx '  StrCmp $0 "0" +2' "$script"
grep -F '  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\app.nimino.windows-demo" "UninstallString"' "$script"

"$nimino" pack "$root/input.toml" --out "$root/no-host-bundle"
if "$nimino" package-windows "$root/no-host-bundle" --format nsis --out "$root/no-host-out" 2>"$root/no-host.err"; then
  exit 1
fi
grep -Fx 'nimino package-windows: Windows package bundle is missing a host executable' "$root/no-host.err"

msi="$root/out/msi/app.nimino.windows-demo-1.2.3.msi"
test -s "$msi"
test ! -e "$root/out/msi/app.nimino.windows-demo-1.2.3.wxs"
msiinfo tables "$msi" | grep -Fx 'File'
msiinfo tables "$msi" | grep -Fx 'Registry'
msiextract -l "$msi" | grep -F 'nimino-manifest.json'
msiextract -l "$msi" | grep -F 'run-nimino.cmd'
msiextract -l "$msi" | grep -F 'nimino-host.exe'
