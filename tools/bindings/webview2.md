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

The completed handler receives an `HRESULT` and a borrowed JSON-encoded UTF-16
result. Nimino copies the result before the callback returns and explicitly
holds the associated Nim request from submission through completion.

The vtable slot order and callback signatures were checked against the header
above.  Later features must be checked against a recorded SDK version before
adding a new slot.

## Distribution boundary

The application must distribute the architecture-matched `WebView2Loader.dll`
next to a Windows executable, or statically link the loader in a future
packaging implementation.  `nimino-native` deliberately does not bundle a
Chromium runtime.  At startup it asks the loader for an available WebView2
runtime and returns `webViewError` if it is unavailable.

Microsoft's distribution guidance:

* [Distribute your app and the WebView2 Runtime](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution)
* [WebView2 Win32 getting started](https://learn.microsoft.com/en-us/microsoft-edge/webview2/get-started/win32)
