# WebView2 private FFI provenance

`nimino-native` uses a hand-maintained, minimal WebView2 Loader/COM FFI in
`packages/native/src/nimino_native/private/windows/ffi.nim`.  It is an
implementation detail and is not published as a general-purpose binding.

## Source checked

| Item | Value |
| --- | --- |
| Package | `Microsoft.Web.WebView2` |
| Version | `1.0.3967.48` |
| SHA-256 | `c66357ac7f324ec9bcafe5241706a023b4122d8c22300c31de4b0eb220db689e` |
| Header | `build/native/include/WebView2.h` |
| License | Microsoft three-clause BSD-style license in the package `LICENSE.txt` |

The package was obtained only for API verification.  Its headers, loader, and
runtime are not copied into this repository.

## M1 surface copied into Nimino

* `CreateCoreWebView2EnvironmentWithOptions`
* `GetAvailableCoreWebView2BrowserVersionString`
* `ICoreWebView2Environment::CreateCoreWebView2Controller`
* `ICoreWebView2Controller::{put_Bounds, Close, get_CoreWebView2}`
* `ICoreWebView2::{Navigate, NavigateToString}`
* the two creation completion handler IIDs and their `IUnknown` methods

## M2 surface copied into Nimino

* `ICoreWebView2::ExecuteScript` (vtable slot 29)
* `ICoreWebView2ExecuteScriptCompletedHandler` and IID
  `49511172-cc67-4bca-9923-137112f4c4cc`
* `ICoreWebView2::{add_WebMessageReceived, remove_WebMessageReceived}`
  (vtable slots 34 and 35)
* `ICoreWebView2WebMessageReceivedEventHandler` and IID
  `57213f19-00e6-49fa-8e07-898ea01ecbd2`
* `ICoreWebView2WebMessageReceivedEventArgs::TryGetWebMessageAsString`
  (vtable slot 5)
* `ICoreWebView2::{add_NavigationCompleted, remove_NavigationCompleted}`
  (vtable slots 15 and 16)
* `ICoreWebView2NavigationCompletedEventHandler` and IID
  `d33a35bf-1c49-4f98-93ab-006e0533fe1c`
* `ICoreWebView2NavigationCompletedEventArgs::get_IsSuccess` (vtable slot 3)
  and `ICoreWebView2::get_Source` (vtable slot 4)
* `ICoreWebView2::{add_NavigationStarting, remove_NavigationStarting}`
  (vtable slots 7 and 8)
* `ICoreWebView2NavigationStartingEventHandler` and IID
  `9adbe429-f36d-432b-9ddc-f8881fbd76e3`
* `ICoreWebView2NavigationStartingEventArgs::{get_Uri, put_Cancel}`
  (vtable slots 3 and 8)
* `ICoreWebView2::{add_NewWindowRequested, remove_NewWindowRequested}`
  (vtable slots 45 and 46)
* `ICoreWebView2NewWindowRequestedEventHandler` and IID
  `d4c185fe-c81c-4989-97af-2d3fa7ab5651`
* `ICoreWebView2NewWindowRequestedEventArgs::{get_Uri, put_Handled}`
  (vtable slots 3 and 6)

The completed handler receives an `HRESULT` and a borrowed JSON-encoded UTF-16
result. Nimino copies the result before the callback returns and explicitly
holds the associated Nim request from submission through completion.

The WebMessage handler copies only a string result and releases every returned
`LPWSTR` with `CoTaskMemFree`. It stores the event token and removes the handler
before releasing the CoreWebView2 object.

The navigation-completed handler likewise stores/removes its event token,
copies and frees `get_Source`'s `LPWSTR`, and reads `IsSuccess` without
assuming that a finished navigation succeeded.

The navigation-starting handler copies/frees its URI and writes `Cancel` only
when the registered Nim callback denies the request. It is registered before
initial content is loaded and removed before releasing CoreWebView2.

The new-window handler copies/frees its URI, notifies Nim, then writes
`Handled = true`. It does not create a hidden or implicit WebView2 instance.

The vtable slot order and callback signatures were checked against the header
above.  Later features must be checked against a recorded SDK version before
adding a new slot.

## M4 Profile/CookieManager (Windows implementation)

The following private declarations are used by
`nimino-native`'s Windows backend.  `nimino-core` exposes them through the
asynchronous `Window.clearWebViewProfileData` API.  This remains a narrow
private implementation rather than a general WebView wrapper.

