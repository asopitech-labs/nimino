#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
make_bin=$(command -v make)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/nimino-make-clean.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

cp "$root/Makefile" "$test_root/Makefile"
mkdir -p "$test_root/.tmp" "$test_root/bin"
printf 'generated\n' > "$test_root/.tmp/sentinel"

for runtime in docker podman; do
  printf '%s\n' '#!/bin/sh' 'exit 64' > "$test_root/bin/$runtime"
  chmod +x "$test_root/bin/$runtime"
done

PATH="$test_root/bin:/usr/bin:/bin" \
  "$make_bin" --no-print-directory -s -C "$test_root" clean \
  >"$test_root/clean.out" 2>&1

test ! -e "$test_root/.tmp"
grep -Fq 'Skipping Windows process cleanup' "$test_root/clean.out"
grep -Fq 'Skipping Compose cleanup' "$test_root/clean.out"

echo "Make clean lifecycle contract passed"
