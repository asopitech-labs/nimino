#!/bin/sh
set -eu

nimino=${1:?usage: test_pack_online.sh <nimino-cli> <nimino-host>}
host=${2:?usage: test_pack_online.sh <nimino-cli> <nimino-host>}
root=$(mktemp -d "${TMPDIR:-/tmp}/nimino-pack-online-test.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

bundle="$root/bundle"
out="$root/out"
mkdir -p "$out"
"$nimino" pack https://example.com --name Example --id app.nimino.online \
  --out "$bundle" --host "$host"
test -s "$bundle/nimino-manifest.json"
test -s "$bundle/nimino-sbom.cdx.json"
test -x "$bundle/nimino-host"
grep -F '"url": "https://example.com"' "$bundle/nimino-manifest.json"
grep -F '"id": "app.nimino.online"' "$bundle/nimino-manifest.json"

auto_bundle="$root/auto-bundle"
"$nimino" pack https://example.com --out "$auto_bundle" --host "$host"
test -s "$auto_bundle/nimino-manifest.json"
grep -F '"name": "Example"' "$auto_bundle/nimino-manifest.json"
grep -F '"id": "com.nimino.example-com"' "$auto_bundle/nimino-manifest.json"
grep -F '"allow": []' "$auto_bundle/nimino-manifest.json"
grep -F '"external": []' "$auto_bundle/nimino-manifest.json"

"$nimino" package-linux "$bundle" --format deb --out "$out" --arch amd64 \
  --maintainer "Nimino Online Build <noreply@nimino.invalid>"
package=$(find "$out" -maxdepth 1 -type f -name '*.deb' -print -quit)
test -n "$package" -a -s "$package"
sha256sum "$package" "$bundle/nimino-sbom.cdx.json" > "$out/SHA256SUMS"
(cd "$out" && sha256sum -c SHA256SUMS)
echo "Nimino online pack smoke passed"
