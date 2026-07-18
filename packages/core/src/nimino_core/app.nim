## M3 application facade.  Native object types remain private to this module.

import std/[asyncfutures, json, os, sequtils, strutils, uri]

when defined(linux):
  import std/options
  import nimino_wsl

import nimino_native as native

import ./[errors, profile, rpc]

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

  Capability* = enum
    multipleWebViews
    transparentWindow
    nativeMenu
    systemTray
    nativeNotification
    customProtocol
    webPermissionEvents

  AppOptions* = object
    id*: string
    name*: string

  CoreWindowOptions* = object
    title*: string
    width*: int
    height*: int
    profile*: string

  NavigationRules* = object
    allow*: seq[string]
    deny*: seq[string]

  NavigationDecision* = enum
    navigationDeny
    navigationAllow

  NavigationRequest* = object
    url*: string

  NewWindowRequest* = object
    url*: string

  WindowError* = object
    operation*: string
    detail*: string

  PermissionKind* = enum
    microphone
    camera
    notifications
    geolocation
    clipboard
    screenCapture

  PermissionDecision* = enum
    permissionDeny
    permissionGrant

  PermissionRequest* = object
    kind*: PermissionKind
    url*: string

  DownloadDecision* = enum
    downloadDeny
    downloadAllow

  DownloadRequest* = object
    url*: string
    suggestedName*: string

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
    profilePath*: string
    profileName: string
    lastUrl: string
    rpc*: RpcRegistry
    documentStartBridgeConfigured: bool
    assetRoot: string
    navigationRules: NavigationRules
    navigationRulesConfigured: bool
    navigationPolicy*: proc(request: NavigationRequest): NavigationDecision
    newWindowHandler*: proc(request: NewWindowRequest): bool
    errorHandler*: proc(error: WindowError)
    permissionHandler*: proc(request: PermissionRequest): PermissionDecision
    downloadHandler*: proc(request: DownloadRequest): DownloadDecision
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

proc navigationPatternMatches(pattern, url: string): bool {.inline.} =
  if pattern.len == 0:
    return false
  if pattern.endsWith("**"):
    return url.startsWith(pattern[0 ..< pattern.len - 2])
  pattern == url

proc navigationAllowed(window: Window; url: string): bool =
  if window.isNil or not window.navigationRulesConfigured:
    return true
  for pattern in window.navigationRules.deny:
    if navigationPatternMatches(pattern, url):
      return false
  for pattern in window.navigationRules.allow:
    if navigationPatternMatches(pattern, url):
      return true
  false

proc decidePermission*(window: Window; request: PermissionRequest): PermissionDecision =
  ## Unhandled permission requests are denied by default.
  if window.isNil or window.permissionHandler.isNil:
    return permissionDeny
  window.permissionHandler(request)

proc decideDownload*(window: Window; request: DownloadRequest): DownloadDecision =
  ## Downloads require an explicit application decision.
  if window.isNil or window.downloadHandler.isNil:
    return downloadDeny
  window.downloadHandler(request)

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
  const WslRpcPollIntervalMs = 10

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
  ## Local HTML is supplied by the application, so the bridge is part of the
  ## document before its scripts execute.
  "<script>" & RpcBootstrapSource & "</script>" & html

proc documentStartBridgeSource(url: string): string =
  ## The native API runs a script in every future document and child frame.
  ## Keep the bridge unavailable unless the initial URL itself identifies a
  ## narrow, serializable origin (or exact application-supplied data URL).
  try:
    let parsed = parseUri(url)
    let scheme = parsed.scheme.toLowerAscii()
    var guard = ""
    case scheme
    of "http", "https":
      if parsed.hostname.len == 0:
        return ""
      let host = if parsed.isIpv6: "[" & parsed.hostname.toLowerAscii() & "]"
                 else: parsed.hostname.toLowerAscii()
      var origin = scheme & "://" & host
      if parsed.port.len > 0 and not
          ((scheme == "http" and parsed.port == "80") or
           (scheme == "https" and parsed.port == "443")):
        origin.add(":" & parsed.port)
      guard = "globalThis.location.origin === " & $(%origin)
    of "data":
      ## Data origins serialize as `null`, so match the complete URL rather
      ## than authorizing every data document in this WebView. `about:blank`
      ## is deliberately excluded: it can inherit a parent document's origin.
      guard = "globalThis.location.href === " & $(%url)
    else:
      return ""
    "(() => { if (!(" & guard & ")) return;\n" & RpcBootstrapSource & "\n})();"
  except CatchableError:
    ""

