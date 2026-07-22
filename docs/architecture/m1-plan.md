# M1実装計画

**M1の完了条件:** Windows、Linux、WSL、macOSのすべてで、Window生成、WebView生成、URL読込、リサイズ、タイトル変更、正常終了を確認すること。任意の一ターゲットだけの成功は完了ではありません。

## 実装・検証状況（2026-07-18）

| 対象 | 実装済み | 確認済み | 未確認・理由 |
| --- | --- | --- | --- |
| Linux | GTK 4/ WebKitGTK 6.0 Window、WebView、URL/HTML、title、終了 | `make test`、`make linux-smoke` | 実表示の拡張機能はM2以降 |
| Windows | Win32 Window、STA、WebView2 Environment/Controller/Core、Bounds、URL/HTML、COM明示解放 | `make windows-cross`でx64 PEとFFI/COM callback ABIを検査。`make wsl-host-smoke`で導入済みRuntime上の実WebView生成、HTML/URL、navigation完了、title/resize、JavaScript評価、message、終了を検査 | 実ユーザー操作によるnew-windowと通常Windows GUI CIは未確認 |
| WSL | CSPRNG token、`WSLENV`転送、constant-time認証、stdio frame、Windows host、object table、URL/HTML要求、shutdown、permission/download/navigation同期decision relay | `make test`、`make wsl-host-cross`、`make wsl-host-smoke`、`make wsl-client-smoke`、`make wsl-core-rpc-async-smoke`（通常core APIでWindows childを起動し、hello→Window→WebView→async RPC→timeout→shutdown） | redirectの実遷移、再接続契約、実ユーザー操作は未確認 |
| macOS | Cocoa `NSApplication`/`NSWindow`、WKWebView、delegate、document-start script、JS/message/navigation、native menu/tray/notification、deep link、custom scheme、profile store、permission/download delegate、`.app`/`.dmg` packaging | `nimble testMacosSmoke`、`nimble testPackMacos`でnative/package smokeを確認 | Apple署名/notarization、通知クリック・deep linkの実ユーザー操作は資格情報/GUI環境依存のrelease確認 |

M1の対象（Window/WebView生成、URL読込、resize、title、正常終了）は4ターゲットで確認済みである。architecture-matched `WebView2Loader.dll`を成果物へ同梱したWindows開発機で、Window→WebView→HTML/URL→resize→title→message→closeを確認し、WSL clientもWindows hostへのURL要求を確認する。macOSはAppKit main run loop上のWKWebViewをローカルGUI smokeで確認する。実ユーザー操作によるnew-windowと通常Windows GUI CIはM2以降の未完了項目として管理する。WebView2 Evergreen RuntimeはWindowsの前提であり、開発WindowsではRegistry検出済みである。

## 実装前ゲート

以下のスパイクが通るまでM1の本実装を開始しません。

1. Windows: 固定したWebView2 SDK header/IDLから、`HRESULT`、COM vtable、callback ABIを検証する最小FFI。
2. Linux: Docker内で`pkg-config --cflags gtk4 webkitgtk-6.0`とGTK 4/WebKitGTK 6.0の最小Windowを確認する。
3. WSL: Windows Interopでhostを起動し、継承stdin/stdoutの双方向frameとEOF終了を確認する。
4. Event loop: Win32 message loopとGLib main contextの各々で、UIを塞がない`asyncdispatch.poll(0)`のタイマー/idle呼出しを確認する。

いずれも既存WebViewラッパーを導入せず、OS公式ヘッダーと公式APIだけで行います。

## ファイル単位の計画

