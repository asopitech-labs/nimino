# `nimino-native` 公開API案

**状態: M2〜M6実装済み。Windows/Linux/macOS native backend と WSL host adapter に、`evalJavaScript`、message/navigation/error/new-window、CookieManager、permission/download callback、native menu/notification、tray、deep link、custom protocol を実装済みです。macOSはAppKit/WKWebView、NSStatusItem、`UNUserNotificationCenter`、profile別WKWebsiteDataStore、`.app`/`.dmg` packagingを提供します。macOS GUIは`nimble testMacosSmoke`、packageは`nimble testPackMacos`で確認します。実Windows GUI、Apple署名/notarization、ユーザー操作依存の通知クリック等は環境依存のrelease検証です。**

このAPIはWindow/WebViewと低水準イベントだけを提供します。RPC、プロファイル、権限ポリシー、アセット配信、URL包装、WSL通信を含めません。

## 型

```nim
type
  NativeApp* = ref object
  NativeAppOptions* = object
    appId*: string
  NativeWindow* = ref object
  NativeWebView* = ref object

  NativeState* = enum
    pending, ready, closing, closed

  NativeErrorKind* = enum
    unsupported, invalidArgument, invalidState, permissionDenied, osError, webViewError

  NativeError* = object
    kind*: NativeErrorKind
    operation*: string
    platformCode*: int32
    detail*: string             # token/cookie/URLの認証情報を含めない

  NativeResult* = object
    isOk*: bool
    error*: NativeError

  NativeResultOf*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: NativeError

  NativeFileDropHandler* = proc(paths: seq[string]) {.closure.}

  WindowOptions* = object
    title*: string
    width*: int
    height*: int
    x*: Option[int]
    y*: Option[int]
    visible*: bool

  Rect* = object
    x*, y*, width*, height*: int

  NavigationRequest* = object
    url*: string
    isMainFrame*: bool
    isRedirect*: bool

  Capability* = enum
    multipleWebViews, transparentWindow, nativeMenu, systemTray,
    nativeNotification, customProtocol, webPermissionEvents
```

Nim 2.2.10コンテナには`std/results`がないことをM1スパイクで確認したため、外部パッケージを増やさずNiminoがこの最小結果型を所有します。`success`/`failure`および`successOf`/`failureOf`はprivate実装を隠す公開constructorです。失敗可能な操作は上記5分類を失いません。

## 操作案

```nim
proc newNativeApp*(options: NativeAppOptions): NativeApp
proc newNativeApp*(): NativeApp
proc supports*(app: NativeApp, capability: Capability): bool
proc run*(app: NativeApp): NativeResult
proc quit*(app: NativeApp): NativeResult
proc close*(app: NativeApp): NativeResult
proc postToUi*(app: NativeApp, callback: NativeUiHandler): NativeResult
proc configureSystemTray*(app: NativeApp, items: openArray[NativeMenuItem],
  handler: NativeMenuHandler): NativeResult
proc configureNativeMenu*(app: NativeApp, title: string,
  items: openArray[NativeMenuItem], handler: NativeMenuHandler): NativeResult
proc sendNativeNotification*(app: NativeApp,
  notification: NativeNotification): NativeResult

proc newWindow*(app: NativeApp, options: WindowOptions): NativeResultOf[NativeWindow]
proc close*(window: NativeWindow): NativeResult
proc setTitle*(window: NativeWindow, title: string): NativeResult
proc setSize*(window: NativeWindow, width, height: int): NativeResult
proc show*(window: NativeWindow): NativeResult
proc hide*(window: NativeWindow): NativeResult
proc minimize*(window: NativeWindow): NativeResult
proc maximize*(window: NativeWindow): NativeResult
proc state*(window: NativeWindow): NativeState
proc onResize*(window: NativeWindow, callback: NativeResizeHandler): NativeResult
proc onFileDrop*(window: NativeWindow, callback: NativeFileDropHandler): NativeResult
proc onCloseRequest*(window: NativeWindow, callback: proc(): bool {.gcsafe.})

proc newWebView*(window: NativeWindow): NativeResultOf[NativeWebView]
proc close*(view: NativeWebView): NativeResult
proc loadUrl*(view: NativeWebView, url: string): NativeResult
proc loadHtml*(view: NativeWebView, html: string, baseUrl = ""): NativeResult
proc setZoom*(view: NativeWebView, factor: float): NativeResult
proc setDocumentStartScript*(view: NativeWebView, script: string): NativeResult
proc evalJavaScript*(view: NativeWebView, script: string): Future[NativeResultOf[string]]
proc getCookies*(view: NativeWebView, url = ""): Future[NativeResultOf[seq[NativeCookie]]]
proc setCookie*(view: NativeWebView, cookie: NativeCookie): Future[NativeResult]
proc deleteCookie*(view: NativeWebView, cookie: NativeCookie): Future[NativeResult]
proc onMessage*(view: NativeWebView, callback: proc(message: string) {.gcsafe.})
proc onNavigationStarting*(view: NativeWebView,
  callback: proc(request: NavigationRequest): bool {.gcsafe.})
proc onNavigationCompleted*(view: NativeWebView,
  callback: proc(url: string, succeeded: bool) {.gcsafe.})
proc onNewWindowRequested*(view: NativeWebView,
  callback: proc(url: string) {.gcsafe.})
proc onError*(view: NativeWebView, callback: proc(error: NativeError) {.gcsafe.})
```

