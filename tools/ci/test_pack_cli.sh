#!/bin/sh
set -eu

nimino="${1:-/tmp/nimino}"
root=/tmp/nimino-pack-cli-test
test_linux="${NIMINO_TEST_REFERENCE_LINUX:-0}"
test_windows="${NIMINO_TEST_REFERENCE_WINDOWS:-0}"

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

## Pake accepts a bare web host, while a missing filesystem-shaped argument
## must be rejected rather than being turned into a broken HTTPS origin.
"$nimino" pack example.com --name BareHost --id app.nimino.bare-host \
  --out "$root/bare-host-out" --host "$root/host"
grep -q '"url": "https://example.com"' "$root/bare-host-out/nimino-manifest.json"
! "$nimino" pack ./missing-local-source --name MissingRelative --id app.nimino.missing-relative \
  --out "$root/missing-relative-out" --host "$root/host"
! "$nimino" pack /tmp/nimino-missing-local-source --name MissingAbsolute --id app.nimino.missing-absolute \
  --out "$root/missing-absolute-out" --host "$root/host"
! "$nimino" pack 'C:\\nimino-missing-local-source' --name MissingWindows --id app.nimino.missing-windows \
  --out "$root/missing-windows-out" --host "$root/host"
test ! -e "$root/missing-relative-out"
test ! -e "$root/missing-absolute-out"
test ! -e "$root/missing-windows-out"

"$nimino" pack "$root/input.toml" --out "$root/out" --host "$root/host"
test -s "$root/out/nimino-manifest.json"
test -s "$root/out/nimino-sbom.cdx.json"
grep -q 'CycloneDX' "$root/out/nimino-sbom.cdx.json"
test -x "$root/out/run-nimino.sh"
test -x "$root/out/host"
if [ "$test_windows" = 1 ]; then
  test -s "$root/out/run-nimino.cmd"
  grep -q 'host"' "$root/out/run-nimino.cmd"
  test -s "$root/out/nimino-windows-installer.json"
  test -s "$root/out/install-windows.ps1"
  test -s "$root/out/uninstall-windows.ps1"
fi
if [ "$test_linux" = 1 ]; then
  test -s "$root/out/app.nimino.demo.desktop"
  test -s "$root/out/nimino-linux-package.json"
  grep -Fx 'Version=1.0' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'Name=Demo' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'Comment=Demo desktop application' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'Exec=/opt/nimino/app.nimino.demo/run-nimino.sh' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'TryExec=/opt/nimino/app.nimino.demo/run-nimino.sh' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'Icon=/opt/nimino/app.nimino.demo/icon.png' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'Categories=Network;Utility;' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'MimeType=x-scheme-handler/nimino;x-scheme-handler/foo+bar;' "$root/out/app.nimino.demo.desktop"
  grep -Fx 'X-Nimino-Deep-Link-Schemes=nimino;foo+bar;' "$root/out/app.nimino.demo.desktop"
fi
grep -q '"version": "1.2.3"' "$root/out/nimino-manifest.json"
grep -q '"deepLink": {' "$root/out/nimino-manifest.json"
if [ "$test_linux" = 1 ]; then
  grep -q '"deepLinkSchemes": \[' "$root/out/nimino-linux-package.json"
fi
if [ "$test_windows" = 1 ]; then
  grep -q '"deepLinkSchemes": \[' "$root/out/nimino-windows-installer.json"
fi
grep -q '"nimino"' "$root/out/nimino-manifest.json"

"$nimino" pack --config "$root/input.toml" --out "$root/config-out" --host "$root/host"
grep -q 'Demo' "$root/config-out/nimino-manifest.json"
"$nimino" pack --config "$root/input.toml" --name Override --width 1111 \
  --multi-window false --internal-url-regex '^https://app[.]example[.]com' \
  --out "$root/config-override-out" --host "$root/host"
grep -q 'Override' "$root/config-override-out/nimino-manifest.json"
grep -q '"width": 1111' "$root/config-override-out/nimino-manifest.json"
grep -q '"multiWindow": false' "$root/config-override-out/nimino-manifest.json"
grep -F '"internalUrlRegex": "^https://app[.]example[.]com"' "$root/config-override-out/nimino-manifest.json"
printf '%s\n' '{"url":"https://example.com","name":"JsonDemo","identifier":"app.nimino.json","title":"Json Window","width":900,"zoom":125}' > "$root/config.json"
"$nimino" pack --config "$root/config.json" --out "$root/json-config-out" --host "$root/host"
grep -q 'JsonDemo' "$root/json-config-out/nimino-manifest.json"
grep -q 'Json Window' "$root/json-config-out/nimino-manifest.json"
grep -q '"zoom": 125' "$root/json-config-out/nimino-manifest.json"
"$nimino" pack --config "$root/config.json" --title "CLI Window" --zoom 150 \
  --out "$root/json-config-override-out" --host "$root/host"
