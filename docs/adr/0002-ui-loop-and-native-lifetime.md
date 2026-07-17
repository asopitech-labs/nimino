# ADR-0002: OS UI loopを所有し、native resourceを明示解放する

- 状態: Accepted
- 日付: 2026-07-17

## 文脈

WebView2はSTAとWin32メッセージポンプを必要とし、GTK/WebKitGTKは作成したmain threadのGLib contextで操作する。NimのGCだけにCOM/GObject/callbackの寿命を委ねると、非同期生成とWindow終了が競合する。

## 決定

- `app.run()`をUIスレッドで呼び、WindowsはWin32 message loop、Linuxは`g_application_run`/GLib default main contextを唯一のUI loop所有者とする。
- すべてのUI/native操作は所有UI threadでのみ実行する。workerまたはIPC readerは`postToUi`を通す。
- Nim asyncはUI loopを置換しない。M2の `evalJavaScript` は OS WebView の完了 callback（GTK main context / Win32 STA）で Future を直接完了する。一般の `asyncdispatch.poll(0)` 統合と worker からの UI dispatch は、message/RPC を追加する前の別スパイクとして残す。
- `NativeApp → NativeWindow → NativeWebView`の順で明示的に所有する。各オブジェクトは`pending/ready/closing/closed`状態を持つ。
- `close`はidempotentとし、Window終了中に完了した非同期create/loadは`invalidState`または`webViewError`へ変換する。

## 終了順序

1. 新規要求を拒否し、Windowを`closing`にする。
2. event/signal handlerを登録解除する。
3. WebViewを停止/closeし、保留Futureを失敗として完了する。
4. Windowsでは`ICoreWebView2Controller::Close`、CoreWebView2/Controller/Environmentの`Release`、最後にHWND破棄と`CoUninitialize`を行う。
5. LinuxではWebView/Windowのsignal contextを解放し、`g_object_unref`、Window破棄、最後にApplication参照を解放する。
6. `closed`を記録して二重解放を防ぐ。

## 根拠

[WebView2 threading model](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/threading-model)はSTA UI thread上のcallbackと、同期的にUIを塞がないことを要求する。[GTK threading](https://docs.gtk.org/gtk4/section-threading.html)はGTK objectsを作成threadだけで操作するよう定める。[GMainContext.invoke](https://docs.gtk.org/glib/method.MainContext.invoke.html)をLinuxのUI復帰に使う。

## 帰結

M1は同期のWindow/URL操作までに限定する。M2の最初の実装として JavaScript 評価だけを追加し、callback user data は `GC_ref`/`GC_unref` で明示保持する。message、WSL 中継、RPCは後続の M2/M3で追加する。UI callbackから同期的にNim Futureを待つAPIは提供しない。