| ファイル/領域 | M1で追加する内容 | 対象 |
| --- | --- | --- |
| `nimino.nimble` | Nim 2.x、`--mm:arc`、パッケージ/テストtask。WebView wrapper依存は追加しない | 共通 |
| `packages/native/nimino_native.nim` | 最小の公開re-export | 共通 |
| `packages/native/src/nimino_native/{app,window,webview,capabilities,errors}.nim` | 公開型、状態遷移、結果、Capability | 共通 |
| `packages/native/src/nimino_native/private/windows/{ffi,app,window,webview}.nim` | Win32、COM、WebView2 direct FFI | Windows |
| `packages/native/src/nimino_native/private/linux/{ffi,app,window,webview}.nim` | GTK 4、GLib、WebKitGTK 6.0 direct FFI | Linux |
| `packages/native/tests/{state,capabilities}.nim` | GUI不要の単体テスト | 共通 |
| `packages/native/tests/integration/{windows,linux}.nim` | Window→WebView→URL→closeの実機テスト | 各OS |
| `packages/wsl/src/nimino_wsl/protocol/{frame,messages,auth,version}.nim` | 長さprefix codec、version、token、ID、制限値 | 共通 |
| `packages/wsl/src/nimino_wsl/client/{launcher,transport,core_adapter}.nim` | `nimino-wsl-host.exe`を起動するclient | WSL |
| `packages/wsl/src/nimino_wsl/host/{main,lifecycle,native_adapter}.nim` | Windows hostとnative object table | Windows |
| `packages/wsl/tests/{protocol,client_host}.nim` | fake stdio、破損frame、EOF、timeout | Linux/Windows |
| `examples/native-minimal/` | URLを表示する最小例 | Windows/Linux |
| `examples/wsl-minimal/` | host起動→Window→URL→shutdown例 | WSL/Windows |
| `tests/integration/` | 3ターゲット共通の期待結果定義 | 共通 |
| `.github/workflows/` | Linux、Windows、WSL2対応runnerのCI | CI |

`nimino-core`と`nimino-pack`の本実装はM1に入れません。空の名前空間や成功するダミー実装を作って未実装機能を偽装しません。

## Windows API一覧（M1）

| 領域 | API/型 | 用途 |
| --- | --- | --- |
| COM | `CoInitializeEx(..., COINIT_APARTMENTTHREADED)`, `CoUninitialize` | UIスレッドのSTA初期化/終了 |
| Win32 | `WNDCLASSEXW`, `RegisterClassExW`, `CreateWindowExW`, `ShowWindow`, `SetWindowTextW`, `GetClientRect`, `GetMessageW`, `TranslateMessage`, `DispatchMessageW`, `DestroyWindow`, `PostQuitMessage` | Windowとメッセージループ |
| Win32 messages | `WM_NCCREATE`, `WM_CREATE`, `WM_SIZE`, `WM_CLOSE`, `WM_DESTROY`, `WM_NCDESTROY` | 所有権、リサイズ、終了 |
| WebView2 | `CreateCoreWebView2EnvironmentWithOptions` | Environmentの非同期作成 |
| WebView2 | `ICoreWebView2Environment::CreateCoreWebView2Controller`, `ICoreWebView2Controller::get_CoreWebView2`, `put_Bounds`, `Close` | Controller/View作成、配置、終了 |
| WebView2 | `ICoreWebView2::Navigate` | URL読込 |

`GetMessageW`は`0`（`WM_QUIT`）と`-1`（OS error）を区別します。Environment作成後にControllerを作る公式順序を守り、`WM_SIZE`ごとにclient rectを`put_Bounds`へ渡します。全WebView2 APIとcallbackをSTA UIスレッドに限定し、COM参照をGCへ委ねません。

