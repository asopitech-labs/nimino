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

proc newApp*(options: AppOptions): CoreResultOf[App]
proc newApp*(id = "tech.asopi.nimino"; name = "Nimino"): CoreResultOf[App]
proc newWindow*(app: App, options: CoreWindowOptions): CoreResultOf[Window]
proc newWindow*(app: App, title = ""; width = 1200; height = 800): CoreResultOf[Window]
proc setTitle*(window: Window, title: string): CoreResult
proc setSize*(window: Window, width, height: int): CoreResult
proc loadUrl*(window: Window, url: string): CoreResult
proc loadHtml*(window: Window, html: string): CoreResult
proc loadAssets*(window: Window, directory: string): CoreResult
proc loadEntry*(window: Window, entry = "index.html"): CoreResult
proc setNavigationRules*(window: Window, rules: NavigationRules): CoreResult
proc evalJavaScript*(window: Window, script: string): Future[CoreResultOf[string]]
proc quit*(app: App): CoreResult
proc run*(app: App): CoreResult
```

`CoreError`はnative FFI型を公開せず、`invalidArgument`、`invalidState`、`platformUnavailable`、`nativeFailure`を返す。Windows/Linux facadeはnative App/Window/WebViewを内部所有する。WSL buildではcoreが`nimino-wsl`の公開client APIだけを使い、Windows hostがnative App/Window/WebViewを所有する。hostは配布物で隣接またはPATHへ置く。`NIMINO_WSL_HOST_EXE`は開発・CIの明示上書きであり、通常利用者にplatform指定を要求するものではない。

## M3以降のRPC面

```nim
window.rpc.register("settings.load") do () -> Settings:
  loadSettings()

window.rpc.register("files.save") do (request: SaveRequest) -> Future[SaveResult]:
  saveFile(request)
```

登録APIは明示的なメソッド名を持つ許可リストです。任意のNim関数、OS API、または`ref object`を自動公開しません。各Windowは独立したRPC registryとrequest ID空間を持ち、request/response、notification、timeout、cancel、JSON errorを扱います。

`registerTyped`と`registerTypedAsync`は、引数なしまたは一つのJSON codec対応入力型を受け、戻り値（または`Future`の戻り値）をJSON化する。これらも明示メソッド名の許可リストであり、reflectionによる任意関数公開ではない。`Window.typescriptDeclarations`は登録済みメソッドだけを`unknown`型で宣言生成します。register macroによる型抽出は未実装であり、native層へ追加しない。

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

document-start scriptはframeと後続ナビゲーションにも適用され得るため、bridge自身が実行時にoriginを検査します。HTTP(S)では初回URLを正規化した同一originだけ、`data:`では初回URLと完全一致する文書だけで初期化します。`about:blank`は親originを継承し得るため対象外です。ほかのscheme、後続の別origin、cross-origin frameではRPCを公開しません。bridge設定は最初に成功した対象`loadUrl`で固定され、後から差し替えられません。これはURL包装向けの全ナビゲーションpolicyではなく、M3 RPCの最小安全境界です。M4のナビゲーションpolicyがこの境界を拡張する場合は、[ADR-0008](../adr/0008-document-start-rpc-bridge.md)を更新して全ターゲットで検証します。

## M4以降の面

```nim
discard window.loadAssets("dist")
discard window.loadEntry("index.html")

window.navigationPolicy = proc(request: NavigationRequest): NavigationDecision =
  if request.url.matches("https://example.com/**"):
    allow()
  else:
    openExternally()

window.onPermission proc(request: PermissionRequest): PermissionDecision =
  deny()
```

プロファイルは`app id / profile`をキーにcookie、local storage、cache、permission、download、settingの永続化ディレクトリを分離します。`ensureProfileLayout`で冪等に領域を作成でき、`writeProfileSetting` / `readProfileSetting`でJSON設定、`writeProfileCookie` / `readProfileCookie`でCookieを安全に保存・読込できます。最初のHTTP(S)読込では、対象domainに一致する非HttpOnly Cookieをdocument-startで復元します。WebViewエンジンのCookieManager/cacheへの完全な自動接続とHttpOnly Cookie復元は未実装です。無処理の権限要求はdenyです。

`loadAssets`はrootディレクトリを正規化してWindowへ固定します。`loadEntry`はroot外の
絶対パス、`..`による脱出、存在しないファイルを拒否してからHTMLを読み込みます。
これはM4のローカルアセット境界であり、外部URLからのasset fetchやMIME配信は未実装です。

`setNavigationRules`はallow/denyの宣言的URL ruleを設定します。denyが優先され、
設定後に未一致のURLは拒否します。nativeはUI callback内で同期評価し、WSLはUI loop
開始前にhostへruleを同期します。任意のWSL側callbackをUI callbackで待つ方式ではありません。

`window.close()`はWindow単位でネイティブWindowを破棄し、Window専用RPCを終了します。
WSLでは認証済みIPCでWindows hostへ中継します。close後の操作と二重closeは
`invalidState`になります。

`window.reload()`は最後に成功したURLを再読込します。URL未読込、close後、または
不正状態では`invalidState`を返します。
