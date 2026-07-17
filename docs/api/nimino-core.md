# `nimino-core` 最小公開API案

**状態: M3部分実装。GUI非依存の明示許可リストJSON RPC registryは実装・単体テスト済みですが、`App`/`Window` facade、WebView bootstrap、WSL adapter、型抽出register macroは未実装です。**

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

proc newApp*(options: AppOptions): CoreResult[App]
proc newWindow*(app: App, options: CoreWindowOptions): CoreResult[Window]
proc loadUrl*(window: Window, url: string): CoreResult[void]
proc run*(app: App): CoreResult[void]
```

現在のWSL hostはcore未実装のため、このAPIを公開・実装済みであるとは扱いません。M3以降、host adapterをこの面へ移します。

## M3以降のRPC面

```nim
window.rpc.register("settings.load") do () -> Settings:
  loadSettings()

window.rpc.register("files.save") do (request: SaveRequest) -> Future[SaveResult]:
  saveFile(request)
```

登録APIは明示的なメソッド名を持つ許可リストです。任意のNim関数、OS API、または`ref object`を自動公開しません。各Windowは独立したRPC registryとrequest ID空間を持ち、request/response、notification、timeout、cancel、JSON errorを扱います。

`register`の型抽出マクロ、JSON codec、TypeScript定義生成の可否はM3の設計スパイクです。これはnative層へ追加しません。

## 実装済みRPC基盤

```nim
import nimino_core

let rpc = newRpcRegistry(proc(wire: string) =
  # WebViewへのresponse送信はApp/Window統合で担当する
  discard
)

discard rpc.registerSync("settings.load", proc(params: JsonNode): RpcResult =
  rpcSuccess(%*{"theme": "dark"})
)

discard rpc.handleMessage(requestWire)
rpc.tick()
```

wire形式は`nimino = "rpc"`、`kind = request | notification | cancel`、文字列ID、明示的method、JSON params、timeoutMsである。responseは同じIDに`ok/result`または構造化`error`を返す。未登録methodは拒否し、cancel/timeout後の遅延Futureはresponseを二重送信しない。`tick()`は完了Futureとtimeoutを回収するが、現時点ではApp UI loopへ未接続であり、呼出側が実行する必要がある。

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