公式根拠: [WebView2 Win32 getting started](https://learn.microsoft.com/en-us/microsoft-edge/webview2/get-started/win32)、[CreateCoreWebView2EnvironmentWithOptions](https://learn.microsoft.com/en-us/microsoft-edge/webview2/reference/win32/webview2-idl)、[WebView2 threading model](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/threading-model)、[GetMessageW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmessagew)。

## Linux API一覧（M1）

| 領域 | API/型 | 用途 |
| --- | --- | --- |
| GTK/GIO | `gtk_application_new`, `g_application_run`, `gtk_application_window_new` | applicationとmain loop |
| GTK | `gtk_window_set_title`, `gtk_window_set_default_size`, `gtk_window_set_child`, `gtk_window_present`, `GtkWindow::close-request` | Window設定、WebView配置、終了 |
| WebKitGTK | `webkit_web_view_new`, `webkit_web_view_load_uri` | WebView生成、URL読込 |
| GObject | `g_signal_connect_data`, `g_signal_handler_disconnect`, `g_object_ref_sink`, `g_object_unref` | callbackと参照寿命 |
| GLib | `g_main_context_invoke_full` | workerからUI threadへの復帰 |

M2の縦機能として、native の `webkit_web_view_evaluate_javascript`/`_finish` と WebView2 `ExecuteScript`、文字列message、ナビゲーション開始/完了、基本error通知、新規Window要求を実装した。Linuxの開始/new-windowは`WebKitWebView::decide-policy`と`::create`、完了/errorは`::load-changed`と`::load-failed`、WindowsはWebView2 `NavigationStarting`/`NavigationCompleted`/`NewWindowRequested`を使用し、WSL hostはeventとして中継する。Windows/Linuxは開始callbackによる中止を実装し、新規Windowは暗黙作成せず拒否する。一方、WSL client同期判定は[ADR-0005提案](../adr/0005-wsl-navigation-policy.md)のスパイク待ちである。新規Windowの実ユーザー操作テストとWindows Runtime実行は未確認である。HTML読込にはM1から`webkit_web_view_load_html`を使用する。GTKのレイアウトがWindowリサイズへ追従するため、WindowsのようなBounds更新は不要である。

公式根拠: [GTK application initialization](https://docs.gtk.org/gtk4/initialization.html)、[GTK threading](https://docs.gtk.org/gtk4/section-threading.html)、[WebKitWebView](https://webkitgtk.org/reference/webkit2gtk/stable/class.WebView.html)、[JavaScript evaluation](https://webkitgtk.org/reference/webkit2gtk/stable/method.WebView.evaluate_javascript.html)。

## WSL操作一覧（M1）

```text
client: spawn host → hello(v2, token) → ready(v2, Capability snapshot) → createWindow → loadUrl/loadHtml → shutdown
host:                  version/auth check        → accepted             → response    → response → graceful exit
```

- WSL clientはWindows Interopで`nimino-wsl-host.exe`を子プロセスとして起動します。
- `stdin`/`stdout`はバイナリframe専用、`stderr`は診断専用です。標準出力にログを書きません。
- frameは最大長、protocol version、session ID、request ID/event ID、method、payload、error、timeout、cancel、heartbeatを定義します。
- protocol versionは完全一致です。v2 client/hostはv1または将来versionを互換fallbackせず、受信側validatorで`unsupportedVersion`として拒否します。認証前の旧clientに対してhostはprotocol responseを返さず終了するため、旧clientが同じerror分類を受ける保証はありません。同一versionのclient/hostを組で配布・更新します。v2の`ready.payload`は既知Capabilityの重複なしsnapshotであり、clientは検証前にsessionを使いません。
- clientがOS CSPRNGで生成する32 byte tokenを、Windows Interop child専用の`NIMINO_WSL_HOST_TOKEN`と`WSLENV`でhostへ転送し、最初の`hello`にも含めます。hostは両値をconstant-time比較し、認証完了前に操作を処理しません。
- hostは一client・一sessionで動作し、EOF、初期handshake timeout、またはshutdownでWindowを閉じ、native resourceを解放します。
- listenerを開かないため、外部ホストから接続できません。WSL Interopが無効なら`unsupported`を返します。

この方式の選定理由とTCP等との比較は[ADR-0003](../adr/0003-wsl-stdio-transport.md)にあります。

## テストと完了判定

| レベル | 証明すること |
| --- | --- |
| 単体 | error正規化、状態遷移、Capability、frame codec、token非ログ化、max frame、EOF、timeout |
| Windows統合 | STA Window生成、WebView2 Environment/Controller、URL、WM_SIZE、title、close後のCOM Release |
| Linux統合 | GTK Window、WebKitWebView、URL、title、close後のGObject/signal解放 |
| WSL統合 | Windows host起動、Window/URL要求、正常shutdown、host crash、client EOF |
| CI | Linux GUIセッション、Windows WebView2 Runtime、WSL2対応のWindows self-hosted runner |

GitHub hosted runnerでWSL2 GUIを再現できない場合は、WSL2対応self-hosted Windows runnerを必須にします。未実行を成功とせず、M1は保留のままにします。
