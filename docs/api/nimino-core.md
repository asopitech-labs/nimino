# `nimino-core` 最小公開API案

**状態: M3部分実装。Windows/Linux向けの`App`/`Window` facade、Window単位の明示許可リストJSON RPC、WebView bootstrapを実装した。Linuxでは実WebViewのrequest/response/notification往復を確認済みで、Windowsはx64クロスコンパイル済み（Runtime実行は未確認）。WSL adapter、型抽出register macro、JSON codec、プロファイルは未実装。WSLでLinux GUI backendを選んでWSLg表示することは明示的に拒否する。**

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
proc loadUrl*(window: Window, url: string): CoreResult
proc loadHtml*(window: Window, html: string): CoreResult
proc evalJavaScript*(window: Window, script: string): Future[CoreResultOf[string]]
proc quit*(app: App): CoreResult
proc run*(app: App): CoreResult
```

`CoreError`はnative FFI型を公開せず、`invalidArgument`、`invalidState`、`platformUnavailable`、`nativeFailure`を返す。Windows/Linux facadeはnative App/Window/WebViewを内部所有する。WSL hostはまだcoreを利用していないため、このAPIのWSL透過性は未達である。

## M3以降のRPC面

```nim
window.rpc.register("settings.load") do () -> Settings:
  loadSettings()

window.rpc.register("files.save") do (request: SaveRequest) -> Future[SaveResult]:
  saveFile(request)
```

登録APIは明示的なメソッド名を持つ許可リストです。任意のNim関数、OS API、または`ref object`を自動公開しません。各Windowは独立したRPC registryとrequest ID空間を持ち、request/response、notification、timeout、cancel、JSON errorを扱います。

`register`の型抽出マクロ、JSON codec、TypeScript定義生成の可否はM3の設計スパイクです。これはnative層へ追加しません。

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

registryの`tick()`はWindows timerとLinux GLib timeout sourceからUI threadで呼ばれる。Linuxの実smokeは`invoke → 許可済みhandler → response → notify`を確認している。async handlerの実WebView完了・timeout、Window close中の遅延Future、Windows Runtime、WSL host/clientのこの経路は未確認である。

`loadHtml`はbridgeを文書の先頭へ挿入する。URL読込では読込完了後にbridgeを入れるため、リモートURLの最初期scriptからの`invoke`はdocument-start script注入スパイクが完了するまで保証しない。この制約を隠して本番向けURL包装には利用しない。

## M4以降の面

```nim
window.loadAssets("dist")
window.loadEntry("index.html")

window.navigationPolicy = proc(request: NavigationRequest): NavigationDecision =
  if request.url.matches("https://example.com/**"):
    allow()
  else:
    openExternally()

window.onPermission proc(request: PermissionRequest): PermissionDecision =
  deny()
```

プロファイルは`app id / profile`をキーにcookie、local storage、cache、permission、download、settingを分離します。無処理の権限要求はdenyです。
