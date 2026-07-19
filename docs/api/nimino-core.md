# `nimino-core` 最小公開API案

**状態: M4部分実装。Windows/Linux向けの`App`/`Window` facade、Window単位の明示許可リストJSON RPC、WebView bootstrap、profile path、local asset root/entry境界を実装した。`registerTyped` / `registerTypedAsync`は標準JSON codecで型付きhandlerを登録でき、`typescriptDeclarations`で登録済みメソッドの保守的な`unknown`宣言を生成できます。Linuxでは実WebViewのrequest/response/notification往復、URLの最初期scriptからのRPCを確認済みで、Windowsはx64クロスコンパイル済みです。WSL build（`-d:niminoWsl`）は同じcore APIから認証済みWindows hostを選び、Linux GUI FFIをリンクしません。Windows WebView2 Runtime上でWSL coreの読込、評価、async response、timeout、URL document-start RPCを確認済みです。permission/download/navigationはnative実装とWSL同期decision relay（timeout時deny）まで完了し、profile設定/Cookieの永続化API、Window単位の参照・削除APIも実装済みです。型抽出register macro、WebViewエンジンへのCookie/cache自動接続、desktop統合は未実装です。**

`nimino-core`は通常の利用者向けの高水準APIです。`nimino-native`を内包してもFFI型を公開せず、`nimino-pack`へはこの公開面だけを提供します。

## M3で実装する最小面

```nim
type
  App* = ref object
  Window* = ref object

  AppOptions* = object
    id*: string
    name*: string

  CoreWindowOptions* = object
    title*: string
    width*: int
    height*: int
    profile*: string
    inlineRemoteAssets*: bool

proc newApp*(options: AppOptions): CoreResultOf[App]
proc newApp*(id = "tech.asopi.nimino"; name = "Nimino"): CoreResultOf[App]
proc onReady*(app: App; handler: proc()): CoreResult
proc onBeforeQuit*(app: App; handler: proc(): bool): CoreResult
proc onExit*(app: App; handler: proc()): CoreResult
proc newWindow*(app: App, options: CoreWindowOptions): CoreResultOf[Window]
proc newWindow*(app: App, title = ""; width = 1200; height = 800): CoreResultOf[Window]
proc setTitle*(window: Window, title: string): CoreResult
proc setSize*(window: Window, width, height: int): CoreResult
proc loadUrl*(window: Window, url: string): CoreResult
proc loadHtml*(window: Window, html: string): CoreResult
proc loadAssets*(window: Window, directory: string): CoreResult
proc loadEntry*(window: Window, entry = "index.html"): CoreResult
proc openExternally*(window: Window, url: string): CoreResult
proc setNavigationRules*(window: Window, rules: NavigationRules): CoreResult
proc evalJavaScript*(window: Window, script: string): Future[CoreResultOf[string]]
proc quit*(app: App): CoreResult
proc run*(app: App): CoreResult
```

`CoreError`はnative FFI型を公開せず、`invalidArgument`、`invalidState`、`platformUnavailable`、`permissionDenied`、`osError`、`webViewError`、`nativeFailure`を返す。Windows/Linux facadeはnative App/Window/WebViewを内部所有する。WSL buildではcoreが`nimino-wsl`の公開client APIだけを使い、Windows hostがnative App/Window/WebViewを所有する。hostは配布物で隣接またはPATHへ置く。`NIMINO_WSL_HOST_EXE`は開発・CIの明示上書きであり、通常利用者にplatform指定を要求するものではない。

`onReady`は`run()`がUIイベントループを開始する直前に、`onBeforeQuit`は明示的な`app.quit()`の前に、`onExit`はネイティブ資源の破棄時に呼び出されます。`onBeforeQuit`が`false`を返した場合は終了を拒否します。コールバックの例外はイベントループへ伝播させず、終了処理を継続します。WSLでも同じ順序で通知されます。

## M3以降のRPC面

