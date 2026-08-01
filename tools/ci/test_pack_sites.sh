#!/bin/sh
set -eu

cli=${1:?usage: test_pack_sites.sh <nimino-cli>}
root=$(mktemp -d /tmp/nimino-site-test.XXXXXX)
trap 'rm -rf "$root"' EXIT

# A bundle must carry the host it launches, so `pack --out` requires --host.
# What this test covers is URL-only manifest derivation, not the runtime, so
# a stub stands in for the real host exactly as the other pack tests do.
printf '#!/bin/sh\nexit 0\n' > "$root/nimino-host"
chmod +x "$root/nimino-host"

for site in \
  "youtube|https://www.youtube.com/" \
  "gmail|https://mail.google.com/mail/u/0/" \
  "google-analytics|https://analytics.google.com/analytics/web/"; do
  slug=${site%%|*}
  url=${site#*|}
  out="$root/$slug"
  "$cli" pack "$url" --out "$out" --host "$root/nimino-host" >/dev/null
  test -s "$out/nimino-manifest.json"
  test -s "$out/run-nimino.sh"
  test -s "$out/run-nimino.cmd"
  test -s "$out/nimino-sbom.cdx.json"
  grep -q '"name":' "$out/nimino-manifest.json"
  grep -q '"id":' "$out/nimino-manifest.json"
  grep -q '"allow": \[\]' "$out/nimino-manifest.json"
  grep -q '"external": \[\]' "$out/nimino-manifest.json"
  # These three sites all serve an icon, so an empty field means discovery
  # broke rather than that the site has none -- the failure mode that
  # shipped seven icon-less releases.
  icon=$(sed -n 's/.*"icon": *"\([^"]*\)".*/\1/p' "$out/nimino-manifest.json")
  if [ -z "$icon" ]; then
    echo "pack sites test: $slug resolved no icon" >&2
    exit 1
  fi
  if [ ! -s "$out/$icon" ]; then
    echo "pack sites test: $slug names icon '$icon' but the bundle lacks it" >&2
    exit 1
  fi
done

echo "nimino-pack URL site bundle tests passed"
