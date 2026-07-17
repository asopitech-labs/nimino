# 技術リスクとスパイク登録簿

**状態: M0記録。M1/M2で判明した未解消項目を継続追跡中。**

| ID | リスク/未確定事項 | 影響 | 解消スパイク・ゲート |
| --- | --- | --- | --- |
| R1 | NimによるWebView2 COM vtable/callback ABIの誤り | Windows crash/参照リーク | 固定SDK header/IDLを基にEnvironment→Controller→Closeを検証する最小FFI |
| R2 | WebView2 Evergreen Runtimeが未導入/更新中 | Window作成不能 | `HRESULT`を`webViewError`へ変換し、Runtimeを同梱せず未導入テストを追加 |
| R3 | GTK 3 APIとWebKitGTK 6.0の混在 | Linux build/runtime不整合 | GTK 4 + WebKitGTK 6.0を固定し、Dockerの`pkg-config`検証をM1 gateにする |
| R4 | GObject浮動参照・signal contextの解放漏れ | use-after-free/リーク | `g_object_ref_sink`、handler ID、`g_signal_connect_data` destroy notifierを最小例で検証 |
| R5 | WebView2/GTK UI loopとNim asyncの競合 | deadlock/UI freeze | Windows timer/GLib idleでbounded poll、worker→UI queue、長時間処理テスト |
| R6 | WSL2 NAT/mirrored network差 | hostへの接続不能/外部公開 | M1はネットワークを使わず継承stdioを使う。TCPは後続スパイクのみ |
| R7 | Windows Interop/パイプの制約 | WSL hostを起動できない | WSL2実機でspawn、token handshake、EOF、異常終了を確認 |
| R8 | Docker Linux imageのWebKitGTK 6.0 package availability | Linux開発環境を再現できない | compose buildと`pkg-config`を実行。失敗時は画像タグ/apt sourceをADR更新して変更理由を記録 |
| R9 | Windows用Docker開発imageのSDK/ヘッダー取得 | Windows M1をDockerだけでbuildできない | Windows daemon上でcontainerized Nim + SDK headerのスパイク。ローカルNim導入はしない |
| R10 | `Result`/asyncdispatch APIのNim 2.x差 | 公開APIのコンパイル不能 | `std/results`がNim 2.2.10にないことを確認済み。外部依存を増やさず独自`NativeResult`/`NativeResultOf[T]`をARCでスパイク済み。asyncdispatchは別途確認 |
| R11 | WebKit process swap後にbackendが無効な内部状態を保持 | Linux不安定 | Web process pointerを公開/保持せず、WebViewのみに操作を閉じる |
| R12 | WSL client上の任意ナビゲーションpolicyを、Windows UI callback時に評価するとUI待機・nested loop・IPC deadlockを招く | coreのURL制御をWSLで透過提供できない | [ADR-0005提案](../adr/0005-wsl-navigation-policy.md)の双方向decision protocolまたはhost適用可能な宣言的ruleのスパイク。任意callbackを既定許可へ偽装しない |

## 依存方針

M0でアプリ依存は追加しません。Linux開発コンテナに入るGTK 4/WebKitGTK 6.0はOS公式パッケージであり、Nim公開APIの依存ではありません。Nim Docker imageはNim公式サイトが案内する`nimlang/nim`を使いますが、community-managed imageであることを認識し、M1前にdigestをCI設定へ固定します。

ライセンスと保守状況を記録せずに、Nim packageまたはnative SDKを追加しません。既存の汎用WebView wrapperは依存候補にしません。