proc documentStartCookieSource(window: Window; url: string): string =
  if window.isNil or window.app.isNil:
    return ""
  try:
    let parsed = parseUri(url)
    if parsed.scheme.toLowerAscii() notin ["http", "https"] or parsed.hostname.len == 0:
      return ""
    let cookies = profileCookiesForDomain(window.app.id, window.profileName, parsed.hostname)
    if not cookies.isOk or cookies.value.len == 0:
      return ""
    var source = "(() => { if (typeof document === 'undefined') return;"
    for cookie in cookies.value:
      if cookie.secure and parsed.scheme.toLowerAscii() != "https":
        continue
      let value = cookie.name & "=" & cookie.value & "; path=" &
        (if cookie.path.len == 0: "/" else: cookie.path)
      source.add("document.cookie = " & $(%value) & ";")
    source.add("})();")
    source
  except CatchableError:
    ""

proc configureDocumentStartBridge(window: Window; url: string): CoreResult =
  if window.documentStartBridgeConfigured:
    return coreSuccess()
  let source = window.documentStartCookieSource(url) & url.documentStartBridgeSource()
  if source.len == 0:
    return coreSuccess()
  var configured: CoreResult
  case window.app.backend
  of nativeBackend:
    if window.nativeView.isNil:
      return coreFailure(coreError(invalidState, "window.loadUrl"))
    configured = native.setDocumentStartScript(window.nativeView, source).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.webview.setDocumentStartScript", $(%*{
        "webViewId": $window.webViewId,
        "script": source
      }))
      if response.isOk:
        configured = coreSuccess()
      else:
        configured = coreFailure(response.failure)
    else:
      configured = coreFailure(coreError(platformUnavailable, "window.loadUrl"))
  if configured.isOk:
    window.documentStartBridgeConfigured = true
  configured

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

proc configureWindow(window: Window): CoreResult =
  let messageConfigured = native.onMessage(window.nativeView, proc(message: string) =
    if window != nil and not window.closed:
      discard window.rpc.handleMessage(message)
  )
  if not messageConfigured.isOk:
    return coreFailure(messageConfigured.failure.mapNativeError())

  let errorConfigured = native.onError(window.nativeView,
    proc(error: native.NativeError) =
      if not window.errorHandler.isNil:
        try: window.errorHandler(WindowError(operation: error.operation,
          detail: error.detail))
        except CatchableError: discard)
  if not errorConfigured.isOk:
    return coreFailure(errorConfigured.failure.mapNativeError())

  let newWindowConfigured = native.onNewWindowRequested(window.nativeView,
    proc(url: string) =
      if window.newWindowHandler.isNil:
        return
      try: discard window.newWindowHandler(NewWindowRequest(url: url))
      except CatchableError: discard)
  if not newWindowConfigured.isOk:
    return coreFailure(newWindowConfigured.failure.mapNativeError())

  let navigationConfigured = native.onNavigationStarting(window.nativeView,
    proc(url: string): bool =
      if not window.navigationPolicy.isNil:
        return window.navigationPolicy(NavigationRequest(url: url)) == navigationAllow
      window.navigationAllowed(url))
  if not navigationConfigured.isOk:
    return coreFailure(navigationConfigured.failure.mapNativeError())

  let permissionConfigured = native.onPermissionRequested(window.nativeView,
    proc(url: string): bool = window.decidePermission(PermissionRequest(
      kind: microphone, url: url)) == permissionGrant)
  if not permissionConfigured.isOk:
    return coreFailure(permissionConfigured.failure.mapNativeError())

  let downloadConfigured = native.onDownloadStarting(window.nativeView,
    proc(url: string): bool = window.decideDownload(DownloadRequest(
      url: url, suggestedName: "download")) == downloadAllow)
  if not downloadConfigured.isOk:
    return coreFailure(downloadConfigured.failure.mapNativeError())

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

