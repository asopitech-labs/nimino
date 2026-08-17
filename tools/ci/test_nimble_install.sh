#!/usr/bin/env bash
set -euo pipefail

# The published install path is `nimble install <repository URL>`, with no
# `?subdir=` fragment and no flags.  nimble resolves the base URL against the
# package registry before it reads any subdirectory, so a repository that only
# carries per-package .nimble files under packages/ fails with "Unable to
# identify url" before it fetches anything.  Installing from a checkout
# exercises the same manifest the URL install reads, without depending on the
# tag history or on network access to the registry.

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
nimble_dir=$(mktemp -d "${TMPDIR:-/tmp}/nimino-nimble-install.XXXXXX")
trap 'rm -rf "$nimble_dir"' EXIT HUP INT TERM

test -s "$root/nimino.nimble" \
  || { echo "nimble install: repository root has no nimino.nimble" >&2; exit 1; }

# The root manifest must publish the CLI itself.  Without `bin`, the URL
# install resolves and then installs nothing a caller can run.
grep -Eq '^bin[[:space:]]*=' "$root/nimino.nimble" \
  || { echo "nimble install: root manifest declares no bin entry" >&2; exit 1; }

(cd "$root" && nimble install -y --nimbleDir:"$nimble_dir" >/dev/null)

binary="$nimble_dir/bin/nimino"
test -x "$binary" \
  || { echo "nimble install: no nimino executable at $binary" >&2; exit 1; }

# A CLI that cannot report its own usage is not installed, only copied.
# Usage goes to stderr and the CLI exits non-zero for an unknown argument, so
# capture both streams without letting the exit status abort the run.
usage=$("$binary" --help 2>&1 || true)
printf '%s' "$usage" | grep -Fq 'nimino pack' \
  || { echo "nimble install: installed CLI does not report pack usage" >&2; exit 1; }

# The JSON schema ships beside the binary; Pake-style configs are validated
# against it, so an install that drops installDirs breaks --config silently.
schema=$(find "$nimble_dir/pkgs2" -name 'nimino-pack.schema.json' -print -quit)
test -n "$schema" \
  || { echo "nimble install: installed package omits nimino-pack.schema.json" >&2; exit 1; }

echo "Nimble install contract passed"
