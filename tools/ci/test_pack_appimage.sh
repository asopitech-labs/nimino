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

echo "AppImage package smoke passed: $artifact"
