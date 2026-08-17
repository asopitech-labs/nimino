#!/usr/bin/env bash
set -euo pipefail

# The Windows host loads WebView2Loader.dll and pcre64.dll by name at process
# start, so they never appear in the PE import table and a bundle carrying only
# the executable installs cleanly and then dies before opening a window.  pack
# stages whatever sits beside the host and is named by it, which means callers
# hand over one --host path instead of repeating cp lines that drift apart.

nimino=${1:?usage: test_pack_host_runtime.sh <nimino-cli> <windows-host>}
windows_host=${2:?usage: test_pack_host_runtime.sh <nimino-cli> <windows-host>}
webview2_loader=${NIMINO_WEBVIEW2_LOADER:-/opt/nimino/webview2/x64/WebView2Loader.dll}
pcre_dll=${NIMINO_WINDOWS_PCRE_DLL:-/opt/nimino/windows-dlls/pcre64.dll}

root=$(mktemp -d "${TMPDIR:-/tmp}/nimino-host-runtime.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

test -s "$windows_host"
test -s "$webview2_loader"
test -s "$pcre_dll"

# Mirror the layout of the released nimino-core Windows archive: the host and
# the libraries it loads sit in one directory.
runtime="$root/runtime"
mkdir -p "$runtime"
cp "$windows_host" "$runtime/nimino-host.exe"
cp "$webview2_loader" "$runtime/WebView2Loader.dll"
cp "$pcre_dll" "$runtime/pcre64.dll"

# A DLL the host never names, and a non-library file, must both stay out of the
# bundle: staging everything beside the host would ship whatever happens to be
# in the directory.
printf 'not a real library' > "$runtime/unrelated.dll"
printf 'release notes' > "$runtime/README.txt"

bundle="$root/bundle"
"$nimino" pack https://example.com --name Example --out "$bundle" \
  --host "$runtime/nimino-host.exe" > /dev/null

for library in WebView2Loader.dll pcre64.dll; do
  test -s "$bundle/$library" \
    || { echo "pack host runtime: bundle omits $library" >&2; exit 1; }
done

for unwanted in unrelated.dll README.txt; do
  if [ -e "$bundle/$unwanted" ]; then
    echo "pack host runtime: bundle carries $unwanted" >&2
    exit 1
  fi
done

# A host that names nothing beside it must produce a bundle with no libraries
# at all, even when the directory holds some: staging is driven by what the
# executable references, not by what the directory happens to contain.
bare_runtime="$root/bare-runtime"
mkdir -p "$bare_runtime"
printf '#!/bin/sh\nexit 0\n' > "$bare_runtime/nimino-host"
chmod +x "$bare_runtime/nimino-host"
cp "$webview2_loader" "$bare_runtime/WebView2Loader.dll"
cp "$pcre_dll" "$bare_runtime/pcre64.dll"
bare_bundle="$root/bare-bundle"
"$nimino" pack https://example.com --name Example --out "$bare_bundle" \
  --host "$bare_runtime/nimino-host" > /dev/null
if compgen -G "$bare_bundle/*.dll" > /dev/null; then
  echo "pack host runtime: staged a library the host never references" >&2
  exit 1
fi

echo "Nimino pack host runtime contract passed"
