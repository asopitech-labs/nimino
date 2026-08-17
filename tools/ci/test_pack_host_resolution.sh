#!/usr/bin/env bash
set -euo pipefail

# `nimino pack <url> --out <dir>` has to work without --host. The CLI looks for
# a host it can bundle before it asks the caller for one, so a reader who
# installed the CLI and nothing else still gets a bundle.

nimino=${1:?usage: test_pack_host_resolution.sh <nimino-cli> <linux-host> <version>}
linux_host=${2:?usage: test_pack_host_resolution.sh <nimino-cli> <linux-host> <version>}
version=${3:?usage: test_pack_host_resolution.sh <nimino-cli> <linux-host> <version>}

root=$(mktemp -d "${TMPDIR:-/tmp}/nimino-host-resolution.XXXXXX")
trap 'rm -rf "$root"' EXIT HUP INT TERM

test -x "$linux_host"

# NIMINO_HOST wins over everything else, including a host on PATH.
NIMINO_HOST="$linux_host" "$nimino" pack https://example.com \
  --out "$root/env" > /dev/null 2>&1
test -s "$root/env/nimino-host" \
  || { echo "pack host resolution: NIMINO_HOST was not used" >&2; exit 1; }

# A NIMINO_HOST that points nowhere is a caller mistake, not a reason to fall
# through to some other host: the bundle would silently carry the wrong one.
if NIMINO_HOST="$root/missing-host" "$nimino" pack https://example.com \
    --out "$root/broken" > /dev/null 2>&1; then
  echo "pack host resolution: a broken NIMINO_HOST was accepted" >&2
  exit 1
fi

# An unpacked release archive in the working directory is what a reader
# following the download instructions ends up with.
unpacked="$root/work/nimino-core-$version-linux-x86_64"
mkdir -p "$unpacked"
cp "$linux_host" "$unpacked/nimino-host"
(cd "$root/work" && env -u NIMINO_HOST PATH=/usr/bin:/bin "$nimino" \
  pack https://example.com --out "$root/work/bundle" > /dev/null 2>&1)
test -s "$root/work/bundle/nimino-host" \
  || { echo "pack host resolution: an unpacked archive was not found" >&2; exit 1; }

echo "Nimino pack host resolution contract passed"
