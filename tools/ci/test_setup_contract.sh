#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
dockerfile="$root/tools/docker/Dockerfile"
compose="$root/compose.yaml"
makefile="$root/Makefile"
setup="$root/tools/ci/setup-windows-webview2.ps1"

grep -Fq 'libgtk-4-dev' "$dockerfile"
grep -Fq 'libwebkitgtk-6.0-dev' "$dockerfile"
grep -Fq 'microsoft.web.webview2/${WEBVIEW2_SDK_VERSION}' "$dockerfile"
grep -Fq 'WEBVIEW2_SDK_SHA256' "$dockerfile"
grep -Fq 'nimlang/nim:latest@sha256:' "$dockerfile"
grep -Fq 'NIM_IMAGE: nimlang/nim:latest@sha256:' "$compose"
grep -Fq 'setup: verify-env' "$makefile"
grep -Fq 'setup-windows-webview2' "$makefile"
grep -Fq 'Start-Process -FilePath $installer -ArgumentList "/silent", "/install" -Verb RunAs' "$setup"
grep -Fq 'WebView2 Runtime already installed' "$setup"
grep -Fq 'WebView2 Runtime installation could not be verified' "$setup"
grep -Fq 'Where-Object { $_.Name -match' "$setup"

echo "Nimino setup contract passed"
