# `nimino-native` 公開API案

**状態: M0 API案。未実装・未安定。**

このAPIはWindow/WebViewと低水準イベントだけを提供します。RPC、プロファイル、権限ポリシー、アセット配信、URL包装、WSL通信を含めません。

## 型

```nim
type
  NativeApp* = ref object
  NativeWindow* = ref object
  NativeWebView* = ref object

  NativeState* = enum
    pending, ready, closing, closed

  NativeErrorKind* = enum
    unsupported, invalidState, permissionDenied, osError, webViewError

  NativeError* = object
    kind*: NativeErrorKind
    operation*: string
    platformCode*: int32
    detail*: string             # token/cookie/URLの認証情報を含めない

  NativeResult*[T] = Result[T, NativeError]

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

`Result`の正確なimportとエラーを伝播するergonomicsは、固定したNimコンテナでM1のコンパイルスパイクを通して決めます。ただし、失敗可能な操作が上記5分類を失う設計にはしません。

## 操作案

```nim
proc newNativeApp*(): NativeApp
proc supports*(app: NativeApp, capability: Capability): bool
proc run*(app: NativeApp): NativeResult[void]
proc quit*(app: NativeApp): NativeResult[void]
proc close*(app: NativeApp): NativeResult[void]
proc postToUi*(app: NativeApp, callback: proc() {.gcsafe.}): NativeResult[void]

proc newWindow*(app: NativeApp, options: WindowOptions): NativeResult[NativeWindow]
proc close*(window: NativeWindow): NativeResult[void]
proc setTitle*(window: NativeWindow, title: string): NativeResult[void]
proc show*(window: NativeWindow): NativeResult[void]
proc hide*(window: NativeWindow): NativeResult[void]
proc minimize*(window: NativeWindow): NativeResult[void]
proc maximize*(window: NativeWindow): NativeResult[void]
proc state*(window: NativeWindow): NativeState
proc onResize*(window: NativeWindow, callback: proc(bounds: Rect) {.gcsafe.})
proc onCloseRequest*(window: NativeWindow, callback: proc(): bool {.gcsafe.})

proc newWebView*(window: NativeWindow, bounds: Option[Rect] = none(Rect)):
  NativeResult[NativeWebView]
proc close*(view: NativeWebView): NativeResult[void]
proc loadUrl*(view: NativeWebView, url: string): NativeResult[void]
proc loadHtml*(view: NativeWebView, html: string, baseUrl = "about:blank"):
  NativeResult[void]
proc evalJavaScript*(view: NativeWebView, script: string): Future[NativeResult[string]]
proc onMessage*(view: NativeWebView, callback: proc(message: string) {.gcsafe.})
proc onNavigationStarting*(view: NativeWebView,
  callback: proc(request: NavigationRequest): bool {.gcsafe.})
proc onNavigationCompleted*(view: NativeWebView,
  callback: proc(url: string, succeeded: bool) {.gcsafe.})
proc onNewWindowRequested*(view: NativeWebView,
  callback: proc(url: string): bool {.gcsafe.})
proc onError*(view: NativeWebView, callback: proc(error: NativeError) {.gcsafe.})
```

`newWebView`が`pending`の間でも、M1では最初の`loadUrl`を一件だけ保持し、ready後に実行します。Windowが先に閉じたときは要求を成功扱いせず`invalidState`または`webViewError`で完了します。M2以降では`loadHtml`、`evalJavaScript`、message callbackを追加します。

## 利用イメージ

エラー処理を省略する簡潔な最終形は次を目標とします。M0時点では実行できません。

```nim
import nimino_native

let app = newNativeApp()
let window = app.newWindow(WindowOptions(title: "Nimino", width: 1200, height: 800)).get()
let view = window.newWebView().get()
discard view.loadUrl("https://example.com")
discard app.run()
```

`.get()`を伴わない便利構文を導入する場合も、失敗を黙殺するAPIにはしません。WindowとWebViewを同一型に統合しないため、将来は同じWindowへ複数のViewを追加できます。
