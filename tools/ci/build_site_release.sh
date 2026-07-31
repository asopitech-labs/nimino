#!/usr/bin/env bash
set -euo pipefail

cli=${1:?usage: build_site_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir> <app-version>}
linux_host=${2:?usage: build_site_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir> <app-version>}
windows_host=${3:?usage: build_site_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir> <app-version>}
output=${4:?usage: build_site_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir> <app-version>}
app_version=${5:?usage: build_site_release.sh <nimino-cli> <linux-host> <windows-host> <output-dir> <app-version>}

test -x "$cli" || { echo "site release: CLI is not executable: $cli" >&2; exit 1; }
test -x "$linux_host" || { echo "site release: Linux host is not executable: $linux_host" >&2; exit 1; }
test -s "$windows_host" || { echo "site release: Windows host is missing: $windows_host" >&2; exit 1; }
webview2_loader=${NIMINO_WEBVIEW2_LOADER:-/opt/nimino/webview2/x64/WebView2Loader.dll}
test -s "$webview2_loader" || { echo "site release: WebView2Loader.dll is missing: $webview2_loader" >&2; exit 1; }
pcre_dll=${NIMINO_WINDOWS_PCRE_DLL:-/opt/nimino/windows-dlls/pcre64.dll}
test -s "$pcre_dll" || { echo "site release: pcre64.dll is missing: $pcre_dll" >&2; exit 1; }
webview2_setup=${NIMINO_WEBVIEW2_SETUP:-/workspace/tools/ci/setup-windows-webview2.ps1}
test -s "$webview2_setup" || { echo "site release: WebView2 setup script is missing: $webview2_setup" >&2; exit 1; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
assets="$output/assets"
rm -rf "$output"
mkdir -p "$assets"

# Release assets are an explicit allowlist: each pattern must match exactly
# one generated file, and any file the allowlist does not cover fails the
# build instead of leaking into the published release.
copy_assets() {
  local app=$1
  local package_dir=$2
  shift 2
  local copied=()
  local pattern artifact name matches
  shopt -s nullglob
  for pattern in "$@"; do
    matches=()
    for artifact in "$package_dir"/$pattern; do
      [[ -f "$artifact" ]] && matches+=("$artifact")
    done
    if [[ "${#matches[@]}" -ne 1 ]]; then
      echo "site release: expected exactly one $pattern artifact for $app, found ${#matches[@]}" >&2
      exit 1
    fi
    cp "${matches[0]}" "$assets/${app}-$(basename "${matches[0]}")"
    copied+=("$(basename "${matches[0]}")")
  done
  for artifact in "$package_dir"/*; do
    [[ -f "$artifact" ]] || continue
    name=$(basename "$artifact")
    case "$name" in
      *-setup.nsi)
        # The NSIS script is a tested local byproduct (test_pack_windows.sh
        # asserts its content); it stays out of the published assets.
        continue
        ;;
    esac
    local expected=0
    for pattern in "${copied[@]}"; do
      [[ "$pattern" == "$name" ]] && expected=1
    done
    if [[ "$expected" -ne 1 ]]; then
      echo "site release: unexpected artifact would leak into the release: $name" >&2
      exit 1
    fi
  done
  shopt -u nullglob
}

# Display names and stable ids are pinned explicitly: URL derivation names
# both Google properties "Google", and passing --name alone would change the
# generated id and break upgrade continuity for installed apps.
for site in \
  "youtube|https://www.youtube.com/|YouTube|com.nimino.youtube-com" \
  "gmail|https://mail.google.com/mail/u/0/|Gmail|com.nimino.mail-google-com" \
  "google-analytics|https://analytics.google.com/analytics/web/|Google Analytics|com.nimino.analytics-google-com"; do
  app=${site%%|*}
  rest=${site#*|}
  url=${rest%%|*}
  rest=${rest#*|}
  display_name=${rest%%|*}
  app_id=${rest##*|}
  linux_bundle="$root/$app-linux"
  linux_packages="$root/$app-linux-packages"
  "$cli" pack "$url" --name "$display_name" --id "$app_id" \
    --out "$linux_bundle" --host "$linux_host" --app-version "$app_version"
  mkdir -p "$linux_packages"
  "$cli" package-linux "$linux_bundle" --format deb --out "$linux_packages" \
    --arch amd64 --maintainer "Nimino Site Release <noreply@nimino.invalid>"
  "$cli" package-linux "$linux_bundle" --format rpm --out "$linux_packages" \
    --arch amd64 --license MIT
  copy_assets "$app" "$linux_packages" '*.deb' '*.rpm'
  cp "$linux_bundle/nimino-manifest.json" "$assets/${app}-linux-nimino-manifest.json"
  cp "$linux_bundle/nimino-sbom.cdx.json" "$assets/${app}-linux-nimino-sbom.cdx.json"

  windows_bundle="$root/$app-windows"
  windows_packages="$root/$app-windows-packages"
  "$cli" pack "$url" --name "$display_name" --id "$app_id" \
    --out "$windows_bundle" --host "$windows_host" --app-version "$app_version"
  cp "$webview2_loader" "$windows_bundle/WebView2Loader.dll"
  cp "$pcre_dll" "$windows_bundle/pcre64.dll"
  mkdir -p "$windows_packages"
  "$cli" package-windows "$windows_bundle" --format nsis --out "$windows_packages"
  "$cli" package-windows "$windows_bundle" --format msi --out "$windows_packages"
  copy_assets "$app" "$windows_packages" '*-setup.exe' '*.msi'
  cp "$windows_bundle/nimino-manifest.json" "$assets/${app}-windows-nimino-manifest.json"
  cp "$windows_bundle/nimino-sbom.cdx.json" "$assets/${app}-windows-nimino-sbom.cdx.json"
done

cp "$webview2_setup" "$assets/Nimino-WebView2-Setup.ps1"
(cd "$assets" && sha256sum -- * > SHA256SUMS)
printf '%s\n' \
  'Nimino reviewed site release assets' \
  '' \
  'Apps: youtube, gmail, google-analytics' \
  'Linux: Debian (.deb), RPM (.rpm)' \
  'Windows: NSIS (.exe), MSI (.msi)' \
  '' \
  'Windows installer behavior:' \
  '  NSIS/MSI checks the WebView2 Evergreen Runtime and downloads the Microsoft Bootstrapper when missing.' \
  '  Internet access is required for the first-time Runtime download.' \
  '  WebView2Loader.dll and pcre64.dll are bundled with each Windows application package.' \
  'Manual SHA-256-verified setup is documented in README for repair and development.' \
  'Verify SHA256SUMS before installation.' \
  > "$output/RELEASE-NOTES.txt"
