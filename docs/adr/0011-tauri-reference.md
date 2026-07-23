# ADR 0011: Tauriを実装比較用の参照プロジェクトとして保持する

## 状態

採用

## 決定

公式Tauriリポジトリを`reference/tauri`へ浅いcloneし、Niminoの実装前に同等機能の制御方式を確認する。

WebサイトをTauriアプリとしてラップして配布するPake（`tw93/Pake`）も`reference/pake`へ浅いcloneし、`nimino-pack`のURL包装、マニフェスト、ビルド、配布制御の比較対象とする。

参照コードは調査用であり、Niminoのビルド依存・実行時依存・公開API依存にはしない。`reference/tauri/`と`reference/pake/`は`.gitignore`で除外し、リポジトリ本体へ取り込まない。

各機能の実装前に、Tauri側の該当コード、境界条件、エラー処理、ライフサイクル制御を確認し、Nimino側の設計判断を記録する。Tauriの抽象化をそのまま移植せず、Niminoの責務分離（native/core/wsl/pack）に合わせて必要な制御だけを再設計する。

## 確認対象

- Window/WebViewの生成・破棄とイベントループ
- ナビゲーション、外部URL、新規Window要求
- 権限・ダウンロード要求の許可判定
- IPCのrequest/response、エラー、タイムアウト
- ネイティブ資源の所有権と解放順序
- PakeのURL包装、設定、アイコン、ビルド・配布フロー

## 初回確認結果（2026-07-18）

Tauriのruntime層では、`RunEvent`を`WindowEvent`と`WebviewEvent`に分離し、`ExitRequested`で終了を抑止できる。WebView生成前の`PendingWebview`に、ナビゲーション・新規Window・ダウンロードの各ハンドラーを個別に保持している（`crates/tauri-runtime/src/lib.rs`、`crates/tauri-runtime/src/webview.rs`）。この分離はNiminoのWindow/WebView別型と、未処理要求を拒否する方針の根拠とする。

IPC権限は`crates/tauri/src/ipc/authority.rs`でmanifestのpermission setを再帰的に解決し、明示的denyをallowより先に評価している。NiminoでもRPC許可リストとURL・権限ポリシーを別レイヤーで評価し、未登録メソッドは拒否する。

Tauriの実装はNiminoの依存として取り込まず、上記の制御上の知見だけを採用する。各M1以降の変更では、対象TauriファイルとNimino側の対応箇所をレビュー記録へ追記する。

## 運用

参照リポジトリを更新した場合は、取得日時と対象revisionを実装記録または作業報告へ記載する。Tauriのコードを依存として追加する場合は、このADRを改訂し、ライセンスと責務境界を再確認する。

## macOS実装への反映（2026-07-22）

`reference/tauri/crates/tauri-runtime-wry/src/window/macos.rs`、`webview.rs`と、`reference/pake/src-tauri/src/app/window.rs`、`src/app/setup.rs`を確認した。Tauriのmain-thread所有、WKWebView delegate、document-start script、custom scheme、new-window policyの分離を採用し、PakeのmacOS固有処理がTauriへ委譲される境界も確認した。

NiminoではこれをCocoa/WebKitの小さなObjective-C bridge（`packages/native/src/nimino_native/private/macos/bridge.m`）とNim backendへ再設計した。Cocoa資源の破棄はWebKit callback中に行わず、AppKit run loop終了後に行う。NSStatusItem、`UNUserNotificationCenter`、NSApplication openURLs、WKWebKit media permission/download delegate、profile別`WKWebsiteDataStore`も同じbridge境界に接続し、`nimino-pack`はURL scheme付き`Info.plist`を含む`.app`と`hdiutil`による`.dmg`を生成する。codesignは`--sign-identity`指定時だけ実行し、実行時にverify/assessまで行う。notarization送信は資格情報を伴うrelease工程としてCLIの自動処理から分離する。

追加監査では、PakeのmacOS固有設定に対応してDock再表示、`hide_title_bar`のtitle-bar overlay、macOS 14+のNetwork.framework proxy、camera/microphone entitlementを実装した。proxyを指定したbundleは`LSMinimumSystemVersion=14.0`とし、macOSが対応しないproxy schemeはpackaging時に明示的に拒否する。検証は`nimble testMacosSmoke`と`tools/ci/test_pack_macos.sh`で行う。
