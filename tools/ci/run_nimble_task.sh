#!/usr/bin/env bash
set -euo pipefail

if (($# == 0)); then
  echo "usage: run_nimble_task.sh <task> [arguments...]" >&2
  exit 64
fi

nimble_bin=${NIMBLE_BIN:-nimble}
log_file=$(mktemp "${TMPDIR:-/tmp}/nimino-nimble-task.XXXXXX")
trap 'rm -f "$log_file"' EXIT

set +e
"$nimble_bin" "$@" 2>&1 | tee "$log_file"
nimble_status=${PIPESTATUS[0]}
set -e

if ((nimble_status != 0)); then
  exit "$nimble_status"
fi

if grep -Fq 'Exception raised during nimble script execution' "$log_file"; then
  echo "ERROR: nimble reported task failure with exit status 0" >&2
  exit 1
fi
