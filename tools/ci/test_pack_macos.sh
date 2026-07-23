#!/bin/sh
set -eu

cli=${1:?usage: test_pack_macos.sh <nimino-cli> <nimino-host>}
host=${2:?usage: test_pack_macos.sh <nimino-cli> <nimino-host>}
root=$(mktemp -d /tmp/nimino-macos-pack.XXXXXX)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/site" "$root/out"
if [ "${NIMINO_TEST_MACOS_NOTIFICATION:-0}" = 1 ]; then
  printf '%s\n' '<!doctype html><title>Nimino macOS notification smoke</title><script>function send(){if(!window.nimino||typeof window.nimino.invoke!=="function"){setTimeout(send,250);return;}window.nimino.invoke("app.sendNotification",{id:"macos-adhoc-notification-click",title:"Nimino Ad-hoc smoke",body:"Click this notification"});}window.addEventListener("load",()=>setTimeout(send,1000));</script>' > "$root/site/index.html"
else
  printf '%s\n' '<!doctype html><title>Nimino macOS package smoke</title>' > "$root/site/index.html"
fi
"$cli" pack "$root/site" --name 'Nimino macOS Smoke' --id com.nimino.macos.smoke \
  --deep-link nimino --allow-permission camera --allow-permission microphone \
  --hide-title-bar --min-width 900 --min-height 600 --dark-mode \
  --disabled-web-shortcuts --enable-wasm --enable-find --new-window \
  --force-internal-navigation --show-system-tray \
  --activation-shortcut CmdOrCtrl+Shift+Space \
  --proxy-url http://127.0.0.1:8080 \
  --out "$root/bundle" --host "$host" --json
grep -F '"hideTitleBar": true' "$root/bundle/nimino-manifest.json"
grep -F '"minWidth": 900' "$root/bundle/nimino-manifest.json"
grep -F '"minHeight": 600' "$root/bundle/nimino-manifest.json"
grep -F '"darkMode": true' "$root/bundle/nimino-manifest.json"
grep -F '"activationShortcut": "CmdOrCtrl+Shift+Space"' "$root/bundle/nimino-manifest.json"
app=$($cli package-macos "$root/bundle" --format app --out "$root/out")
test -x "$app/Contents/MacOS/com.nimino.macos.smoke"
file "$app/Contents/MacOS/com.nimino.macos.smoke" | grep -E 'Mach-O|executable'
plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" | grep -Fx 'com.nimino.macos.smoke'
plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$app/Contents/Info.plist" | grep -Fx 'nimino'
plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist" | grep -Fx '14.0'
plutil -extract NSCameraUsageDescription raw "$app/Contents/Info.plist" | grep -F 'Camera access'
plutil -extract NSMicrophoneUsageDescription raw "$app/Contents/Info.plist" | grep -F 'Microphone access'
test -s "$app/Contents/Resources/nimino-entitlements.plist"
grep -F 'com.apple.security.device.camera' "$app/Contents/Resources/nimino-entitlements.plist"
grep -F 'com.apple.security.device.audio-input' "$app/Contents/Resources/nimino-entitlements.plist"
if [ "${NIMINO_TEST_MACOS_ADHOC:-0}" = 1 ] || [ "${NIMINO_TEST_MACOS_NOTIFICATION:-0}" = 1 ]; then
  codesign --deep --force --options runtime --sign - "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
fi
if [ "${NIMINO_TEST_MACOS_LAUNCH:-0}" = 1 ]; then
  open -n "$app"
  sleep 3
  pkill -f "$app/Contents/MacOS/com.nimino.macos.smoke" || true
  sleep 1
  open -n "$app" --args nimino://macos-package-smoke
  sleep 2
  pkill -f "$app/Contents/MacOS/com.nimino.macos.smoke" || true
fi
if [ "${NIMINO_TEST_MACOS_NOTIFICATION:-0}" = 1 ]; then
  log="$root/macos-notification.log"
  "$app/Contents/MacOS/com.nimino.macos.smoke" >"$log" 2>&1 &
  app_pid=$!
  trap 'kill "$app_pid" 2>/dev/null || true; rm -rf "$root"' EXIT
  sleep 5
  test -f "$log"
  echo 'macOS notification smoke log before click:'
  cat "$log" || true
  echo "macOS notification request was issued; if a notification is visible, click it in Notification Center, then press Return here."
  read _ || true
  echo 'macOS notification smoke log after click:'
  cat "$log" || true
  grep -F 'nimino-host: notification activated: macos-adhoc-notification-click' "$log"
  kill "$app_pid" 2>/dev/null || true
fi
if [ "${NIMINO_TEST_MACOS_DMG:-0}" = 1 ] && command -v hdiutil >/dev/null 2>&1; then
  dmg=$($cli package-macos "$root/bundle" --format dmg --out "$root/out")
  test -s "$dmg"
fi
echo 'macOS package smoke passed'