```nim
window.rpc.register("settings.load") do () -> Settings:
  loadSettings()

window.rpc.register("files.save") do (request: SaveRequest) -> Future[SaveResult]:
  saveFile(request)
```

登録APIは明示的なメソッド名を持つ許可リストです。任意のNim関数、OS API、または`ref object`を自動公開しません。各Windowは独立したRPC registryとrequest ID空間を持ち、request/response、notification、timeout、cancel、JSON errorを扱います。応答不要の通知は`registerNotification`で専用登録でき、requestとして呼び出されることはありません。

`registerTyped`と`registerTypedAsync`は、引数なしまたは一つのJSON codec対応入力型を受け、戻り値（または`Future`の戻り値）をJSON化する。通知には`registerTypedNotification`（引数あり／なし）を使用できる。これらも明示メソッド名の許可リストであり、reflectionによる任意関数公開ではない。`Window.typescriptDeclarations`は登録済みメソッドだけを宣言生成し、primitive型（string、bool、数値）とそれらの`seq`配列を対応するTypeScript型へ変換し、複合型は安全に`unknown`として扱います。register macroによる複合型の自動抽出は未実装であり、native層へ追加しない。
複合型の宣言を手動で補完する場合は、実行時に登録済みのメソッドへ`registerTypeScriptSchema(method, paramsType, resultType)`を呼び出せます。これは宣言生成だけを変更し、RPC codecや許可リストを変更しません。改行・制御文字・`{}`・`;`を含む型文字列は拒否します。
`window.rpc.unregister("method")`で登録済みの一つのメソッドを撤去できます。撤去後の新規呼び出しは拒否され、既に実行中のrequestは完了まで維持されます。

`parseCookieHeader`はSet-Cookie形式の名前・値を共通検証し、プロファイル保存前の入力境界として利用できます。ブラウザ固有の属性ポリシーは呼び出し側で明示的に適用します。
`window.syncDocumentCookies()`は現在の文書でスクリプトから見える`document.cookie`だけをプロファイルへ同期します。成功したナビゲーション完了時にも自動実行されます。HttpOnly cookieは取得・上書きせず、ブラウザCookie managerの完全な自動同期とは異なります。
メソッド名は制御文字・空白・引用符を含められず、256文字以内に制限されます。

```nim
type Settings = object
  theme: string

discard window.rpc.registerTyped("settings.load", proc(): Settings =
  Settings(theme: "dark")
)

discard window.rpc.registerTypedAsync("settings.save",
  proc(settings: Settings): Future[Settings] = saveSettings(settings)
)
```

## 実装済みRPCとWebView bridge

```nim
import nimino_core

let app = newApp(id = "tech.asopi.example", name = "Example").value
let window = app.newWindow(title = "Example").value

discard window.rpc.registerSync("settings.load", proc(params: JsonNode): RpcResult =
  rpcSuccess(%*{"theme": "dark"})
)
discard window.loadHtml("<main>Example</main>")
discard app.run()
```

Web側には`window.nimino.invoke(method, params, { timeoutMs })`および`window.nimino.notify(method, params)`を提供する。wire形式は`nimino = "rpc"`、`kind = request | notification | cancel`、文字列ID、明示的method、JSON params、timeoutMsである。responseは同じIDに`ok/result`または構造化`error`を返す。未登録methodは拒否し、cancel/timeout後の遅延Futureはresponseを二重送信しない。

registryの`tick()`はWindows timerとLinux GLib timeout sourceからUI threadで呼ばれる。Linuxの実smokeは`invoke → 許可済みhandler → response → notify`に加え、通知で完了するFutureと許可済み未完了Futureのtimeout responseを確認している。WSLではcoreがhostの`native.webview.message` eventを同じWindow registryへ渡し、responseを`native.webview.evalJavaScript` requestとして中継する。WSL clientは10ms以下の待機ごとにregistryをtickするため、host eventが続かない無応答requestも期限切れになる。fake hostとWindows WebView2 Runtimeの実スモークでasync response/timeoutを確認済みである。Window close中の遅延Futureと通常Windows Runtime上のcore RPCは未確認である。

