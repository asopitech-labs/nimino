#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
make_bin=$(command -v make)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/nimino-container-runtime.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

make_runtime_stub() {
  local bin_dir=$1
  local name=$2

  mkdir -p "$bin_dir"
  printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s %s\n" "${0##*/}" "$*" >> "$RUNTIME_LOG"' \
    'case "$*" in' \
    '  "compose version"|"version"|"info") exit 0 ;;' \
    '  *) exit 64 ;;' \
    'esac' \
    > "$bin_dir/$name"
  chmod +x "$bin_dir/$name"
}

make_compose_only_runtime_stub() {
  local bin_dir=$1
  local name=$2

  mkdir -p "$bin_dir"
  printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s %s\n" "${0##*/}" "$*" >> "$RUNTIME_LOG"' \
    'case "$*" in' \
    '  "compose version"|"version") exit 0 ;;' \
    '  *) exit 64 ;;' \
    'esac' \
    > "$bin_dir/$name"
  chmod +x "$bin_dir/$name"
}

make_failing_runtime_stub() {
  local bin_dir=$1
  local name=$2

  mkdir -p "$bin_dir"
  printf '%s\n' \
    '#!/bin/sh' \
    'printf "%s %s\n" "${0##*/}" "$*" >> "$RUNTIME_LOG"' \
    'exit 64' \
    > "$bin_dir/$name"
  chmod +x "$bin_dir/$name"
}

run_check() {
  local bin_dir=$1
  local log_file=$2
  shift 2

  PATH="$bin_dir" RUNTIME_LOG="$log_file" \
    "$make_bin" --no-print-directory -s -C "$root" "$@" container-runtime-check
}

both_bin="$test_root/both"
both_log="$test_root/both.log"
make_runtime_stub "$both_bin" docker
make_runtime_stub "$both_bin" podman
both_output=$(run_check "$both_bin" "$both_log")
grep -Fq 'Using docker compose' <<<"$both_output"
test "$(grep -Fxc 'docker compose version' "$both_log")" -eq 2
grep -Fxq 'docker info' "$both_log"

podman_bin="$test_root/podman"
podman_log="$test_root/podman.log"
make_runtime_stub "$podman_bin" podman
podman_output=$(run_check "$podman_bin" "$podman_log")
grep -Fq 'Using podman compose' <<<"$podman_output"
test "$(grep -Fxc 'podman compose version' "$podman_log")" -eq 2

fallback_bin="$test_root/fallback"
fallback_log="$test_root/fallback.log"
make_compose_only_runtime_stub "$fallback_bin" docker
make_runtime_stub "$fallback_bin" podman
fallback_output=$(run_check "$fallback_bin" "$fallback_log")
grep -Fq 'Using podman compose' <<<"$fallback_output"
grep -Fxq 'docker info' "$fallback_log"
test "$(grep -Fxc 'podman compose version' "$fallback_log")" -eq 2

override_bin="$test_root/override"
override_log="$test_root/override.log"
make_runtime_stub "$override_bin" custom-compose
override_output=$(run_check \
  "$override_bin" "$override_log" COMPOSE=custom-compose)
grep -Fq 'Using custom-compose' <<<"$override_output"
grep -Fxq 'custom-compose version' "$override_log"

missing_bin="$test_root/missing"
missing_output="$test_root/missing.out"
mkdir -p "$missing_bin"
if run_check "$missing_bin" "$test_root/missing.log" >"$missing_output" 2>&1; then
  echo "container runtime check unexpectedly succeeded without Docker or Podman" >&2
  exit 1
fi
grep -Fq 'ERROR: neither Docker nor Podman was found' "$missing_output"

echo "container runtime selection contract passed"
