#!/usr/bin/env bash
# Verify the exact private Profile/CookieManager ABI entries against the
# WebView2 SDK version recorded in tools/bindings/webview2.md.
set -euo pipefail

readonly sdk_version="1.0.3967.48"
readonly sdk_sha256="c66357ac7f324ec9bcafe5241706a023b4122d8c22300c31de4b0eb220db689e"
readonly package_url="https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/${sdk_version}/microsoft.web.webview2.${sdk_version}.nupkg"
readonly work_dir="$(mktemp -d)"
readonly package_path="${work_dir}/webview2.nupkg"
readonly header_path="${work_dir}/WebView2.h"

curl --fail --silent --show-error -L -o "${package_path}" "${package_url}"
echo "${sdk_sha256}  ${package_path}" | sha256sum --check --status
unzip -p "${package_path}" build/native/include/WebView2.h > "${header_path}"

grep -q 'MIDL_INTERFACE("9E8F0CF8-E670-4B5E-B2BC-73E061E3184C")' "${header_path}"
grep -q 'MIDL_INTERFACE("f75f09a8-667e-4983-88d6-c8773f315e84")' "${header_path}"
grep -q 'MIDL_INTERFACE("177CD9E7-B6F5-451A-94A0-5D7A3A4C4141")' "${header_path}"
grep -q 'MIDL_INTERFACE("fa740d4b-5eae-4344-a8ad-74be31925397")' "${header_path}"
grep -q 'MIDL_INTERFACE("e9710a06-1d1d-49b2-8234-226f35846ae5")' "${header_path}"
grep -q 'MIDL_INTERFACE("5a4f5069-5c15-47c3-8646-f4de1c116670")' "${header_path}"
grep -q 'MIDL_INTERFACE("af641f58-72b2-11ee-b962-0242ac120002")' "${header_path}"
grep -q 'MIDL_INTERFACE("2fde08a8-1e9a-4766-8c05-95a9ceb9d1c5")' "${header_path}"
grep -q 'MIDL_INTERFACE("12aae616-8ccb-44ec-bcb3-eb1831881635")' "${header_path}"

slot_for() {
  local vtable="$1"
  local method="$2"

  awk -v target="${vtable}" -v method="${method}" '
    index($0, "typedef struct " target) {
      inside = 1
      slot = 0
      next
    }
    inside && /STDMETHODCALLTYPE \*/ {
      if (index($0, "*" method " )") > 0) {
        print slot
        exit 0
      }
      slot++
    }
    inside && index($0, "} " target ";") {
      exit 1
    }
  ' "${header_path}"
}

test "$(slot_for ICoreWebView2_2Vtbl get_CookieManager)" = "66"
test "$(slot_for ICoreWebView2_13Vtbl get_Profile)" = "105"
test "$(slot_for ICoreWebView2Profile2Vtbl ClearBrowsingData)" = "10"
test "$(slot_for ICoreWebView2CookieManagerVtbl DeleteAllCookies)" = "10"
test "$(slot_for ICoreWebView2CookieManagerVtbl CreateCookie)" = "3"
test "$(slot_for ICoreWebView2CookieManagerVtbl GetCookies)" = "5"
test "$(slot_for ICoreWebView2CookieManagerVtbl AddOrUpdateCookie)" = "6"
test "$(slot_for ICoreWebView2CookieManagerVtbl DeleteCookie)" = "7"
test "$(slot_for ICoreWebView2CookieListVtbl get_Count)" = "3"
test "$(slot_for ICoreWebView2CookieListVtbl GetValueAtIndex)" = "4"
test "$(slot_for ICoreWebView2CookieVtbl get_Name)" = "3"
test "$(slot_for ICoreWebView2CookieVtbl get_Value)" = "4"
test "$(slot_for ICoreWebView2CookieVtbl get_Domain)" = "6"
test "$(slot_for ICoreWebView2CookieVtbl get_Path)" = "7"
test "$(slot_for ICoreWebView2CookieVtbl get_Expires)" = "8"
test "$(slot_for ICoreWebView2CookieVtbl put_Expires)" = "9"
test "$(slot_for ICoreWebView2CookieVtbl get_IsHttpOnly)" = "10"
test "$(slot_for ICoreWebView2CookieVtbl put_IsHttpOnly)" = "11"
test "$(slot_for ICoreWebView2CookieVtbl get_IsSecure)" = "14"
test "$(slot_for ICoreWebView2CookieVtbl put_IsSecure)" = "15"
test "$(slot_for ICoreWebView2CookieVtbl get_IsSession)" = "16"
test "$(slot_for ICoreWebView2Environment13Vtbl CreateCoreWebView2ControllerOptions)" = "20"
test "$(slot_for ICoreWebView2Environment13Vtbl CreateCoreWebView2ControllerWithOptions)" = "21"
test "$(slot_for ICoreWebView2ControllerOptionsVtbl put_IsInPrivateModeEnabled)" = "6"
test "$(slot_for ICoreWebView2EnvironmentOptionsVtbl put_AdditionalBrowserArguments)" = "4"
