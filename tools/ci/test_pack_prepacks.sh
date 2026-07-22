#!/bin/sh
set -eu

cli=${1:?usage: test_pack_prepacks.sh <nimino-cli>}
root=$(mktemp -d /tmp/nimino-prepack-test.XXXXXX)
trap 'rm -rf "$root"' EXIT

for slug in youtube gmail google-analytics; do
  out="$root/$slug"
  "$cli" pack prepack "$slug" --out "$out" >/dev/null
  test -s "$out/nimino-manifest.json"
  test -s "$out/run-nimino.sh"
  test -s "$out/run-nimino.cmd"
  test -s "$out/nimino-sbom.cdx.json"
  grep -q '"name":' "$out/nimino-manifest.json"
  grep -q '"navigation":' "$out/nimino-manifest.json"
  snapshot="$root/$slug-snapshot"
  "$cli" pack "catalog/prepacks/$slug.toml" --out "$snapshot" >/dev/null
  cmp "$out/nimino-manifest.json" "$snapshot/nimino-manifest.json"
done

if "$cli" pack prepack unknown --out "$root/unknown" >/dev/null 2>&1; then
  echo "unknown prepack unexpectedly succeeded" >&2
  exit 1
fi

echo "nimino-pack prepack CLI tests passed"
