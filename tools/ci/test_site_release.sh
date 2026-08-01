#!/bin/sh
set -eu

release_dir=${1:?usage: test_site_release.sh <site-release-dir> [expected-app-version]}
expected_version=${2:-}
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

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Icon coverage is checked on the published artifact, not just the manifest.
# Seven releases shipped with an empty icon field and passed this suite,
# because nothing here looked at icons at all: the manifest key was blank,
# no icon file was packaged, and the desktop entry had no Icon= line.
require_deb_icon() {
  app=$1
  deb=$2
  extracted="$work/$app-deb"
  rm -rf "$extracted"
  mkdir -p "$extracted"
  (cd "$extracted" && ar x "$deb" && tar -xf data.tar.* )

  desktop=$(find "$extracted/usr/share/applications" -name '*.desktop' | head -n 1)
  if [ -z "$desktop" ]; then
    echo "site release: $app package has no desktop entry" >&2
    exit 1
  fi
  icon_line=$(grep '^Icon=' "$desktop" || true)
  if [ -z "$icon_line" ]; then
    echo "site release: $app desktop entry has no Icon= line; the launcher would" >&2
    echo "site release: fall back to a generic icon" >&2
    exit 1
  fi
  icon_path=${icon_line#Icon=}
  if [ ! -s "$extracted$icon_path" ]; then
    echo "site release: $app desktop entry points at $icon_path, which the package does not install" >&2
    exit 1
  fi
}

for app in youtube gmail google-analytics; do
  case "$app" in
    youtube) expected_name="YouTube" ;;
    gmail) expected_name="Gmail" ;;
    google-analytics) expected_name="Google Analytics" ;;
  esac
  for platform in linux windows; do
    test -s "$assets/${app}-${platform}-nimino-manifest.json"
    test -s "$assets/${app}-${platform}-nimino-sbom.cdx.json"
    # Reviewed display names, not the URL-derived defaults (both Google
    # properties would otherwise be called "Google").
    grep -Fq "\"name\": \"$expected_name\"" "$assets/${app}-${platform}-nimino-manifest.json"
    # All three reviewed sites serve an icon, so an empty icon field means
    # discovery failed rather than that the site has none.
    manifest_icon=$(sed -n 's/.*"icon": *"\([^"]*\)".*/\1/p' \
      "$assets/${app}-${platform}-nimino-manifest.json")
    if [ -z "$manifest_icon" ]; then
      echo "site release: ${app} (${platform}) manifest has an empty icon" >&2
      exit 1
    fi
  done
  require_artifact "$assets/${app}-*.deb"
  require_artifact "$assets/${app}-*.rpm"
  require_artifact "$assets/${app}-*-setup.exe"
  require_artifact "$assets/${app}-*.msi"
  for deb in "$assets/${app}-"*.deb; do
    require_deb_icon "$app" "$deb"
  done
  # The Windows installers write the "Installed apps" DisplayIcon from the
  # bundle's icon; without one the entry shows no icon in Windows settings
  # and the multi-resolution ICO conversion never runs. NSIS compresses its
  # payload, so assert on the MSI, which stores file names uncompressed.
  windows_icon=$(sed -n 's/.*"icon": *"\([^"]*\)".*/\1/p' \
    "$assets/${app}-windows-nimino-manifest.json")
  for installer in "$assets/${app}-"*.msi; do
    if ! grep -aq "$windows_icon" "$installer"; then
      echo "site release: $app MSI does not install the icon $windows_icon" >&2
      exit 1
    fi
  done
  if [ -n "$expected_version" ]; then
    # Site applications must carry the Nimino release version, not the
    # generator default.
    grep -Fq "\"version\": \"$expected_version\"" "$assets/${app}-windows-nimino-manifest.json"
    grep -Fq "\"version\": \"$expected_version\"" "$assets/${app}-linux-nimino-manifest.json"
    require_artifact "$assets/${app}-*-${expected_version}-setup.exe"
    require_artifact "$assets/${app}-*-${expected_version}.msi"
  fi
done

# Every asset must be on the release allowlist; anything else is a build
# intermediate or packaging leak and must fail the release.
for artifact in "$assets"/*; do
  name=$(basename "$artifact")
  case "$name" in
    SHA256SUMS|Nimino-WebView2-Setup.ps1) ;;
    # The standalone component archives are published from the same release;
    # test_component_release.sh verifies their contents.
    nimino-core-*.tar.gz|nimino-core-*.zip|nimino-pack-*.tar.gz) ;;
    youtube-*|gmail-*|google-analytics-*)
      case "$name" in
        *-nimino-manifest.json|*-nimino-sbom.cdx.json|*.deb|*.rpm|*-setup.exe|*.msi) ;;
        *)
          echo "site release: unexpected asset would be published: $name" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      echo "site release: unexpected asset would be published: $name" >&2
      exit 1
      ;;
  esac
done

(cd "$assets" && sha256sum -c SHA256SUMS)
grep -Fq 'Apps: youtube, gmail, google-analytics' "$release_dir/RELEASE-NOTES.txt"
echo "nimino ready-made site installer rebuild verified"