`loadHtml`はbridgeを文書の先頭へ挿入します。Viewが`pending`の間の最初の対象`loadUrl`では、native Viewにdocument-start scriptとしてbridgeを登録してから読込を開始します。このため許可されたURLの最初期scriptも`window.nimino.invoke`を利用できます。

document-start scriptはframeと後続ナビゲーションにも適用され得るため、bridge自身が実行時にoriginを検査します。HTTP(S)では対象URLを正規化した同一originだけ、`data:`では対象URLと完全一致する文書だけで初期化します。`about:blank`は親originを継承し得るため対象外です。ほかのscheme、後続の別origin、cross-origin frameではRPCを公開しません。`loadUrl`ごとに対象URLを更新し、`loadHtml`後も次のURLで新しいbridgeを設定します。これはURL包装向けの全ナビゲーションpolicyではなく、M3 RPCの最小安全境界です。M4のナビゲーションpolicyがこの境界を拡張する場合は、[ADR-0008](../adr/0008-document-start-rpc-bridge.md)を更新して全ターゲットで検証します。

## M4以降の面

```nim
discard window.loadAssets("dist")
discard window.loadEntry("index.html")

window.navigationPolicy = proc(request: NavigationRequest): NavigationDecision =
  if request.url.matches("https://example.com/**"):
    allow()
  else:
    openExternally()

window.onExternalNavigation proc(request: NavigationRequest) =
  echo "open externally: " & request.url

window.onNavigationCompleted proc(url: string; succeeded: bool) =
  echo url & " loaded=" & $succeeded

window.onPermission proc(request: PermissionRequest): PermissionDecision =
  deny()
```

プロファイルは`app id / profile`をキーにcookie、local storage、cache、permission、download、settingの永続化ディレクトリを分離します。`ensureProfileLayout`で冪等に領域を作成でき、`writeProfileSetting` / `readProfileSetting`でJSON設定、`writeProfileCookie` / `readProfileCookie`でCookieを安全に保存・読込できます。最初のHTTP(S)読込では、対象domainとrequest pathに一致する非HttpOnly Cookieをdocument-startで復元します。LinuxはWebKitNetworkSession、Windows/WSLはWebView2 UserDataFolderをprofileへ接続するため、エンジン管理のCookie・HttpOnly Cookie・localStorageもprofile単位で永続化されます。無処理の権限要求はdenyです。
`window.clearCookies()`で現在のprofileに保存したCookieを全削除できます。
`window.cookiesForDomain(domain)`では、指定hostに可視な期限切れでないCookieをprofileから取得できます。
`window.clearSettings()`では同じprofileのJSON設定を全削除できます。
`window.clearCache()`ではNimino管理のprofile cacheファイルを削除できます。WebView
Linux WebKitのcacheはprofileのcacheディレクトリへ接続され、Windows WebView2の既知のcacheディレクトリは`clearCache()`で削除されます。
`window.clearDownloads()`ではprofile内のNimino管理downloadファイルを削除できます。
`window.downloadPath(suggestedName)`ではprofile内downloadsディレクトリに限定した安全な保存先を取得できます。実際の書込みはアプリケーション側で行います。
`window.saveDownload(suggestedName, content)`は一時ファイル経由でprofile内へ保存し、成功時に実パスを返します。
`window.listDownloads()`はprofile内の保存済みダウンロード実パスを返します。
`window.deleteDownload(path)`はprofile内に限定して一つの保存済みファイルを削除します。
`window.onDownloadEvent`は`DownloadEvent`（`downloadStarted` / `downloadProgress` / `downloadCompleted` / `downloadFailed` / `downloadCancelled`、進捗値）を通知します。バックエンドが取得できる状態だけを通知し、未対応状態を成功扱いにはしません。
Linux WebKitGTKでは許可したレスポンスについて、開始・進捗・完了・失敗イベントを通知します。Windows WebView2でも`BytesReceivedChanged`と`StateChanged`を購読し、進捗・完了・失敗・キャンセルを通知します。
`window.clearPermissions()`ではprofileに保存した権限判断履歴を削除できます。
`window.clearLocalStorage()`ではNimino管理のprofile local-storage領域を削除できます。
WebView内部localStorageはprofileのエンジンデータ領域へ保存され、`clearProfileData()`でprofile全体とともに削除されます。
`window.clearProfileData()`では上記のNimino管理profile領域を一括初期化できます。
WSLでは`clearCache()`と`clearDownloads()`がWindows hostのWebView2 `Cache`／`Code Cache`／`GPUCache`／`DawnCache`／`Downloads`にも中継されます。削除失敗は成功扱いにせずエラーを返します。
WebViewエンジン内部のCookie/cache/localStorageは対象外です。

