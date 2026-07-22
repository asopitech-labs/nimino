#!/bin/sh
set -eu

nimino="${1:-/tmp/nimino}"
root=/tmp/nimino-pack-cli-test

rm -rf "$root"
mkdir -p "$root"
printf '%s\n' \
  'name = "Demo"' \
  'id = "app.nimino.demo"' \
  'url = "https://example.com"' \
  'icon = "/tmp/nimino-pack-cli-test/icon.png"' \
  '' \
  '[package]' \
  'version = "1.2.3"' \
  'description = "Demo desktop application"' \
  'publisher = "Nimino Labs"' \
  'homepage = "https://nimino.example/demo"' \
  'categories = ["Network", "Utility"]' \
  '' \
  '[deepLink]' \
  'schemes = ["NIMINO", "foo+bar"]' \
  > "$root/input.toml"
printf '#!/bin/sh\n' > "$root/host"
printf 'icon' > "$root/icon.png"
printf 'body{}' > "$root/custom.css"
printf 'console.log(1)' > "$root/custom.js"

"$nimino" pack "$root/input.toml" --out "$root/out" --host "$root/host"
test -s "$root/out/nimino-manifest.json"
test -s "$root/out/nimino-sbom.cdx.json"
grep -q 'CycloneDX' "$root/out/nimino-sbom.cdx.json"
test -x "$root/out/run-nimino.sh"
test -x "$root/out/host"
test -s "$root/out/run-nimino.cmd"
grep -q 'host"' "$root/out/run-nimino.cmd"
test -s "$root/out/app.nimino.demo.desktop"
test -s "$root/out/nimino-linux-package.json"
test -s "$root/out/nimino-windows-installer.json"
test -s "$root/out/install-windows.ps1"
test -s "$root/out/uninstall-windows.ps1"
grep -Fx 'Version=1.0' "$root/out/app.nimino.demo.desktop"
grep -Fx 'Name=Demo' "$root/out/app.nimino.demo.desktop"
grep -Fx 'Comment=Demo desktop application' "$root/out/app.nimino.demo.desktop"
grep -Fx 'Exec=/opt/nimino/app.nimino.demo/run-nimino.sh' "$root/out/app.nimino.demo.desktop"
grep -Fx 'TryExec=/opt/nimino/app.nimino.demo/run-nimino.sh' "$root/out/app.nimino.demo.desktop"
grep -Fx 'Icon=/opt/nimino/app.nimino.demo/icon.png' "$root/out/app.nimino.demo.desktop"
grep -Fx 'Categories=Network;Utility;' "$root/out/app.nimino.demo.desktop"
grep -Fx 'MimeType=x-scheme-handler/nimino;x-scheme-handler/foo+bar;' "$root/out/app.nimino.demo.desktop"
grep -Fx 'X-Nimino-Deep-Link-Schemes=nimino;foo+bar;' "$root/out/app.nimino.demo.desktop"
grep -q '"version": "1.2.3"' "$root/out/nimino-manifest.json"
grep -q '"deepLink": {' "$root/out/nimino-manifest.json"
grep -q '"deepLinkSchemes": \[' "$root/out/nimino-linux-package.json"
grep -q '"deepLinkSchemes": \[' "$root/out/nimino-windows-installer.json"
grep -q '"nimino"' "$root/out/nimino-manifest.json"
grep -q '"installScope": "perUser"' "$root/out/nimino-windows-installer.json"
grep -Eq '"toastActivatorClsid": "[0-9A-Fa-f-]{36}"' "$root/out/nimino-windows-installer.json"
grep -q 'System.AppUserModel.ToastActivatorCLSID' "$root/out/register-windows-shortcut.ps1"
grep -q 'LocalServer32' "$root/out/install-windows.ps1"
grep -q 'DisplayVersion' "$root/out/install-windows.ps1"
grep -q 'UninstallString' "$root/out/install-windows.ps1"
grep -q 'Remove-Item -LiteralPath \$target' "$root/out/uninstall-windows.ps1"

printf '#!/bin/sh\n' > "$root/host&name"
"$nimino" pack https://example.com --name DemoCmdEscape --id app.nimino.demo-cmd-escape \
  --out "$root/cmd-escape-out" --host "$root/host&name"
grep -q 'host^&name' "$root/cmd-escape-out/run-nimino.cmd"

! "$nimino" pack https://example.com --name MissingHost --id app.nimino.missing-host \
  --out "$root/missing-host-no-flag-out"
