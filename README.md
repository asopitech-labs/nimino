# Nimino

Nimをホスト言語に、OS公式APIの薄いFFIでネイティブWindowとWebViewを扱う、軽量なクロスプラットフォームWeb UIデスクトップアプリケーション基盤です。

> M0（調査・設計）は完了し、M1を実装中です。エラー分類・結果値・Capability、WSL IPCのframe/token/protocol codecとclient Stream transportの単体テスト、Linux GTK 4/WebKitGTK 6.0の最小Window/WebView/URL/終了経路は実装済みです。Windows native backend、WSL host、RPC、パッケージ生成は未実装です。

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

主なターゲットは`make image`（image作成）、`make verify-env`（Nim/Nimble/GTK/WebKitGTK検証）、`make shell`（コンテナshell）、`make test`（M1以降のNimbleテスト）、`make clean`（Compose資源の停止・削除）です。`nimble test`は、M1で`nimino.nimble`とテストを追加してから実行します。

Linuxの実ネイティブスモークは`make linux-smoke`で実行します。これはDockerのnamespace制限を回避するため、そのテストコンテナだけでWebKit sandboxを無効にします。アプリの本番実行設定にはこの環境変数を含めません。

Dockerデーモンが利用できない環境では、コンテナ内ビルド・テストは実行できません。WindowsのWin32/WebView2実行確認とWSL統合確認はWindows CIまたはWindows開発機で行います。

## 現在の状態と次の段階

M0では責務境界、公開API案、所有権、イベントループ、WSL IPC、Capability、技術リスク、M1計画を文書化します。M1ではWindows・Linux・WSLを機能単位で並行させ、次だけを実装対象にします。

1. Window生成
2. WebView生成とWindow内配置
3. URL読込
4. リサイズとタイトル変更
5. 正常終了
6. WSLからのWindowsホスト起動・Window作成・URL読込・終了

M1でJavaScriptメッセージ、RPC、プロファイル、パッケージングは実装しません。

## 文書

- [アーキテクチャ](ARCHITECTURE.md)
- [アーキテクチャ詳細](docs/architecture/)
- [Architecture Decision Records](docs/adr/)
- [公開API案](docs/api/)

これらの文書はM0の成果物です。将来の実装は、記録済みの前提を満たすかをテストで確認してから進めます。

## ライセンス

[MIT](LICENSE)
