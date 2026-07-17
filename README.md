# Nimino

Nimをホスト言語に、OS公式APIの薄いFFIでネイティブWindowとWebViewを扱う、軽量なクロスプラットフォームWeb UIデスクトップアプリケーション基盤です。

> M0（調査・設計）は完了し、M2とM3を部分実装中です。Linux GTK 4/WebKitGTK 6.0ではWindow/WebView、URL/HTML、JavaScript評価、文字列message、ナビゲーション開始/完了、基本エラー通知をXvfb smokeで確認済みです。`nimino-core`はWindows/Linux向けApp/Window facade、明示許可リストJSON RPC、型付き`registerTyped`/`registerTypedAsync`を実装し、Linuxで同期往復に加えて非同期Future完了とtimeout responseを実WebViewで確認しました。WSL向けcore build（`-d:niminoWsl`）はLinux GUI FFIをリンクせず、通常の`newApp`からWindows hostを起動してWindow/WebView setup・shutdownまで実機確認済みです。新規Window要求はWindows/Linuxで明示拒否しWSL hostがeventを中継しますが、実ユーザー操作による要求eventはGUI CIで未確認です。Windowsは同じnative/core機能のWin32/WebView2 direct FFIとx64クロスコンパイル済みです。現在の開発機にはWebView2 Loader/Runtimeがないため、Windows/WSLでの実WebView表示、JavaScript評価、message受信、ナビゲーションeventは未検証です。WSL側で任意のナビゲーション開始callbackによる同期中止、WSLのasync/timeout実行、パッケージ生成は未実装です。

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

主なターゲットは`make image`（image作成）、`make verify-env`（Nim/Nimble/GTK/WebKitGTK検証）、`make shell`（コンテナshell）、`make test`（単体テストとfake hostによるWSL core RPC）、`make linux-smoke`（native Linux GUI smoke）、`make core-linux-rpc-smoke`（core RPC同期往復）、`make core-linux-rpc-async-smoke`（core RPC async/timeout実往復）、`make windows-cross`（Windows native x64クロスコンパイル）、`make core-windows-cross`（Windows core x64クロスコンパイル）、`make wsl-host-cross`（Windows WSL hostクロスコンパイル）、`make wsl-host-smoke`（host単体の認証・Window/WebView・shutdown実機確認）、`make wsl-client-smoke`（通常WSL client APIでWindows hostを起動する実機確認）、`make wsl-core-smoke`（通常core APIでWindows hostを選ぶ実機確認）、`make clean`（Compose資源と一時成果物の削除）です。

Linuxの実ネイティブスモークは`make linux-smoke`で実行します。これはDockerのnamespace制限を回避するため、そのテストコンテナだけでWebKit sandboxを無効にします。アプリの本番実行設定にはこの環境変数を含めません。

Dockerデーモンが利用できない環境では、コンテナ内ビルド・テストは実行できません。`make wsl-host-smoke`はWSLとWindows Interop、PowerShellを必要とします。WebView2 Runtimeを含むWindowsの実GUI確認はWindows CIまたはWindows開発機で行います。

## 現在の状態と次の段階

M0の責務境界、公開API案、所有権、イベントループ、WSL IPC、Capability、技術リスク、M1計画は文書化済みです。M1のWindow/WebView/URL/HTML/タイトル/終了、M2のJavaScript評価、文字列message、ナビゲーション開始/完了、基本エラー通知、新規Window要求を、Windows・Linux・WSLの共通API形状で実装しています。Windows/Linuxでは開始callbackが同期的に許可/中止を決めます。新規Windowは暗黙生成せず拒否します。WSL hostは開始/error/new-window eventを中継しますが、WSL client側による同期判定は未実装です。M3ではcore facadeがnative型を隠し、JSON RPCのみを明示登録する。WSL buildは`nimino-wsl` clientを選び、Linux GUI backendをリンク・起動しない。

- Linux: `make linux-smoke` が URL/HTML、JavaScript評価、文字列message、ナビゲーション開始/完了、明示解放を実行します。`make core-linux-rpc-smoke` はcoreの`invoke → response → notification`を実行します。
- Windows: `make windows-cross` と `make core-windows-cross` が Win32/WebView2/native-core のx64 PEとCOM callback ABIを検査します。WebView2 Runtimeを備えた実機実行は未検証です。
- WSL: `make wsl-host-smoke`、`make wsl-client-smoke`、`make wsl-core-smoke` が認証、host起動、Window/WebView、shutdownを検証します。`make test`はfake hostでcoreのWebView event/RPC response relayを検証します。Windows Runtimeを要するURL/HTML後の評価/message往復は未検証です。

次はWindows/WSLでのRPC async/timeout実行、URL向けdocument-start bridge、WSLナビゲーション制御スパイクです。型抽出マクロ、プロファイル、権限、パッケージングは未実装です。

## 文書

- [アーキテクチャ](ARCHITECTURE.md)
- [アーキテクチャ詳細](docs/architecture/)
- [Architecture Decision Records](docs/adr/)
- [公開API案](docs/api/)

設計文書と実装状況は区別しています。将来の実装は、記録済みの前提を満たすかをテストで確認してから進めます。

## ライセンス

[MIT](LICENSE)