proc supports*(app: App; capability: Capability): CoreResultOf[bool] =
  if app.isNil or app.state == coreFinished:
    return coreFailureOf[bool](coreError(invalidState, "app.supports"))
  case app.backend
  of nativeBackend:
    let nativeCapability = case capability
      of multipleWebViews: native.multipleWebViews
      of transparentWindow: native.transparentWindow
      of nativeMenu: native.nativeMenu
      of systemTray: native.systemTray
      of nativeNotification: native.nativeNotification
      of customProtocol: native.customProtocol
      of webPermissionEvents: native.webPermissionEvents
    coreSuccessOf(app.nativeApp.supports(nativeCapability))
  of wslBackend:
    when defined(linux):
      let response = app.wslCall("app.capabilities", "{}")
      if not response.isOk:
        return coreFailureOf[bool](response.failure)
      try:
        let payload = parseJson(response.value.payload)
        if payload.kind != JObject or not payload.hasKey("capabilities") or
            payload["capabilities"].kind != JArray:
          return coreFailureOf[bool](coreError(nativeFailure, "app.supports",
            detail = "host capabilities response is malformed"))
        for item in payload["capabilities"].items:
          if item.kind == JString and item.getStr() == $capability:
            return coreSuccessOf(true)
        coreSuccessOf(false)
      except CatchableError:
        coreFailureOf[bool](coreError(nativeFailure, "app.supports",
          detail = "host capabilities response is malformed"))
    else:
      coreFailureOf[bool](coreError(platformUnavailable, "app.supports"))

proc newWindow*(app: App; options: CoreWindowOptions): CoreResultOf[Window] =
  if app.isNil or app.state != coreCreated:
    return coreFailureOf[Window](coreError(invalidState, "window.create"))
  if options.width <= 0 or options.height <= 0:
    return coreFailureOf[Window](coreError(invalidArgument, "window.create",
      detail = "size must be positive"))
  let profileName = if options.profile.len == 0: "default" else: options.profile
  let profile = ensureProfileLayout(app.id, profileName)
  if not profile.isOk:
    return coreFailureOf[Window](coreError(invalidArgument, "window.create",
      detail = profile.error))

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
      let window = Window(app: app, windowId: windowId.value, webViewId: webViewId.value,
                          profilePath: profile.value, profileName: profileName)
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
                      nativeView: nativeView.value, profilePath: profile.value,
                      profileName: profileName)
  window.rpc = newRpcRegistry(proc(message: string) = window.sendRpcReply(message))
  let configured = window.configureWindow()
  if not configured.isOk:
    window.rpc.close()
    return coreFailureOf[Window](configured.failure)
  app.windows.add(window)
  coreSuccessOf(window)

proc newWindow*(app: App; title = ""; width = 1200; height = 800;
                profile = "default"): CoreResultOf[Window] =
  app.newWindow(CoreWindowOptions(title: title, width: width, height: height,
    profile: profile))

proc windows*(app: App): seq[Window] =
  if app.isNil or app.state == coreFinished:
    return @[]
  for window in app.windows:
    if not window.isNil and not window.closed:
      result.add(window)

proc windowCount*(app: App): int =
  app.windows().len

proc typescriptDeclarations*(window: Window): CoreResultOf[string] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[string](coreError(invalidState,
      "window.typescriptDeclarations"))
  coreSuccessOf(window.rpc.typescriptDeclarations())

proc writeSetting*(window: Window; key: string; value: JsonNode): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.writeSetting"))
  let written = writeProfileSetting(window.app.id, window.profileName, key, value)
  if written.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.writeSetting", detail = written.error))

proc readSetting*(window: Window; key: string): CoreResultOf[JsonNode] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[JsonNode](coreError(invalidState, "window.readSetting"))
  let loaded = readProfileSetting(window.app.id, window.profileName, key)
  if not loaded.isOk:
    return coreFailureOf[JsonNode](coreError(invalidArgument, "window.readSetting", detail = loaded.error))
  try:
    coreSuccessOf(parseJson(loaded.value))
  except CatchableError:
    coreFailureOf[JsonNode](coreError(nativeFailure, "window.readSetting"))

proc listSettings*(window: Window): CoreResultOf[seq[string]] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[seq[string]](coreError(invalidState, "window.listSettings"))
  let listed = listProfileSettings(window.app.id, window.profileName)
  if not listed.isOk:
    return coreFailureOf[seq[string]](coreError(invalidArgument, "window.listSettings", detail = listed.error))
  coreSuccessOf(listed.value.splitLines().filterIt(it.len > 0))

