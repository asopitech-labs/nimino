## M3 application facade.  Native object types remain private to this module.

import std/[asyncfutures, strutils]

when defined(linux):
  import std/os

import nimino_native as native

import ./[errors, rpc]

const RpcBootstrapSource = """
(() => {
  const transport =
    globalThis.chrome && globalThis.chrome.webview &&
    typeof globalThis.chrome.webview.postMessage === "function"
      ? (message) => globalThis.chrome.webview.postMessage(message)
      : globalThis.webkit && globalThis.webkit.messageHandlers &&
        globalThis.webkit.messageHandlers.nimino &&
        typeof globalThis.webkit.messageHandlers.nimino.postMessage === "function"
          ? (message) => globalThis.webkit.messageHandlers.nimino.postMessage(message)
          : null;
  if (!transport) return;

  const existing = globalThis.nimino;
  const nimino = existing && typeof existing === "object" ? existing : {};
  globalThis.nimino = nimino;
  if (nimino.__niminoRpcV1) return;
  Object.defineProperty(nimino, "__niminoRpcV1", { value: true });

  let sequence = 0;
  const pending = new Map();
  const nextId = () => `r${Date.now().toString(36)}_${(++sequence).toString(36)}`;

  nimino.__receiveFromNative = (message) => {
    if (!message || message.nimino !== "rpc" || message.kind !== "response" ||
        typeof message.id !== "string") return;
    const request = pending.get(message.id);
    if (!request) return;
    pending.delete(message.id);
    clearTimeout(request.timer);
    if (message.ok === true) {
      request.resolve(message.result);
      return;
    }
    const error = new Error(message.error && typeof message.error.message === "string"
      ? message.error.message : "Nimino RPC request failed");
    error.code = message.error && message.error.code;
    request.reject(error);
  };

  nimino.invoke = (method, params = null, options = {}) => new Promise((resolve, reject) => {
    if (typeof method !== "string" || method.length === 0) {
      reject(new TypeError("Nimino RPC method must be a non-empty string"));
      return;
    }
    const timeoutMs = Number.isInteger(options.timeoutMs) && options.timeoutMs > 0
      ? options.timeoutMs : 30000;
    const id = nextId();
    const timer = setTimeout(() => {
      if (!pending.delete(id)) return;
      transport(JSON.stringify({ nimino: "rpc", kind: "cancel", id }));
      const error = new Error("Nimino RPC request timed out");
      error.code = "timeout";
      reject(error);
    }, timeoutMs);
    pending.set(id, { resolve, reject, timer });
    transport(JSON.stringify({
      nimino: "rpc", kind: "request", id, method, params, timeoutMs
    }));
  });

  nimino.notify = (method, params = null) => {
    if (typeof method !== "string" || method.length === 0) {
      throw new TypeError("Nimino RPC method must be a non-empty string");
    }
    transport(JSON.stringify({ nimino: "rpc", kind: "notification", method, params }));
  };
})();
"""

type
  CoreAppState = enum
    coreCreated
    coreRunning
    coreFinished

  AppOptions* = object
    id*: string
    name*: string

  CoreWindowOptions* = object
    title*: string
    width*: int
    height*: int

  App* = ref object
    state: CoreAppState
    id: string
    name: string
    nativeApp: native.NativeApp
    windows: seq[Window]

  Window* = ref object
    app: App
    nativeWindow: native.NativeWindow
    nativeView: native.NativeWebView
    rpc*: RpcRegistry
    closed: bool

proc mapNativeError(error: native.NativeError): CoreError =
  let kind = case error.kind
    of native.unsupported: platformUnavailable
    of native.invalidState: invalidState
    else: nativeFailure
  coreError(kind, error.operation, error.platformCode, error.detail)

proc fromNative(nativeResult: native.NativeResult): CoreResult =
  if nativeResult.isOk:
    coreSuccess()
  else:
    coreFailure(nativeResult.failure.mapNativeError())

proc fromNativeOf[T](nativeResult: native.NativeResultOf[T]): CoreResultOf[T] =
  if nativeResult.isOk:
    coreSuccessOf(nativeResult.value)
  else:
    coreFailureOf[T](nativeResult.failure.mapNativeError())

proc isWslEnvironment(): bool =
  when defined(linux):
    ## Only the Docker/Xvfb smoke target may exercise the Linux backend on a
    ## WSL kernel.  Normal WSL applications must select nimino-wsl instead.
    if getEnv("NIMINO_TEST_ALLOW_NATIVE_IN_WSL") == "1":
      return false
    try:
      return readFile("/proc/sys/kernel/osrelease").toLowerAscii().contains("microsoft")
    except CatchableError:
      return false
  else:
    false

proc bridgeDocument(html: string): string =
  ## `loadHtml` is the one M3 content source where the bridge can be made
  ## available before application scripts.  URL document-start injection needs
  ## a dedicated native API and remains a separately tracked spike.
  "<script>" & RpcBootstrapSource & "</script>" & html

proc sendRpcReply(window: Window; message: string) =
  if window.isNil or window.closed or window.nativeView.isNil:
    return
  ## `message` is generated by RpcRegistry with Nim's JSON encoder.  It is a
  ## JSON expression, not concatenated user JavaScript.
  discard native.evalJavaScript(window.nativeView,
    "if (window.nimino && typeof window.nimino.__receiveFromNative === 'function') {" &
    "window.nimino.__receiveFromNative(" & message & ");}void 0;")

proc installBridge(window: Window) =
  if window.isNil or window.closed or window.nativeView.isNil:
    return
  discard native.evalJavaScript(window.nativeView, RpcBootstrapSource)

