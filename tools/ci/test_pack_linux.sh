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
  '' \
  '[package]' \
  'version = "1.2.3"' \
  'description = "Nimino Linux package test"' \
  'homepage = "https://nimino.example/linux-demo"' \
  'categories = ["Network", "Utility"]' \
  > "$root/input.toml"
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

if "$nimino" package-linux "$root/bundle" --format appimage --out "$root/out" 2>"$root/appimage.err"; then
  exit 1
fi
grep -Fx 'nimino package-linux: AppImage package generation requires appimagetool in the Docker image' "$root/appimage.err"
