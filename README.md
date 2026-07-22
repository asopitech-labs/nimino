# Nimino

Nimをホスト言語に、OS公式APIの薄いFFIでネイティブWindowとWebViewを扱う、軽量なクロスプラットフォームWeb UIデスクトップアプリケーション基盤です。

> M0〜M4のprofile、local asset境界、navigation/permission/download policy、Windows tray/WinRT Toast notification、Linux GTK menubar/notification、Windows/GTK/WSLのOSファイルダイアログを実装済みです。`nimino-pack`はLinux desktop entry、Debian/RPM archive、Flatpak build context、Docker内のGNOME 49実bundle、Windowsのper-user NSIS/MSI setup、CycloneDX SBOM、PowerShell templateを生成します。AppImageは固定依存preflight、GTK/WebKitGTK dependency closure、補助process再配置、AppDir生成まで実装し、不完全な閉包はfail-closedで拒否します。署名、clean target runtimeでのGUI起動、通常Windows GUI CI、macOSは未整備です。NSIS/MSI setupのWindows実機実行とToastの配布統合も未検証です。


## 目標

Niminoは次の4コンポーネントで構成します。

| コンポーネント | 役割 |
| --- | --- |
| `nimino-native` | Win32 + WebView2、GTK + WebKitGTKを直接利用する薄いWindow/WebView層 |
| `nimino-core` | アプリライフサイクル、RPC、プロファイル、ナビゲーション・権限ポリシーを提供するアプリ基盤 |
| `nimino-wsl` | WSLのNimプロセスとWindows GUIホストを認証付きIPCで接続するアダプター |
| `nimino-pack` | URLまたはマニフェストからアプリを生成するCLI |

初期ターゲットはWindows、ネイティブLinux、WSLです。macOS（Cocoa + WKWebView）は将来の拡張点として扱い、初期実装の対象外です。

## 設計原則

- WebViewラッパーや大型GUIフレームワークに依存せず、Win32/WebView2およびGTK/WebKitGTKへ直接接続します。
- `nimino-native`はWindow・WebView・低水準イベント・Capability照会に限定します。
- RPC、プロファイル、権限、ローカルアセット、ダウンロード、デスクトップ統合は`nimino-core`に置きます。
- WSLはGUIバックエンドではありません。WSL側アプリはWindows側の`nimino-wsl-host.exe`へ接続し、ホストがWindows GUIを所有します。
- URL包装と配布物生成は`nimino-pack`だけが担当し、`nimino-core`の公開APIだけを利用します。
- Chromiumをアプリに同梱せず、WindowsのWebView2 Evergreen RuntimeとLinuxのGTK/WebKitGTKはNiminoの`make setup`／固定Dockerイメージで準備します。利用者へ手動インストールを要求しません。

使用しないものには、`webview/webview`、Photino.Native、Tauri、Electron、WRY、TAO、CEF、Qt WebEngine、Sciter、およびNode.jsランタイムの必須化が含まれます。

## 開発環境

Nim、Nimble、Cコンパイラ、Linux向けのGTK/WebKitGTK開発ヘッダーは、ローカルには導入しません。すべてDocker開発コンテナで実行し、手順は`Makefile`へ固定します。

```bash
make help
make setup
```

