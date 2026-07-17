# Nimino Architecture

**状態: M0完了、M1実装とM2（JavaScript評価・文字列message・ナビゲーション開始/完了・基本エラー通知・新規Window拒否）を部分実装中（2026-07-17）**

Niminoは、NimアプリケーションがOS固有のWindow、WebView、またはWSL通信を直接意識せずにWeb UIを構築できるようにするモノレポです。レンダリングエンジンや汎用WebViewラッパーは実装・導入しません。

## コンポーネント境界

| コンポーネント | 所有する責務 | 所有しない責務 |
| --- | --- | --- |
| `nimino-native` | Appイベントループ、Window、WebView、低水準イベント、Capability、ネイティブ資源の明示解放 | RPC、プロファイル、権限ポリシー、アセット配信、URL包装、WSL通信 |
| `nimino-core` | アプリ/Window管理、型付きRPC、プロファイル、セッション、ポリシー、ローカルアセット、デスクトップ機能 | WebViewのFFI、URL包装、WSLプロトコル本体 |
| `nimino-wsl` | Windows GUIホストの起動、認証済みIPC、プロトコル、ホストのライフサイクル | Linux GUI、WebView実装、アプリ固有RPC |
| `nimino-pack` | URL/manifest解析、配布物生成、インストーラー/desktop entry生成 | WebView、RPC、Window、OS別WebView処理 |

```text
Application
    |
    +-- nimino-core ------------------------+-- nimino-native
    |                                       |       +-- Win32 + WebView2
    |                                       |       `-- GTK 4 + WebKitGTK 6.0
    `-- nimino-wsl client -- stdio IPC -- nimino-wsl-host.exe
                                                  `-- nimino-native (Windows)

URL / manifest -- nimino-pack -- nimino-core public API -- nimino-native
```

`nimino-wsl-host.exe`はWindowsのGUI資源を所有します。WSL側はGUIバックエンドではなく、ホストのプロキシです。M1ではホストが`nimino-native`を直接利用し、`nimino-core`実装後に同じ操作をcore adapterへ移します。

## 対象プラットフォーム

| ターゲット | Window/WebView | M0の決定 | M1状態 |
| --- | --- | --- | --- |
| Windows | Win32 + WebView2 Evergreen Runtime | Win32 COM APIを直接FFIする | M1/M2をx64クロスコンパイル済み。Loader/Runtime不足のため実GUI未検証 |
| Linux | GTK 4 + WebKitGTK 6.0 + libsoup 3 | GTK 3 / WebKitGTK 4.1との混在を許容しない | M1とM2評価/message/navigation開始/完了/errorをXvfb実行済み |
| WSL | WSL Nim client + Windows host | 継承stdin/stdoutによる認証付きIPC | host/client smoke済み。M2 request/event adapter実装済み。開始/new-window eventは中継するがWSL側の同期中止は未実装 |
| macOS | Cocoa + WKWebView | 将来のprivate backendのみ。共通APIへ固有要件を入れない | 対象外 |

## 公開面とエラー

`NativeApp`、`NativeWindow`、`NativeWebView`は別型です。Windowは複数のWebViewを所有でき、M1が一つだけを配置しても型を一対一へ固定しません。

低水準操作の結果は、少なくとも次を区別する`NativeErrorKind`で返します。

```text
success / unsupported / invalidState / permissionDenied / osError / webViewError
```

OS固有のHRESULT、Win32 error、`GError`はprivate backendでこの共通エラーへ正規化し、詳細な数値・メッセージを診断用フィールドとして保持します。未対応を成功や無視として扱いません。公開APIの詳細案は[Native API](docs/api/nimino-native.md)および[Core API](docs/api/nimino-core.md)にあります。

## Capability

初期の共通Capabilityは次です。バックエンドは実装済みかつ実行時に利用可能なものだけを`true`として返します。

```nim
type Capability* = enum
  multipleWebViews, transparentWindow, nativeMenu, systemTray,
  nativeNotification, customProtocol, webPermissionEvents