test ! -e "$root/missing-host-no-flag-out"

"$nimino" pack https://example.com --name DemoUrl --id app.nimino.demo-url \
  --icon https://example.com/icon.png --out "$root/url-out" --host "$root/host"
grep -q 'DemoUrl' "$root/url-out/nimino-manifest.json"
grep -q 'https://example.com' "$root/url-out/nimino-manifest.json"
grep -q 'icon.png' "$root/url-out/nimino-manifest.json"
test -s "$root/url-out/app.nimino.demo-url.desktop"
! grep -q '^Icon=' "$root/url-out/app.nimino.demo-url.desktop"

"$nimino" pack https://example.com --name DemoUrlDeep --id app.nimino.demo-url-deep \
  --deep-link "DEMO" --out "$root/url-deep-out" --host "$root/host"
grep -Fq '"schemes": [' "$root/url-deep-out/nimino-manifest.json"
grep -Fq '"demo"' "$root/url-deep-out/nimino-manifest.json"
grep -Fq 'MimeType=x-scheme-handler/demo;' "$root/url-deep-out/app.nimino.demo-url-deep.desktop"

"$nimino" pack HTTPS://example.com --name DemoUpperUrl --id app.nimino.demo-upper-url \
  --out "$root/upper-url-out" --host "$root/host"
grep -q 'DemoUpperUrl' "$root/upper-url-out/nimino-manifest.json"

! "$nimino" pack https://example.com --name MissingHost --id app.nimino.missing-host \
  --out "$root/missing-host-out" --host "$root/no-such-host"
test ! -e "$root/missing-host-out"

"$nimino" pack https://example.com --name DemoLocalIcon --id app.nimino.demo-local-icon \
  --icon "$root/icon.png" --out "$root/local-icon-out" --host "$root/host"
test -s "$root/local-icon-out/icon.png"
grep -q '"icon": "icon.png"' "$root/local-icon-out/nimino-manifest.json"

! "$nimino" pack https://example.com --name MissingIcon --id app.nimino.missing-icon \
  --icon "$root/no-such-icon.png" --out "$root/missing-icon-out"
test ! -e "$root/missing-icon-out"

printf '%s\n' \
  'name = "DemoInject"' \
  'id = "app.nimino.demo-inject"' \
  'url = "https://example.com"' \
  '' \
  '[injection]' \
  'css = ["/tmp/nimino-pack-cli-test/custom.css"]' \
  'javascript = ["/tmp/nimino-pack-cli-test/custom.js"]' \
  > "$root/inject.toml"
"$nimino" pack "$root/inject.toml" --out "$root/inject-out" --host "$root/host"
test -s "$root/inject-out/custom.css"
test -s "$root/inject-out/custom.js"
grep -q 'custom.css' "$root/inject-out/nimino-manifest.json"
grep -q 'custom.js' "$root/inject-out/nimino-manifest.json"

printf '%s\n' \
  'name = "MissingInject"' \
  'id = "app.nimino.missing-inject"' \
  'url = "https://example.com"' \
  '' \
  '[injection]' \
  'css = ["/tmp/nimino-pack-cli-test/no-such.css"]' \
  > "$root/missing-inject.toml"
! "$nimino" pack "$root/missing-inject.toml" --out "$root/missing-inject-out" --host "$root/host"
test ! -e "$root/missing-inject-out"

"$nimino" pack https://example.com --name DemoOptions --id app.nimino.demo-options \
  --width 1440 --height 900 --resizable false --fullscreen --maximize \
  --hide-window-decorations --incognito false --multi-window \
  --allow-permission notifications --inject-css "$root/custom.css" \
  --inject-js "$root/custom.js" --allow-url 'https://example.com/**' \
  --external-url 'https://support.example.com/**' --out "$root/options-out" --host "$root/host"
grep -q '"width": 1440' "$root/options-out/nimino-manifest.json"
grep -q '"height": 900' "$root/options-out/nimino-manifest.json"
grep -q '"resizable": false' "$root/options-out/nimino-manifest.json"
grep -q '"notifications"' "$root/options-out/nimino-manifest.json"
grep -q 'custom.css' "$root/options-out/nimino-manifest.json"
grep -q 'custom.js' "$root/options-out/nimino-manifest.json"
grep -q 'support.example.com' "$root/options-out/nimino-manifest.json"
grep -q '"fullscreen": true' "$root/options-out/nimino-manifest.json"
grep -q '"maximized": true' "$root/options-out/nimino-manifest.json"
