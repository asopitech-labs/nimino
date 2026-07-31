#!/usr/bin/env bash
set -euo pipefail

cli=${1:?usage: build_rpm_smoke.sh <nimino-cli> <linux-host> <output-dir>}
linux_host=${2:?usage: build_rpm_smoke.sh <nimino-cli> <linux-host> <output-dir>}
output=${3:?usage: build_rpm_smoke.sh <nimino-cli> <linux-host> <output-dir>}
url=${NIMINO_PACK_SMOKE_URL:-https://asopi.tech}

test -x "$cli" || { echo "rpm smoke: CLI is not executable: $cli" >&2; exit 1; }
test -x "$linux_host" || { echo "rpm smoke: Linux host is not executable: $linux_host" >&2; exit 1; }

rm -rf "$output"
"$cli" pack "$url" --out "$output/bundle" --host "$linux_host"
mkdir -p "$output/packages"
"$cli" package-linux "$output/bundle" --format rpm --out "$output/packages" \
  --arch amd64 --license MIT
count=$(find "$output/packages" -name '*.rpm' | wc -l)
test "$count" -eq 1 || { echo "rpm smoke: expected exactly one RPM, found $count" >&2; exit 1; }
echo "rpm smoke bundle: $output ($url)"