```

M1では`multipleWebViews`だけを実装候補とし、残りは明示的に`false`または`unsupported`です。Capabilityが`true`でも、権限または現在の状態による失敗は別途結果で返します。

## 所有権とスレッド

```text
NativeApp (明示 close)
  owns NativeWindow 0..n (明示 close)
    owns NativeWebView 0..n (明示 close)
      owns platform controller/view and callback registrations
```

- 各オブジェクトは`pending`、`ready`、`closing`、`closed`の状態を持ち、`close`はUIスレッドで一度だけ実行します。
- NimのGC/ARC/ORCはNimメモリの回収だけに使用し、COM参照、GObject参照、イベント登録、OS handleの解放トリガーにしません。
- WindowsではApp UIスレッドがSTA COMを初期化し、すべてのWebView2 API・callback・`Release`をそのスレッドで実行します。
- LinuxではGTK/GLib default main contextを所有するスレッドだけがGTK widgetとWebKitWebViewを操作します。
- バックグラウンド処理は`postToUi`でUIキューへ投入します。UIスレッドは待機、同期RPC、ネストしたイベントループで塞ぎません。
- WSL clientが保持するのは不透明なIDだけです。`HWND`、COM pointer、GObject pointerはIPCを越えません。
- Windows/Linuxのnative navigation-starting callbackは同期的に許可/中止を決める。WSL clientの任意callbackを同じ時点で評価する方式は、UI threadを待機・ネストloopで塞がない設計を要するため、[ADR-0005提案](docs/adr/0005-wsl-navigation-policy.md)のスパイク完了まで公開policyに昇格させない。

詳しい終了順序とasync統合は[ADR-0002](docs/adr/0002-ui-loop-and-native-lifetime.md)、メモリ方式は[ADR-0004](docs/adr/0004-arc-and-explicit-native-release.md)を参照してください。

## セキュリティ境界

- `nimino-native`は文字列メッセージを運ぶだけで、Nim関数・OS APIをWebへ公開しません。
- `nimino-core`のRPCはWindow単位の許可リストを必要とし、M3でリクエストID、タイムアウト、キャンセル、JSONエラーを実装します。
- ナビゲーション、権限、外部URL、ダウンロードはcoreの明示ポリシーで扱い、未処理要求は許可しません。
- WSL hostはネットワークlistenerを開かず、起動元clientへ継承された標準入出力だけを制御面に使用します。token、cookie、認証情報をログへ出しません。
- ローカルアセットはM4で正規化済みパスをアセットrootの配下に限定し、パストラバーサルを拒否します。

## リポジトリ配置

M1/M2では`native`と`wsl`を実装済みです。`core`と`pack`は、実用機能を偽装する空実装を避けるためまだ作成していません。最終配置は次です。

```text
packages/
  native/{nimino_native.nim,src/nimino_native/{app,window,webview,events,capabilities,errors,private/}}
  core/{nimino_core.nim,src/nimino_core/}
  wsl/{nimino_wsl.nim,src/nimino_wsl/{client,host,protocol}/}
  pack/{nimino_pack.nim,src/nimino_pack/}
examples/{native-minimal,core-local-app,core-remote-url,core-rpc,wsl-minimal,pack-example}/
tests/{integration,smoke}/
docs/{architecture,adr,api}/
tools/{bindings,ci,docker}/
```

OS別FFIは`packages/native/src/nimino_native/private/{windows,linux,macos}`だけに置きます。FFIモジュールは公開パッケージではありません。

## 実装の順序

機能はWindows、Linux、WSLの縦スライスで進めます。Windowsだけで共通APIを確定したり、Linuxを後追い移植したりしません。M1のファイル単位計画、API一覧、テスト完了条件、スパイクは[M1実装計画](docs/architecture/m1-plan.md)に記録します。

M0の未確定事項・リスクは[リスク登録簿](docs/architecture/risks-and-spikes.md)に記録し、解消前にスコープを広げません。
