#!/bin/sh
set -eu

nimino="${1:-/tmp/nimino}"
root=/tmp/nimino-pack-flatpak-test
runtime="org.gnome.Platform"
runtime_version="49"
sdk="org.gnome.Sdk"
branch="stable"

rm -rf "$root"
mkdir -p "$root/out"
printf '%s\n' \
  'name = "Flatpak Demo"' \
  'id = "app.nimino.flatpak-demo"' \
  'url = "https://example.com"' \
  "icon = \"$root/icon.svg\"" \
  '' \
  '[package]' \
  'version = "1.2.3"' \
  'description = "Nimino Flatpak package test"' \
  'homepage = "https://nimino.example/flatpak-demo"' \
  'categories = ["Network", "Utility"]' \
  > "$root/input.toml"
printf '%s\n' \
  '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">' \
  '<rect width="64" height="64" fill="#1b6ac9"/>' \
  '</svg>' \
  > "$root/icon.svg"
printf '#!/bin/sh\nexit 0\n' > "$root/nimino-host"
chmod +x "$root/nimino-host"

"$nimino" pack "$root/input.toml" --out "$root/bundle" --host "$root/nimino-host"
"$nimino" package-linux "$root/bundle" --format flatpak --out "$root/out"

context="$root/out/app.nimino.flatpak-demo-1.2.3-flatpak"
manifest="$context/app.nimino.flatpak-demo.flatpak.json"
repo="$root/repo"
build="$root/build"
artifact="$root/app.nimino.flatpak-demo.flatpak"
test -s "$manifest"
test -f "$context/bundle/run-nimino.sh"
grep -Fq '"runtime-version": "'"$runtime_version"'"' "$manifest"
grep -Fq '"type": "dir"' "$manifest"
grep -Fq '"path": "bundle"' "$manifest"

command -v flatpak >/dev/null
command -v flatpak-builder >/dev/null
flatpak --version
flatpak-builder --version

# Runtime and SDK refs are intentionally explicit.  A named /var/lib/flatpak
# volume in compose.yaml keeps this download out of every subsequent smoke run.
flatpak remote-add --if-not-exists --system flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak install --system --noninteractive flathub \
  "$runtime//$runtime_version" "$sdk//$runtime_version"

# The manifest source is the same bundle that package-linux emits.  Building
# into an OSTree repository and exporting a .flatpak proves that the context is
# consumable by flatpak-builder; no context-only grep is treated as success.
flatpak-builder --force-clean --disable-rofiles-fuse --state-dir="$root/state" --repo="$repo" \
  "$build" "$manifest"
flatpak build-bundle "$repo" "$artifact" app.nimino.flatpak-demo "$branch"
test -s "$artifact"
