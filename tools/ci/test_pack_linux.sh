#!/bin/sh
set -eu

nimino="${1:-/tmp/nimino}"
root=/tmp/nimino-pack-linux-test

rm -rf "$root"
mkdir -p "$root/out"
printf '%s\n' \
  'name = "Linux Demo"' \
  'id = "app.nimino.linux-demo"' \
  'url = "https://example.com"' \
  "icon = \"$root/icon.svg\"" \
  '' \
  '[package]' \
  'version = "1.2.3"' \
  'description = "Nimino Linux package test"' \
  'homepage = "https://nimino.example/linux-demo"' \
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
"$nimino" package-linux "$root/bundle" --format deb --out "$root/out" \
  --arch amd64 --maintainer 'Nimino Tests <tests@nimino.invalid>'
test -s "$root/out/app.nimino.linux-demo_1.2.3_amd64.deb"
dpkg-deb -f "$root/out/app.nimino.linux-demo_1.2.3_amd64.deb" Package | grep -Fx 'app.nimino.linux-demo'
dpkg-deb -f "$root/out/app.nimino.linux-demo_1.2.3_amd64.deb" Architecture | grep -Fx 'amd64'
dpkg-deb -c "$root/out/app.nimino.linux-demo_1.2.3_amd64.deb" | grep -q './opt/nimino/app.nimino.linux-demo/run-nimino.sh'
dpkg-deb -c "$root/out/app.nimino.linux-demo_1.2.3_amd64.deb" | grep -q './usr/share/applications/app.nimino.linux-demo.desktop'

"$nimino" package-linux "$root/bundle" --format rpm --out "$root/out" \
  --arch amd64 --license MIT
test -s "$root/out/app.nimino.linux-demo-1.2.3-1.x86_64.rpm"
rpm -qp --qf '%{NAME} %{VERSION} %{ARCH}\n' "$root/out/app.nimino.linux-demo-1.2.3-1.x86_64.rpm" | grep -Fx 'app.nimino.linux-demo 1.2.3 x86_64'
rpm -qpl "$root/out/app.nimino.linux-demo-1.2.3-1.x86_64.rpm" | grep -Fx '/opt/nimino/app.nimino.linux-demo/run-nimino.sh'
rpm -qpl "$root/out/app.nimino.linux-demo-1.2.3-1.x86_64.rpm" | grep -Fx '/usr/share/applications/app.nimino.linux-demo.desktop'

"$nimino" package-linux "$root/bundle" --format appimage --out "$root/out" --arch amd64
appimage="$root/out/app.nimino.linux-demo-1.2.3-x86_64.AppImage"
test -s "$appimage"
mkdir "$root/extracted"
(
  cd "$root/extracted"
  APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" --appimage-extract
)
test -x "$root/extracted/squashfs-root/AppRun"
test -x "$root/extracted/squashfs-root/usr/bin/app.nimino.linux-demo"
test -f "$root/extracted/squashfs-root/usr/lib/nimino/app.nimino.linux-demo/run-nimino.sh"
test -x "$root/extracted/squashfs-root/usr/lib/nimino/app.nimino.linux-demo/run-nimino.sh"
test -x "$root/extracted/squashfs-root/usr/lib/nimino/app.nimino.linux-demo/nimino-host"
test -f "$root/extracted/squashfs-root/icon.svg"
grep -Fx 'Exec=app.nimino.linux-demo' "$root/extracted/squashfs-root/app.nimino.linux-demo.desktop"
grep -Fx 'Icon=icon' "$root/extracted/squashfs-root/app.nimino.linux-demo.desktop"
! grep -F 'X-Nimino-Manifest=' "$root/extracted/squashfs-root/app.nimino.linux-demo.desktop"
APPIMAGE_EXTRACT_AND_RUN=1 "$appimage" --smoke

flatpak_context="$root/out/app.nimino.linux-demo-1.2.3-flatpak"
"$nimino" package-linux "$root/bundle" --format flatpak --out "$root/out"
test -s "$flatpak_context/app.nimino.linux-demo.flatpak.json"
test -f "$flatpak_context/bundle/run-nimino.sh"
grep -F '"app-id": "app.nimino.linux-demo"' "$flatpak_context/app.nimino.linux-demo.flatpak.json"
grep -F '"runtime": "org.gnome.Platform"' "$flatpak_context/app.nimino.linux-demo.flatpak.json"
grep -F '"type": "dir"' "$flatpak_context/app.nimino.linux-demo.flatpak.json"
grep -F '"path": "bundle"' "$flatpak_context/app.nimino.linux-demo.flatpak.json"

if "$nimino" package-linux "$root/bundle" --format appimage --out "$root/out" --arch arm64 2>"$root/appimage-arm64.err"; then
  exit 1
fi
grep -Fx 'nimino package-linux: AppImage package generation currently supports amd64 only' "$root/appimage-arm64.err"