`loadAssets`はrootディレクトリを正規化してWindowへ固定します。`loadEntry`はroot外の
絶対パス、`..`による脱出、存在しないファイルを拒否してからHTMLを読み込みます。
native backendではentryをroot内の`file:` URLとして読み込み、相対CSS/JavaScript/画像を
WebView自身に解決させます。WSLではWindows hostへローカルrootを転送できないため、HTML本文を
転送し、root内の相対`<script src="…">`とstylesheet`<link href="…">`を本文へインライン化します。
一般的な画像形式（PNG/JPEG/GIF/SVG/WebP）の相対`<img src="…">`もdata URIへ変換します。
CSS内のローカル`url(...)`も画像・フォント（WOFF/WOFF2/TTF）をdata URIへ変換します。
WSLの`loadEntry`では、ローカルのCSS、JavaScript、画像、音声・動画、`srcset`候補、Web Manifestなどを安全にasset root内へ限定してインライン化します。`CoreWindowOptions.inlineRemoteAssets`を明示的に有効化した場合だけ、HTTP(S)画像、CSS内URL、stylesheet linkを最大8MiBまで取得してインライン化します。既定値は無効です。

`setNavigationRules`はallow/denyの宣言的URL ruleを設定します。denyが優先され、
設定後に未一致のURLは拒否します。nativeはUI callback内で同期評価し、WSLはUI loop
開始前にhostへruleを同期します。任意のWSL側callbackをUI callbackで待つ方式ではありません。
`navigationExternal`を返した場合は`onExternalNavigation`へ通知し、handler未登録時は
外部URLもdenyします。許可したURLを既定ブラウザへ渡す場合は`window.openExternally(url)`を明示的に呼び出します。URLはHTTP(S)に限定され、起動失敗は`CoreErrorKind.osError`として返ります。

`window.close()`はWindow単位でネイティブWindowを破棄し、Window専用RPCを終了します。
WSLでは認証済みIPCでWindows hostへ中継します。close後の操作と二重closeは
`invalidState`になります。
`window.onClosed`はOSまたはアプリによる破棄完了後に一度だけ呼ばれます。

`window.reload()`は最後に成功したURLを再読込します。URL未読込、close後、または
不正状態では`invalidState`を返します。

`app.windows()`はcloseされていないWindowのsnapshotを返し、`app.windowCount()`は
同じ集合の件数を返します。App終了後は空集合・0です。
`app.isRunning()`と`window.isClosed()`でライフサイクル状態を照会できます。
`window.focus()`はWindowを表示して前面化します。LinuxではGTK present、Windowsでは
Win32 `SetForegroundWindow`、WSLではWindows hostへ中継します。

`window.onNewWindow`は新規Window要求を通知します。暗黙生成は行わず、アプリケーションが
許可した場合に`window.openPopup(request)`を呼ぶことで、実行中のWindows/Linux/WSLでも
Popup WindowとWebViewを生成してURLを読み込みます。
