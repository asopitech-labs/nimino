## M3 application facade.  Native object types remain private to this module.

import std/[asyncfutures, strutils]

when defined(linux):
  import std/[json, os]
  import nimino_wsl

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

  CoreBackend = enum
    nativeBackend
    wslBackend

  AppOptions* = object
    id*: string
    name*: string

  CoreWindowOptions* = object
    title*: string
    width*: int
    height*: int

  App* = ref object
    state: CoreAppState
    backend: CoreBackend
    id: string
    name: string
    nativeApp: native.NativeApp
    quitRequested: bool
    wslUiStarted: bool
    when defined(linux):
      wslClient: WslClient
    windows: seq[Window]

  Window* = ref object
    app: App
    nativeWindow: native.NativeWindow
    nativeView: native.NativeWebView
    windowId: uint64
    webViewId: uint64
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
  when defined(niminoWsl):
    true
  elif defined(linux):
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

when defined(linux):
  proc mapProtocolError(operation: string; error: ProtocolError): CoreError =
    let kind = case error.kind
      of invalidMessage, invalidFrame, unexpectedEof, frameTooLarge: nativeFailure
      of unsupportedVersion, authenticationFailed: platformUnavailable
    coreError(kind, operation, detail = error.detail)

  proc wslHostExecutable(): string =
    ## Packaging places the host beside or on PATH for the WSL application.
    ## The environment override is intentionally for development/CI only; the
    ## public App API does not expose a platform selector.
    let configured = getEnv("NIMINO_WSL_HOST_EXE")
    if configured.len > 0:
      return configured
    findExe("nimino-wsl-host.exe")

  proc wslCall(app: App; methodName, payload: string): CoreResultOf[ProtocolMessage] =
    if app.isNil or app.wslClient.isNil:
      return coreFailureOf[ProtocolMessage](coreError(invalidState, "wsl." & methodName))
    let reply = app.wslClient.call(methodName, payload)
    if not reply.isOk:
      return coreFailureOf[ProtocolMessage](mapProtocolError("wsl." & methodName, reply.failure))
    coreSuccessOf(reply.value)

  proc responseId(response: ProtocolMessage; name: string): CoreResultOf[uint64] =
    try:
      let node = parseJson(response.payload)
      if node.kind != JObject or not node.hasKey(name) or node[name].kind != JString:
        return coreFailureOf[uint64](coreError(nativeFailure, "wsl.response",
          detail = "host response is missing " & name))
      coreSuccessOf(uint64(parseUInt(node[name].getStr())))
    except CatchableError:
      coreFailureOf[uint64](coreError(nativeFailure, "wsl.response",
        detail = "host response is malformed"))

proc bridgeDocument(html: string): string =
  ## `loadHtml` is the one M3 content source where the bridge can be made
  ## available before application scripts.  URL document-start injection needs
  ## a dedicated native API and remains a separately tracked spike.
  "<script>" & RpcBootstrapSource & "</script>" & html

proc sendRpcReply(window: Window; message: string) =
  if window.isNil or window.closed or window.app.isNil:
    return
  ## `message` is generated by RpcRegistry with Nim's JSON encoder.  It is a
  ## JSON expression, not concatenated user JavaScript.
  let script = "if (window.nimino && typeof window.nimino.__receiveFromNative === 'function') {" &
    "window.nimino.__receiveFromNative(" & message & ");}void 0;"
  case window.app.backend
  of nativeBackend:
    if not window.nativeView.isNil:
      discard native.evalJavaScript(window.nativeView, script)
  of wslBackend:
    when defined(linux):
      if window.webViewId != 0:
        discard window.app.wslCall("native.webview.evalJavaScript", $(%*{
          "webViewId": $window.webViewId,
          "script": script
        }))

