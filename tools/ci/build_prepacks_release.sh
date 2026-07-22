#!/usr/bin/env bash
set -euo pipefail

cli=${1:?usage: build_prepacks_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir>}
linux_host=${2:?usage: build_prepacks_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir>}
windows_host=${3:?usage: build_prepacks_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir>}
output=${4:?usage: build_prepacks_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir>}

test -x "$cli" || { echo "prepack release: CLI is not executable: $cli" >&2; exit 1; }
test -x "$linux_host" || { echo "prepack release: Linux host is not executable: $linux_host" >&2; exit 1; }
test -s "$windows_host" || { echo "prepack release: Windows host is missing: $windows_host" >&2; exit 1; }
webview2_loader=${NIMINO_WEBVIEW2_LOADER:-/opt/nimino/webview2/x64/WebView2Loader.dll}
test -s "$webview2_loader" || { echo "prepack release: WebView2Loader.dll is missing: $webview2_loader" >&2; exit 1; }
webview2_setup=${NIMINO_WEBVIEW2_SETUP:-/workspace/tools/ci/setup-windows-webview2.ps1}
test -s "$webview2_setup" || { echo "prepack release: WebView2 setup script is missing: $webview2_setup" >&2; exit 1; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
assets="$output/assets"
rm -rf "$output"
mkdir -p "$assets"

copy_assets() {
  local app=$1
  local package_dir=$2
  local found=0
  shopt -s nullglob
  for artifact in "$package_dir"/*; do
    if [[ -f "$artifact" ]]; then
      cp "$artifact" "$assets/${app}-$(basename "$artifact")"
      found=1
    fi
  done
  shopt -u nullglob
  if [[ "$found" -eq 0 ]]; then
    echo "prepack release: no package artifact was generated for $app" >&2
    exit 1
  fi
}

for app in youtube gmail google-analytics; do
  linux_bundle="$root/$app-linux"
  linux_packages="$root/$app-linux-packages"
  "$cli" pack prepack "$app" --out "$linux_bundle" --host "$linux_host"
  mkdir -p "$linux_packages"
  "$cli" package-linux "$linux_bundle" --format deb --out "$linux_packages" \
    --arch amd64 --maintainer "Nimino Prepack Release <noreply@nimino.invalid>"
  "$cli" package-linux "$linux_bundle" --format rpm --out "$linux_packages" \
    --arch amd64 --license MIT
  copy_assets "$app" "$linux_packages"
  cp "$linux_bundle/nimino-sbom.cdx.json" "$assets/${app}-linux-nimino-sbom.cdx.json"

  windows_bundle="$root/$app-windows"
  windows_packages="$root/$app-windows-packages"
  "$cli" pack prepack "$app" --out "$windows_bundle" --host "$windows_host"
  cp "$webview2_loader" "$windows_bundle/WebView2Loader.dll"
  mkdir -p "$windows_packages"
  "$cli" package-windows "$windows_bundle" --format nsis --out "$windows_packages"
  "$cli" package-windows "$windows_bundle" --format msi --out "$windows_packages"
  copy_assets "$app" "$windows_packages"
  cp "$windows_bundle/nimino-sbom.cdx.json" "$assets/${app}-windows-nimino-sbom.cdx.json"
done

cp "$webview2_setup" "$assets/Nimino-WebView2-Setup.ps1"
(cd "$assets" && sha256sum -- * > SHA256SUMS)
printf '%s\n' \
  'Nimino prepack release assets' \
  '' \
  'Apps: youtube, gmail, google-analytics' \
  'Linux: Debian (.deb), RPM (.rpm)' \
  'Windows: NSIS (.exe), MSI (.msi)' \
  '' \
  'Windows prerequisite (required before installing):' \
  'Shortest command (convenience mode): run the README irm URL | iex bootstrap.' \
  'Managed installation (if winget is available):' \
  '  winget install --id Microsoft.EdgeWebView2Runtime --exact --silent --accept-source-agreements --accept-package-agreements' \
  'The URL convenience command has no local SHA-256 check.' \
  'Strict path: verify SHA256SUMS, then run the downloaded setup script from elevated PowerShell.' \
  'After the runtime is confirmed, install the downloaded NSIS or MSI package.' \
  'WebView2Loader.dll is bundled; the Evergreen Runtime itself is not bundled.' \
  'Verify SHA256SUMS before installation.' \
  > "$output/RELEASE-NOTES.txt"
