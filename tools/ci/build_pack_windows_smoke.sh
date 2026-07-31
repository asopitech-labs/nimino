#!/usr/bin/env bash
set -euo pipefail

cli=${1:?usage: build_pack_windows_smoke.sh <nimino-cli> <windows-host> <output-dir>}
windows_host=${2:?usage: build_pack_windows_smoke.sh <nimino-cli> <windows-host> <output-dir>}
output=${3:?usage: build_pack_windows_smoke.sh <nimino-cli> <windows-host> <output-dir>}
url=${NIMINO_PACK_SMOKE_URL:-https://asopi.tech}

test -x "$cli" || { echo "pack windows smoke: CLI is not executable: $cli" >&2; exit 1; }
test -s "$windows_host" || { echo "pack windows smoke: Windows host is missing: $windows_host" >&2; exit 1; }
webview2_loader=${NIMINO_WEBVIEW2_LOADER:-/opt/nimino/webview2/x64/WebView2Loader.dll}
test -s "$webview2_loader" || { echo "pack windows smoke: WebView2Loader.dll is missing: $webview2_loader" >&2; exit 1; }
pcre_dll=${NIMINO_WINDOWS_PCRE_DLL:-/opt/nimino/windows-dlls/pcre64.dll}
test -s "$pcre_dll" || { echo "pack windows smoke: pcre64.dll is missing: $pcre_dll" >&2; exit 1; }

rm -rf "$output"
"$cli" pack "$url" --out "$output" --host "$windows_host"
cp "$webview2_loader" "$output/WebView2Loader.dll"
cp "$pcre_dll" "$output/pcre64.dll"
echo "pack windows smoke bundle: $output ($url)"
