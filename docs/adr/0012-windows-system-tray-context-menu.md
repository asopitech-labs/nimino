# ADR-0012: Windows system tray context menu

## Status

Accepted — Windows native M5 の最小部分実装。

## Context

`nimino-native` は OS 固有の WebView ラッパーを導入せず、薄い
Window/WebView 層に限定する。Windows デスクトップ統合の第一歩として、
URL 包装や設定形式を必要としない system tray と context menu を追加する。

Pake は start-to-tray / hide-on-close を利用者向けの包装オプションとして
提供している。これは tray が実用アプリの基本的な統合点である根拠にはするが、
Nimino では Pake/Tauri の runtime や API を依存として取り込まない。
hide-on-close、start-to-tray、アプリ固有アイコン、通知は `nimino-core` と
`nimino-pack` のポリシー・配布責務が必要なため、この変更の対象外とする。

## Decision

Windows backend は private FFI の `NOTIFYICONDATAW` と
`Shell_NotifyIconW`、`CreatePopupMenu`、`TrackPopupMenu` を直接使用する。
FFI の struct 順序は Docker image に固定した MinGW Win32 SDK の
`shellapi.h` で確認する。公開 API は created 状態で一度だけ menu item と
handler を登録する `configureSystemTray` とし、Windows 以外は
`unsupported` を返す。未対応を成功として扱わない。

通知 icon は次の順序で管理する。

1. 最初に作成された native Window の `HWND` を owner とし、`NIM_ADD` を行う。
2. 同じ `NOTIFYICONDATAW` に `NOTIFYICON_VERSION_4` を設定し、毎回
   `NIM_SETVERSION` を行う。
3. callback message の `WM_CONTEXTMENU`、`NIN_SELECT`、`NIN_KEYSELECT` を
   UI thread の window procedure で受け、同期的に native popup menu を表示する。
4. `TrackPopupMenu(TPM_RETURNCMD)` の選択 ID だけを Nim handler へ渡す。
   handler の例外を Win32 callback 境界から外へ送出しない。
5. menu 終了後に `NIM_SETFOCUS` を送る。owner Window の破棄前と app shutdown
   時に idempotent に `NIM_DELETE` を送る。

Windows system-tray のイベント解釈、`NIM_SETVERSION` の毎回呼出し、menu 後の
`NIM_SETFOCUS` は Microsoft の
[Shell_NotifyIconW documentation](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw)
に従う。`NOTIFYICON_VERSION_4` では callback `lParam` の LOWORD が
notification event であることも同ドキュメントで確認した。

## Consequences

- `systemTray` と `nativeMenu` capability は Windows build だけで true になる。
- M1 で複数 native Window が作られた場合も、tray owner は最初の live Window
  一つである。その Window を閉じると icon は削除される。別 Window への再関連付け
  は将来の multi-window tray policy で設計する。
- icon は Windows 標準の `IDI_APPLICATION` を使う。アプリ icon 供給は pack の
  配布設定と統合するまで追加しない。
- Windows toast notification は実装しない。AppUserModelID、shortcut/
  activation registration、installer を伴うため、`nativeNotification` capability は
  false のままにする。
- GUI 実機なしでも、Docker の MinGW cross compile が public contract と FFI ABI を
  検証する。notification area に実際に icon が現れることは Windows GUI smoke の
  今後の検証対象である。