proc installBridge(window: Window) =
  if window.isNil or window.closed or window.app.isNil:
    return
  case window.app.backend
  of nativeBackend:
    if not window.nativeView.isNil:
      discard native.evalJavaScript(window.nativeView, RpcBootstrapSource)
  of wslBackend:
    when defined(linux):
      if window.webViewId != 0:
        discard window.app.wslCall("native.webview.evalJavaScript", $(%*{
          "webViewId": $window.webViewId,
          "script": RpcBootstrapSource
        }))

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
    when defined(linux):
      let hostExecutable = wslHostExecutable()
      if hostExecutable.len == 0:
        return coreFailureOf[App](coreError(platformUnavailable, "app.create",
          detail = "nimino-wsl-host.exe was not found"))
      let launched = launchHost(hostExecutable)
      if not launched.isOk:
        return coreFailureOf[App](mapProtocolError("app.create", launched.failure))
      return coreSuccessOf(App(
        state: coreCreated,
        backend: wslBackend,
        id: options.id,
        name: options.name,
        wslClient: launched.value
      ))
    else:
      return coreFailureOf[App](coreError(platformUnavailable, "app.create",
        detail = "WSL requires the nimino-wsl adapter"))

  let app = App(state: coreCreated, backend: nativeBackend, id: options.id, name: options.name,
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
  if app.backend == wslBackend:
    when defined(linux):
      let remoteWindow = app.wslCall("native.window.create", $(%*{
        "title": title,
        "width": options.width,
        "height": options.height
      }))
      if not remoteWindow.isOk:
        return coreFailureOf[Window](remoteWindow.failure)
      let windowId = remoteWindow.value.responseId("windowId")
      if not windowId.isOk:
        return coreFailureOf[Window](windowId.failure)
      let remoteView = app.wslCall("native.webview.create", $(%*{
        "windowId": $windowId.value
      }))
      if not remoteView.isOk:
        return coreFailureOf[Window](remoteView.failure)
      let webViewId = remoteView.value.responseId("webViewId")
      if not webViewId.isOk:
        return coreFailureOf[Window](webViewId.failure)
      let window = Window(app: app, windowId: windowId.value, webViewId: webViewId.value)
      window.rpc = newRpcRegistry(proc(message: string) = window.sendRpcReply(message))
      app.windows.add(window)
      return coreSuccessOf(window)
    else:
      return coreFailureOf[Window](coreError(platformUnavailable, "window.create"))

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
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.loadUrl"))
  case window.app.backend
  of nativeBackend:
    if window.nativeView.isNil:
      return coreFailure(coreError(invalidState, "window.loadUrl"))
    native.loadUrl(window.nativeView, url).fromNative()
  of wslBackend:
    when defined(linux):
      let loaded = window.app.wslCall("native.webview.loadUrl", $(%*{
        "webViewId": $window.webViewId,
        "url": url
      }))
      if loaded.isOk:
        window.app.wslUiStarted = true
        coreSuccess()
      else:
        coreFailure(loaded.failure)
    else:
      coreFailure(coreError(platformUnavailable, "window.loadUrl"))

proc loadHtml*(window: Window; html: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.loadHtml"))
  let document = bridgeDocument(html)
  case window.app.backend
  of nativeBackend:
    if window.nativeView.isNil:
      return coreFailure(coreError(invalidState, "window.loadHtml"))
    native.loadHtml(window.nativeView, document).fromNative()
  of wslBackend:
    when defined(linux):
      let loaded = window.app.wslCall("native.webview.loadHtml", $(%*{
        "webViewId": $window.webViewId,
        "html": document
      }))
      if loaded.isOk:
        window.app.wslUiStarted = true
        coreSuccess()
      else:
        coreFailure(loaded.failure)
    else:
      coreFailure(coreError(platformUnavailable, "window.loadHtml"))

proc evalJavaScript*(window: Window; script: string): Future[CoreResultOf[string]] =
  let target = newFuture[CoreResultOf[string]]("nimino.core.evalJavaScript")
  result = target
  if window.isNil or window.closed or window.app.isNil:
    target.complete(coreFailureOf[string](coreError(invalidState, "window.evalJavaScript")))
    return
  case window.app.backend
  of nativeBackend:
    if window.nativeView.isNil:
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
  of wslBackend:
    when defined(linux):
      let evaluated = window.app.wslCall("native.webview.evalJavaScript", $(%*{
        "webViewId": $window.webViewId,
        "script": script
      }))
      if not evaluated.isOk:
        target.complete(coreFailureOf[string](evaluated.failure))
        return
      try:
        let payload = parseJson(evaluated.value.payload)
        if payload.kind != JObject or not payload.hasKey("result") or
            payload["result"].kind != JString:
          target.complete(coreFailureOf[string](coreError(nativeFailure,
            "window.evalJavaScript", detail = "host response is malformed")))
        else:
          target.complete(coreSuccessOf(payload["result"].getStr()))
      except CatchableError:
        target.complete(coreFailureOf[string](coreError(nativeFailure,
          "window.evalJavaScript", detail = "host response is malformed")))
    else:
      target.complete(coreFailureOf[string](coreError(platformUnavailable,
        "window.evalJavaScript")))

proc dispose(app: App)

when defined(linux):
  proc processWslEvent(app: App; event: ProtocolMessage): CoreResultOf[bool] =
    if event.kind != ProtocolMessageKind.event:
      return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
        detail = "unexpected host response"))
    case event.methodName
    of "app.closed":
      return coreSuccessOf(true)
    of "app.error":
      return coreFailureOf[bool](coreError(nativeFailure, "app.run",
        detail = "WSL host reported an application error"))
    of "native.webview.message":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("webViewId") or
            not payload.hasKey("message") or payload["webViewId"].kind != JString or
            payload["message"].kind != JString:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "WebView message event is malformed"))
        let webViewId = uint64(parseUInt(payload["webViewId"].getStr()))
        for window in app.windows:
          if not window.closed and window.webViewId == webViewId:
            discard window.rpc.handleMessage(payload["message"].getStr())
            break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "WebView message event is malformed"))
    of "native.webview.navigationCompleted":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("webViewId") or
            not payload.hasKey("succeeded") or payload["webViewId"].kind != JString or
            payload["succeeded"].kind != JBool:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "navigation completion event is malformed"))
        if payload["succeeded"].getBool():
          let webViewId = uint64(parseUInt(payload["webViewId"].getStr()))
          for window in app.windows:
            if not window.closed and window.webViewId == webViewId:
              window.installBridge()
              break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "navigation completion event is malformed"))
    else:
      ## M4 navigation, permission, and download policies have no core event
      ## surface yet.  The host has already applied its safe native defaults.
      discard
    for window in app.windows:
      if not window.closed:
        window.rpc.tick()
    coreSuccessOf(false)

  proc runWsl(app: App): CoreResult =
    if not app.wslUiStarted:
      return coreFailure(coreError(invalidState, "app.run",
        detail = "a WSL window must load URL or HTML before run"))
    app.state = coreRunning
    while true:
      let buffered = app.wslClient.takeEvents()
      for event in buffered:
        let handled = app.processWslEvent(event)
        if not handled.isOk:
          app.dispose()
          return coreFailure(handled.failure)
        if handled.value:
          app.dispose()
          return coreSuccess()
      let received = app.wslClient.receiveNext()
      if not received.isOk:
        app.dispose()
        return coreFailure(mapProtocolError("app.run", received.failure))
      let handled = app.processWslEvent(received.value)
      if not handled.isOk:
        app.dispose()
        return coreFailure(handled.failure)
      if handled.value:
        app.dispose()
        return coreSuccess()

