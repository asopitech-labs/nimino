#!/bin/sh
set -eu

nimino=${1:?usage: test_pack_online.sh <nimino-cli> <nimino-host> <windows-host>}
host=${2:?usage: test_pack_online.sh <nimino-cli> <nimino-host> <windows-host>}
windows_host=${3:?usage: test_pack_online.sh <nimino-cli> <nimino-host> <windows-host>}
webview2_loader=${NIMINO_WEBVIEW2_LOADER:-/opt/nimino/webview2/x64/WebView2Loader.dll}
pcre_dll=${NIMINO_WINDOWS_PCRE_DLL:-/opt/nimino/windows-dlls/pcre64.dll}
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

# The Windows target stages two runtime libraries the host loads at process
# start.  A bundle that ships without either one installs cleanly and then
# fails before opening a window, so assert the staging the workflow performs
# rather than trusting it to stay in step with the site release.
windows_bundle="$root/windows-bundle"
windows_out="$root/windows-out"
mkdir -p "$windows_out"
"$nimino" pack https://example.com --name Example --id app.nimino.online \
  --out "$windows_bundle" --host "$windows_host"
test -s "$webview2_loader"
test -s "$pcre_dll"
install -m 0644 "$webview2_loader" "$windows_bundle/WebView2Loader.dll"
install -m 0644 "$pcre_dll" "$windows_bundle/pcre64.dll"
test -s "$windows_bundle/nimino-host.exe"
"$nimino" package-windows "$windows_bundle" --format nsis --out "$windows_out"
setup=$(find "$windows_out" -maxdepth 1 -type f -name '*-setup.exe' -print -quit)
test -n "$setup" -a -s "$setup"
# NSIS installs the bundle directory wholesale (File /r), so what reaches the
# user is whatever the staging step left behind.  Assert the directory the
# installer is built from rather than the compressed output.
for library in WebView2Loader.dll pcre64.dll; do
  test -s "$windows_bundle/$library" \
    || { echo "online pack: Windows bundle omits $library" >&2; exit 1; }
done
echo "Nimino online pack smoke passed"
