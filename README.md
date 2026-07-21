# Nimino

Nimをホスト言語に、OS公式APIの薄いFFIでネイティブWindowとWebViewを扱う、軽量なクロスプラットフォームWeb UIデスクトップアプリケーション基盤です。

> M0〜M4のprofile、local asset境界、navigation/permission/download policy、Windows tray/notification、Linux GTK menubar/notification、Windows/GTK/WSLのOSファイルダイアログを実装済みです。`nimino-pack`はLinux desktop entry、Debian/RPM archive、amd64 AppImage、Windowsのper-user NSIS setup、CycloneDX SBOM、PowerShell templateを生成します。署名済みMSI、Flatpak、通常Windows GUI CI、macOS、toast activationは未整備です。AppImageのGTK/WebKitGTK依存ライブラリ同梱と署名、NSIS setupのWindows実機実行は未検証です。


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
- Chromiumをアプリに同梱せず、WindowsではWebView2 Evergreen Runtime、LinuxではシステムのWebKitGTKを前提にします。

使用しないものには、`webview/webview`、Photino.Native、Tauri、Electron、WRY、TAO、CEF、Qt WebEngine、Sciter、およびNode.jsランタイムの必須化が含まれます。

## 開発環境

Nim、Nimble、Cコンパイラ、Linux向けのGTK/WebKitGTK開発ヘッダーは、ローカルには導入しません。すべてDocker開発コンテナで実行し、手順は`Makefile`へ固定します。

```bash
make help
make verify-env
```

主なターゲットは`make image`（image作成）、`make verify-env`（Nim/Nimble/GTK/WebKitGTK検証）、`make shell`（コンテナshell）、`make test`（単体テストとfake hostによるWSL core RPC）、`make linux-smoke`（native Linux GUI smoke）、`make core-linux-rpc-smoke`（core RPC同期往復）、`make core-linux-rpc-url-smoke`（core URLのdocument-start RPC実往復）、`make core-linux-rpc-async-smoke`（core RPC async/timeout実往復）、`make windows-cross`（Windows native x64クロスコンパイル）、`make core-windows-cross`（Windows core x64クロスコンパイル）、`make wsl-host-cross`（Windows WSL hostクロスコンパイル）、`make wsl-host-smoke`（host単体のWebView2実機確認）、`make wsl-host-abnormal-smoke`（client EOF時のhost終了確認）、`make wsl-host-popup-smoke`（WebView2新規Window要求と暗黙popup抑止の実機確認）、`make wsl-client-smoke`（通常WSL client APIでWindows hostを起動する実機確認）、`make wsl-core-smoke`（通常core APIでWindows hostを選ぶ実機確認）、`make wsl-core-rpc-url-smoke`（Windows WebView2上のWSL core URL document-start RPC実機確認）、`make wsl-core-rpc-async-smoke`（Windows WebView2上のWSL core async RPC/timeout実機確認）、`make clean`（Compose資源と一時成果物の削除）です。

Linux配布物は`make pack-linux-test`でDebian/RPM/AppImageの生成、archive内容、AppImageの自己展開・起動器をDocker内で検証します。

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

このWindows側セットアップはWSL開発環境の事前条件です。具体的には、(1) WSL 2、(2) Windows Interop、(3) WebView2 Evergreen Runtime、(4) WindowsユーザーのGUIログオンを満たしてから、WindowsにユーザーとしてログオンしたGUIセッションで`make wsl-host-popup-smoke`を実行します。WSLgの`DISPLAY`はLinux GUI用であり、Windows WebView2のRuntime/Win32 Windowの代替ではありません。

権限の扱いは次のとおりです。`make setup-windows-webview2`だけはWebView2/Edge UpdateのためUAC昇格を自動要求します。`wsl-host-*` smoke、WSL client/core smoke、NSISのper-user生成、生成されたPowerShell install templateは管理者権限を要求しません。別ユーザーのhostを停止する`taskkill`は失敗しても無視します。

実行前チェックは次のとおりです。Windowsデスクトップへログオン済みであることは、GUI smokeを実行するための通常条件であり、追加の別セッションは不要です。

```bash
test -n "$WSL_INTEROP" && command -v powershell.exe && command -v cmd.exe
docker compose version
make verify-env
make wsl-host-cross
```

最後の`wsl-host-cross`で`.tmp/nimino-wsl-host.exe`と同じ場所に`WebView2Loader.dll`が配置されます。`make setup-windows-webview2`で導入したWindows側Evergreen Runtime、WSL 2のディストリビューション、Docker daemon/Compose、Windows側への`wslpath`アクセスが、WSL smokeの実行事前条件です。`WSLg`のWayland/X11環境変数やLinux GPUドライバーは、Windows WebView2 hostの必須条件ではありません。

