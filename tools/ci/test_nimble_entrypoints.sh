#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
workflows=(
  "$root/.github/workflows/nimino-pack-online.yml"
  "$root/.github/workflows/nimino-site-release.yml"
)

for workflow in "${workflows[@]}"; do
  if grep -nE '(^|[[:space:];])nimble[[:space:]]' "$workflow"; then
    echo "Workflow bypasses the Nimble false-success guard: $workflow" >&2
    exit 1
  fi
  grep -Fq 'tools/ci/run_nimble_task.sh' "$workflow"
done

echo "Nimble workflow entrypoint contract passed"