主なターゲットは`make image`（image作成）、`make verify-env`（Nim/Nimble/GTK/WebKitGTK検証）、`make shell`（コンテナshell）、`make test`（単体テストとfake hostによるWSL core RPC）、`make linux-smoke`（native Linux GUI smoke）、`make core-linux-rpc-smoke`（core RPC同期往復）、`make core-linux-rpc-url-smoke`（core URLのdocument-start RPC実往復）、`make core-linux-rpc-async-smoke`（core RPC async/timeout実往復）、`make windows-cross`（Windows native x64クロスコンパイル）、`make core-windows-cross`（Windows core x64クロスコンパイル）、`make wsl-host-cross`（Windows WSL hostクロスコンパイル）、`make wsl-host-smoke`（host単体のWebView2実機確認）、`make wsl-host-abnormal-smoke`（client EOF時のhost終了確認）、`make wsl-host-popup-smoke`（WebView2新規Window要求と暗黙popup抑止の実機確認）、`make wsl-client-smoke`（通常WSL client APIでWindows hostを起動する実機確認）、`make wsl-core-smoke`（通常core APIでWindows hostを選ぶ実機確認）、`make wsl-core-rpc-url-smoke`（Windows WebView2上のWSL core URL document-start RPC実機確認）、`make wsl-core-rpc-async-smoke`（Windows WebView2上のWSL core async RPC/timeout実機確認）、`make clean`（Compose資源と一時成果物の削除）です。

Linux配布物は`make pack-linux-test`でDebian/RPM生成、Flatpak context、archive内容を、`make pack-flatpak-test`でGNOME Platform/SDK 49からOSTree経由の`.flatpak` exportをDocker内で検証します。`make pack-appimage-guardrails`は固定toolchain・GTK4/WebKitGTK6資産・静的dependency reportの検査と、不完全なAppImageが成果物を残さず明示的に失敗することを検証します。Flatpak smokeだけはbubblewrapのため専用privileged Compose serviceを使い、通常の開発serviceへ権限を広げません。

Popular Packagesは`catalog/popular-packages.json`を厳格に読み込む公開pack APIを持ちます。未検証artifactは登録せず、現時点の正式catalogは空です。登録時にはversion付きrelease URL、artifact/SBOMのSHA-256、生成commit/workflow/run IDをminisign署名へ結合し、別経路で信頼した公開鍵による検証を必須とします。

Windows配布物は`make pack-windows-test`でDocker内のNSISを使いper-user setup EXEをクロス生成します。setupのWindows実機でのinstall/uninstall/upgradeとcode signingは別途検証が必要です。

WSLの自動smokeは既定120秒でhostを回収します。環境に応じて`WSL_SMOKE_TIMEOUT=30 make wsl-host-popup-smoke`のように短縮できます。手動操作用`wsl-host-interactive`は既定300秒で、`WSL_INTERACTIVE_TIMEOUT=600 make wsl-host-interactive`のように延長できます。

GitHub Actionsの`.github/workflows/ci.yml`は、Docker内の`verify-env`、Nimble単体（protocol/core/WSL fake host）、pack、Linux GTK/WebKitGTK smoke、Windows x64 cross-buildをpush/PRごとに実行します。Windows WebView2のGUI実機smokeは、ログオン済みWindowsとWSL Interopを必要とするため、Actionsの`workflow_dispatch`で`run_wsl_gui=true`を明示し、`self-hosted,wsl2,windows-gui`ラベルのrunner上でのみ実行します。未選択の手動実行は成功扱いになりません。

### Windows WebView2/Interopのセットアップ

WSLから`powershell.exe`が`UtilBindVsockAnyPort: socket failed`で起動できない場合は、まずWindows Terminal（管理者）でInteropを再起動します。

```powershell
wsl --shutdown
Restart-Service LxssManager
wsl -d Ubuntu-22.04 -- bash -lc 'echo interop-ok'
```

`echo interop-ok`が成功した後、Windows PowerShellでWebView2 Evergreen Runtimeを導入します。RuntimeはDocker内のSDK DLLとは別物です。

```powershell
Set-ExecutionPolicy -Scope Process Bypass
& "$env:USERPROFILE\works\nimino\tools\ci\setup-windows-webview2.ps1"
```

リポジトリがWindows側にない場合は、WSLからWindows PowerShellを直接呼び出せます。

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File \
  "$(wslpath -w "$PWD/tools/ci/setup-windows-webview2.ps1")"
