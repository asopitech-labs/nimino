#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
catalog="$root/tools/ci/wsl-public-sites.txt"
makefile="$root/Makefile"
smoke="$root/tools/ci/wsl-host-smoke.ps1"

if [[ ! -f "$catalog" ]]; then
  echo "Public WSL site smoke catalog is missing" >&2
  exit 1
fi

mapfile -t actual < "$catalog"
expected=(
  "https://www.youtube.com/"
  "https://github.com/nim-lang/Nim"
  "https://www.openstreetmap.org/"
)
if [[ "${actual[*]}" != "${expected[*]}" ]]; then
  echo "Public WSL site smoke catalog does not match the reviewed targets" >&2
  exit 1
fi

if grep -Eiq 'mail\.google\.com|analytics\.google\.com|/login|/signin' "$catalog"; then
  echo "Login-oriented URL found in public WSL site smoke catalog" >&2
  exit 1
fi

grep -Fq 'tools/ci/wsl-public-sites.txt' "$makefile"
grep -Fq -- '-VerifyPublicPage' "$makefile"
grep -Fq 'read -r url <&3' "$makefile"
grep -Fq 'done 3< tools/ci/wsl-public-sites.txt' "$makefile"
grep -Fq '[switch]$VerifyPublicPage' "$smoke"
grep -Fq 'public page content validation' "$smoke"
grep -Fq 'bodyTextLength' "$smoke"

echo "WSL public site target contract passed"
