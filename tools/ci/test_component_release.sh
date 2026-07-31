#!/usr/bin/env bash
set -euo pipefail

# Verify the two independently distributable component archives. Each one is
# unpacked and inspected: a release that ships an archive whose executable is
# missing, empty, or built for the wrong platform must fail here rather than
# on a user's machine.

release_dir=${1:?usage: test_component_release.sh <site-release-dir> <version>}
version=${2:?usage: test_component_release.sh <site-release-dir> <version>}
assets="$release_dir/assets"

test -d "$assets" || {
  echo "component release: assets directory is missing: $assets" >&2
  exit 1
}

core_linux="$assets/nimino-core-$version-linux-x86_64.tar.gz"
core_windows="$assets/nimino-core-$version-windows-x64.zip"
pack_linux="$assets/nimino-pack-$version-linux-x86_64.tar.gz"

for archive in "$core_linux" "$core_windows" "$pack_linux"; do
  test -s "$archive" || {
    echo "component release: expected archive was not generated: $archive" >&2
    exit 1
  }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Each archive must unpack into a single top-level directory named after it,
# so extracting in a working directory never scatters loose files.
require_single_root() {
  local archive=$1
  local extracted=$2
  local expected=$3
  local entries
  entries=$(find "$extracted" -mindepth 1 -maxdepth 1 | wc -l)
  if [ "$entries" -ne 1 ] || [ ! -d "$extracted/$expected" ]; then
    echo "component release: $archive must unpack into the single directory $expected" >&2
    exit 1
  fi
}

## nimino-core, Linux x86_64 -------------------------------------------------
mkdir -p "$work/core-linux"
tar -xzf "$core_linux" -C "$work/core-linux"
require_single_root "$(basename "$core_linux")" "$work/core-linux" \
  "nimino-core-$version-linux-x86_64"
work_core_linux="$work/core-linux/nimino-core-$version-linux-x86_64"
test -x "$work_core_linux/nimino-host"
test -s "$work_core_linux/LICENSE"
test -s "$work_core_linux/README.txt"
file "$work_core_linux/nimino-host" | grep -q 'ELF 64-bit.*x86-64' || {
  echo "component release: nimino-host is not a Linux x86-64 executable" >&2
  exit 1
}
# The host statically links PCRE so it starts on EL10, where the legacy
# libpcre.so that std/re loads at process start is gone.
if ldd "$work_core_linux/nimino-host" | grep -q libpcre; then
  echo "component release: nimino-host must not link libpcre dynamically" >&2
  exit 1
fi
# The host is a GUI binary: launching it here would need a display server, so
# the site release smoke test owns its runtime behavior and this check stays
# at the artifact level.

## nimino-core, Windows x64 --------------------------------------------------
mkdir -p "$work/core-windows"
unzip -q "$core_windows" -d "$work/core-windows"
require_single_root "$(basename "$core_windows")" "$work/core-windows" \
  "nimino-core-$version-windows-x64"
work_core_windows="$work/core-windows/nimino-core-$version-windows-x64"
test -s "$work_core_windows/nimino-host.exe"
test -s "$work_core_windows/WebView2Loader.dll"
test -s "$work_core_windows/pcre64.dll"
test -s "$work_core_windows/LICENSE"
test -s "$work_core_windows/README.txt"
file "$work_core_windows/nimino-host.exe" | grep -q 'PE32+ executable.*x86-64' || {
  echo "component release: nimino-host.exe is not a Windows x64 executable" >&2
  exit 1
}
# A packaged GUI application must not allocate a console window at launch.
x86_64-w64-mingw32-objdump -p "$work_core_windows/nimino-host.exe" |
  grep -q 'Subsystem.*Windows GUI' || {
  echo "component release: nimino-host.exe is not a Windows GUI subsystem binary" >&2
  exit 1
}

## nimino-pack, Linux x86_64 -------------------------------------------------
mkdir -p "$work/pack-linux"
tar -xzf "$pack_linux" -C "$work/pack-linux"
require_single_root "$(basename "$pack_linux")" "$work/pack-linux" \
  "nimino-pack-$version-linux-x86_64"
work_pack_linux="$work/pack-linux/nimino-pack-$version-linux-x86_64"
test -x "$work_pack_linux/nimino"
test -s "$work_pack_linux/LICENSE"
test -s "$work_pack_linux/README.txt"
test -s "$work_pack_linux/nimino-pack.schema.json"
file "$work_pack_linux/nimino" | grep -q 'ELF 64-bit.*x86-64' || {
  echo "component release: nimino CLI is not a Linux x86-64 executable" >&2
  exit 1
}
# The packaging toolkit must not drag in a GUI stack; that independence is
# the reason it is released separately from nimino-core.
if ldd "$work_pack_linux/nimino" | grep -Eq 'libgtk|libwebkit'; then
  echo "component release: nimino CLI must not link a GUI toolkit" >&2
  exit 1
fi
# Automatic icon discovery fetches over HTTPS. A CLI built without TLS
# support reports "unable to download remote icon" for every site and
# silently produces icon-less bundles, so require the TLS runtime. -d:ssl
# loads OpenSSL through dlopen rather than linking it, so the candidate
# library names are embedded in the binary instead of listed by ldd.
if ! grep -aq 'libssl' "$work_pack_linux/nimino"; then
  echo "component release: nimino CLI is missing TLS support (build with -d:ssl)" >&2
  exit 1
fi
if "$work_pack_linux/nimino" >/dev/null 2>&1; then
  echo "component release: nimino CLI did not report usage without arguments" >&2
  exit 1
fi
if ! "$work_pack_linux/nimino" 2>&1 | grep -q 'usage: nimino pack'; then
  echo "component release: nimino CLI usage output is missing" >&2
  exit 1
fi

## Checksums ----------------------------------------------------------------
# The component archives must be covered by the published checksum file.
for archive in "$core_linux" "$core_windows" "$pack_linux"; do
  grep -Fq "$(basename "$archive")" "$assets/SHA256SUMS" || {
    echo "component release: archive is missing from SHA256SUMS: $(basename "$archive")" >&2
    exit 1
  }
done
(cd "$assets" && sha256sum -c SHA256SUMS >/dev/null)

grep -Fq 'Components (released independently of the site installers):' \
  "$release_dir/RELEASE-NOTES.txt"

echo "nimino component release verified: nimino-core and nimino-pack $version"
