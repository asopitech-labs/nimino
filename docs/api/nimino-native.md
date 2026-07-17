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

  NativeResult* = object
    isOk*: bool
    error*: NativeError

  NativeResultOf*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: NativeError

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
proc newNativeApp*(): NativeApp
proc supports*(app: NativeApp, capability: Capability): bool
proc run*(app: NativeApp): NativeResult
proc quit*(app: NativeApp): NativeResult
proc close*(app: NativeApp): NativeResult
proc postToUi*(app: NativeApp, callback: proc() {.gcsafe.}): NativeResult

proc newWindow*(app: NativeApp, options: WindowOptions): NativeResultOf[NativeWindow]
proc close*(window: NativeWindow): NativeResult
proc setTitle*(window: NativeWindow, title: string): NativeResult
proc show*(window: NativeWindow): NativeResult
proc hide*(window: NativeWindow): NativeResult
proc minimize*(window: NativeWindow): NativeResult
proc maximize*(window: NativeWindow): NativeResult
proc state*(window: NativeWindow): NativeState
proc onResize*(window: NativeWindow, callback: proc(bounds: Rect) {.gcsafe.})
proc onCloseRequest*(window: NativeWindow, callback: proc(): bool {.gcsafe.})

proc newWebView*(window: NativeWindow, bounds: Option[Rect] = none(Rect)):
  NativeResultOf[NativeWebView]
proc close*(view: NativeWebView): NativeResult
proc loadUrl*(view: NativeWebView, url: string): NativeResult
proc loadHtml*(view: NativeWebView, html: string, baseUrl = "about:blank"):
  NativeResult
proc evalJavaScript*(view: NativeWebView, script: string): Future[NativeResultOf[string]]
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
let window = app.newWindow(WindowOptions(title: "Nimino", width: 1200, height: 800)).value
let view = window.newWebView().value
discard view.loadUrl("https://example.com")
discard app.run()
```

`.value`を伴わない便利構文を導入する場合も、失敗を黙殺するAPIにはしません。WindowとWebViewを同一型に統合しないため、将来は同じWindowへ複数のViewを追加できます。