proc deleteSetting*(window: Window; key: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.deleteSetting"))
  let deleted = deleteProfileSetting(window.app.id, window.profileName, key)
  if deleted.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.deleteSetting", detail = deleted.error))

proc writeCookie*(window: Window; cookie: ProfileCookie): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.writeCookie"))
  let written = writeProfileCookie(window.app.id, window.profileName, cookie)
  if written.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.writeCookie", detail = written.error))

proc readCookie*(window: Window; domain, name: string): CoreResultOf[ProfileCookie] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[ProfileCookie](coreError(invalidState, "window.readCookie"))
  let loaded = readProfileCookie(window.app.id, window.profileName, domain, name)
  if loaded.isOk:
    coreSuccessOf(loaded.value)
  else:
    coreFailureOf[ProfileCookie](coreError(invalidArgument, "window.readCookie", detail = loaded.error))

proc listCookies*(window: Window): CoreResultOf[seq[string]] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[seq[string]](coreError(invalidState, "window.listCookies"))
  let listed = listProfileCookies(window.app.id, window.profileName)
  if not listed.isOk:
    return coreFailureOf[seq[string]](coreError(invalidArgument, "window.listCookies", detail = listed.error))
  let lines = listed.value.splitLines()
  coreSuccessOf(lines.filterIt(it.len > 0))

proc deleteCookie*(window: Window; domain, name: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.deleteCookie"))
  let deleted = deleteProfileCookie(window.app.id, window.profileName, domain, name)
  if deleted.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.deleteCookie", detail = deleted.error))

proc close*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.close"))
  case window.app.backend
  of nativeBackend:
    if window.nativeWindow.isNil:
      return coreFailure(coreError(invalidState, "window.close"))
    let closed = native.close(window.nativeWindow).fromNative()
    if closed.isOk:
      window.closed = true
      window.rpc.close()
    closed
  of wslBackend:
    when defined(linux):
      let closed = window.app.wslCall("native.window.close", $(%*{
        "windowId": $window.windowId
      }))
      if closed.isOk:
        window.closed = true
        window.rpc.close()
        coreSuccess()
      else:
        coreFailure(closed.failure)
    else:
      coreFailure(coreError(platformUnavailable, "window.close"))

proc show*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.show"))
  case window.app.backend
  of nativeBackend:
    native.show(window.nativeWindow).fromNative()
  of wslBackend:
    when defined(linux):
      let shown = window.app.wslCall("native.window.show", $(%*{"windowId": $window.windowId}))
      if shown.isOk: coreSuccess() else: coreFailure(shown.failure)
    else: coreFailure(coreError(platformUnavailable, "window.show"))

proc hide*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.hide"))
  case window.app.backend
  of nativeBackend:
    native.hide(window.nativeWindow).fromNative()
  of wslBackend:
    when defined(linux):
      let hidden = window.app.wslCall("native.window.hide", $(%*{"windowId": $window.windowId}))
      if hidden.isOk: coreSuccess() else: coreFailure(hidden.failure)
    else: coreFailure(coreError(platformUnavailable, "window.hide"))

proc minimize*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.minimize"))
  case window.app.backend
  of nativeBackend: native.minimize(window.nativeWindow).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.window.minimize", $(%*{"windowId": $window.windowId}))
      if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else: coreFailure(coreError(platformUnavailable, "window.minimize"))

proc maximize*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.maximize"))
  case window.app.backend
  of nativeBackend: native.maximize(window.nativeWindow).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.window.maximize", $(%*{"windowId": $window.windowId}))
      if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else: coreFailure(coreError(platformUnavailable, "window.maximize"))

proc restore*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.restore"))
  case window.app.backend
  of nativeBackend: native.restore(window.nativeWindow).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.window.restore", $(%*{"windowId": $window.windowId}))
      if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else: coreFailure(coreError(platformUnavailable, "window.restore"))

proc setResizable*(window: Window; resizable: bool): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setResizable"))
  case window.app.backend
  of nativeBackend:
    native.setResizable(window.nativeWindow, resizable).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.window.setResizable", $(%*{
        "windowId": $window.windowId, "resizable": resizable
      }))
      if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else: coreFailure(coreError(platformUnavailable, "window.setResizable"))

proc setPosition*(window: Window; x, y: int): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setPosition"))
  case window.app.backend
  of nativeBackend:
    native.setPosition(window.nativeWindow, x, y).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.window.setPosition", $(%*{
        "windowId": $window.windowId, "x": x, "y": y
      }))
      if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else: coreFailure(coreError(platformUnavailable, "window.setPosition"))

