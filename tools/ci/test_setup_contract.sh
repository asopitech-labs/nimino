#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
dockerfile="$root/tools/docker/Dockerfile"
compose="$root/compose.yaml"
makefile="$root/Makefile"
setup="$root/tools/ci/setup-windows-webview2.ps1"
cleanup="$root/tools/ci/kill-nimino-windows.ps1"
makefile="$root/Makefile"

grep -Fq 'libgtk-4-dev' "$dockerfile"
grep -Fq 'libwebkitgtk-6.0-dev' "$dockerfile"
grep -Fq 'microsoft.web.webview2/${WEBVIEW2_SDK_VERSION}' "$dockerfile"
grep -Fq 'WEBVIEW2_SDK_SHA256' "$dockerfile"
grep -Fq 'docker.io/nimlang/nim:latest@sha256:' "$dockerfile"
grep -Fq 'NIM_IMAGE: docker.io/nimlang/nim:latest@sha256:' "$compose"
grep -Fq 'setup: verify-env' "$makefile"
grep -Fq 'Windows Interop (powershell.exe) is required' "$makefile"
grep -Fq 'WSL_INTEROP' "$makefile"
grep -Fq 'setup-windows-webview2' "$makefile"
grep -Fq 'Start-Process -FilePath $installer -ArgumentList "/silent", "/install" -Verb RunAs' "$setup"
grep -Fq 'WebView2 Runtime already installed' "$setup"
grep -Fq 'WebView2 Runtime installation could not be verified' "$setup"
grep -Fq 'Where-Object { $_.Name -match' "$setup"
if grep -Fq 'Verb RunAs' "$cleanup"; then
  echo "Windows test cleanup must not block on a UAC elevation prompt" >&2
  exit 1
fi
grep -Fq '& taskkill.exe /PID $process.ProcessId /T /F' "$cleanup"
grep -Fq 'clean: container-runtime-check kill-nimino-windows' "$makefile"
if grep -Fq 'taskkill.exe /IM nimino-wsl-host.exe' "$makefile"; then
  echo "Make cleanup must use the scoped Windows cleanup target" >&2
  exit 1
fi

echo "Nimino setup contract passed"
