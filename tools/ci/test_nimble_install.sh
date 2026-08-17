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

# The CLI builds release archive names from its own version. nimble builds
# `bin` entries without passing a -d: define, so a version read from a compile
# flag is empty in exactly the binary a reader installs -- and pack then asks
# for "nimino-core--windows-x64.zip" and fails to download it.
archive=$("$binary" pack https://example.com --out "$nimble_dir/probe" \
  --targets nsis 2>&1 | grep -oE 'nimino-core-[^ ]*\.zip' | head -1 || true)
case "$archive" in
  nimino-core--*)
    echo "nimble install: the installed CLI reports no version ($archive)" >&2
    exit 1
    ;;
  nimino-core-*) ;;
  *)
    echo "nimble install: could not read the archive name the CLI resolves" >&2
    exit 1
    ;;
esac

# The CLI fetches over HTTPS to discover icons and to download a released
# host for another platform. nimble builds `bin` entries without the -d: flags
# a task would pass, so ssl has to come from the package's own config; without
# it those fetches fail at run time with a bare "unable to download".
# grep -q exits at the first match, so strings dies of SIGPIPE and pipefail
# turns a successful search into a failed pipeline. Count instead of matching.
ssl_symbols=$(strings -a "$binary" | grep -ciE 'libssl|openssl' || true)
if [ "$ssl_symbols" = "0" ]; then
  echo "nimble install: the installed CLI was built without ssl" >&2
  exit 1
fi

echo "Nimble install contract passed"
