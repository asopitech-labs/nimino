# ADR-0013: Windows WebView2 new-window smoke harness

## Status

Accepted — WSL から Windows WebView2 Runtime を実起動する smoke test。

## Context

Windows native backend の cross compile は COM callback の構成と PE link を確認できる。
既存の `wsl-host-smoke` は Windows WebView2 Runtime 上で Window/WebView、URL/HTML、
JavaScript、message、navigation、shutdown を確認する。一方、`window.open()` または
`target="_blank"` の要求が callback として Windows host へ届き、暗黙に別の WebView を
生成しないことは別に確認する必要がある。

Nimino native は `NewWindowRequested` を通知したあと `Handled=true` にし、暗黙の
Window/WebView 作成を許可しない。このため、popup content が opener へ返す message を
待つ旧 harness は正しい成功条件ではない。Microsoft の
[WebView2 NewWindowRequested API](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/icorewebview2newwindowrequestedeventargs?view=webview2-1.0.3967.48)
に従い、host が `Handled` を設定した場合の期待結果は新しい Window を開かないことである。

この作業では公式 `WebView2.h` 1.0.3967.48 を照合し、`ICoreWebView2_4` の
`add/remove_DownloadStarting` が slot 75/76、`ICoreWebView2` の
`add/remove_NewWindowRequested` が slot 44/45 であることを確認した。既存 FFI の
slot が誤っていたため、実機 smoke が不安定または callback 未到達になる問題も同時に修正する。

## Decision

`make wsl-host-popup-smoke` は次の手順を固定する。

1. Docker 内で `nimino-wsl-host.exe` と WebView2Loader を生成する。
2. Windows PowerShell が authenticated stdio host を起動し、native Window/WebView を作る。
3. `data:` URL の test document に button を読み込み、`onclick` で DOM message と
   `window.open(data:...)` を同時に実行する。
4. `evalJavaScript` から button を一度だけ起動する。WebView callback が
   ExecuteScript completion より先に届いても、protocol frame を保持して後続 assertion で
   消費する。
5. 同じ WebView ID について DOM message `new-window-triggered` と
   `native.webview.newWindowRequested` の両方を確認する。
6. protocol shutdown を送って host の終了を確認し、失敗・timeout 時も process を回収する。

このテストは WebView2 Runtime、Win32 Window、COM callback、WSL protocol を通るが、
`evalJavaScript` による synthetic click である。したがって `IsUserInitiated` や物理 input の
自動検証を主張しない。実ポインタ/アクセシビリティ入力を扱う場合は、別の Windows desktop
test runner と専用 ADR を追加する。

## Consequences

- CI は Windows Runtime を利用できる WSL/Windows runner でこの target を opt-in として
  実行できる。GitHub Actions の必須 job には、対話 desktop が必要な input test を追加しない。
- `make windows-cross` と unit test は静的・protocol 層を、`make wsl-host-popup-smoke` は
  Runtime 上の NewWindow callback と `Handled` 方針を検証する。
- system tray、toast、OS permission dialog、物理 user gesture、アクセシビリティ tree は
  この target の成功範囲に含めない。
