#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/nimino-make-reference-env.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

compose_stub="$test_root/compose-stub"
compose_log="$test_root/compose.log"
cat >"$compose_stub" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$COMPOSE_LOG"
exit 0
EOF
chmod +x "$compose_stub"

COMPOSE_LOG="$compose_log" \
NIMINO_TEST_REFERENCE_LINUX=1 \
NIMINO_TEST_REFERENCE_WINDOWS=1 \
NIMINO_TEST_REFERENCE_WSL=1 \
  make --no-print-directory -s -C "$root" \
    COMPOSE="$compose_stub" test

run_line=$(grep -F 'run --rm' "$compose_log")
grep -Fq -- '-e NIMINO_TEST_REFERENCE_LINUX=1' <<<"$run_line"
grep -Fq -- '-e NIMINO_TEST_REFERENCE_WINDOWS=1' <<<"$run_line"
grep -Fq -- '-e NIMINO_TEST_REFERENCE_WSL=1' <<<"$run_line"

echo "Make reference-test environment contract passed"
