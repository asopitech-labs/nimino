#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
wrapper="$root/tools/ci/run_nimble_task.sh"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/nimino-nimble-wrapper.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

fake_bin="$test_root/bin"
mkdir -p "$fake_bin"
printf '%s\n' \
  '#!/bin/sh' \
  'case "$FAKE_NIMBLE_MODE" in' \
  '  success) echo "task completed"; exit 0 ;;' \
  '  failure) echo "task failed" >&2; exit 23 ;;' \
  '  false-success) echo "Error: Exception raised during nimble script execution" >&2; exit 0 ;;' \
  '  *) exit 64 ;;' \
  'esac' \
  > "$fake_bin/nimble"
chmod +x "$fake_bin/nimble"

success_output=$(PATH="$fake_bin:$PATH" FAKE_NIMBLE_MODE=success \
  bash "$wrapper" example)
grep -Fq 'task completed' <<<"$success_output"

set +e
PATH="$fake_bin:$PATH" FAKE_NIMBLE_MODE=failure \
  bash "$wrapper" example >"$test_root/failure.out" 2>&1
failure_status=$?
set -e
test "$failure_status" -eq 23
grep -Fq 'task failed' "$test_root/failure.out"

if PATH="$fake_bin:$PATH" FAKE_NIMBLE_MODE=false-success \
    bash "$wrapper" example >"$test_root/false-success.out" 2>&1; then
  echo "Nimble false success was not rejected" >&2
  exit 1
fi
grep -Fq 'reported task failure with exit status 0' \
  "$test_root/false-success.out"

echo "Nimble task wrapper contract passed"
