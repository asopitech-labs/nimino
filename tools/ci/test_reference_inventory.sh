#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root"

## These counts deliberately make additions to the checked-in Pake/Tauri
## references visible. Updating either reference must be accompanied by an
## explicit parity audit rather than silently reducing the comparison scope.
pake_unit_cases=$(rg -n '^\s*it\(' reference/pake/tests/unit | wc -l | tr -d ' ')
pake_integration_cases=$(rg -n '^\s*(it|test)\(' reference/pake/tests/integration \
  reference/pake/tests/index.js reference/pake/tests/config.js reference/pake/tests/release.js 2>/dev/null \
  | wc -l | tr -d ' ')
tauri_cases=$(rg -n '#\[test\]|#\[tokio::test\]' reference/tauri --glob '*.rs' | wc -l | tr -d ' ')
tauri_files=$(rg -l '#\[test\]|#\[tokio::test\]' reference/tauri --glob '*.rs' | wc -l | tr -d ' ')

test "$pake_unit_cases" -eq 281
test "$pake_integration_cases" -eq 18
test "$tauri_cases" -eq 202
test "$tauri_files" -eq 59

printf '%s\n' "reference inventory: Pake unit=$pake_unit_cases integration=$pake_integration_cases; Tauri cases=$tauri_cases files=$tauri_files"