```

通常は`make setup`だけを実行してください。Docker内のNim/GTK/WebKitGTKと、WSL Interop経由でWindows WebView2 Evergreen Runtimeを順に準備し、必要なWebView2導入時だけUAC昇格を要求します。利用者がGTK/WebKitGTKやWebView2を個別に導入することは前提にしません。具体的な実行条件は、(1) WSL 2、(2) Windows Interop、(3) WindowsユーザーのGUIログオンです。これらを満たしたGUIセッションで`make wsl-host-popup-smoke`を実行します。WSLgの`DISPLAY`はLinux GUI用であり、Windows WebView2のRuntime/Win32 Windowの代替ではありません。

権限の扱いは次のとおりです。`make setup`はDocker内のNim/GTK/WebKitGTK検証と、Windows WebView2/Edge UpdateのためのUAC昇格を自動実行します。`make setup-windows-webview2`だけを直接呼ぶ場合もUAC昇格を自動要求します。`wsl-host-*` smoke、WSL client/core smoke、NSISのper-user生成、生成されたPowerShell install templateは管理者権限を要求しません。別ユーザーのhostを停止する`taskkill`は失敗しても無視します。

実行前チェックは次のとおりです。Windowsデスクトップへログオン済みであることは、GUI smokeを実行するための通常条件であり、追加の別セッションは不要です。

```bash
test -n "$WSL_INTEROP" && command -v powershell.exe && command -v cmd.exe
docker compose version
make setup
make wsl-host-cross
```

最後の`wsl-host-cross`で`.tmp/nimino-wsl-host.exe`と同じ場所に`WebView2Loader.dll`が配置されます。`make setup`が準備するWindows側Evergreen RuntimeとDocker内GTK/WebKitGTKに加え、WSL 2のディストリビューション、Docker daemon/Compose、Windows側への`wslpath`アクセスを、WSL smokeの実行時に自動検証します。`WSLg`のWayland/X11環境変数やLinux GPUドライバーは、Windows WebView2 hostの必須条件ではありません。PowerShellの直接実行例はInterop復旧や診断が必要な場合の手動フォールバックであり、通常の事前条件ではありません。

Linuxの実ネイティブスモークは`make linux-smoke`で実行します。これはDockerのnamespace制限を回避するため、そのテストコンテナだけでWebKit sandboxを無効にし、GIO notification request用にprivate D-Bus sessionを起動します。アプリの本番実行設定にはこの環境変数やテスト用sessionを含めません。

Dockerデーモンが利用できない環境では、コンテナ内ビルド・テストは実行できません。`make wsl-host-smoke`はWSL、Windows Interop、PowerShell、およびWindowsのWebView2 Evergreen Runtimeを必要とします。LoaderはDocker image内で固定SDKから取り出すため、ローカルのNim開発ツールやSDK導入は不要です。

## 現在の状態と次の段階

M0の責務境界、公開API案、所有権、イベントループ、WSL IPC、Capability、技術リスク、M1計画は文書化済みです。M1のWindow/WebView/URL/HTML/タイトル/終了、M2のJavaScript評価、文字列message、ナビゲーション開始/完了、基本エラー通知、新規Window要求を、Windows・Linux・WSLの共通API形状で実装しています。Windows/Linuxでは開始callbackが同期的に許可/中止を決めます。新規Windowは暗黙生成せず拒否します。WSL hostとclient間のpermission/download同期decision relayも実装済みで、タイムアウト時はdenyします。M3ではcore facadeがnative型を隠し、JSON RPCのみを明示登録します。M4のprofile pathとlocal asset root境界を追加済みです。WSL buildは`nimino-wsl` clientを選び、Linux GUI backendをリンク・起動しません。

- Linux: `make linux-smoke` が URL/HTML、JavaScript評価、文字列message、ナビゲーション開始/完了、WebKitWebsiteDataManagerによるCookie・localStorage・cache消去、GTK `GMenu`/`GSimpleAction` によるnative menubar設定、GIO `GNotification` のOS通知要求、明示解放を実行します。通知APIの成功はdesktop shellへ要求を渡せたことだけを示し、shell側の抑止・表示までは保証しません。`make core-linux-rpc-smoke` はcoreの`invoke → response → notification`を、`make core-linux-rpc-url-smoke`はURLの最初期scriptからのRPCを実行します。
- Windows: `make windows-cross` と `make core-windows-cross` が Win32/WebView2/native-core のx64 PEとCOM callback ABIを検査します。`make wsl-host-smoke` は導入済みRuntime上でWindows hostのHTML・URL読込、document-start script、navigation ruleによる拒否完了、タイトル・サイズ更新、JavaScript評価、message受信、終了を実行します。`make wsl-host-popup-smoke`はWebView2の`NewWindowRequested`通知を受信した後、明示的にWindow/WebViewを生成してpopup HTMLからのmessage受信まで確認し、暗黙popupを生成しないことも確認します。`make wsl-host-abnormal-smoke`はclient stdin EOF時のhost終了を確認します。通常のWindowsログオン環境で直接起動するnativeアプリのGUI smokeは、Actionsのself-hosted手動ジョブでのみ実行します。
- WSL: `make wsl-host-smoke`、`make wsl-client-smoke`、`make wsl-core-smoke` が認証、host起動、Window/WebView、shutdownを検証します。`make test`はfake hostでcoreのWebView event、非同期応答、timeout relayを検証し、`make wsl-core-rpc-url-smoke`と`make wsl-core-rpc-async-smoke`はそれぞれURL document-start RPC、async/timeoutをWindows WebView2 Runtime上で実行します。

URLのRPC bridgeはViewが`pending`の間の最初の対象`loadUrl`前に登録し、HTTP(S)は初回URLと同一origin、`data:`は完全一致のURLだけで初期化します。`about:`を含むほかのschemeと後続の別originではRPCを公開しません。WSL経路のpermission/download/navigation relay、型付きRPC、profile/Cookie同期、外部ナビゲーション、ローカル・明示許可リモートasset、OSファイルダイアログ処理まで実装済みです。`registerTyped*`のTypeScript宣言はrecord object、入れ子object、`seq`/固定array、`Option`、基本型、enumをinline型へ抽出し、それ以外は`unknown`へ後退します。WebView内部custom protocolはWindows/Linux nativeとWSL relayを実装済みです。Windows WinRT Toast表示とプロセス内Activated通知も実装済みですが、AppUserModelId/Start Menu shortcut/COM activatorを含む署名済み配布統合と実Windows GUI表示は未検証です。AppImage dependency closureとFlatpak実bundle exportはDockerハーネスで実装・検証済みですが、署名と配布先runtimeでの起動検証は未完了です。macOSは未実装です。Windows GUI実機smokeはself-hosted手動ジョブが実行条件です。

### 追加ゴール: 初心者向け配布導線

PakeのPopular Packages／Online Buildingに相当する導線を`nimino-pack`へ追加します。GitHub Actionsの`workflow_dispatch`から固定Docker toolchainで汎用`nimino-host`をビルドし、URLからbundleとDebian/RPM/NSIS artifact、checksum、SBOMを生成するオンラインビルドを実装済みです。利用者のローカルへNim、Nimble、Dockerを要求しません。checksum・署名・生成元を厳格に検証するPopular Packages APIと空の正式catalogも実装済みで、署名済みreleaseだけを登録します。仕様と受け入れ条件は[ADR 0018](docs/adr/0018-pack-online-build-and-popular-catalog.md)に記録しています。未実装形式をworkflowが成功扱いしないことも要件です。

## 文書

- [アーキテクチャ](ARCHITECTURE.md)
- [アーキテクチャ詳細](docs/architecture/)
- [Architecture Decision Records](docs/adr/)
- [公開API案](docs/api/)

設計文書と実装状況は区別しています。将来の実装は、記録済みの前提を満たすかをテストで確認してから進めます。

## ライセンス

[MIT](LICENSE)