grep -q 'CLI Window' "$root/json-config-override-out/nimino-manifest.json"
grep -q '"zoom": 150' "$root/json-config-override-out/nimino-manifest.json"

## Pake's --no-bundle contract maps to Nimino's metadata-only mode. A config
## may describe an unbundled wrapper, but `--out` must not silently assemble a
## partial installer directory.
printf '%s\n' '{"name":"MetadataOnly","id":"app.nimino.metadata-only","url":"https://example.com","bundle":false}' > "$root/no-bundle.json"
"$nimino" pack --config "$root/no-bundle.json" --json | grep -q 'MetadataOnly'
! "$nimino" pack --config "$root/no-bundle.json" --out "$root/no-bundle-out" --host "$root/host"
test ! -e "$root/no-bundle-out/nimino-manifest.json"
if [ "$test_windows" = 1 ]; then
  grep -q '"installScope": "perUser"' "$root/out/nimino-windows-installer.json"
  grep -Eq '"toastActivatorClsid": "[0-9A-Fa-f-]{36}"' "$root/out/nimino-windows-installer.json"
  grep -q 'System.AppUserModel.ToastActivatorCLSID' "$root/out/register-windows-shortcut.ps1"
  grep -q 'LocalServer32' "$root/out/install-windows.ps1"
  grep -q 'DisplayVersion' "$root/out/install-windows.ps1"
  grep -q 'UninstallString' "$root/out/install-windows.ps1"
  grep -q 'Remove-Item -LiteralPath \$target' "$root/out/uninstall-windows.ps1"
fi

printf '#!/bin/sh\n' > "$root/host&name"
"$nimino" pack https://example.com --name DemoCmdEscape --id app.nimino.demo-cmd-escape \
  --out "$root/cmd-escape-out" --host "$root/host&name"
if [ "$test_windows" = 1 ]; then
  grep -q 'host^&name' "$root/cmd-escape-out/run-nimino.cmd"
fi

! "$nimino" pack https://example.com --name MissingHost --id app.nimino.missing-host \
  --out "$root/missing-host-no-flag-out"
test ! -e "$root/missing-host-no-flag-out"

"$nimino" pack https://example.com --name DemoUrl --id app.nimino.demo-url \
  --icon 'data:image/png;base64,aWNvbg==' --out "$root/url-out" --host "$root/host"
grep -q 'DemoUrl' "$root/url-out/nimino-manifest.json"
grep -q 'https://example.com' "$root/url-out/nimino-manifest.json"
grep -q '"icon": "icon.png"' "$root/url-out/nimino-manifest.json"
test -s "$root/url-out/icon.png"
if [ "$test_linux" = 1 ]; then
  test -s "$root/url-out/app.nimino.demo-url.desktop"
  grep -Fx 'Icon=/opt/nimino/app.nimino.demo-url/icon.png' "$root/url-out/app.nimino.demo-url.desktop"
fi

mkdir -p "$root/icon-server"
printf 'remote-icon' > "$root/icon-server/remote.png"
printf 'auto-favicon' > "$root/icon-server/favicon.ico"
printf '<svg xmlns="http://www.w3.org/2000/svg"></svg>' > "$root/icon-server/icon.svg"
printf '<!doctype html><svg></svg>' > "$root/icon-server/not-an-icon.html"
python3 -m http.server 18765 --bind 0.0.0.0 --directory "$root/icon-server" > "$root/icon-server.log" 2>&1 &
icon_server=$!
trap 'kill "$icon_server" 2>/dev/null || true' EXIT
sleep 1
"$nimino" pack https://example.com --name DemoRemoteIcon --id app.nimino.demo-remote-icon \
  --icon http://127.0.0.1:18765/remote.png --out "$root/remote-icon-out" --host "$root/host"
test -s "$root/remote-icon-out/remote.png"
grep -q '"icon": "remote.png"' "$root/remote-icon-out/nimino-manifest.json"
"$nimino" pack https://example.com --name DemoSvgIcon --id app.nimino.demo-svg-icon \
  --icon http://127.0.0.1:18765/icon.svg --out "$root/svg-icon-out" --host "$root/host"
test -s "$root/svg-icon-out/icon.svg"
grep -q '"icon": "icon.svg"' "$root/svg-icon-out/nimino-manifest.json"
! "$nimino" pack https://example.com --name HtmlIcon --id app.nimino.html-icon \
  --icon http://127.0.0.1:18765/not-an-icon.html --out "$root/html-icon-out" --host "$root/host"
"$nimino" pack http://127.0.0.1:18765/app --name DemoAutoFavicon --id app.nimino.demo-auto-favicon \
  --out "$root/auto-favicon-out" --host "$root/host"
