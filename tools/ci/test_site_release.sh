#!/bin/sh
set -eu

release_dir=${1:?usage: test_site_release.sh <site-release-dir>}
assets="$release_dir/assets"

test -d "$assets" || {
  echo "site release: assets directory is missing: $assets" >&2
  exit 1
}
test -s "$release_dir/RELEASE-NOTES.txt"
test -s "$assets/SHA256SUMS"
test -s "$assets/Nimino-WebView2-Setup.ps1"

require_artifact() {
  pattern=$1
  found=0
  for artifact in $pattern; do
    if [ -f "$artifact" ] && [ -s "$artifact" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -ne 1 ]; then
    echo "site release: expected artifact was not generated: $pattern" >&2
    exit 1
  fi
}

for app in youtube gmail google-analytics; do
  for platform in linux windows; do
    test -s "$assets/${app}-${platform}-nimino-manifest.json"
    test -s "$assets/${app}-${platform}-nimino-sbom.cdx.json"
  done
  require_artifact "$assets/${app}-*.deb"
  require_artifact "$assets/${app}-*.rpm"
  require_artifact "$assets/${app}-*-setup.exe"
  require_artifact "$assets/${app}-*.msi"
done

(cd "$assets" && sha256sum -c SHA256SUMS)
grep -Fq 'Apps: youtube, gmail, google-analytics' "$release_dir/RELEASE-NOTES.txt"
echo "nimino ready-made site installer rebuild verified"