| Purpose | Interface / method | IID / slot |
| --- | --- | --- |
| Obtain a cookie manager | `ICoreWebView2_2::get_CookieManager` | `9e8f0cf8-e670-4b5e-b2bc-73e061e3184c` / 66 |
| Obtain a profile | `ICoreWebView2_13::get_Profile` | `f75f09a8-667e-4983-88d6-c8773f315e84` / 105 |
| Clear selected data | `ICoreWebView2Profile2::ClearBrowsingData` | `fa740d4b-5eae-4344-a8ad-74be31925397` / 10 |
| Completion callback | `ICoreWebView2ClearBrowsingDataCompletedHandler::Invoke` | `e9710a06-1d1d-49b2-8234-226f35846ae5` / 3 |
| Delete all cookies | `ICoreWebView2CookieManager::DeleteAllCookies` | `177cd9e7-b6f5-451a-94a0-5d7a3a4c4141` / 10 |

`ClearBrowsingData` is asynchronous.  The backend owns its completed-handler
COM object from successful registration through `Invoke`, holds the associated
Nim request until the callback returns, maps the callback `HRESULT` to
`NativeError`, and releases queried interfaces on the UI thread.  It queries
`ICoreWebView2_13` and `ICoreWebView2Profile2` at runtime and returns
`unsupported` when an installed Evergreen Runtime does not expose either
interface; it never reports a successful clear in that case.

The current focused data mapping is intentionally narrow:

* cookies: `0x0040` (`COOKIES`)
* local storage: `0x0004` (`LOCAL_STORAGE`)
* cache: `0x0010 | 0x0100` (`CACHE_STORAGE | DISK_CACHE`)

For cookies only, the backend uses the synchronous
`ICoreWebView2CookieManager::DeleteAllCookies` path.  Any request that also
contains local storage or cache uses the asynchronous Profile2 path and the
same Future result surface.

This feature has a real Windows WebView2 Runtime dependency: Docker CI can
verify the official header, fake COM dispatch, and a Windows cross-compile, but
cannot exercise an installed Evergreen Runtime or complete a real callback.
Linux and the WSL Windows-host adapter deliberately return `unsupported`; the
WSL protocol has no async browser-profile-clear lifecycle yet.

Profile reset remains a restart operation.  Microsoft documents the User Data
Folder as in-use while a WebView2 session is active, so deleting or recreating
the UDF remains outside this live-clear path.  `ICoreWebView2CookieManager`
is used only for the cookies-only operation; broader clear requests use
Profile2 so the result accurately represents the browser operation.

Run the reproducible spike through Docker only:

```sh
make webview2-profile-ffi-spike
```

The command first downloads and SHA-256 verifies the pinned official header,
then verifies these exact IIDs and vtable slots, runs the executable
fake-vtable test, and cross-compiles the Windows ABI contract.

## M3 document-start surface copied into Nimino

* `ICoreWebView2::AddScriptToExecuteOnDocumentCreated` (vtable slot 27)
* `ICoreWebView2AddScriptToExecuteOnDocumentCreatedCompletedHandler` and IID
  `b99369f3-9b11-47b5-bc6f-8e7895fcea17`

The operation is asynchronous. Nimino defers the first pending load until its
completion callback succeeds, so a caller that configured a script while the
View was `pending` does not race the first navigation. Nimino releases its
initial callback reference immediately after registration; WebView2 retains
the callback until completion and controls the final release. The returned
script ID is deliberately not retained because the low-level API does not
support mutation after the View is ready. The Core layer owns URL and origin
policy; the native API only registers a prepared string.

## Distribution boundary

The application must distribute the architecture-matched `WebView2Loader.dll`
next to a Windows executable, or statically link the loader in a future
packaging implementation. `tools/docker/Dockerfile` downloads the above
fixed SDK from NuGet, verifies its recorded SHA-256, and extracts only the x64
loader plus its `LICENSE.txt` and `NOTICE.txt` into the Docker image. The WSL
host artifact copies all three files beside `nimino-wsl-host.exe`; this keeps
the Loader architecture-matched and preserves its distribution notices. The
Windows backend loads that exact sibling path instead of relying on DLL search
order.

`nimino-native` deliberately does not bundle a Chromium runtime. At startup it
asks the loader for an available WebView2 runtime and returns `webViewError` if
it is unavailable. The Evergreen Runtime is a Windows prerequisite, separate
from the SDK loader. Future package targets must reuse this owned Loader
staging path rather than fetch an unpinned SDK during packaging.

The Windows backend passes a writable, local User Data Folder to environment
creation. Its temporary native fallback is documented in
[ADR-0007](../../docs/adr/0007-windows-native-user-data-folder.md); `nimino-core`
will replace it with an app-ID/profile-specific path in M4.

Microsoft's distribution guidance:

* [Distribute your app and the WebView2 Runtime](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
* [WebView2 Win32 getting started](https://learn.microsoft.com/en-us/microsoft-edge/webview2/get-started/win32)