test -s "$root/auto-favicon-out/favicon.ico"
grep -q '"icon": "favicon.ico"' "$root/auto-favicon-out/nimino-manifest.json"
kill "$icon_server" 2>/dev/null || true
wait "$icon_server" 2>/dev/null || true
trap - EXIT

"$nimino" pack https://example.com --name DemoUrlDeep --id app.nimino.demo-url-deep \
  --deep-link "DEMO" --safe-domain ' slack.com , , acme.com ' \
  --out "$root/url-deep-out" --host "$root/host"
grep -Fq '"schemes": [' "$root/url-deep-out/nimino-manifest.json"
grep -Fq '"demo"' "$root/url-deep-out/nimino-manifest.json"
grep -Fq 'https://*.slack.com/**' "$root/url-deep-out/nimino-manifest.json"
grep -Fq 'https://*.acme.com/**' "$root/url-deep-out/nimino-manifest.json"
if [ "$test_linux" = 1 ]; then
  grep -Fq 'MimeType=x-scheme-handler/demo;' "$root/url-deep-out/app.nimino.demo-url-deep.desktop"
fi

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

mkdir -p "$root/local-app/subdir"
printf '<!doctype html><script src="subdir/app.js"></script>\n' > "$root/local-app/index.html"
printf 'console.log("local");\n' > "$root/local-app/subdir/app.js"
printf 'sibling\n' > "$root/local-app/sibling.txt"
"$nimino" pack "$root/local-app/index.html" --name DemoLocalFile \
  --id app.nimino.demo-local-file --use-local-file --out "$root/local-file-out" --host "$root/host"
test -s "$root/local-file-out/assets/index.html"
test -s "$root/local-file-out/assets/subdir/app.js"
test -s "$root/local-file-out/assets/sibling.txt"
grep -q '"localEntry": "assets/index.html"' "$root/local-file-out/nimino-manifest.json"

"$nimino" pack "$root/local-app/index.html" --name DemoSingleFile \
  --id app.nimino.demo-single-file --out "$root/single-file-out" --host "$root/host"
test -s "$root/single-file-out/assets/index.html"
test ! -e "$root/single-file-out/assets/subdir/app.js"
grep -q '"localEntry": "assets/index.html"' "$root/single-file-out/nimino-manifest.json"

"$nimino" pack "$root/local-app" --name DemoLocalDir \
  --id app.nimino.demo-local-dir --out "$root/local-dir-out" --host "$root/host"
test -s "$root/local-dir-out/assets/index.html"
test -s "$root/local-dir-out/assets/subdir/app.js"
grep -q '"localEntry": "assets/index.html"' "$root/local-dir-out/nimino-manifest.json"
## Pake stages a symlinked input tree without mutating the source. Nimino
## copies the resolved logical tree into the bundle and never writes beside it.
ln -s "$root/local-app" "$root/local-app-link"
"$nimino" pack "$root/local-app-link" --name DemoLocalSymlink \
  --id app.nimino.demo-local-symlink --out "$root/local-symlink-out" --host "$root/host"
test -s "$root/local-symlink-out/assets/index.html"
test -s "$root/local-app/index.html"
## A symlink inside the asset tree could escape the selected source root.
## Fail closed and leave no successfully assembled bundle behind.
ln -s "$root/no-such-local-asset" "$root/local-app/dangling-asset"
! "$nimino" pack "$root/local-app" --name DanglingLocalAsset \
  --id app.nimino.dangling-local-asset --out "$root/dangling-local-asset-out" --host "$root/host"
test ! -e "$root/dangling-local-asset-out/nimino-manifest.json"
rm "$root/local-app/dangling-asset"
! "$nimino" pack "$root/local-app" --name NestedOutput --id app.nimino.nested-output \
  --out "$root/local-app/bundle" --host "$root/host"
test ! -e "$root/local-app/bundle"

json_result=$("$nimino" pack https://example.com --name DemoJson --id app.nimino.demo-json \
  --json --out "$root/json-out" --host "$root/host")
## Port Pake's json-output contract: machine mode has one parseable JSON line
## on stdout, with diagnostics kept separate on stderr.
test "$(printf '%s\n' "$json_result" | wc -l | tr -d ' ')" -eq 1
printf '%s\n' "$json_result" | grep -q '"manifest"'
printf '%s\n' "$json_result" | grep -q 'nimino-manifest.json'

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

"$nimino" pack https://example.com --name DemoOptions --id app.nimino.demo-options --title 'Options Window' --zoom 125 \
  --width 1440 --height 900 --resizable false --fullscreen --maximize \
  --hide-window-decorations --enable-drag-drop --incognito false --multi-window \
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
grep -q '"enableDragDrop": true' "$root/options-out/nimino-manifest.json"
grep -q '"title": "Options Window"' "$root/options-out/nimino-manifest.json"
grep -q '"zoom": 125' "$root/options-out/nimino-manifest.json"
