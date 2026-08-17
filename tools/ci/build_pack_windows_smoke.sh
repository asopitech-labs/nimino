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

# Assemble the layout the released nimino-core archive ships: the host and the
# libraries it loads at process start in one directory.  pack stages what the
# host names from there, so the smoke exercises the same path a caller who
# unpacks that archive takes, instead of copying the libraries in afterwards.
runtime=$(mktemp -d)
trap 'rm -rf "$runtime"' EXIT HUP INT TERM
cp "$windows_host" "$runtime/nimino-host.exe"
cp "$webview2_loader" "$runtime/WebView2Loader.dll"
cp "$pcre_dll" "$runtime/pcre64.dll"

"$cli" pack "$url" --out "$output" --host "$runtime/nimino-host.exe"
for library in WebView2Loader.dll pcre64.dll; do
  test -s "$output/$library" || {
    echo "pack windows smoke: bundle omits $library" >&2
    exit 1
  }
done
echo "pack windows smoke bundle: $output ($url)"
