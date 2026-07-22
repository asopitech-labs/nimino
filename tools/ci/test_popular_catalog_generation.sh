#!/usr/bin/env bash
set -euo pipefail

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
assets="$root/assets"
mkdir -p "$assets"

for app in youtube gmail google-analytics; do
  for target in linux windows; do
    cat > "$assets/${app}-${target}-nimino-manifest.json" <<EOF
{"name":"${app}","id":"app.nimino.${app}","url":"https://${app}.example/","package":{"version":"1.2.3"}}
EOF
    printf '%s\n' '{"bomFormat":"CycloneDX"}' > "$assets/${app}-${target}-nimino-sbom.cdx.json"
  done
  printf 'deb %s\n' "$app" > "$assets/${app}-${app}.deb"
  printf 'exe %s\n' "$app" > "$assets/${app}-${app}-1.2.3-setup.exe"
done

minisign -G -W -p "$root/release.pub" -s "$root/release.key" >/dev/null 2>&1
python3 tools/ci/generate_popular_catalog.py \
  --assets-dir "$assets" \
  --output "$root/popular-packages.json" \
  --tag v1.2.3 \
  --commit "$(printf 'c%.0s' {1..40})" \
  --run-id 123456789 \
  --secret-key "$root/release.key" \
  --key-id nimino-release-test

python3 - "$root/popular-packages.json" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1], encoding="utf-8"))
assert catalog["schemaVersion"] == 1
assert len(catalog["entries"]) == 6
assert {entry["format"] for entry in catalog["entries"]} == {"deb", "nsis"}
assert all(entry["signature"]["value"] for entry in catalog["entries"])
print("popular catalog generation passed")
PY
