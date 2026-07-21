#!/usr/bin/env bash
set -euo pipefail

package_path="${1:?usage: verify-webview2-header.sh WEBVIEW2_NUPKG}"
header_path="$(mktemp)"
trap 'rm -f "$header_path"' EXIT

unzip -p "$package_path" build/native/include/WebView2.h >"$header_path"

grep -q 'ICoreWebView2PermissionRequestedEventHandler' "$header_path"
grep -q 'ICoreWebView2DownloadStartingEventHandler' "$header_path"
grep -q 'COREWEBVIEW2_PERMISSION_KIND_MICROPHONE' "$header_path"
grep -q 'COREWEBVIEW2_PERMISSION_KIND_CAMERA' "$header_path"

verify_slots() {
  local table_name="$1"
  local first_method="$2"
  local first_slot="$3"
  local second_method="$4"
  local second_slot="$5"

  awk \
    -v table_name="$table_name" \
    -v first_method="$first_method" \
    -v first_slot="$first_slot" \
    -v second_method="$second_method" \
    -v second_slot="$second_slot" '
      $0 ~ ("^[[:space:]]*typedef struct " table_name "Vtbl[[:space:]]*$") {
        inside = 1
        count = 0
        next
      }
      inside && /DECLSPEC_XFGVIRT/ {
        count++
        if ($0 ~ first_method) {
          first_found = 1
          if (count - 1 != first_slot) exit 1
        }
        if ($0 ~ second_method) {
          second_found = 1
          if (count - 1 != second_slot) exit 1
        }
      }
      inside && $0 ~ ("^[[:space:]]*} " table_name "Vtbl;[[:space:]]*$") {
        found_end = 1
        exit !(first_found && second_found)
      }
      END {
        if (!found_end) exit 1
      }
    ' "$header_path"
}

verify_slots ICoreWebView2 add_NewWindowRequested 44 remove_NewWindowRequested 45
verify_slots ICoreWebView2 get_Settings 3 get_Source 4
verify_slots ICoreWebView2Settings get_AreDevToolsEnabled 11 put_AreDevToolsEnabled 12
verify_slots ICoreWebView2_4 add_DownloadStarting 75 remove_DownloadStarting 76
verify_slots ICoreWebView2PermissionRequestedEventArgs get_PermissionKind 4 put_State 7
verify_slots ICoreWebView2DownloadStartingEventArgs get_DownloadOperation 3 put_Cancel 5
verify_slots ICoreWebView2DownloadStartingEventArgs get_ResultFilePath 6 put_ResultFilePath 7
verify_slots ICoreWebView2DownloadOperation add_BytesReceivedChanged 3 get_Uri 9
