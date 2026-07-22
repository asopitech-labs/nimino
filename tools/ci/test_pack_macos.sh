#!/bin/sh
set -eu

cli=${1:?usage: test_pack_macos.sh <nimino-cli> <nimino-host>}
host=${2:?usage: test_pack_macos.sh <nimino-cli> <nimino-host>}
root=$(mktemp -d /tmp/nimino-macos-pack.XXXXXX)
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/site" "$root/out"
printf '%s\n' '<!doctype html><title>Nimino macOS package smoke</title>' > "$root/site/index.html"
"$cli" pack "$root/site" --name 'Nimino macOS Smoke' --id com.nimino.macos.smoke \
  --deep-link nimino --allow-permission camera --allow-permission microphone \
  --out "$root/bundle" --host "$host" --json
app=$($cli package-macos "$root/bundle" --format app --out "$root/out")
test -x "$app/Contents/MacOS/com.nimino.macos.smoke"
file "$app/Contents/MacOS/com.nimino.macos.smoke" | grep -E 'Mach-O|executable'
plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" | grep -Fx 'com.nimino.macos.smoke'
plutil -extract CFBundleURLTypes.0.CFBundleURLSchemes.0 raw "$app/Contents/Info.plist" | grep -Fx 'nimino'
plutil -extract NSCameraUsageDescription raw "$app/Contents/Info.plist" | grep -F 'Camera access'
plutil -extract NSMicrophoneUsageDescription raw "$app/Contents/Info.plist" | grep -F 'Microphone access'
if [ "${NIMINO_TEST_MACOS_DMG:-0}" = 1 ] && command -v hdiutil >/dev/null 2>&1; then
  dmg=$($cli package-macos "$root/bundle" --format dmg --out "$root/out")
  test -s "$dmg"
fi
echo 'macOS package smoke passed'
