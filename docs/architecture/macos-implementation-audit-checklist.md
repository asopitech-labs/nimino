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
| [x] | P1 | Native resize、Dock reopen、quit時にWindow状態を更新・保存する | `packages/core/src/nimino_core/app.nim`, macOS backend | 手動リサイズ、移動、非表示、再表示、最大化、フルスクリーン、always-on-topの状態が次回起動時に復元される |
| [x] | P1 | `setSize`をframe sizeではなくcontent/inner size基準に統一する | `packages/native/src/nimino_native/private/macos/bridge.m` | `onResize`の値、初期サイズ、保存サイズが同じcontent領域を表す |
| [x] | P1 | 生成hostで`enableDragDrop`と`window.onFileDrop`を接続する | `tools/hosts/nimino_host.nim` | macOS packaged appへ絶対パスの配列が通知される |
| [x] | P1 | permission manifestの許可対象とmacOS実装を一致させる | `tools/hosts/nimino_host.nim`, `bridge.m`, package plist | camera/microphone以外を実装するか、未対応permissionを起動前に拒否する |
| [x] | P1 | macOS Cookie URLフィルタをdomain境界、path、Secure、schemeに対応させる | `packages/native/src/nimino_native/private/macos/bridge.m` | `example.com`が`notexample.com`に一致せず、URLに該当するCookieだけ返る |
| [x] | P0 | 生成hostからPake相当のmacOSネイティブアプリメニューを接続する | `tools/hosts/nimino_host.nim`, Core/native menu API | App/File/Edit/View/Navigation/Window/Helpの階層、標準編集操作、Zoom、Fullscreen、Hide/Show/Quit、New Windowが登録される |
| [x] | P0 | Pake相当のSystem Tray操作を生成hostへ接続する | `tools/hosts/nimino_host.nim`, macOS bridge | New Window/Hide/Show/Quit、左クリック表示切替、Trayアイコンが機能する |
| [x] | P1 | 生成hostから汎用Native通知をRPCで呼び出せるようにする | `tools/hosts/nimino_host.nim`, Core RPC | `window.nimino.invoke('app.sendNotification', ...)`が通知を表示する |
| [x] | P1 | macOS Dock badgeと通知のin-app fallbackを生成hostへ接続する | `tools/hosts/nimino_host.nim`, Core/native macOS bridge | Apple署名通知はDock/Notification Centerへ送り、未署名・Ad-hocではWebバナーへフォールバックする |
| [x] | P1 | `localEntry`でもPake相当の追加Windowを生成する | `tools/hosts/nimino_host.nim`, Core popup API | File URLとして追加Windowを開き、multiWindowのtray/menu操作がローカルbundleでも機能する |
| [x] | P1 | Pake互換のWindow/WebView CLIオプションをmanifestへ反映する | `tools/cli/nimino.nim`, `packages/pack/src/nimino_pack/manifest.nim` | min size、dark mode、find、WASM、new window、内部遷移等がCLI/TOML/JSONで保持される |
| [x] | P1 | macOS dark mode、shortcut抑止、Find helperを実装する | Core/native macOS bridge、document-start injection | dark appearance、ブラウザshortcut抑止、`window.nimino.find`が有効になる |
| [x] | P1 | macOS activation shortcutを実装する | `packages/native/src/nimino_native/private/macos/bridge.m` | Cmd/Ctrl系ショートカットでWindowの表示/非表示を切り替えられる |
| [x] | P2 | systemTrayIconをmacOS package Resourcesへ同梱する | `packages/pack/src/nimino_pack/macos_package.nim` | 絶対パスをmanifestへ残さず、生成`.app`内のアイコンを参照する |
| [x] | P0 | `localEntry` の `file:` navigation policyを許可する | `packages/core/src/nimino_core/app.nim` | 初期ローカル文書、同梱asset遷移、New Windowがhostnameなしの`file:` URLを拒否しない |
| [x] | P0 | 実行中のmacOS Appへ追加Windowを生成する | `packages/native/src/nimino_native/types.nim` | menu/tray/WebView popupからのWindowが即座にNSWindow/WKWebViewとして作成される |
| [x] | P1 | AppKitのWindow/Help menu roleを登録する | `packages/native/src/nimino_native/private/macos/bridge.m` | 標準のWindow移動・タイル・循環機能をAppKitへ委譲する |
| [x] | P1 | macOS single-instance activationを実装する | Core instance lock、macOS distributed notification | 2回目の起動は既存hostを前面化し、2プロセス目を残さない |
| [x] | P1 | Pake互換の`window.Notification`、click callback、Dock badge連携を提供する | `tools/hosts/nimino_host.nim` | Apple署名時はnative通知、Ad-hoc時はクリック可能なin-app bannerへフォールバックする |
| [x] | P1 | Clear Cache操作をWebKit消去完了後にreloadする | Core/macOS bridge | `WKWebsiteDataStore`のcompletion handlerより前にreloadしない |
| [x] | P2 | macOS activation shortcutをCarbon global hotkeyへ移行する | `bridge.m`, `ffi.nim` | NSEvent監視に依存せず、OS登録・重複抑止・解除を行う |

