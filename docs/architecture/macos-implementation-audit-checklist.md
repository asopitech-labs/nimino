# macOS実装監査チェックリスト

更新日: 2026-07-23

Pake/Tauri参照コードとの比較、macOS native smoke、Objective-C bridgeの静的監査で抽出した対応タスク。

## 修正タスク

| 状態 | 優先度 | タスク | 主な対象 | 完了条件 |
|---|---|---|---|---|
| [x] | P0 | JavaScript評価、Cookie、閲覧データ処理の非同期callbackで`GC_ref/GC_unref`または同等の所有権を実装する | `packages/native/src/nimino_native/private/macos/{backend.nim,bridge.m}` | 処理中にWebView/Windowを閉じてもクラッシュせず、Futureが一度だけ完了する |
| [x] | P0 | Window/WebView終了と非同期callbackの競合テストを追加する | `packages/native/tests/test_macos_smoke.nim` | eval、Cookie、clearBrowsingDataを開始直後にclose/quitするテストが安定して通る |
| [x] | P1 | Pakeの`enable_wasm`をmacOS WebView設定へ伝播する | `tools/hosts/nimino_host.nim`, `packages/core/src/nimino_core/app.nim` | manifest flagを保持し、WKWebViewに存在しないChromium browser argsは明示的に文書化する |
| [x] | P1 | `min_width`/`min_height`をmacOS Windowへ適用するか、macOS manifest parserで明示的に拒否する | `tools/hosts/nimino_host.nim`, macOS bridge | Pake互換実装または起動前の一貫したunsupportedエラーになる |
| [x] | P1 | Popupのposition、inner size、focusを`NewWindowRequest`からmacOSへ伝播する | `packages/core/src/nimino_core/app.nim`, native new-window ABI | PakeのmacOS `NewWindowFeatures`相当が再現される |
| [x] | P1 | Popupへproxy、incognito、user-agent、title bar、権限、download設定などを完全に引き継ぐ | `packages/core/src/nimino_core/app.nim` | 親WindowとPopupの設定差分が意図した項目以外存在しない |
| [x] | P1 | Native resize、Dock reopen、quit時にWindow状態を更新・保存する | `packages/core/src/nimino_core/app.nim`, macOS backend | 手動リサイズ、移動、非表示、再表示後の状態が次回起動時に復元される |
| [x] | P1 | `setSize`をframe sizeではなくcontent/inner size基準に統一する | `packages/native/src/nimino_native/private/macos/bridge.m` | `onResize`の値、初期サイズ、保存サイズが同じcontent領域を表す |
| [x] | P1 | 生成hostで`enableDragDrop`と`window.onFileDrop`を接続する | `tools/hosts/nimino_host.nim` | macOS packaged appへ絶対パスの配列が通知される |
| [x] | P1 | permission manifestの許可対象とmacOS実装を一致させる | `tools/hosts/nimino_host.nim`, `bridge.m`, package plist | camera/microphone以外を実装するか、未対応permissionを起動前に拒否する |
| [x] | P1 | macOS Cookie URLフィルタをdomain境界、path、Secure、schemeに対応させる | `packages/native/src/nimino_native/private/macos/bridge.m` | `example.com`が`notexample.com`に一致せず、URLに該当するCookieだけ返る |

## 配布・互換性タスク

| 状態 | 優先度 | タスク | 完了条件 |
|---|---|---|---|
| [x] | P2 | 旧通知APIを`UNUserNotificationCenter`ベースへ更新する | 権限要求、通知表示、activation、identifierを現行macOS APIで検証する |
| [x] | P2 | `hideTitleBar`と`hideWindowDecorations`のmacOS意味論をPake/Tauriと統一する | overlay指定時にtraffic-light buttonsとWindow操作性が意図どおり維持される |
| [x] | P2 | codesign後に`codesign --verify`、`spctl --assess`、notarization後にstapler検証を行う | 署名済み`.app`/DMGの検証失敗をpackage成功扱いにしない |
| [x] | P2 | `stopURLSchemeTask`のキャンセル処理を実装する | 中断済みscheme taskへresponseを返さず、handlerが長時間ブロックしない |
| [x] | P2 | 個別WebView close時にmacOS側のViewContextをunlink/freeする | Windowを長時間使い続けても閉じたWebViewのnative contextが蓄積しない |
| [x] | P2 | macOS bridgeのclang warningを解消する | `bridge.m`のsyntax checkがwarning 0件で通る |

## 意図的に未対応とする場合の確認

- [x] `systemTrayIcon`はmacOS generated hostで明示的に未対応とし、API docsにも記載する
- [x] notifications/geolocation/clipboard/screenCaptureはmacOS generated hostで拒否し、manifest validationとAPI docsを一致させる
- [ ] Apple署名・notarization・通知クリック・deep linkの実ユーザー操作検証をrelease環境で実施する

## 現時点の検証結果

- [x] `nimble testMacosSmoke`
- [x] Objective-C bridgeのsyntax check
- [x] macOS package smoke本体
- [x] `git diff --check`
- [ ] `nimble testPackMacos`全体終了（Nimbleの`~/.nimble/nimbledata2.json`書込み失敗）
- [ ] `nimble test`全体終了（macOS実装外のWSL用autostartテストが環境条件で失敗）
