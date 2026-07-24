# Pake test migration checklist

参照元は `reference/pake/tests/`。この表は「似た機能がある」ことではなく、各
参照 suite の入力境界と期待結果が Nimino のテストで実行されることを完了条件とする。
`[~]` は一部のケースのみ移植済みであり、完了扱いにしない。

OS 固有 suite は実行フラグを必須とする。macOS では共通と macOS のみを実行し、
Linux/Windows を実行したことにしない。

| 状態 | Pake suite | Nimino の対応先・実行条件 |
|---|---|---|
| [x] | `auth-sso-patterns` | `packages/core/tests/test_app.nim` |
| [ ] | `base-builder` | Nimino pack builder の toolchain/host artifact 契約として個別移植が必要 |
| [ ] | `builders` | Linux target parser。`NIMINO_TEST_REFERENCE_LINUX=1` |
| [x] | `cli-options` | `tools/ci/test_pack_macos.sh`, `tools/ci/test_pack_cli.sh` |
| [x] | `combine` | `packages/core/tests/test_macos_find_smoke.nim`, `test_pack_cli.sh` |
| [x] | `config-file` | `packages/pack/tests/test_manifest.nim`, `packages/pack/schema/nimino-pack.schema.json` |
| [~] | `error` | `PackResult` failure pathsはテスト済み。Pake相当のCLI error/exit-code契約は未移植 |
| [~] | `event-clipboard-shortcuts` | macOS 非介入は `test_macos_find_smoke`。Windows/Linux editable/fallback ケースは各 OS suite が未移植 |
| [~] | `event-fullscreen-shortcuts` | macOS F11 非介入は `test_macos_find_smoke`。Windows/Linux F11 は各 OS suite が未移植 |
| [~] | `event-link-guard` | auth/popup/navigation は `test_app` と macOS smoke。Badge/Notification DOM 契約は未移植 |
| [ ] | `file-finding` | pack artifact discovery helper の独立テストが未移植 |
| [x] | `find-shortcuts` | `packages/core/tests/test_macos_find_smoke.nim` |
| [ ] | `ico` | Windows ICO multi-resolution。`NIMINO_TEST_REFERENCE_WINDOWS=1` |
| [ ] | `icon-source` | dashboard/local icon source priority helper が未移植 |
| [~] | `icon` | MIME 型受理/拒否は `test_pack_cli.sh`。source priority は未移植 |
| [x] | `identifier` | `packages/pack/tests/test_manifest.nim` |
| [x] | `json-output` | `tools/ci/test_pack_cli.sh` |
| [ ] | `linux-desktop` | `NIMINO_TEST_REFERENCE_LINUX=1` |
| [ ] | `linux-distro` | `NIMINO_TEST_REFERENCE_LINUX=1` |
| [ ] | `linux-icon` | `NIMINO_TEST_REFERENCE_LINUX=1` |
| [x] | `local-input` | `test_manifest.nim`, `test_pack_cli.sh` |
| [~] | `local-staging` | input symlink/dangling asset は `test_pack_cli.sh`。rollback/self-package guard は未移植 |
| [x] | `mac-builder-targets` | `tools/ci/test_pack_macos.sh`; `NIMINO_TEST_REFERENCE_MACOS=1` |
| [~] | `merge-window-options` | macOS defaults/options は manifest + package smoke。Windows/Linux platform mapping は未移植 |
| [~] | `name` | registrable URL名・local display name は移植済み。Pakeの全 sanitizer utility ケースは未移植 |
| [x] | `no-bundle` | `tools/ci/test_pack_cli.sh` |
| [x] | `options-name` | `packages/pack/tests/test_manifest.nim` |
| [x] | `safe-domains` | `test_manifest.nim`, `test_app.nim`, `test_pack_cli.sh` |
| [~] | `system-tray-icon` | macOS icon copy/missing path は `test_pack_macos.sh`。fallback/copy-failure ケースは未移植 |
| [x] | `url` | `packages/pack/tests/test_manifest.nim`, `test_pack_cli.sh` |
| [x] | `validate-url-input` | `tools/ci/test_pack_cli.sh` |
| [ ] | `window-icon-reapply` | Windows taskbar icon lifecycle。`NIMINO_TEST_REFERENCE_WINDOWS=1` |
| [x] | `integration/workflow-paths` | `tools/ci/test_pack_cli.sh` の URL/local/config path flows |
| [ ] | `release` | Pake release packaging workflow への Nimino 対応テストを明示化する必要あり |

## 実行分離

| 条件 | 実行対象 |
|---|---|
| フラグなし | `nimble test` と共通 pack tests。Linux/Windows/WSL 契約は実行しない |
| `NIMINO_TEST_REFERENCE_MACOS=1` | `nimble testReferenceParity` の macOS WKWebView・package suite |
| `NIMINO_TEST_REFERENCE_LINUX=1` | Linux runtime/package suite |
| `NIMINO_TEST_REFERENCE_WINDOWS=1` | Windows/WebView2/installer suite |
| `NIMINO_TEST_REFERENCE_WSL=1` | WSL host protocol suite |