proc quit*(app: App): CoreResult =
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.quit"))
  case app.backend
  of nativeBackend:
    if app.nativeApp.isNil:
      return coreFailure(coreError(invalidState, "app.quit"))
    native.quit(app.nativeApp).fromNative()
  of wslBackend:
    when defined(linux):
      let stopped = app.wslCall("app.shutdown", "{}")
      if not stopped.isOk:
        return coreFailure(stopped.failure)
      app.quitRequested = true
      if app.state == coreCreated:
        app.dispose()
      coreSuccess()
    else:
      coreFailure(coreError(platformUnavailable, "app.quit"))

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
  when defined(linux):
    if app.wslClient != nil:
      discard app.wslClient.close()
      app.wslClient = nil
  app.state = coreFinished

proc run*(app: App): CoreResult =
  if app.isNil or app.state != coreCreated:
    return coreFailure(coreError(invalidState, "app.run"))
  if app.windows.len == 0:
    return coreFailure(coreError(invalidState, "app.run", detail = "at least one window is required"))
  if app.backend == wslBackend:
    when defined(linux):
      return app.runWsl()
    else:
      return coreFailure(coreError(platformUnavailable, "app.run"))
  if app.nativeApp.isNil:
    return coreFailure(coreError(invalidState, "app.run"))
  app.state = coreRunning
  let nativeResult = native.run(app.nativeApp)
  let appResult = nativeResult.fromNative()
  app.dispose()
  appResult
