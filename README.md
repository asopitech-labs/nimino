# Nimino

Nimをホスト言語に、OS公式APIの薄いFFIでネイティブWindowとWebViewを扱う、軽量なクロスプラットフォームWeb UIデスクトップアプリケーション基盤です。

> M0（調査・設計）は完了し、M2を部分実装中です。Linux GTK 4/WebKitGTK 6.0ではWindow/WebView、URL/HTML、JavaScript評価、文字列messageをXvfb smokeで確認済みです。Windowsは同じ機能のWin32/WebView2 direct FFIとx64クロスコンパイル、WSLは認証済みWindows hostの実機stdio smoke（Window/WebView作成とshutdown）とM2 adapter/unit contractまで確認済みです。現在の開発機にはWebView2 Loader/Runtimeがないため、Windows/WSLでの実WebView表示、JavaScript評価、message受信は未検証です。`nimino-core`、RPC、パッケージ生成は未実装です。

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

主なターゲットは`make image`（image作成）、`make verify-env`（Nim/Nimble/GTK/WebKitGTK検証）、`make shell`（コンテナshell）、`make test`（単体テスト）、`make windows-cross`（Windows native x64クロスコンパイル）、`make wsl-host-cross`（Windows WSL hostクロスコンパイル）、`make wsl-host-smoke`（host単体の認証・Window/WebView・shutdown実機確認）、`make wsl-client-smoke`（通常WSL client APIでWindows hostを起動する実機確認）、`make linux-smoke`（Linux GUI smoke）、`make clean`（Compose資源と一時成果物の削除）です。

Linuxの実ネイティブスモークは`make linux-smoke`で実行します。これはDockerのnamespace制限を回避するため、そのテストコンテナだけでWebKit sandboxを無効にします。アプリの本番実行設定にはこの環境変数を含めません。

Dockerデーモンが利用できない環境では、コンテナ内ビルド・テストは実行できません。`make wsl-host-smoke`はWSLとWindows Interop、PowerShellを必要とします。WebView2 Runtimeを含むWindowsの実GUI確認はWindows CIまたはWindows開発機で行います。

## 現在の状態と次の段階

M0の責務境界、公開API案、所有権、イベントループ、WSL IPC、Capability、技術リスク、M1計画は文書化済みです。M1のWindow/WebView/URL/HTML/タイトル/終了、M2のJavaScript評価と文字列messageを、Windows・Linux・WSLの共通API形状で実装しています。

- Linux: `make linux-smoke` が URL/HTML、JavaScript評価、文字列message、明示解放を実行します。
- Windows: `make windows-cross` が Win32/WebView2 のx64 PEとCOM callback ABIを検査します。WebView2 Runtimeを備えた実機実行は未検証です。
- WSL: `make wsl-host-smoke` と `make wsl-client-smoke` が認証、host起動、Window/WebView、shutdownを検証します。Windows Runtimeを要するURL/HTML後の評価/message往復は未検証です。

次はM2のnavigation/new-window/load event、続いてM3の`nimino-core` lifecycleと明示許可リスト型付きRPCです。プロファイル、権限、パッケージングは未実装です。

## 文書

- [アーキテクチャ](ARCHITECTURE.md)
- [アーキテクチャ詳細](docs/architecture/)
- [Architecture Decision Records](docs/adr/)
- [公開API案](docs/api/)

設計文書と実装状況は区別しています。将来の実装は、記録済みの前提を満たすかをテストで確認してから進めます。

## ライセンス

[MIT](LICENSE)
