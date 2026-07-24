# Pake test migration checklist

参照元は `reference/pake/tests/`。この表は「似た機能がある」ことではなく、各
参照 suite の入力境界と期待結果が Nimino のテストで実行されることを完了条件とする。
`[~]` は一部のケースのみ移植済みであり、完了扱いにしない。

OS 固有 suite は実行フラグを必須とする。macOS では共通と macOS のみを実行し、
Linux/Windows を実行したことにしない。

| 状態 | Pake suite | Nimino の対応先・実行条件 |
|---|---|---|
| [x] | `auth-sso-patterns` | `packages/core/tests/test_app.nim` |
| [x] | `base-builder` | `test_pack_macos.sh` がhost欠落・不正output・不正arch拒否と実DMG toolchain生成を確認。Pake固有のnpm/Cargo環境選択はNiminoには存在しない |
| [x] | `builders` | `test_pack_linux.sh` がexplicit format選択・deb/RPM/Flatpakのtarget生成を確認。Niminoはambient distro推測をしない。`NIMINO_TEST_REFERENCE_LINUX=1` |
| [x] | `cli-options` | `tools/ci/test_pack_macos.sh`, `tools/ci/test_pack_cli.sh` |
| [x] | `combine` | `packages/core/tests/test_macos_find_smoke.nim`, `test_pack_cli.sh` |
| [x] | `config-file` | `packages/pack/tests/test_manifest.nim`, `packages/pack/schema/nimino-pack.schema.json` |
| [x] | `error` | `packages/pack/tests/test_reference_foundation.nim` が成功・失敗branch、全`PackErrorKind`とdetail契約を確認 |
| [x] | `event-clipboard-shortcuts` | `test_macos_find_smoke` が実WKWebViewで無効化対象のCmd+Rと、Niminoが介入しないCmd+Cを同時に確認。Pake の Ctrl+C/X/A/V、rich-paste 優先、text fallback、TTL、synthetic/非テキスト input を `tools/hosts/tests/test_web_shortcuts.js` に移植し、Windows/Linux フラグ時のみ実行（このmacOSでは未実行） |
| [x] | `event-fullscreen-shortcuts` | `test_macos_find_smoke` が実WKWebViewでF11を抑止しないことを確認。Pake の Windows/Linux F11 trusted/repeat/disabled/Alt+Enter と `hide_window_decorations` 時だけのtop drag region・native drag RPC・double-click fullscreen を `tools/hosts/tests/test_web_shortcuts.js` に移植し、Windows/Linux フラグ時のみ実行（このmacOSでは未実行） |
| [x] | `event-link-guard` | `test_policy`、`test_app`、実 WKWebView の `test_macos_web_compat_smoke`、`tools/hosts/tests/test_macos_link_guard.js` が `javascript:`/hash bypass、内部 `target=_blank` の `_self` 再ターゲット、Badge/Notification DOM、通常認証の同一 window、`about:blank` / named Apple popup の WindowProxy・後続遷移・blocked fallback を確認 |
| [x] | `file-finding` | `test_reference_foundation.nim` がglob、`.app`、directory除外、primary/fallback discoveryを確認 |
| [x] | `find-shortcuts` | `packages/core/tests/test_macos_find_smoke.nim` |
| [x] | `ico` | `test_ico.nim` がPNG-in-ICOのheader/layout、preferred frame、全Windows標準サイズ、既存exact PNG保持、異常入力を確認。`NIMINO_TEST_REFERENCE_WINDOWS=1`（このmacOSでは未実行） |
| [x] | `icon-source` | `packages/pack/tests/test_icon_source.nim` と自動icon解決がdashboard-icons/domain faviconの優先順位・local host判定を確認 |
| [x] | `icon` | `test_icon_source.nim` と`test_pack_cli.sh`がsource priority、dashboard icon取得、MIME型受理/拒否を確認 |
| [x] | `identifier` | `packages/pack/tests/test_manifest.nim` |
| [x] | `json-output` | `tools/ci/test_pack_cli.sh` |
| [x] | `linux-desktop` | `test_pack_linux.sh` がExec/Icon/categories/deep-linkとUTF-8表示名を確認。`NIMINO_TEST_REFERENCE_LINUX=1` |
| [x] | `linux-distro` | `test_pack_linux.sh` がformat省略を拒否し、明示deb/RPM/Flatpak選択を確認。`NIMINO_TEST_REFERENCE_LINUX=1` |
| [x] | `linux-icon` | `test_pack_linux.sh` がSVG iconのbundle stagingとdesktop icon pathを確認。`NIMINO_TEST_REFERENCE_LINUX=1` |
| [x] | `local-input` | `test_manifest.nim`, `test_pack_cli.sh` |
| [x] | `local-staging` | `test_pack_cli.sh` がdirectory/symlink入力、元入力の非変更、破損symlink失敗時のbundle非生成、自己包含output拒否を確認 |
| [x] | `mac-builder-targets` | `tools/ci/test_pack_macos.sh`; `NIMINO_TEST_REFERENCE_MACOS=1` |
| [x] | `merge-window-options` | `test_manifest.nim` が全window/webview/runtime optionのdefault・explicit値・startToTray条件を確認。platform固有backendは該当値だけを消費 |
| [x] | `name` | `test_manifest.nim` がPake suiteの表示名入力群（Unicode/記号/長文を含む）と拒否境界を確認。Niminoはdisplay nameと安全なIDを分離 |
| [x] | `new-window-macos` | `packages/native/tests/test_macos_smoke.nim` が実WKWebViewの`window.open`を別NSWindow/WKWebViewとして生成することを確認。`NIMINO_TEST_REFERENCE_MACOS=1` |
| [x] | `no-bundle` | `tools/ci/test_pack_cli.sh` |
| [x] | `options-name` | `packages/pack/tests/test_manifest.nim` |
| [x] | `safe-domains` | `test_manifest.nim`, `test_app.nim`, `test_pack_cli.sh` |
| [x] | `system-tray-icon` | `test_pack_macos.sh` がdefault tray、ICNS copy、欠落/dir copy失敗、SVG拒否を確認。NiminoはPakeのwarn+fallbackより厳格に配布前失敗とする |
| [x] | `url` | `packages/pack/tests/test_manifest.nim`, `test_pack_cli.sh` |
| [x] | `validate-url-input` | `tools/ci/test_pack_cli.sh` |
| [x] | `window-icon-reapply` | `test_windows_icon_reapply_contract.nim` が`WM_SETICON`のlarge/small設定とexplicit show後の再適用を確認。`NIMINO_TEST_REFERENCE_WINDOWS=1`（このmacOSでは未実行） |
| [x] | `integration/workflow-paths` | `tools/ci/test_pack_cli.sh` の URL/local/config path flows |
| [x] | `release` | `tools/ci/test_pack_macos_release.sh` が2アプリのbundle→DMG生成とartifact検査を実行。Linux/Windowsのrelease再構築は手動CIフラグに分離 |

## 実行分離

| 条件 | 実行対象 |
|---|---|
| フラグなし | `nimble test` と共通 pack tests。Linux/Windows/WSL 契約は実行しない |
| `NIMINO_TEST_REFERENCE_MACOS=1` | `nimble testReferenceParity` の macOS WKWebView・package suite |
| `NIMINO_TEST_REFERENCE_LINUX=1` | Linux runtime/package suite |
| `NIMINO_TEST_REFERENCE_WINDOWS=1` | Windows/WebView2/installer suite |
| `NIMINO_TEST_REFERENCE_WSL=1` | WSL host protocol suite |