proc configureWindow(window: Window): CoreResult =
  let messageConfigured = native.onMessage(window.nativeView, proc(message: string) =
    if window != nil and not window.closed:
      discard window.rpc.handleMessage(message)
  )
  if not messageConfigured.isOk:
    return coreFailure(messageConfigured.failure.mapNativeError())

  let navigationConfigured = native.onNavigationCompleted(window.nativeView,
    proc(url: string; succeeded: bool) =
      if succeeded:
        window.installBridge()
  )
  if not navigationConfigured.isOk:
    return coreFailure(navigationConfigured.failure.mapNativeError())
  coreSuccess()

proc newApp*(options: AppOptions): CoreResultOf[App] =
  if options.id.len == 0:
    return coreFailureOf[App](coreError(invalidArgument, "app.create",
      detail = "application id must not be empty"))
  if options.name.len == 0:
    return coreFailureOf[App](coreError(invalidArgument, "app.create",
      detail = "application name must not be empty"))
  if isWslEnvironment():
    return coreFailureOf[App](coreError(platformUnavailable, "app.create",
      detail = "WSL requires the nimino-wsl adapter; the Linux GUI backend is not selected"))

  let app = App(state: coreCreated, id: options.id, name: options.name,
                nativeApp: native.newNativeApp())
  let idleConfigured = native.setIdleHandler(app.nativeApp, proc() =
    if app != nil and app.state == coreRunning:
      for window in app.windows:
        if not window.closed:
          window.rpc.tick()
  )
  if not idleConfigured.isOk:
    return coreFailureOf[App](idleConfigured.failure.mapNativeError())
  coreSuccessOf(app)

proc newApp*(id = "tech.asopi.nimino"; name = "Nimino"): CoreResultOf[App] =
  newApp(AppOptions(id: id, name: name))

proc newWindow*(app: App; options: CoreWindowOptions): CoreResultOf[Window] =
  if app.isNil or app.state != coreCreated:
    return coreFailureOf[Window](coreError(invalidState, "window.create"))
  if options.width <= 0 or options.height <= 0:
    return coreFailureOf[Window](coreError(invalidArgument, "window.create",
      detail = "size must be positive"))

  let title = if options.title.len == 0: app.name else: options.title
  let nativeWindow = native.newWindow(app.nativeApp, title, options.width, options.height)
  if not nativeWindow.isOk:
    return coreFailureOf[Window](nativeWindow.failure.mapNativeError())
  let nativeView = native.newWebView(nativeWindow.value)
  if not nativeView.isOk:
    return coreFailureOf[Window](nativeView.failure.mapNativeError())

  let window = Window(app: app, nativeWindow: nativeWindow.value,
                      nativeView: nativeView.value)
  window.rpc = newRpcRegistry(proc(message: string) = window.sendRpcReply(message))
  let configured = window.configureWindow()
  if not configured.isOk:
    window.rpc.close()
    return coreFailureOf[Window](configured.failure)
  app.windows.add(window)
  coreSuccessOf(window)

proc newWindow*(app: App; title = ""; width = 1200; height = 800): CoreResultOf[Window] =
  app.newWindow(CoreWindowOptions(title: title, width: width, height: height))

proc loadUrl*(window: Window; url: string): CoreResult =
  if window.isNil or window.closed or window.nativeView.isNil:
    return coreFailure(coreError(invalidState, "window.loadUrl"))
  native.loadUrl(window.nativeView, url).fromNative()

proc loadHtml*(window: Window; html: string): CoreResult =
  if window.isNil or window.closed or window.nativeView.isNil:
    return coreFailure(coreError(invalidState, "window.loadHtml"))
  native.loadHtml(window.nativeView, bridgeDocument(html)).fromNative()

proc evalJavaScript*(window: Window; script: string): Future[CoreResultOf[string]] =
  let target = newFuture[CoreResultOf[string]]("nimino.core.evalJavaScript")
  result = target
  if window.isNil or window.closed or window.nativeView.isNil:
    target.complete(coreFailureOf[string](coreError(invalidState, "window.evalJavaScript")))
    return
  let source = native.evalJavaScript(window.nativeView, script)
  source.addCallback(proc(completed: Future[native.NativeResultOf[string]]) {.gcsafe.} =
    if target.finished:
      return
    if completed.failed:
      target.complete(coreFailureOf[string](coreError(nativeFailure, "window.evalJavaScript",
        detail = "native JavaScript evaluation failed")))
    else:
      target.complete(completed.read().fromNativeOf())
  )

proc quit*(app: App): CoreResult =
  if app.isNil or app.state == coreFinished or app.nativeApp.isNil:
    return coreFailure(coreError(invalidState, "app.quit"))
  native.quit(app.nativeApp).fromNative()

proc dispose(app: App) =
  if app.isNil:
    return
  for window in app.windows:
    window.closed = true
    if window.rpc != nil:
      window.rpc.close()
    window.nativeView = nil
    window.nativeWindow = nil
    window.app = nil
  app.windows.setLen(0)
  app.nativeApp = nil
  app.state = coreFinished

proc run*(app: App): CoreResult =
  if app.isNil or app.state != coreCreated or app.nativeApp.isNil:
    return coreFailure(coreError(invalidState, "app.run"))
  if app.windows.len == 0:
    return coreFailure(coreError(invalidState, "app.run", detail = "at least one window is required"))
  app.state = coreRunning
  let nativeResult = native.run(app.nativeApp)
  let appResult = nativeResult.fromNative()
  app.dispose()
  appResult
