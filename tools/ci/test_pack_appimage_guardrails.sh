#!/bin/sh
set -eu

nimino="${1:-/tmp/nimino}"
root=/tmp/nimino-pack-appimage-guardrails

rm -rf "$root"
mkdir -p "$root/out"
printf '%s\n' \
  'name = "AppImage Guardrails"' \
  'id = "app.nimino.appimage-guardrails"' \
  'url = "https://example.com"' \
  "icon = \"$root/icon.svg\"" \
  > "$root/input.toml"
printf '%s\n' \
  '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64">' \
  '<rect width="64" height="64" fill="#1b6ac9"/>' \
  '</svg>' \
  > "$root/icon.svg"
printf '#!/bin/sh\nexit 0\n' > "$root/nimino-host"
chmod +x "$root/nimino-host"

"$nimino" pack "$root/input.toml" --out "$root/bundle" --host "$root/nimino-host"
if "$nimino" package-linux "$root/bundle" --format appimage \
    --out "$root/out" --arch amd64 2>"$root/appimage.err"; then
  echo 'incomplete AppImage generation unexpectedly succeeded' >&2
  exit 1
fi
grep -F 'nimino package-linux: AppImage package generation is unavailable:' \
  "$root/appimage.err"
grep -Eq 'missing fixed build dependencies|dependency tool failed|dependency closure' \
  "$root/appimage.err"
test -z "$(find "$root/out" -maxdepth 1 -name '*.AppImage' -print -quit)"

echo 'AppImage CLI guardrail test passed'