proc setTitle*(window: Window; title: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setTitle"))
  case window.app.backend
  of nativeBackend:
    if window.nativeWindow.isNil:
      return coreFailure(coreError(invalidState, "window.setTitle"))
    native.setTitle(window.nativeWindow, title).fromNative()
  of wslBackend:
    when defined(linux):
      let updated = window.app.wslCall("native.window.setTitle", $(%*{
        "windowId": $window.windowId,
        "title": title
      }))
      if updated.isOk:
        coreSuccess()
      else:
        coreFailure(updated.failure)
    else:
      coreFailure(coreError(platformUnavailable, "window.setTitle"))

proc setSize*(window: Window; width, height: int): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setSize"))
  if width <= 0 or height <= 0:
    return coreFailure(coreError(invalidArgument, "window.setSize",
      detail = "size must be positive"))
  case window.app.backend
  of nativeBackend:
    if window.nativeWindow.isNil:
      return coreFailure(coreError(invalidState, "window.setSize"))
    native.setSize(window.nativeWindow, width, height).fromNative()
  of wslBackend:
    when defined(linux):
      let updated = window.app.wslCall("native.window.setSize", $(%*{
        "windowId": $window.windowId,
        "width": width,
        "height": height
      }))
      if updated.isOk:
        coreSuccess()
      else:
        coreFailure(updated.failure)
    else:
      coreFailure(coreError(platformUnavailable, "window.setSize"))

proc setNavigationRules*(window: Window; rules: NavigationRules): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setNavigationRules"))
  for pattern in rules.allow & rules.deny:
    if pattern.len == 0:
      return coreFailure(coreError(invalidArgument, "window.setNavigationRules",
        detail = "navigation patterns must not be empty"))
  case window.app.backend
  of nativeBackend:
    discard
  of wslBackend:
    when defined(linux):
      if window.app.wslUiStarted:
        return coreFailure(coreError(invalidState, "window.setNavigationRules",
          detail = "WSL navigation rules must be set before the UI loop starts"))
      let configured = window.app.wslCall("native.webview.setNavigationRules", $(%*{
        "webViewId": $window.webViewId,
        "allow": rules.allow,
        "deny": rules.deny
      }))
      if not configured.isOk:
        return coreFailure(configured.failure)
    else:
      return coreFailure(coreError(platformUnavailable, "window.setNavigationRules"))
  window.navigationRules = rules
  window.navigationRulesConfigured = true
  coreSuccess()

proc setNavigationPolicy*(window: Window;
                          policy: proc(request: NavigationRequest): NavigationDecision): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setNavigationPolicy"))
  window.navigationPolicy = policy
  coreSuccess()

proc onPermission*(window: Window;
                   handler: proc(request: PermissionRequest): PermissionDecision): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onPermission"))
  window.permissionHandler = handler
  coreSuccess()

proc onDownload*(window: Window;
                 handler: proc(request: DownloadRequest): DownloadDecision): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onDownload"))
  window.downloadHandler = handler
  coreSuccess()

proc onNewWindow*(window: Window;
                  handler: proc(request: NewWindowRequest): bool): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onNewWindow"))
  window.newWindowHandler = handler
  coreSuccess()

proc onError*(window: Window; handler: proc(error: WindowError)): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onError"))
  window.errorHandler = handler
  coreSuccess()

proc loadUrl*(window: Window; url: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.loadUrl"))
  let bridge = window.configureDocumentStartBridge(url)
  if not bridge.isOk:
    return bridge
  window.lastUrl = url
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

proc reload*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.reload"))
  if window.lastUrl.len == 0:
    return coreFailure(coreError(invalidState, "window.reload",
      detail = "no URL has been loaded"))
  window.loadUrl(window.lastUrl)

proc loadHtml*(window: Window; html: string): CoreResult

proc loadAssets*(window: Window; directory: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.loadAssets"))
  if directory.len == 0 or not dirExists(directory):
    return coreFailure(coreError(invalidArgument, "window.loadAssets",
      detail = "asset root does not exist"))
  try:
    let root = absolutePath(directory).normalizedPath()
    if not dirExists(root):
      return coreFailure(coreError(invalidArgument, "window.loadAssets",
        detail = "asset root is not a directory"))
    window.assetRoot = root
    coreSuccess()
  except CatchableError:
    coreFailure(coreError(invalidArgument, "window.loadAssets",
      detail = "asset root could not be normalized"))

proc loadEntry*(window: Window; entry = "index.html"): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.loadEntry"))
  if window.assetRoot.len == 0:
    return coreFailure(coreError(invalidState, "window.loadEntry",
      detail = "loadAssets must be called first"))
  if entry.len == 0 or entry.isAbsolute:
    return coreFailure(coreError(invalidArgument, "window.loadEntry",
      detail = "entry must be a relative path"))
  try:
    let root = window.assetRoot.normalizedPath()
    let path = (root / entry).absolutePath().normalizedPath()
    let relative = relativePath(path, root)
    if relative == ".." or relative.startsWith(".." & DirSep) or not fileExists(path):
      return coreFailure(coreError(invalidArgument, "window.loadEntry",
        detail = "entry escapes the asset root or does not exist"))
    let content = readFile(path)
    window.loadHtml(content)
  except CatchableError:
    coreFailure(coreError(nativeFailure, "window.loadEntry",
      detail = "asset entry could not be read"))

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
    if event.kind == ProtocolMessageKind.request and
        event.methodName == "native.webview.policyRequested":
      let policy = parsePolicyRequest(event.payload)
      if not policy.isOk:
        discard app.wslClient.sendResponse(event.requestId, "{}", policy.failure.detail)
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.policy",
          detail = policy.failure.detail))
      var allowed = false
      for window in app.windows:
        if not window.closed and window.webViewId == policy.value.webViewId:
          if policy.value.kind == permissionPolicy:
            allowed = window.decidePermission(PermissionRequest(
              kind: microphone, url: policy.value.url)) == permissionGrant
          elif policy.value.kind == downloadPolicy:
            allowed = window.decideDownload(DownloadRequest(
              url: policy.value.url,
              suggestedName: policy.value.suggestedName)) == downloadAllow
          elif not window.navigationPolicy.isNil:
            allowed = window.navigationPolicy(NavigationRequest(
              url: policy.value.url)) == navigationAllow
          else:
            allowed = window.navigationAllowed(policy.value.url)
          break
      let sent = app.wslClient.sendResponse(event.requestId,
        policyResponseJson(PolicyResponse(allow: allowed)))
      if not sent.isOk:
        let detail = sent.failure.detail
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.policy",
          detail = detail))
      return coreSuccessOf(false)
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
      ## The bridge is installed before the initial navigation.  Completion is
      ## retained as a host lifecycle event but requires no post-load script.
      discard
    of "native.webview.newWindowRequested":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("webViewId") or
            not payload.hasKey("url") or payload["webViewId"].kind != JString or
            payload["url"].kind != JString:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "new-window event is malformed"))
        let webViewId = uint64(parseUInt(payload["webViewId"].getStr()))
        for window in app.windows:
          if not window.closed and window.webViewId == webViewId and
              not window.newWindowHandler.isNil:
            try: discard window.newWindowHandler(NewWindowRequest(
              url: payload["url"].getStr()))
            except CatchableError: discard
            break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "new-window event is malformed"))
    of "native.webview.error":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("webViewId") or
            not payload.hasKey("operation") or not payload.hasKey("detail") or
            payload["webViewId"].kind != JString or
            payload["operation"].kind != JString or
            payload["detail"].kind != JString:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "WebView error event is malformed"))
        let webViewId = uint64(parseUInt(payload["webViewId"].getStr()))
        for window in app.windows:
          if not window.closed and window.webViewId == webViewId and
              not window.errorHandler.isNil:
            try: window.errorHandler(WindowError(operation: payload["operation"].getStr(),
              detail: payload["detail"].getStr()))
            except CatchableError: discard
            break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "WebView error event is malformed"))
    of "native.webview.permissionRequested", "native.webview.downloadStarting",
       "native.webview.policyRequested":
      ## These events require a synchronous decision from the WSL client.  The
      ## current transport is request/response plus one-way events, so silently
      ## ignoring them would turn a protocol mismatch into an implicit grant.
      ## Fail closed until the decision-relay protocol is negotiated.
      return coreFailureOf[bool](coreError(platformUnavailable, "wsl.policy",
        detail = "WSL policy decision relay is not negotiated"))
    else:
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
      ## Do not block indefinitely in the host transport.  A pending Nim RPC
      ## Future has an independent deadline and must expire even when WebView2
      ## has no subsequent event to wake this loop.
      let received = app.wslClient.receiveNextWithin(WslRpcPollIntervalMs)
      if not received.isOk:
        app.dispose()
        return coreFailure(mapProtocolError("app.run", received.failure))
      if received.value.isSome:
        let handled = app.processWslEvent(received.value.get())
        if not handled.isOk:
          app.dispose()
          return coreFailure(handled.failure)
        if handled.value:
          app.dispose()
          return coreSuccess()
      for window in app.windows:
        if not window.closed:
          window.rpc.tick()

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
