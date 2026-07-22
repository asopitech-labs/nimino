#!/bin/sh
set -eu

nimino="${1:-/tmp/nimino}"
host="${2:-/tmp/nimino-host}"
root=/tmp/nimino-pack-appimage-test

rm -rf "$root"
mkdir -p "$root/out"
printf '%s\n' \
  '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">' \
  '<rect width="64" height="64" fill="#2563eb"/>' \
  '</svg>' > "$root/icon.svg"

"$nimino" pack https://example.com \
  --name AppImageSmoke \
  --id app.nimino.appimage-smoke \
  --icon "$root/icon.svg" \
  --out "$root/bundle" \
  --host "$host"

# The CLI URL form has no deep-link flag, so add a manifest fixture through the
# TOML path and ensure the AppImage keeps the OS registration metadata in both
# desktop-entry copies.
cat > "$root/input.toml" <<EOF
name = "AppImageSmoke"
id = "app.nimino.appimage-smoke"
url = "https://example.com"
icon = "$root/icon.svg"
[deepLink]
schemes = ["nimino"]
EOF
rm -rf "$root/bundle"
"$nimino" pack "$root/input.toml" \
  --out "$root/bundle" \
  --host "$host"
"$nimino" package-linux "$root/bundle" --format appimage \
  --out "$root/out" --arch amd64

artifact="$(find "$root/out" -maxdepth 1 -type f -name '*.AppImage' -print -quit)"
test -n "$artifact"
test -s "$artifact"
test -x "$artifact"
offset="$(grep -abo 'hsqs' "$artifact" | tail -1 | cut -d: -f1)"
test -n "$offset"
unsquashfs -offset "$offset" -l "$artifact" | grep -F "app.nimino.appimage-smoke.desktop"
unsquashfs -offset "$offset" -l "$artifact" | grep -F 'AppRun'
unsquashfs -offset "$offset" -l "$artifact" | grep -F 'libwebkitgtk-6.0.so.4'
unsquashfs -offset "$offset" -cat "$artifact" \
  "app.nimino.appimage-smoke.desktop" | \
  grep -F 'MimeType=x-scheme-handler/nimino;'

echo "AppImage package smoke passed: $artifact"