## 配布・互換性タスク

| 状態 | 優先度 | タスク | 完了条件 |
|---|---|---|---|
| [x] | P2 | 旧通知APIを`UNUserNotificationCenter`ベースへ更新する | 権限要求、Apple-issued署名の事前判定、通知表示、activation、identifier、未署名fallbackを実装する |
| [x] | P2 | `hideTitleBar`と`hideWindowDecorations`のmacOS意味論をPake/Tauriと統一する | overlay指定時にtraffic-light buttonsとWindow操作性が意図どおり維持される |
| [ ] | P2 | Developer IDで署名し、Gatekeeper、notarization、staplerを配布用に検証する（Issue #3） | Developer ID証明書、hardened runtime、notarization ticketを用いた`.app`/DMGの配布検証が成功する |
| [x] | P2 | `stopURLSchemeTask`のキャンセル処理を実装する | 中断済みscheme taskへresponseを返さず、handlerが長時間ブロックしない |
| [x] | P2 | 個別WebView close時にmacOS側のViewContextをunlink/freeする | Windowを長時間使い続けても閉じたWebViewのnative contextが蓄積しない |
| [x] | P2 | macOS bridgeのclang warningを解消する | `bridge.m`のsyntax checkがwarning 0件で通る |

## 意図的に未対応とする場合の確認

- [x] `systemTrayIcon`はmacOS package Resourcesへ同梱し、生成hostで解決する
- [x] notifications/geolocation/clipboard/screenCaptureはWKWebViewの公開API差分のためmacOS hostでは明示拒否する。Native通知は`app.sendNotification` RPCで提供する
- [ ] Apple署名・notarization・Gatekeeper・staplerの配布検証を実施する（Issue #3）
- [ ] Ad-hoc署名の実機で通知表示→Notification Centerクリック→`onNotificationActivated` callbackを確認する（現行macOSの`usernotificationsd`がAd-hoc bundleを拒否。Apple Development署名で別途確認する）
- [x] Ad-hoc署名の実機でcustom URL scheme／Deep Linkの起動とcallbackを確認する
- [x] Ad-hoc署名の実機でメニューとトレイ左クリックを確認する（SystemUIServerの実`AXMenuExtra`をクリックするpackage smoke）
- [ ] Ad-hoc署名の実機でトレイメニュー、Dock reopen、TCC権限、ドラッグ＆ドロップを手動確認する

## 現時点の検証結果

- [x] `nimble testMacosSmoke`
- [x] Objective-C bridgeのsyntax check
- [x] macOS package smoke本体
- [x] CLI parity manifest smoke（min size/dark mode/find/WASM/new window/shortcut）
- [x] Pake parity smoke（標準macOS menu、Dock badge RPC、localEntry追加Window、OS Downloads保存、通知in-app fallback）
- [x] 生成hostコンパイル（`nimble buildNiminoHost`。Nimble global cache警告のみ）
- [x] `.app`生成とDMG生成（Ad-hoc署名は別途実機手順で検証）
- [x] Ad-hoc実機GUI smoke（起動、Deep Link）
- [x] Ad-hoc実機GUI menu smoke（File > New Window、Clear Cache & Reload、localEntry追加Window）
- [x] Ad-hoc実機GUI tray smoke（SystemUIServerのトレイ主クリックを2回実行）
- [x] Ad-hoc実機single-instance smoke（2回の`open -n`後もhostプロセスは1つ）
- [x] `git diff --check`
- [x] `nimble testPackMacos`全体終了（Ad-hoc署名、GUI menu、single-instance、Deep Link、DMG）
- [ ] `nimble test`全体終了（macOS実装外のWSL用autostartテストが環境条件で失敗）
