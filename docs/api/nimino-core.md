# `nimino-core` 最小公開API案

**状態: M0 API案。M3以降の対象であり、未実装です。**

`nimino-core`は通常の利用者向けの高水準APIです。`nimino-native`を内包してもFFI型を公開せず、`nimino-pack`へはこの公開面だけを提供します。

## M1で必要な最小面

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

M1のWSL hostはcore未実装のため、これを公開・実装済みであるとは扱いません。M3以降、host adapterをこの面へ移します。

## M3以降のRPC面

```nim
window.rpc.register("settings.load") do () -> Settings:
  loadSettings()

window.rpc.register("files.save") do (request: SaveRequest) -> Future[SaveResult]:
  saveFile(request)
```

登録APIは明示的なメソッド名を持つ許可リストです。任意のNim関数、OS API、または`ref object`を自動公開しません。各Windowは独立したRPC registryとrequest ID空間を持ち、request/response、notification、timeout、cancel、JSON errorを扱います。

`register`の型抽出マクロ、JSON codec、TypeScript定義生成の可否はM3の設計スパイクです。これはnative層へ追加しません。

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