`newWebView`が`pending`の間でも、直近の`loadUrl`または`loadHtml`を一件だけ保持し、ready後に実行します。Windows/Linux nativeでは一つのWindowに複数WebViewを作成できます。WebViewはWindow内に順番に配置されます。`close(view)`はそのWebViewだけをNative資源解放し、Windowは維持します。Windowが先に閉じたときは要求を成功扱いせず`invalidState`または`webViewError`で完了します。

`loadHtml`の`baseUrl`はネイティブLinuxだけで利用できます。非空値は
[`webkit_web_view_load_html`](https://webkitgtk.org/reference/webkit2gtk/2.39.1/method.WebView.load_html.html)
の`base_uri`へそのまま渡され、HTML内の相対URLを解決します。WebKitGTKの仕様上、base URI外の絶対ローカルパスはweb processを終了させ得るため、ローカルassetの許可・パス制御は`nimino-core`が担います。空文字列は`NULL`として渡され、WebKitGTKの既定`about:blank`を使います。

Windowsの[`ICoreWebView2::NavigateToString`](https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/working-with-local-content)はbase URIを受け取らず、生成文書は`about:blank` originです。そのためWindowsと`-d:niminoWsl`では非空`baseUrl`を黙って無視せず`unsupported`で拒否します。通常の`loadHtml(html)`は従来どおり全ターゲットで使えます。

```nim
## Linux native build only
discard view.loadHtml("<img src=\"images/logo.svg\">",
  baseUrl = "https://example.test/assets/")
```

## Windows system tray（最小実装）

Windows build では、`created` 状態の App に固定の context menu を一度だけ登録できます。
Linux native buildでも、session D-BusにfreedesktopまたはKDEのStatusNotifierWatcherが
存在する場合は、同じAPIでStatusNotifierItemとdbusmenuを登録できます。tray icon は最初に
作成された native Window を owner にし、その Window または App を閉じる前に削除されます。
この層は hide-on-close、start-to-tray、アプリ固有 icon、URL包装を実装しません。WindowsのToast表示と、生成されたper-user installerが登録するCOM local-server activationは、AUMID/ToastActivatorCLSIDが揃った配布構成で利用できます。

```nim
let window = app.newWindow(title = "Nimino").value
discard app.configureSystemTray([
  NativeMenuItem(id: 1, title: "Show", enabled: true),
  NativeMenuItem(id: 2, title: "Quit", enabled: true)
], proc(itemId: uint32) =
  case itemId
  of 1: discard window.show()
  of 2: discard app.quit()
  else: discard
)
```

ID `0`、空 title、重複 ID、nil handler は `invalidArgument` で拒否します。callback は
native UI thread で呼ばれ、例外は Win32 callback 境界へ伝播しません。

## Linux native menu / notification / system tray（最小実装）

ネイティブLinux buildでは、`nativeMenu` と `nativeNotification` Capabilityを常に提供し、
session D-BusにStatusNotifierWatcherが存在する場合だけ`systemTray`を提供します。GTK4/GLib
には従来のstatus icon APIがないため、Niminoはfreedesktop StatusNotifierItemと
`com.canonical.dbusmenu`をGioの公式D-Bus APIへ直接登録します。

`app.systemTraySupportDetail()` は `DBUS_SESSION_BUS_ADDRESS`、session bus、
`org.freedesktop.StatusNotifierWatcher`（旧KDE名へfallback）のownerを順に検査し、具体的な理由を返します。
`configureSystemTray` は同じ理由を `unsupported` エラーへ含め、未対応を成功扱い
しません。例えばsession busがない場合は
`session D-Bus is unavailable (DBUS_SESSION_BUS_ADDRESS is not set)` になります。
StatusNotifierWatcherのない環境では`configureSystemTray`が`unsupported`を返します。
tray依存の導線は`configureNativeMenu`でアプリメニューを提供し、状態変化は
`sendNativeNotification`で通知してください。外部のAppIndicator実装は導入しません。
`configureNativeMenu` は `run` 前に一度だけ呼べ、GTK の
[`GtkApplication.set_menubar`](https://docs.gtk.org/gtk4/method.Application.set_menubar.html)
へ `GMenu` を登録します。各項目はアプリケーション `GSimpleAction` となり、enabled
状態と ID を保ったまま `NativeMenuHandler` を UI thread で呼びます。現在のWindows実装は
同じ最小メニューAPIを既存のtray context menuへ対応付けます。WindowsではWinRT Toastまたは
通知領域balloonのクリックを`onNotificationActivated`で受け取れます。ToastはAppUserModelIdと
ToastActivatorCLSIDを要求し、各Toastのlaunch IDをcallbackへ伝えます。アプリが終了済みの場合は、
COM `INotificationActivationCallback` local-serverが起動され、同じcallbackへ一度だけ通知します。
生成launcherのlaunch引数転送も互換補助経路として利用します。Linux/WSLの`onNotificationActivated`登録は
`unsupported`を返します。

`sendNativeNotification` は `running` 状態のLinux Appだけで利用でき、GIO の
[`GApplication.send_notification`](https://docs.gtk.org/gio/method.Application.send_notification.html)
へ `NativeNotification(id, title, body)` を渡します。成功はOS APIに通知要求を渡せたことを
意味するだけで、desktop shellの設定や通知抑止による非表示を検出・成功扱いにはしません。
アプリIDに対応するdesktop entry、通知action、画像はこの最小実装の範囲外です。Windows toastの
AppUserModelId shortcut/installer登録は`nimino-pack`が担当します。

```nim
discard app.configureNativeMenu("Nimino", [
  NativeMenuItem(id: 1, title: "Quit", enabled: true)
], proc(itemId: uint32) =
  if itemId == 1:
    discard app.quit()
)

## Idle callbackなど、app.run()中に呼ぶ
discard app.sendNativeNotification(NativeNotification(
  id: "ready", title: "Nimino", body: "Application started"
))
```

## macOS native backend

macOSはCocoa/WebKitのprivate bridgeで`NSApplication`、`NSWindow`、複数`WKWebView`、native menu、`NSStatusItem` tray、`UNUserNotificationCenter`、通知activation、`NSApplication`の`openURLs` deep linkを提供します。通知登録時はAlert/Sound/Badge権限を要求し、activationは`UNNotificationRequest.identifier`で通知します。`onPermissionRequested`はWKWebKitのmedia capture（camera/microphone）をdeny-defaultで判定し、`onDownloadStarting`/`onDownloadPath`/`onDownloadEvent`はWKDownloadの開始・保存先・進捗・完了/失敗へ接続します。Dockクリック時の`applicationShouldHandleReopen`では、非表示の全Windowを再表示します。

非incognito WebViewの`profilePath`はSHA-256から安定UUIDを作り、`WKWebsiteDataStore dataStoreForIdentifier:`でprofileごとに分離します。空のprofileは既定store、incognitoはnon-persistent storeです。`proxyUrl`はmacOS 14+でWebView構築時にNetwork.frameworkのHTTP CONNECT/SOCKS5設定として適用し、ready後の変更は`invalidState`で拒否します。`transparentWindow`とsystem proxyの動的変更はmacOS WebKitの共通API境界では提供しません。`hideTitleBar`は`NSWindowTitleHidden`、透明titlebar、`NSWindowStyleMaskFullSizeContentView`を組み合わせたoverlayとして提供します。

`nimino package-macos --format app|dmg`はbundle内のmanifest、Mach-O host、assetsをmacOS application bundleへ配置し、manifestのdeep-link schemeとcamera/microphone用途説明を`Info.plist`へ登録します。macOSアイコンは`.icns`を使用します。`--arch`でhostのMach-Oアーキテクチャを検証し、`--sign-identity`を指定した場合は`codesign --verify --deep --strict`と`spctl --assess --type execute`まで成功しなければ完了扱いにしません。DMGのnotarizationは`--notary-profile`で明示的に要求でき、staple後に`xcrun stapler validate`を実行します。

`setDocumentStartScript`は`pending`のViewに一つだけscriptを設定・置換する低水準操作です。ready後の追加・変更は`invalidState`で拒否し、次のナビゲーションへ黙って適用しません。WindowsはWebView2の非同期`AddScriptToExecuteOnDocumentCreated`完了を待ってから保留中の最初の読込を開始し、LinuxはWebKitGTKの`WebKitUserScript`をdocument-startで登録します。どちらも以後のframe/ナビゲーションへ影響し得るため、URL・origin・注入ポリシーはこの層で判断しません。`nimino-core`がその制約を用いてRPC bridgeを限定します。

`evalJavaScript` は pending の View へも要求でき、ready 後に一度だけ実行します。成功値は JavaScript の評価値を JSON 化した UTF-8 文字列です（文字列値なら JSON の引用符を含みます）。Linux は WebKitGTK の `evaluate_javascript`、Windows は WebView2 の `ExecuteScript` で UI thread 上の完了 callback から Future を完了します。WSL host は完了済み Future を Win32 timer 上で polling し、同じ request ID の response として `{"result":"…"}` を返します。Linux実行スモーク、Windows Runtime上のhost実行、WSLの評価往復を確認済みです。

`NativeCookie`はname、value、domain、path、Secure、HttpOnly、UNIX秒のexpiryを、ネイティブオブジェクトからコピーしたNim値として保持します。`getCookies` / `setCookie` / `deleteCookie`はreadyなWebViewだけで使えるFuture APIです。Windowsは公式WebView2 SDKの`ICoreWebView2CookieManager` / `ICoreWebView2CookieList`を直接呼び、LinuxはWebKitGTK 6.0の`WebKitCookieManager`とlibsoup 3の`SoupCookie`を直接呼びます。COM interface/callbackの参照数、WebKitのtransfer-full list、SoupCookieの寿命はNim GCへ委ねず各完了経路で明示管理します。WSL buildのnative型自身はIPCを内包せず、`nimino-wsl` host adapterが同じ操作を認証済みrequestとして中継します。

`onMessage` は文字列だけを受け入れます。Windows の Web コンテンツは `window.chrome.webview.postMessage("…")`、Linux の Web コンテンツは `window.webkit.messageHandlers.nimino.postMessage("…")` を使用します。非文字列メッセージは native 層で破棄します。Linux の実 WebView スモークは handler の登録、文字列受信、signal 切断まで確認しています。WSL host は `native.webview.message` event として中継し、client は response を待つ間に受けた event を `takeEvents()` で取得できます。Windows Runtime と WSL host経由の実行確認済みです。

`onFileDrop`は明示的に登録した場合だけ、Windowsの`WM_DROPFILES`またはLinux GTK4
`GtkDropTarget`からコピー済みの絶対パス配列を通知します。未登録時はWebViewの標準ドロップ処理を
変更しません。WSLではhostから認証済み`native.window.fileDrop`イベントとして中継されます。

`onNavigationStarting` はWindowsで `NavigationStartingEventArgs::put_Cancel`、Linuxで `decide-policy` の`use/ignore`を使い、callbackが`false`または例外を返したときに中止します。handler未登録時は許可します。Linux実WebViewでは許可経路を確認済みです。WSL hostは`native.webview.navigationStarting` eventをclientへ中継しますが、eventはnative callbackが戻った後に送信されるため、現時点では既定許可でありclientが中止を決めることはできません。この差をcore APIへ漏らさないための候補は[ADR-0005提案](../adr/0005-wsl-navigation-policy.md)で管理します。

`onNavigationCompleted` は主frameの読込完了後に URL と成功可否を通知します。Linuxは `load-changed` と `load-failed` を併用して失敗を成功扱いせず、Windowsは `ICoreWebView2::NavigationCompleted` の `IsSuccess` を使用します。hostは `native.webview.navigationCompleted` eventとして中継します。各バックエンドはWindow破棄前にsignal/COM event登録を解除します。Linux実WebView、Windows Runtime、WSL往復の成功経路を確認済みです。

`onCloseRequested` はユーザーまたはOSからWindow終了要求が発生した時に同期的に呼ばれ、`true`で終了を許可し、`false`で拒否します。コールバック例外は安全側（拒否）として扱います。
`onClosed`はOS側の破棄完了後に一度だけ通知されます。coreはこの通知でWindow状態とWindow単位RPCを終了させます。

`onError` はまず入力検証とmain-frame navigation失敗を通知します。入力検証では該当操作の戻り値も失敗になります。Linuxでは`load-failed`、Windowsでは`NavigationCompleted`の失敗を`webViewError`として通知します。WSL hostは`native.webview.error` eventへ`kind`、`operation`、`platformCode`、`detail`を渡します。JavaScript評価の失敗は引き続きそのFutureで返し、この通知へ二重送信しません。

`onNewWindowRequested` は`window.open`や`target="_blank"`要求のURLを通知します。native層は暗黙にWindow/WebViewを増やさず、Windowsは`NewWindowRequested::Handled = true`、Linuxはnew-window policyを`ignore`し、`create` signalを登録して予期しない生成も返却値`nil`で拒否します。WSL hostは`native.webview.newWindowRequested` eventを中継します。Windows/Linux/WSLの実ユーザー操作による発火確認は、WebView2 Runtimeを備えたGUI CIで残っています。

## 利用イメージ

エラー処理を省略する簡潔な最終形は次を目標とします。M0時点では実行できません。

```nim
import nimino_native

let app = newNativeApp()
let window = app.newWindow(WindowOptions(title: "Nimino", width: 1200, height: 800)).value
let view = window.newWebView().value
discard view.loadUrl("https://example.com")
discard app.run()
```

`.value`を伴わない便利構文を導入する場合も、失敗を黙殺するAPIにはしません。WindowとWebViewを同一型に統合しないため、将来は同じWindowへ複数のViewを追加できます。
### WebView custom protocol

`app.registerCustomProtocol("nimino", handler)` registers one WebView-internal
resource scheme. The handler returns a status code, MIME type, and body and is
executed synchronously on the native UI thread. This is separate from OS
deep-link registration. Windows uses WebView2 `WebResourceRequested`; Linux
uses WebKitGTK's URI-scheme callback. WSL uses an authenticated synchronous
request/response relay; the real Windows WebView2 Runtime path still requires
the GUI harness.
