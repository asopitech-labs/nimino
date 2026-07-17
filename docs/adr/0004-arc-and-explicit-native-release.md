# ADR-0004: Nimメモリ管理はARC、native resourceは明示解放とする

- 状態: Accepted
- 日付: 2026-07-17

## 文脈

NimのARC/ORCはいずれもNim objectのメモリ管理を支援するが、COM、GObject、HWND、event registration、WSL host processを正しいUI thread・正しい順序で解放することは保証しない。callbackとWindowの強参照循環も避ける必要がある。

## 決定

- プロジェクトのコンパイル既定を`--mm:arc`にする。
- `NativeApp`、`NativeWindow`、`NativeWebView`、WSL sessionに明示的かつidempotentな`close`を設ける。
- native handleのfinalizerを主解放経路にしない。安全な場合だけ、リーク検出用の防御的補助とする。
- COMは`AddRef`/`Release`、GObjectは`g_object_ref_sink`/`g_object_unref`、callbackはevent token/signal handler IDによって所有・解除する。
- callbackは親を強参照しない設計にし、登録解除時だけcontextを解放する。

## 根拠

ARCは循環を隠さず、Window/WebView/callbackの所有権を設計・テストで明示できる。いずれのNim memory managerでもnative thread affinityを解決しないため、明示closeが正しい根本対策である。[COM reference count rules](https://learn.microsoft.com/en-us/windows/win32/com/rules-for-managing-reference-counts)と[GObject ownership](https://docs.gtk.org/gobject/concepts.html)に従う。

## 帰結

テストはcloseの二重実行、Window先行終了、保留中のWebView作成、host/client異常終了後の資源解放を検証する。循環を必要とする純Nimデータ構造が将来必要になった場合も、native object graphにORCを導入する理由にはならない。
