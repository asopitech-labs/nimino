#!/bin/sh
set -eu

cli=${1:?usage: test_pack_macos.sh <nimino-cli> <nimino-host>}
host=${2:?usage: test_pack_macos.sh <nimino-cli> <nimino-host>}
root=$(mktemp -d /tmp/nimino-macos-pack.XXXXXX)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/site" "$root/out"
tray_icon=/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns
test -f "$tray_icon"
wait_for_gui_windows() {
  expected=$1
  attempts=0
  while [ "$attempts" -lt 10 ]; do
    gui_window_count=$(osascript -e 'tell application "System Events" to tell process "com.nimino.macos.smoke" to count windows')
    if [ "$gui_window_count" -ge "$expected" ]; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 1
  done
  return 1
}
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
  --system-tray-icon "$tray_icon" \
  --activation-shortcut CmdOrCtrl+Shift+Space \
  --proxy-url http://127.0.0.1:8080 \
  --out "$root/bundle" --host "$host" --json
grep -F '"hideTitleBar": true' "$root/bundle/nimino-manifest.json"
grep -F '"minWidth": 900' "$root/bundle/nimino-manifest.json"
grep -F '"minHeight": 600' "$root/bundle/nimino-manifest.json"
grep -F '"darkMode": true' "$root/bundle/nimino-manifest.json"
grep -F '"activationShortcut": "CmdOrCtrl+Shift+Space"' "$root/bundle/nimino-manifest.json"
grep -F '"hideOnClose": true' "$root/bundle/nimino-manifest.json"
grep -F '"systemTrayIcon": "GenericApplicationIcon.icns"' "$root/bundle/nimino-manifest.json"
test -f "$root/bundle/GenericApplicationIcon.icns"
## Pake's system-tray-icon suite also covers rejecting a configured icon that
## cannot be read. Nimino reports this at pack time instead of silently
## falling back to the default icon.
if "$cli" pack "$root/site" --name 'Nimino missing tray icon' --id com.nimino.missing-tray-icon \
  --system-tray-icon "$root/missing-tray-icon.icns" --out "$root/missing-tray-icon" --host "$host" >/dev/null 2>&1; then
  echo 'nimino pack unexpectedly accepted a missing system tray icon' >&2
  exit 1
fi
## Pake's macOS default must not override an explicit opt-out.
"$cli" pack "$root/site" --name 'Nimino macOS Explicit Close' --id com.nimino.macos.explicit-close \
  --hide-on-close false --out "$root/explicit-close" --host "$host" --json >/dev/null
grep -F '"hideOnClose": false' "$root/explicit-close/nimino-manifest.json"
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
test -f "$app/Contents/Resources/GenericApplicationIcon.icns"
grep -F '"systemTrayIcon": "GenericApplicationIcon.icns"' "$app/Contents/Resources/nimino-manifest.json"
if [ "${NIMINO_TEST_MACOS_ADHOC:-0}" = 1 ] || [ "${NIMINO_TEST_MACOS_NOTIFICATION:-0}" = 1 ]; then
  codesign --deep --force --options runtime --sign - "$app"
  codesign --verify --deep --strict --verbose=2 "$app"
fi
if [ "${NIMINO_TEST_MACOS_LAUNCH:-0}" = 1 ]; then
  open -n "$app"
  sleep 3
  host_process="$app/Contents/MacOS/com.nimino.macos.smoke"
  first_count=$(pgrep -f "$host_process" | wc -l | tr -d ' ')
  test "$first_count" -eq 1
  ## The generated host implements Pake-style single-instance activation.
  ## A second LaunchServices request must focus the original process rather
  ## than leave a second host alive.
  open -n "$app"
  sleep 2
  second_count=$(pgrep -f "$host_process" | wc -l | tr -d ' ')
  test "$second_count" -eq 1
  if [ "${NIMINO_TEST_MACOS_GUI:-0}" = 1 ]; then
    ## Exercise the actual AppKit menu rather than merely checking that it was
    ## configured. This covers localEntry's File > New Window action on a
    ## GUI-login macOS runner with Accessibility permission.
    osascript -e 'tell application "System Events" to tell process "com.nimino.macos.smoke" to set frontmost to true' \
      -e 'tell application "System Events" to tell process "com.nimino.macos.smoke" to click menu bar item "File" of menu bar 1' \
      -e 'tell application "System Events" to tell process "com.nimino.macos.smoke" to click menu item "New Window" of menu "File" of menu bar item "File" of menu bar 1'
    wait_for_gui_windows 2
    osascript -e 'tell application "System Events" to tell process "com.nimino.macos.smoke" to click menu bar item "File" of menu bar 1' \
      -e 'tell application "System Events" to tell process "com.nimino.macos.smoke" to click menu item "Clear Cache & Reload" of menu "File" of menu bar item "File" of menu bar 1'
    wait_for_gui_windows 2
    if [ "${NIMINO_TEST_MACOS_TRAY:-0}" = 1 ]; then
      ## The menu-bar status item belongs to SystemUIServer's accessibility
      ## tree. On this GUI runner it is the only exposed AXMenuExtra. Exercise
      ## two actual primary clicks, verifying that AppKit publishes the signed
      ## status item and accepts real Accessibility-driven pointer events.
      tray_count=$(osascript -e 'tell application "System Events" to tell process "SystemUIServer" to tell menu bar 1 to count (every menu bar item whose subrole is "AXMenuExtra")')
      test "$tray_count" -eq 1
      osascript -e 'tell application "System Events" to tell process "SystemUIServer" to tell menu bar 1 to click first menu bar item whose subrole is "AXMenuExtra"'
      sleep 1
      osascript -e 'tell application "System Events" to tell process "SystemUIServer" to tell menu bar 1 to click first menu bar item whose subrole is "AXMenuExtra"'
      sleep 1
    fi
  fi
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