Linuxの実ネイティブスモークは`make linux-smoke`で実行します。これはDockerのnamespace制限を回避するため、そのテストコンテナだけでWebKit sandboxを無効にし、GIO notification request用にprivate D-Bus sessionを起動します。アプリの本番実行設定にはこの環境変数やテスト用sessionを含めません。

Dockerデーモンが利用できない環境では、コンテナ内ビルド・テストは実行できません。`make wsl-host-smoke`はWSL、Windows Interop、PowerShell、およびWindowsのWebView2 Evergreen Runtimeを必要とします。LoaderはDocker image内で固定SDKから取り出すため、ローカルのNim開発ツールやSDK導入は不要です。

## 現在の状態と次の段階

M0の責務境界、公開API案、所有権、イベントループ、WSL IPC、Capability、技術リスク、M1計画は文書化済みです。M1のWindow/WebView/URL/HTML/タイトル/終了、M2のJavaScript評価、文字列message、ナビゲーション開始/完了、基本エラー通知、新規Window要求を、Windows・Linux・WSLの共通API形状で実装しています。Windows/Linuxでは開始callbackが同期的に許可/中止を決めます。新規Windowは暗黙生成せず拒否します。WSL hostとclient間のpermission/download同期decision relayも実装済みで、タイムアウト時はdenyします。M3ではcore facadeがnative型を隠し、JSON RPCのみを明示登録します。M4のprofile pathとlocal asset root境界を追加済みです。WSL buildは`nimino-wsl` clientを選び、Linux GUI backendをリンク・起動しません。

- Linux: `make linux-smoke` が URL/HTML、JavaScript評価、文字列message、ナビゲーション開始/完了、WebKitWebsiteDataManagerによるCookie・localStorage・cache消去、GTK `GMenu`/`GSimpleAction` によるnative menubar設定、GIO `GNotification` のOS通知要求、明示解放を実行します。通知APIの成功はdesktop shellへ要求を渡せたことだけを示し、shell側の抑止・表示までは保証しません。`make core-linux-rpc-smoke` はcoreの`invoke → response → notification`を、`make core-linux-rpc-url-smoke`はURLの最初期scriptからのRPCを実行します。
- Windows: `make windows-cross` と `make core-windows-cross` が Win32/WebView2/native-core のx64 PEとCOM callback ABIを検査します。`make wsl-host-smoke` は導入済みRuntime上でWindows hostのHTML・URL読込、document-start script、navigation ruleによる拒否完了、タイトル・サイズ更新、JavaScript評価、message受信、終了を実行します。`make wsl-host-popup-smoke`はWebView2の`NewWindowRequested`通知を受信した後、明示的にWindow/WebViewを生成してpopup HTMLからのmessage受信まで確認し、暗黙popupを生成しないことも確認します。`make wsl-host-abnormal-smoke`はclient stdin EOF時のhost終了を確認します。通常のWindowsログオン環境で直接起動するnativeアプリのGUI smokeは、Actionsのself-hosted手動ジョブでのみ実行します。
- WSL: `make wsl-host-smoke`、`make wsl-client-smoke`、`make wsl-core-smoke` が認証、host起動、Window/WebView、shutdownを検証します。`make test`はfake hostでcoreのWebView event、非同期応答、timeout relayを検証し、`make wsl-core-rpc-url-smoke`と`make wsl-core-rpc-async-smoke`はそれぞれURL document-start RPC、async/timeoutをWindows WebView2 Runtime上で実行します。

URLのRPC bridgeはViewが`pending`の間の最初の対象`loadUrl`前に登録し、HTTP(S)は初回URLと同一origin、`data:`は完全一致のURLだけで初期化します。`about:`を含むほかのschemeと後続の別originではRPCを公開しません。WSL経路のpermission/download/navigation relay、型付きRPC、profile/Cookie同期、外部ナビゲーション、ローカル・明示許可リモートasset、OSファイルダイアログ処理まで実装済みです。`registerTyped*`のTypeScript宣言はrecord object、入れ子object、`seq`/固定array、`Option`、基本型、enumをinline型へ抽出し、それ以外は`unknown`へ後退します。残る大項目はWindows toast activation、署名済み配布物、AppImage依存ライブラリ同梱、Flatpak、macOSです。Windows GUI実機smokeはself-hosted手動ジョブが実行条件です。

## 文書

- [アーキテクチャ](ARCHITECTURE.md)
- [アーキテクチャ詳細](docs/architecture/)
- [Architecture Decision Records](docs/adr/)
- [公開API案](docs/api/)

設計文書と実装状況は区別しています。将来の実装は、記録済みの前提を満たすかをテストで確認してから進めます。

## ライセンス

[MIT](LICENSE)
