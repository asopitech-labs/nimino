#!/bin/sh
set -eu

cli=${1:?usage: test_pack_sites.sh <nimino-cli>}
root=$(mktemp -d /tmp/nimino-site-test.XXXXXX)
trap 'rm -rf "$root"' EXIT

for site in \
  "youtube|https://www.youtube.com/" \
  "gmail|https://mail.google.com/mail/u/0/" \
  "google-analytics|https://analytics.google.com/analytics/web/"; do
  slug=${site%%|*}
  url=${site#*|}
  out="$root/$slug"
  "$cli" pack "$url" --out "$out" >/dev/null
  test -s "$out/nimino-manifest.json"
  test -s "$out/run-nimino.sh"
  test -s "$out/run-nimino.cmd"
  test -s "$out/nimino-sbom.cdx.json"
  grep -q '"name":' "$out/nimino-manifest.json"
  grep -q '"id":' "$out/nimino-manifest.json"
  grep -q '"allow": \[\]' "$out/nimino-manifest.json"
  grep -q '"external": \[\]' "$out/nimino-manifest.json"
done

echo "nimino-pack URL site bundle tests passed"
