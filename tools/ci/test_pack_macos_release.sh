#!/bin/sh
set -eu

cli=${1:?usage: test_pack_macos_release.sh <nimino-cli> <nimino-host>}
host=${2:?usage: test_pack_macos_release.sh <nimino-cli> <nimino-host>}
host_name=$(basename "$host")
root=$(mktemp -d /tmp/nimino-macos-release.XXXXXX)
trap 'rm -rf "$root"' EXIT HUP INT TERM

test -x "$cli"
test -x "$host"
icon=/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns
test -f "$icon"
mkdir -p "$root/out"

## Pake's release suite packages two fixed web applications and checks that
## each build emits a distributable artifact.  Keep the same release-path
## boundary on macOS without treating Windows/Linux artifacts as local tests.
build_release_app() {
  name=$1
  id=$2
  url=$3
  bundle="$root/$id"

  "$cli" pack "$url" --name "$name" --id "$id" --icon "$icon" \
    --out "$bundle" --host "$host" >/dev/null
  test -s "$bundle/nimino-manifest.json"
  test -x "$bundle/$host_name"

  dmg=$("$cli" package-macos "$bundle" --out "$root/out")
  test -s "$dmg"
  case "$dmg" in
    "$root/out"/*.dmg) ;;
    *) echo "release package did not produce a DMG: $dmg" >&2; exit 1 ;;
  esac
  hdiutil imageinfo "$dmg" >/dev/null
}

build_release_app 'Example Web' com.nimino.release.example-web https://example.com
build_release_app 'IANA Example' com.nimino.release.iana-example https://example.org

count=$(find "$root/out" -maxdepth 1 -type f -name '*.dmg' | wc -l | tr -d ' ')
test "$count" -eq 2
echo 'macOS release package smoke passed'
