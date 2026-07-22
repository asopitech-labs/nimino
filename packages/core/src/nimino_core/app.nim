## M3 application facade.  Native object types remain private to this module.

import std/[asyncfutures, base64, json, os, osproc, sequtils, strutils, uri]
import std/httpclient except ProtocolError

when defined(linux):
  import std/options
  import nimino_wsl

import nimino_native as native

import ./[errors, logging, profile, rpc]

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

  CustomProtocolRequest* = object
    methodName*: string
    url*: string
    path*: string

  CustomProtocolResponse* = object
    statusCode*: int
    mimeType*: string
    body*: string

  CustomProtocolHandler* = proc(
    request: CustomProtocolRequest): CustomProtocolResponse {.closure.}

  DeepLinkHandler* = proc(url: string) {.closure.}

  DesktopMenuItem* = object
    ## A validated command item for the application menu or system tray.
    id*: uint32
    title*: string
    enabled*: bool

  DesktopNotification* = object
    id*: string
    title*: string
    body*: string

  FileDialogOptions* = object
    title*: string
    save*: bool
    multiple*: bool
    suggestedName*: string

  CoreWindowOptions* = object
    title*: string
    width*: int
    height*: int
    profile*: string
    inlineRemoteAssets*: bool
    injectionCss*: seq[string]
    injectionJavaScript*: seq[string]
    injectionEnabled*: bool
    ## Disable browser developer tools for production windows.
    disableDevTools*: bool

  NavigationRules* = object
    allow*: seq[string]
    deny*: seq[string]

  NavigationDecision* = enum
    navigationDeny
    navigationAllow
    navigationExternal

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

  StoredPermission* = object
    ## A persisted decision scoped to one normalized HTTP(S) origin.
    origin*: string
    kind*: PermissionKind
    decision*: PermissionDecision

  DownloadDecision* = enum
    downloadDeny
    downloadAllow

  DownloadRequest* = object
    url*: string
    suggestedName*: string

  DownloadState* = enum
    downloadStarted
    downloadProgress
    downloadCompleted
    downloadFailed
    downloadCancelled

  DownloadEvent* = object
    request*: DownloadRequest
    state*: DownloadState
    progress*: float

  WebViewProfileDataKind* = enum
    ## Data owned by the platform WebView engine, rather than Nimino's
    ## profile metadata directories.
    webViewCookies
    webViewLocalStorage
    webViewCache

  PendingWslProfileDataClear = object
    requestId: uint64
    target: Future[CoreResult]

  PendingWslFileDialog = object
    requestId: uint64
    target: Future[CoreResultOf[seq[string]]]

  App* = ref object
    state: CoreAppState
    backend: CoreBackend
    id: string
    name: string
    nativeApp: native.NativeApp
    quitRequested: bool
    wslUiStarted: bool
    readyHandler: proc()
    beforeQuitHandler: proc(): bool
    exitHandler: proc()
    nativeMenuHandler: proc(itemId: uint32)
    trayMenuHandler: proc(itemId: uint32)
    notificationActivatedHandler: proc(notificationId: string)
    deepLinkHandler: DeepLinkHandler
    ## Activation can arrive before application bootstrap registers its
    ## callback (for example a terminated-process launcher). Keep validated
    ## URLs until `onDeepLink` installs the consumer instead of dropping them.
    pendingDeepLinks: seq[string]
    appLogger: Logger
    customProtocolHandler: CustomProtocolHandler
    when defined(linux):
      wslClient: WslClient
      pendingWslProfileDataClears: seq[PendingWslProfileDataClear]
      pendingWslFileDialogs: seq[PendingWslFileDialog]
    windows: seq[Window]

  Window* = ref object
    app: App
    nativeWindow: native.NativeWindow
    nativeView: native.NativeWebView
    webViews: seq[WebView]
    windowId: uint64
    webViewId: uint64
    profilePath*: string
    profileName: string
    lastUrl: string
    rpc*: RpcRegistry
    documentStartBridgeScript: string
    assetRoot: string
    injectionCss: seq[string]
    injectionJavaScript: seq[string]
    injectionEnabled: bool
    devToolsEnabled: bool
    navigationRules: NavigationRules
    navigationRulesConfigured: bool
    navigationPolicy*: proc(request: NavigationRequest): NavigationDecision
    navigationCompletedHandler*: proc(url: string; succeeded: bool)
    externalNavigationHandler*: proc(request: NavigationRequest)
    newWindowHandler*: proc(request: NewWindowRequest): bool
    closeRequestedHandler*: proc(): bool
    closedHandler*: proc()
    resizeHandler*: proc(width, height: int)
    errorHandler*: proc(error: WindowError)
    permissionHandler*: proc(request: PermissionRequest): PermissionDecision
    downloadHandler*: proc(request: DownloadRequest): DownloadDecision
    downloadEventHandler*: proc(event: DownloadEvent)
    closed: bool
    inlineRemoteAssets: bool

  WebView* = ref object
    window: Window
    nativeView: native.NativeWebView
    webViewId: uint64
    messageHandler: proc(message: string)
    closed: bool

proc mapNativeError(error: native.NativeError): CoreError =
  let kind = case error.kind
    of native.unsupported: platformUnavailable
    of native.invalidArgument: invalidArgument
    of native.invalidState: invalidState
    of native.permissionDenied: permissionDenied
    of native.osError: osError
    of native.webViewError: webViewError
  
  coreError(kind, error.operation, error.platformCode, error.detail)

proc normalizeCustomProtocolResponse(response: CustomProtocolResponse):
    CustomProtocolResponse =
  ## Keep the WSL relay identical to native dispatch: invalid status codes
  ## become a deterministic server error and an empty MIME type uses the
  ## WebView-safe binary default.  The handler body is preserved verbatim.
  if response.statusCode < 100 or response.statusCode > 599:
    return CustomProtocolResponse(statusCode: 500, mimeType: "text/plain",
      body: "Invalid custom protocol response")
  result = response
  if result.mimeType.len == 0:
    result.mimeType = "application/octet-stream"

proc findWebView(window: Window; webViewId: uint64): WebView =
  if window.isNil:
    return nil
  for view in window.webViews:
    if not view.isNil and not view.closed and view.webViewId == webViewId:
      return view

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
  if pattern.find('*') < 0:
    return pattern == url
  var cursor = 0
  var first = true
  for part in pattern.split('*'):
    if part.len == 0:
      continue
    let found = url.find(part, cursor)
    if found < 0 or (first and found != 0):
      return false
    cursor = found + part.len
    first = false
  pattern.endsWith('*') or cursor == url.len

proc matchesNavigationPattern*(pattern, url: string): bool =
  ## Pure URL-rule matcher for policy tests and manifest tooling.
  navigationPatternMatches(pattern, url)

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

proc openExternally*(window: Window; url: string): CoreResult

proc applyNavigationDecision*(window: Window; request: NavigationRequest): bool =
  let decision = if window.navigationPolicy.isNil:
                   if window.navigationAllowed(request.url): navigationAllow else: navigationDeny
                 else: window.navigationPolicy(request)
  case decision
  of navigationAllow: true
  of navigationDeny: false
  of navigationExternal:
    if not window.externalNavigationHandler.isNil:
      try: window.externalNavigationHandler(request)
      except CatchableError: discard
    else:
      ## An explicit external decision is actionable even without a callback.
      ## Keep the current WebView navigation cancelled regardless of launch
      ## success; callers that need fallback UI can register the callback.
      discard window.openExternally(request.url)
    false

proc decidePermission*(window: Window; request: PermissionRequest): PermissionDecision =
  ## A saved profile decision wins over the callback. Unhandled requests are
  ## denied for this request only; default denial is not persisted because a
  ## handler may be registered later in the application lifecycle.
  if window.isNil or window.app.isNil:
    return permissionDeny
  let kind = case request.kind
    of microphone: "microphone"
    of camera: "camera"
    of notifications: "notifications"
    of geolocation: "geolocation"
    of clipboard: "clipboard"
    of screenCapture: "screenCapture"
  let saved = readProfilePermission(window.app.id, window.profileName,
    request.url, kind)
  if saved.isOk:
    return if saved.value.decision == "grant": permissionGrant else: permissionDeny
  if window.permissionHandler.isNil:
    return permissionDeny
  try:
    result = window.permissionHandler(request)
    let encoded = if result == permissionGrant: "grant" else: "deny"
    discard writeProfilePermission(window.app.id, window.profileName,
      request.url, kind, encoded)
  except CatchableError:
    result = permissionDeny

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
    if error.nativeKind.len > 0:
      let kind = case error.nativeKind
        of "unsupported": platformUnavailable
        of "invalidArgument": invalidArgument
        of "invalidState": invalidState
        of "permissionDenied": permissionDenied
        of "osError": osError
        of "webViewError": webViewError
        else: nativeFailure
      let nativeOperation = if error.nativeOperation.len > 0:
          error.nativeOperation
        else: operation
      let nativeDetail = if error.nativeDetail.len > 0:
          error.nativeDetail
        else: error.detail
      return coreError(kind, nativeOperation,
        platformCode = error.nativePlatformCode, detail = nativeDetail)
    let kind = case error.kind
      of invalidMessage, invalidFrame, unexpectedEof, frameTooLarge, timedOut: nativeFailure
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

  proc wslSupportsProfileDataClear(app: App): bool {.inline.} =
    not app.isNil and not app.wslClient.isNil and
      WebViewProfileDataClearCapability in app.wslClient.capabilities

  proc wslSupportsCookieManager(app: App): bool {.inline.} =
    not app.isNil and not app.wslClient.isNil and
      WebViewCookieManagerCapability in app.wslClient.capabilities

  proc wslNativeErrorKind(value: string): CoreErrorKind =
    case value
    of "unsupported": platformUnavailable
    of "invalidArgument": invalidArgument
    of "invalidState": invalidState
    of "permissionDenied": permissionDenied
    of "osError": osError
    of "webViewError": webViewError
    else: nativeFailure

  proc wslProfileDataKinds(kinds: set[WebViewProfileDataKind]): JsonNode =
    result = newJArray()
    for kind in kinds:
      case kind
      of webViewCookies:
        result.add(%"cookies")
      of webViewLocalStorage:
        result.add(%"localStorage")
      of webViewCache:
        result.add(%"cache")

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

proc injectionDocumentStartSource(window: Window): string

proc bridgeDocument(window: Window; html: string): string =
  ## Local HTML is supplied by the application, so the bridge is part of the
  ## document before its scripts execute.
  "<script>" & RpcBootstrapSource & window.injectionDocumentStartSource() &
    "</script>" & html

proc injectionDocumentStartSource(window: Window): string =
  if window.isNil or not window.injectionEnabled:
    return ""
  var source = ""
  for css in window.injectionCss:
    source.add("(() => { const install = () => { const style = document.createElement('style'); " &
      "style.setAttribute('data-nimino-injection', 'css'); style.textContent = " &
      $(%css) & "; (document.head || document.documentElement || document).appendChild(style); }; " &
      "if (document.head || document.documentElement) install(); else " &
      "document.addEventListener('DOMContentLoaded', install, { once: true }); })();")
  for script in window.injectionJavaScript:
    source.add("(() => { try { " & script & " } catch (_) {} })();")
  source

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
    of "file":
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
    let cookies = profileCookiesForUrl(window.app.id, window.profileName, url)
    if not cookies.isOk or cookies.value.len == 0:
      return ""
    var source = "(() => { if (typeof document === 'undefined') return;"
    for cookie in cookies.value:
      if cookie.httpOnly:
        ## HttpOnly cookies may be mirrored from the engine for inspection,
        ## but must never be downgraded through document.cookie injection.
        continue
      let cookiePath = if cookie.path.len == 0: "/" else: cookie.path
      let requestPath = if parsed.path.len == 0: "/" else: parsed.path
      if not requestPath.startsWith(cookiePath) or
          (cookiePath[^1] != '/' and requestPath.len > cookiePath.len and
            requestPath[cookiePath.len] != '/'):
        continue
      let value = cookie.name & "=" & cookie.value & "; path=" &
        cookiePath
      source.add("document.cookie = " & $(%value) & ";")
    source.add("})();")
    source
  except CatchableError:
    ""

proc configureDocumentStartBridge(window: Window; url: string): CoreResult =
  let source = window.documentStartCookieSource(url) & url.documentStartBridgeSource() &
    window.injectionDocumentStartSource()
  if source.len == 0 and window.documentStartBridgeScript.len == 0:
    return coreSuccess()
  ## HTTP(S) bridge guards are origin-scoped, so two paths commonly produce
  ## exactly the same script.  Compare the effective script rather than the
  ## raw URL; otherwise every same-origin navigation attempts an unnecessary
  ## document-start re-registration after the WebView is already running.
  if window.documentStartBridgeScript == source:
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
    window.documentStartBridgeScript = source
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

proc suggestedDownloadName(url: string): string =
  try:
    let parsed = parseUri(url)
    let decoded = decodeUrl(parsed.path)
    let parts = splitFile(decoded)
    let name = parts.name & parts.ext
    if name.len > 0 and name notin [".", ".."]:
      return name
  except CatchableError:
    discard
  "download"

proc syncDocumentCookies*(window: Window): Future[CoreResult]
proc downloadPath*(window: Window; suggestedName: string): CoreResultOf[string]

proc configureDevTools(window: Window; enabled: bool): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setDevToolsEnabled"))
  var configured: CoreResult
  case window.app.backend
  of nativeBackend:
    configured = native.setDevToolsEnabled(window.nativeView, enabled).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.webview.setDevToolsEnabled", $(%*{
        "webViewId": $window.webViewId,
        "enabled": enabled
      }))
      configured = if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else:
      configured = coreFailure(coreError(platformUnavailable,
        "window.setDevToolsEnabled"))
  if configured.isOk:
    window.devToolsEnabled = enabled
  configured

proc configureWindow(window: Window): CoreResult =
  let messageConfigured = native.onMessage(window.nativeView, proc(message: string) =
    if window != nil and not window.closed:
      if window.webViews.len > 0 and not window.webViews[0].messageHandler.isNil:
        try: window.webViews[0].messageHandler(message)
        except CatchableError: discard
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
    proc(url: string): bool =
      if window.newWindowHandler.isNil:
        return true
      try: window.newWindowHandler(NewWindowRequest(url: url))
      except CatchableError: true)
  if not newWindowConfigured.isOk:
    return coreFailure(newWindowConfigured.failure.mapNativeError())

  let navigationConfigured = native.onNavigationStarting(window.nativeView,
    proc(url: string): bool =
      window.applyNavigationDecision(NavigationRequest(url: url)))
  if not navigationConfigured.isOk:
    return coreFailure(navigationConfigured.failure.mapNativeError())

  let completionConfigured = native.onNavigationCompleted(window.nativeView,
    proc(url: string; succeeded: bool) =
      if succeeded:
        discard window.syncDocumentCookies()
      if not window.navigationCompletedHandler.isNil:
        try: window.navigationCompletedHandler(url, succeeded)
        except CatchableError: discard)
  if not completionConfigured.isOk:
    return coreFailure(completionConfigured.failure.mapNativeError())

  let closeConfigured = native.onCloseRequested(window.nativeWindow,
    proc(): bool =
      if window.closeRequestedHandler.isNil:
        return true
      try: window.closeRequestedHandler()
      except CatchableError: false)
  if not closeConfigured.isOk:
    return coreFailure(closeConfigured.failure.mapNativeError())
  let closedConfigured = native.onClosed(window.nativeWindow, proc() =
    if window != nil and not window.closed:
      window.closed = true
      window.rpc.close()
      if not window.closedHandler.isNil:
        try: window.closedHandler()
        except CatchableError: discard)
  if not closedConfigured.isOk:
    return coreFailure(closedConfigured.failure.mapNativeError())

  let resizeConfigured = native.onResize(window.nativeWindow,
    proc(width, height: int) =
      if window != nil and not window.closed and not window.resizeHandler.isNil:
        try: window.resizeHandler(width, height)
        except CatchableError: discard)
  if not resizeConfigured.isOk:
    return coreFailure(resizeConfigured.failure.mapNativeError())

  let permissionConfigured = native.onPermissionRequested(window.nativeView,
    proc(kind, url: string): bool =
      let permissionKind = case kind
        of "microphone": microphone
        of "camera": camera
        of "notifications": notifications
        of "geolocation": geolocation
        of "clipboard": clipboard
        of "screenCapture": screenCapture
        else: return false
      window.decidePermission(PermissionRequest(
        kind: permissionKind, url: url)) == permissionGrant)
  if not permissionConfigured.isOk:
    return coreFailure(permissionConfigured.failure.mapNativeError())

  let downloadConfigured = native.onDownloadStarting(window.nativeView,
    proc(url: string): bool = window.decideDownload(DownloadRequest(
      url: url, suggestedName: suggestedDownloadName(url))) == downloadAllow)
  if not downloadConfigured.isOk:
    return coreFailure(downloadConfigured.failure.mapNativeError())

  let downloadPathConfigured = native.onDownloadPath(window.nativeView,
    proc(url: string): string =
      let path = window.downloadPath(suggestedDownloadName(url))
      if path.isOk: path.value else: "")
  if not downloadPathConfigured.isOk:
    return coreFailure(downloadPathConfigured.failure.mapNativeError())

  let downloadEventsConfigured = native.onDownloadEvent(window.nativeView,
    proc(url: string; state: native.NativeDownloadState; progress: float) =
      if not window.downloadEventHandler.isNil:
        try: window.downloadEventHandler(DownloadEvent(
          request: DownloadRequest(url: url, suggestedName: suggestedDownloadName(url)),
          state: case state
            of native.nativeDownloadStarted: downloadStarted
            of native.nativeDownloadProgress: downloadProgress
            of native.nativeDownloadCompleted: downloadCompleted
            of native.nativeDownloadFailed: downloadFailed
            of native.nativeDownloadCancelled: downloadCancelled,
          progress: progress))
        except CatchableError: discard)
  if not downloadEventsConfigured.isOk:
    return coreFailure(downloadEventsConfigured.failure.mapNativeError())

  coreSuccess()

proc configureAdditionalWebView(window: Window; view: WebView): CoreResult =
  let messageConfigured = native.onMessage(view.nativeView, proc(message: string) =
    if view != nil and not view.closed and not view.messageHandler.isNil:
      try: view.messageHandler(message)
      except CatchableError: discard)
  if not messageConfigured.isOk:
    return coreFailure(messageConfigured.failure.mapNativeError())
  let errorConfigured = native.onError(view.nativeView,
    proc(error: native.NativeError) =
      if not window.errorHandler.isNil:
        try: window.errorHandler(WindowError(operation: error.operation,
          detail: error.detail))
        except CatchableError: discard)
  if not errorConfigured.isOk:
    return coreFailure(errorConfigured.failure.mapNativeError())
  let navigationConfigured = native.onNavigationStarting(view.nativeView,
    proc(url: string): bool = window.applyNavigationDecision(NavigationRequest(url: url)))
  if not navigationConfigured.isOk:
    return coreFailure(navigationConfigured.failure.mapNativeError())
  let completionConfigured = native.onNavigationCompleted(view.nativeView,
    proc(url: string; succeeded: bool) =
      if not window.navigationCompletedHandler.isNil:
        try: window.navigationCompletedHandler(url, succeeded)
        except CatchableError: discard)
  if not completionConfigured.isOk:
    return coreFailure(completionConfigured.failure.mapNativeError())
  let newWindowConfigured = native.onNewWindowRequested(view.nativeView,
    proc(url: string): bool =
      if window.newWindowHandler.isNil:
        return true
      try: window.newWindowHandler(NewWindowRequest(url: url))
      except CatchableError: true)
  if not newWindowConfigured.isOk:
    return coreFailure(newWindowConfigured.failure.mapNativeError())
  let permissionConfigured = native.onPermissionRequested(view.nativeView,
    proc(kind, url: string): bool =
      let permissionKind = case kind
        of "microphone": microphone
        of "camera": camera
        of "notifications": notifications
        of "geolocation": geolocation
        of "clipboard": clipboard
        of "screenCapture": screenCapture
        else: return false
      window.decidePermission(PermissionRequest(kind: permissionKind, url: url)) == permissionGrant)
  if not permissionConfigured.isOk:
    return coreFailure(permissionConfigured.failure.mapNativeError())
  let downloadConfigured = native.onDownloadStarting(view.nativeView,
    proc(url: string): bool = window.decideDownload(DownloadRequest(
      url: url, suggestedName: suggestedDownloadName(url))) == downloadAllow)
  if not downloadConfigured.isOk:
    return coreFailure(downloadConfigured.failure.mapNativeError())

  let downloadPathConfigured = native.onDownloadPath(view.nativeView,
    proc(url: string): string =
      let path = window.downloadPath(suggestedDownloadName(url))
      if path.isOk: path.value else: "")
  if not downloadPathConfigured.isOk:
    return coreFailure(downloadPathConfigured.failure.mapNativeError())
  let downloadEventsConfigured = native.onDownloadEvent(view.nativeView,
    proc(url: string; state: native.NativeDownloadState; progress: float) =
      if not window.downloadEventHandler.isNil:
        try: window.downloadEventHandler(DownloadEvent(
          request: DownloadRequest(url: url, suggestedName: suggestedDownloadName(url)),
          state: case state
            of native.nativeDownloadStarted: downloadStarted
            of native.nativeDownloadProgress: downloadProgress
            of native.nativeDownloadCompleted: downloadCompleted
            of native.nativeDownloadFailed: downloadFailed
            of native.nativeDownloadCancelled: downloadCancelled,
          progress: progress))
        except CatchableError: discard)
  if not downloadEventsConfigured.isOk:
    return coreFailure(downloadEventsConfigured.failure.mapNativeError())
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
      let launched = launchHost(hostExecutable, @[options.id])
      if not launched.isOk:
        return coreFailureOf[App](mapProtocolError("app.create", launched.failure))
      return coreSuccessOf(App(
        state: coreCreated,
        backend: wslBackend,
        id: options.id,
        name: options.name,
        wslClient: launched.value,
        appLogger: newLogger()
      ))
    else:
      return coreFailureOf[App](coreError(platformUnavailable, "app.create",
        detail = "WSL requires the nimino-wsl adapter"))

  let app = App(state: coreCreated, backend: nativeBackend, id: options.id, name: options.name,
                nativeApp: native.newNativeApp(native.NativeAppOptions(appId: options.id)),
                appLogger: newLogger())
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

proc setLogger*(app: App; logger: Logger): CoreResult =
  ## Replace the application-owned sink.  A nil logger disables emission.
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.setLogger"))
  app.appLogger = if logger.isNil: newLogger() else: logger
  coreSuccess()

proc logger*(app: App): Logger =
  ## Return the current logger for integrations that want to emit records
  ## without exposing native backend objects.
  if app.isNil: nil else: app.appLogger

proc log*(app: App; level: LogLevel; operation, message: string): CoreResult =
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.log"))
  app.appLogger.emit(level, operation, message)
  coreSuccess()

proc registerCustomProtocol*(app: App; scheme: string;
                             handler: CustomProtocolHandler): CoreResult =
  ## Register a WebView-internal resource scheme. This does not register an
  ## operating-system deep link and does not expose arbitrary Nim functions.
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.registerCustomProtocol"))
  if handler.isNil:
    return coreFailure(coreError(invalidArgument, "app.registerCustomProtocol",
      detail = "a protocol handler is required"))
  if app.backend == wslBackend:
    when defined(linux):
      let registered = app.wslCall("app.registerCustomProtocol", $(%*{
        "scheme": scheme
      }))
      if not registered.isOk:
        return coreFailure(registered.failure)
      app.customProtocolHandler = handler
      return coreSuccess()
    else:
      return coreFailure(coreError(platformUnavailable, "app.registerCustomProtocol"))
  app.customProtocolHandler = handler
  let registered = native.registerCustomProtocol(app.nativeApp, scheme,
    proc(request: native.NativeCustomProtocolRequest): native.NativeCustomProtocolResponse =
      let response = handler(CustomProtocolRequest(methodName: request.methodName,
        url: request.url, path: request.path))
      native.NativeCustomProtocolResponse(statusCode: response.statusCode,
        mimeType: response.mimeType, body: response.body))
  registered.fromNative()

proc onReady*(app: App; handler: proc()): CoreResult =
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.onReady"))
  app.readyHandler = handler
  coreSuccess()

proc onExit*(app: App; handler: proc()): CoreResult =
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.onExit"))
  app.exitHandler = handler
  coreSuccess()

proc onBeforeQuit*(app: App; handler: proc(): bool): CoreResult =
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.onBeforeQuit"))
  app.beforeQuitHandler = handler
  coreSuccess()

proc validateDesktopMenuItems(items: openArray[DesktopMenuItem]): CoreResult =
  if items.len == 0:
    return coreFailure(coreError(invalidArgument, "app.desktopMenu",
      detail = "at least one menu item is required"))
  for item in items:
    if item.id == 0 or item.title.len == 0 or '\0' in item.title:
      return coreFailure(coreError(invalidArgument, "app.desktopMenu",
        detail = "menu item IDs must be non-zero and titles must not be empty or contain NUL"))
  for i in 0 ..< items.len:
    for j in i + 1 ..< items.len:
      if items[i].id == items[j].id:
        return coreFailure(coreError(invalidArgument, "app.desktopMenu",
          detail = "menu item IDs must be unique"))
  coreSuccess()

proc desktopMenuJson(items: openArray[DesktopMenuItem]): JsonNode =
  result = newJArray()
  for item in items:
    result.add(%*{
      "id": item.id,
      "title": item.title,
      "enabled": item.enabled
    })

proc configureNativeMenu*(app: App; title: string;
                          items: openArray[DesktopMenuItem];
                          handler: proc(itemId: uint32)): CoreResult =
  if app.isNil or app.state != coreCreated:
    return coreFailure(coreError(invalidState, "app.configureNativeMenu"))
  if title.len == 0 or '\0' in title:
    return coreFailure(coreError(invalidArgument, "app.configureNativeMenu",
      detail = "menu title must be non-empty and must not contain NUL"))
  if handler.isNil:
    return coreFailure(coreError(invalidArgument, "app.configureNativeMenu",
      detail = "a menu handler is required"))
  let valid = validateDesktopMenuItems(items)
  if not valid.isOk:
    return valid
  case app.backend
  of nativeBackend:
    var nativeItems: seq[native.NativeMenuItem]
    for item in items:
      nativeItems.add(native.NativeMenuItem(id: item.id, title: item.title,
        enabled: item.enabled))
    let configured = native.configureNativeMenu(app.nativeApp, title, nativeItems,
      proc(itemId: uint32) =
        if not handler.isNil:
          try: handler(itemId)
          except CatchableError: discard)
    if not configured.isOk:
      return coreFailure(configured.failure.mapNativeError())
  of wslBackend:
    when defined(linux):
      let response = app.wslCall("app.configureNativeMenu", $(%*{
        "title": title,
        "items": desktopMenuJson(items)
      }))
      if not response.isOk:
        return coreFailure(response.failure)
    else:
      return coreFailure(coreError(platformUnavailable, "app.configureNativeMenu"))
  app.nativeMenuHandler = handler
  coreSuccess()

proc configureSystemTray*(app: App; items: openArray[DesktopMenuItem];
                          handler: proc(itemId: uint32)): CoreResult =
  if app.isNil or app.state != coreCreated:
    return coreFailure(coreError(invalidState, "app.configureSystemTray"))
  if handler.isNil:
    return coreFailure(coreError(invalidArgument, "app.configureSystemTray",
      detail = "a tray menu handler is required"))
  let valid = validateDesktopMenuItems(items)
  if not valid.isOk:
    return valid
  case app.backend
  of nativeBackend:
    var nativeItems: seq[native.NativeMenuItem]
    for item in items:
      nativeItems.add(native.NativeMenuItem(id: item.id, title: item.title,
        enabled: item.enabled))
    let configured = native.configureSystemTray(app.nativeApp, nativeItems,
      proc(itemId: uint32) =
        if not handler.isNil:
          try: handler(itemId)
          except CatchableError: discard)
    if not configured.isOk:
      return coreFailure(configured.failure.mapNativeError())
  of wslBackend:
    when defined(linux):
      let response = app.wslCall("app.configureSystemTray", $(%*{
        "items": desktopMenuJson(items)
      }))
      if not response.isOk:
        return coreFailure(response.failure)
    else:
      return coreFailure(coreError(platformUnavailable, "app.configureSystemTray"))
  app.trayMenuHandler = handler
  coreSuccess()

proc sendNotification*(app: App; notification: DesktopNotification): CoreResult =
  if app.isNil or app.state != coreRunning:
    return coreFailure(coreError(invalidState, "app.sendNotification"))
  if notification.id.len == 0 or notification.title.len == 0 or
      '\0' in notification.id or '\0' in notification.title or '\0' in notification.body:
    return coreFailure(coreError(invalidArgument, "app.sendNotification",
      detail = "notification ID and title are required and text must not contain NUL"))
  case app.backend
  of nativeBackend:
    let sent = native.sendNativeNotification(app.nativeApp, native.NativeNotification(
      id: notification.id, title: notification.title, body: notification.body))
    if sent.isOk: coreSuccess() else: coreFailure(sent.failure.mapNativeError())
  of wslBackend:
    when defined(linux):
      let response = app.wslCall("app.sendNativeNotification", $(%*{
        "id": notification.id,
        "title": notification.title,
        "body": notification.body
      }))
      if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else:
      coreFailure(coreError(platformUnavailable, "app.sendNotification"))

proc onNotificationActivated*(app: App;
                              handler: proc(notificationId: string)): CoreResult =
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.onNotificationActivated"))
  if handler.isNil:
    return coreFailure(coreError(invalidArgument, "app.onNotificationActivated",
      detail = "a notification activation handler is required"))
  app.notificationActivatedHandler = handler
  case app.backend
  of nativeBackend:
    let registered = native.onNotificationActivated(app.nativeApp,
      proc(notificationId: string) =
        if not app.notificationActivatedHandler.isNil:
          try: app.notificationActivatedHandler(notificationId)
          except CatchableError: discard)
    if not registered.isOk:
      return coreFailure(registered.failure.mapNativeError())
  of wslBackend:
    discard
  coreSuccess()

proc onDeepLink*(app: App; handler: DeepLinkHandler): CoreResult =
  ## Register an explicit OS deep-link callback.  Packaging registers the
  ## scheme with the desktop shell; this callback only delivers a validated
  ## launcher/host activation payload and never registers an OS scheme itself.
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.onDeepLink"))
  if handler.isNil:
    return coreFailure(coreError(invalidArgument, "app.onDeepLink",
      detail = "a deep-link handler is required"))
  app.deepLinkHandler = handler
  let pending = app.pendingDeepLinks
  app.pendingDeepLinks.setLen(0)
  for url in pending:
    try: handler(url)
    except CatchableError: discard
  coreSuccess()

proc deliverDeepLink*(app: App; url: string): CoreResult =
  ## Host adapters use this narrow entry point to deliver startup activation.
  ## The caller remains responsible for manifest-level scheme allowlisting.
  if app.isNil or app.state == coreFinished:
    return coreFailure(coreError(invalidState, "app.deliverDeepLink"))
  try:
    let parsed = parseUri(url)
    if parsed.scheme.len == 0 or url.find({'\r', '\n', '\0'}) >= 0:
      return coreFailure(coreError(invalidArgument, "app.deliverDeepLink",
        detail = "deep-link URL must contain a scheme and no control characters"))
  except CatchableError:
    return coreFailure(coreError(invalidArgument, "app.deliverDeepLink",
      detail = "deep-link URL is malformed"))
  if not app.deepLinkHandler.isNil:
    try: app.deepLinkHandler(url)
    except CatchableError: discard
  else:
    app.pendingDeepLinks.add(url)
  coreSuccess()

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
  if app.isNil or app.state notin {coreCreated, coreRunning}:
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
        "height": options.height,
        "appId": app.id,
        "profile": profileName
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
                          profilePath: profile.value, profileName: profileName,
                          inlineRemoteAssets: options.inlineRemoteAssets,
                          injectionCss: options.injectionCss,
                          injectionJavaScript: options.injectionJavaScript,
                          injectionEnabled: options.injectionEnabled or
                            options.injectionCss.len > 0 or options.injectionJavaScript.len > 0,
                          devToolsEnabled: not options.disableDevTools)
      window.webViews = @[WebView(window: window, webViewId: webViewId.value)]
      let devTools = window.configureDevTools(not options.disableDevTools)
      if not devTools.isOk:
        return coreFailureOf[Window](devTools.failure)
      window.rpc = newRpcRegistry(proc(message: string) = window.sendRpcReply(message))
      app.windows.add(window)
      return coreSuccessOf(window)
    else:
      return coreFailureOf[Window](coreError(platformUnavailable, "window.create"))

  let nativeWindow = native.newWindow(app.nativeApp, title, options.width, options.height,
    profile.value)
  if not nativeWindow.isOk:
    return coreFailureOf[Window](nativeWindow.failure.mapNativeError())
  let nativeView = native.newWebView(nativeWindow.value)
  if not nativeView.isOk:
    return coreFailureOf[Window](nativeView.failure.mapNativeError())

  let window = Window(app: app, nativeWindow: nativeWindow.value,
                      nativeView: nativeView.value, profilePath: profile.value,
                      profileName: profileName,
                      inlineRemoteAssets: options.inlineRemoteAssets,
                      injectionCss: options.injectionCss,
                      injectionJavaScript: options.injectionJavaScript,
                      injectionEnabled: options.injectionEnabled or
                        options.injectionCss.len > 0 or options.injectionJavaScript.len > 0,
                      devToolsEnabled: not options.disableDevTools)
  window.webViews = @[WebView(window: window, nativeView: nativeView.value)]
  let devTools = window.configureDevTools(not options.disableDevTools)
  if not devTools.isOk:
    return coreFailureOf[Window](devTools.failure)
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

proc newWebView*(window: Window): CoreResultOf[WebView] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[WebView](coreError(invalidState, "webview.create"))
  let supported = window.app.supports(multipleWebViews)
  if not supported.isOk:
    return coreFailureOf[WebView](supported.failure)
  if not supported.value:
    return coreFailureOf[WebView](coreError(platformUnavailable, "webview.create",
      detail = "multiple WebViews are not supported by this backend"))
  when defined(linux):
    if window.app.backend == wslBackend:
      let remote = window.app.wslCall("native.webview.create", $(%*{
        "windowId": $window.windowId
      }))
      if not remote.isOk:
        return coreFailureOf[WebView](remote.failure)
      let webViewId = remote.value.responseId("webViewId")
      if not webViewId.isOk:
        return coreFailureOf[WebView](webViewId.failure)
      let view = WebView(window: window, webViewId: webViewId.value)
      window.webViews.add(view)
      return coreSuccessOf(view)
  let created = native.newWebView(window.nativeWindow)
  if not created.isOk:
    return coreFailureOf[WebView](created.failure.mapNativeError())
  let view = WebView(window: window, nativeView: created.value)
  let configured = window.configureAdditionalWebView(view)
  if not configured.isOk:
    discard native.close(created.value)
    return coreFailureOf[WebView](configured.failure)
  window.webViews.add(view)
  coreSuccessOf(view)

proc onMessage*(view: WebView; handler: proc(message: string)): CoreResult =
  if view.isNil or view.closed or view.window.isNil or view.window.closed:
    return coreFailure(coreError(invalidState, "webview.onMessage"))
  view.messageHandler = handler
  coreSuccess()

proc loadUrl*(view: WebView; url: string): CoreResult =
  if view.isNil or view.closed or view.window.isNil or view.window.closed:
    return coreFailure(coreError(invalidState, "webview.loadUrl"))
  if not view.window.applyNavigationDecision(NavigationRequest(url: url)):
    return coreFailure(coreError(permissionDenied, "webview.loadUrl",
      detail = "URL was rejected by navigation policy"))
  when defined(linux):
    if view.window.app.backend == wslBackend:
      let loaded = view.window.app.wslCall("native.webview.loadUrl", $(%*{
        "webViewId": $view.webViewId, "url": url
      }))
      if not loaded.isOk:
        return coreFailure(loaded.failure)
      if view == view.window.webViews[0]:
        view.window.lastUrl = url
      return coreSuccess()
  let loaded = native.loadUrl(view.nativeView, url).fromNative()
  if loaded.isOk and view == view.window.webViews[0]:
    view.window.lastUrl = url
  loaded

proc loadHtml*(view: WebView; html: string): CoreResult =
  if view.isNil or view.closed or view.window.isNil or view.window.closed:
    return coreFailure(coreError(invalidState, "webview.loadHtml"))
  when defined(linux):
    if view.window.app.backend == wslBackend:
      let loaded = view.window.app.wslCall("native.webview.loadHtml", $(%*{
        "webViewId": $view.webViewId, "html": html
      }))
      if not loaded.isOk:
        return coreFailure(loaded.failure)
      return coreSuccess()
  native.loadHtml(view.nativeView, html).fromNative()

proc evalJavaScript*(view: WebView; script: string): Future[CoreResultOf[string]] =
  if view.isNil or view.closed or view.window.isNil or view.window.closed:
    let future = newFuture[CoreResultOf[string]]("core.webview.evalJavaScript")
    future.complete(coreFailureOf[string](coreError(invalidState, "webview.evalJavaScript")))
    return future
  when defined(linux):
    if view.window.app.backend == wslBackend:
      let reply = view.window.app.wslCall("native.webview.evalJavaScript", $(%*{
        "webViewId": $view.webViewId, "script": script
      }))
      let future = newFuture[CoreResultOf[string]]("core.webview.evalJavaScript")
      if not reply.isOk:
        future.complete(coreFailureOf[string](reply.failure))
      else:
        try:
          let payload = parseJson(reply.value.payload)
          if payload.kind != JObject or not payload.hasKey("result") or
              payload["result"].kind != JString:
            future.complete(coreFailureOf[string](coreError(nativeFailure,
              "webview.evalJavaScript", detail = "host response is malformed")))
          else:
            future.complete(coreSuccessOf(payload["result"].getStr()))
        except CatchableError:
          future.complete(coreFailureOf[string](coreError(nativeFailure,
            "webview.evalJavaScript", detail = "host response is malformed")))
      return future
  let nativeFuture = native.evalJavaScript(view.nativeView, script)
  let future = newFuture[CoreResultOf[string]]("core.webview.evalJavaScript")
  nativeFuture.addCallback(proc(completed: Future[native.NativeResultOf[string]]) {.gcsafe.} =
    if completed.failed:
      future.complete(coreFailureOf[string](coreError(nativeFailure,
        "webview.evalJavaScript", detail = "native JavaScript evaluation failed")))
    else:
      let value = completed.read()
      if value.isOk:
        future.complete(coreSuccessOf(value.value))
      else:
        future.complete(coreFailureOf[string](value.failure.mapNativeError())))
  future

proc close*(view: WebView): CoreResult =
  if view.isNil or view.closed or view.window.isNil or view.window.closed:
    return coreFailure(coreError(invalidState, "webview.close"))
  if view.window.webViews.len > 0 and view == view.window.webViews[0]:
    return coreFailure(coreError(invalidState, "webview.close",
      detail = "the primary WebView is owned by its Window"))
  when defined(linux):
    if view.window.app.backend == wslBackend:
      let closed = view.window.app.wslCall("native.webview.close", $(%*{
        "webViewId": $view.webViewId
      }))
      if not closed.isOk:
        return coreFailure(closed.failure)
    else:
      let closed = native.close(view.nativeView).fromNative()
      if not closed.isOk:
        return closed
  else:
    let closed = native.close(view.nativeView).fromNative()
    if not closed.isOk:
      return closed
  view.closed = true
  for index in countdown(view.window.webViews.high, 0):
    if view.window.webViews[index] == view:
      view.window.webViews.delete(index)
      break
  coreSuccess()

proc windows*(app: App): seq[Window] =
  if app.isNil or app.state == coreFinished:
    return @[]
  for window in app.windows:
    if not window.isNil and not window.closed:
      result.add(window)

proc windowCount*(app: App): int =
  app.windows().len

proc isRunning*(app: App): bool =
  not app.isNil and app.state == coreRunning

proc isClosed*(window: Window): bool =
  window.isNil or window.closed

proc focus*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.focus"))
  case window.app.backend
  of nativeBackend:
    native.focus(window.nativeWindow).fromNative()
  of wslBackend:
    when defined(linux):
      let response = window.app.wslCall("native.window.focus", $(%*{"windowId": $window.windowId}))
      if response.isOk: coreSuccess() else: coreFailure(response.failure)
    else: coreFailure(coreError(platformUnavailable, "window.focus"))

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

proc clearSettings*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.clearSettings"))
  let cleared = clearProfileSettings(window.app.id, window.profileName)
  if cleared.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.clearSettings", detail = cleared.error))

proc clearCache*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.clearCache"))
  let cleared = clearProfileCache(window.app.id, window.profileName)
  if cleared.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.clearCache", detail = cleared.error))

proc clearDownloads*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.clearDownloads"))
  if window.app.backend == wslBackend:
    when defined(linux):
      let remote = window.app.wslCall("native.window.clearDownloads", $(%*{
        "windowId": $window.windowId
      }))
      if not remote.isOk:
        return coreFailure(remote.failure)
    else:
      return coreFailure(coreError(platformUnavailable, "window.clearDownloads"))
  let cleared = clearProfileDownloads(window.app.id, window.profileName)
  if cleared.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.clearDownloads", detail = cleared.error))

proc downloadPath*(window: Window; suggestedName: string): CoreResultOf[string] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[string](coreError(invalidState, "window.downloadPath"))
  let path = profileDownloadPath(window.app.id, window.profileName, suggestedName)
  if path.isOk:
    coreSuccessOf(path.value)
  else:
    coreFailureOf[string](coreError(invalidArgument, "window.downloadPath", detail = path.error))

proc saveDownload*(window: Window; suggestedName, content: string): CoreResultOf[string] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[string](coreError(invalidState, "window.saveDownload"))
  let stored = storeProfileDownload(window.app.id, window.profileName, suggestedName, content)
  if stored.isOk:
    coreSuccessOf(stored.value)
  else:
    coreFailureOf[string](coreError(osError, "window.saveDownload", detail = stored.error))

proc listDownloads*(window: Window): CoreResultOf[seq[string]] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[seq[string]](coreError(invalidState, "window.listDownloads"))
  let listed = listProfileDownloads(window.app.id, window.profileName)
  if listed.isOk:
    coreSuccessOf(listed.value)
  else:
    coreFailureOf[seq[string]](coreError(osError, "window.listDownloads", detail = listed.error))

proc deleteDownload*(window: Window; path: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.deleteDownload"))
  let deleted = deleteProfileDownload(window.app.id, window.profileName, path)
  if deleted.isOk:
    coreSuccess()
  else:
    coreFailure(coreError(osError, "window.deleteDownload", detail = deleted.error))

proc clearPermissions*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.clearPermissions"))
  let cleared = clearProfilePermissions(window.app.id, window.profileName)
  if cleared.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.clearPermissions", detail = cleared.error))

proc permissionKindName(kind: PermissionKind): string =
  case kind
  of microphone: "microphone"
  of camera: "camera"
  of notifications: "notifications"
  of geolocation: "geolocation"
  of clipboard: "clipboard"
  of screenCapture: "screenCapture"

proc parsePermissionKind(value: string): CoreResultOf[PermissionKind] =
  case value
  of "microphone": coreSuccessOf(microphone)
  of "camera": coreSuccessOf(camera)
  of "notifications": coreSuccessOf(notifications)
  of "geolocation": coreSuccessOf(geolocation)
  of "clipboard": coreSuccessOf(clipboard)
  of "screenCapture": coreSuccessOf(screenCapture)
  else: coreFailureOf[PermissionKind](coreError(nativeFailure,
    "window.listPermissions", detail = "stored permission kind is invalid"))

proc rememberPermission*(window: Window; request: PermissionRequest;
                         decision: PermissionDecision): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.rememberPermission"))
  let stored = writeProfilePermission(window.app.id, window.profileName,
    request.url, request.kind.permissionKindName(),
    if decision == permissionGrant: "grant" else: "deny")
  if stored.isOk:
    coreSuccess()
  else:
    coreFailure(coreError(invalidArgument, "window.rememberPermission",
      detail = stored.error))

proc readPermission*(window: Window; request: PermissionRequest):
                     CoreResultOf[PermissionDecision] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[PermissionDecision](coreError(invalidState,
      "window.readPermission"))
  let loaded = readProfilePermission(window.app.id, window.profileName,
    request.url, request.kind.permissionKindName())
  if not loaded.isOk:
    return coreFailureOf[PermissionDecision](coreError(invalidArgument,
      "window.readPermission", detail = loaded.error))
  coreSuccessOf(if loaded.value.decision == "grant":
    permissionGrant else: permissionDeny)

proc listPermissions*(window: Window): CoreResultOf[seq[StoredPermission]] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[seq[StoredPermission]](coreError(invalidState,
      "window.listPermissions"))
  let loaded = listProfilePermissions(window.app.id, window.profileName)
  if not loaded.isOk:
    return coreFailureOf[seq[StoredPermission]](coreError(invalidArgument,
      "window.listPermissions", detail = loaded.error))
  var entries: seq[StoredPermission]
  for stored in loaded.value:
    let kind = parsePermissionKind(stored.kind)
    if not kind.isOk:
      return coreFailureOf[seq[StoredPermission]](kind.failure)
    entries.add(StoredPermission(origin: stored.origin, kind: kind.value,
      decision: if stored.decision == "grant": permissionGrant else: permissionDeny))
  coreSuccessOf(entries)

proc deletePermission*(window: Window; request: PermissionRequest): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.deletePermission"))
  let deleted = deleteProfilePermission(window.app.id, window.profileName,
    request.url, request.kind.permissionKindName())
  if deleted.isOk:
    coreSuccess()
  else:
    coreFailure(coreError(invalidArgument, "window.deletePermission",
      detail = deleted.error))

proc clearLocalStorage*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.clearLocalStorage"))
  let cleared = clearProfileLocalStorage(window.app.id, window.profileName)
  if cleared.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.clearLocalStorage", detail = cleared.error))

proc clearProfileData*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.clearProfileData"))
  let cleared = clearAllProfileData(window.app.id, window.profileName)
  if cleared.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.clearProfileData", detail = cleared.error))

proc openFileDialog*(window: Window; options: FileDialogOptions):
                    Future[CoreResultOf[seq[string]]] =
  ## Use the platform's own file chooser.  Cancellation is represented by a
  ## successful empty sequence; OS/IPC failures remain structured errors.
  let target = newFuture[CoreResultOf[seq[string]]]("nimino.core.openFileDialog")
  result = target
  if window.isNil or window.closed or window.app.isNil:
    target.complete(coreFailureOf[seq[string]](coreError(invalidState,
      "window.openFileDialog")))
    return
  if options.title.len == 0:
    target.complete(coreFailureOf[seq[string]](coreError(invalidArgument,
      "window.openFileDialog", detail = "title must not be empty")))
    return
  if options.save and options.multiple:
    target.complete(coreFailureOf[seq[string]](coreError(invalidArgument,
      "window.openFileDialog", detail = "save dialogs cannot select multiple files")))
    return
  for value in [options.title, options.suggestedName]:
    for character in value:
      if ord(character) < 0x20 or ord(character) == 0x7f:
        target.complete(coreFailureOf[seq[string]](coreError(invalidArgument,
          "window.openFileDialog", detail = "dialog text contains a control character")))
        return
  let nativeOptions = native.NativeFileDialogOptions(
    title: options.title,
    save: options.save,
    multiple: options.multiple,
    suggestedName: options.suggestedName
  )
  case window.app.backend
  of nativeBackend:
    let opened = native.openFileDialog(window.nativeWindow, nativeOptions)
    opened.addCallback(proc(completed: Future[native.NativeResultOf[seq[string]]]) {.gcsafe.} =
      if target.finished:
        return
      let value = completed.read()
      if value.isOk:
        target.complete(coreSuccessOf(value.value))
      else:
        target.complete(coreFailureOf[seq[string]](mapNativeError(value.failure)))
    )
  of wslBackend:
    when defined(linux):
      if window.app.state != coreRunning or not window.app.wslUiStarted:
        target.complete(coreFailureOf[seq[string]](coreError(invalidState,
          "window.openFileDialog", detail = "WSL file dialog requires an active UI session")))
        return
      let sent = window.app.wslClient.sendRequest("native.window.openFileDialog", $(%*{
        "windowId": $window.windowId,
        "title": options.title,
        "save": options.save,
        "multiple": options.multiple,
        "suggestedName": options.suggestedName
      }))
      if not sent.isOk:
        target.complete(coreFailureOf[seq[string]](mapProtocolError(
          "window.openFileDialog", sent.failure)))
        return
      window.app.pendingWslFileDialogs.add(PendingWslFileDialog(
        requestId: sent.value,
        target: target
      ))
    else:
      target.complete(coreFailureOf[seq[string]](coreError(platformUnavailable,
        "window.openFileDialog")))

proc clearWebViewProfileData*(window: Window;
                              kinds: set[WebViewProfileDataKind]): Future[CoreResult] =
  ## Clear data owned by the browser engine.  This deliberately does not fall
  ## back to deleting files below a live WebView2 user-data folder.  WebView2
  ## Profile2 completion is asynchronous, so even a cookies-only clear keeps
  ## a Future return type.
  let target = newFuture[CoreResult]("nimino.core.clearWebViewProfileData")
  result = target
  if window.isNil or window.closed or window.app.isNil:
    target.complete(coreFailure(coreError(invalidState, "window.clearWebViewProfileData")))
    return
  if kinds == {}:
    target.complete(coreFailure(coreError(invalidArgument, "window.clearWebViewProfileData",
      detail = "at least one WebView profile data kind is required")))
    return

  case window.app.backend
  of nativeBackend:
    if window.nativeView.isNil:
      target.complete(coreFailure(coreError(invalidState, "window.clearWebViewProfileData")))
      return
    var nativeKinds: set[native.NativeBrowsingDataKind]
    for kind in kinds:
      case kind
      of webViewCookies:
        nativeKinds.incl(native.nativeBrowsingCookies)
      of webViewLocalStorage:
        nativeKinds.incl(native.nativeBrowsingLocalStorage)
      of webViewCache:
        nativeKinds.incl(native.nativeBrowsingCache)
    let cleared = native.clearBrowsingData(window.nativeView, nativeKinds)
    cleared.addCallback(proc(completed: Future[native.NativeResult]) {.gcsafe.} =
      if target.finished:
        return
      if completed.failed:
        target.complete(coreFailure(coreError(nativeFailure, "window.clearWebViewProfileData",
          detail = "native browsing-data clear failed")))
      else:
        target.complete(completed.read().fromNative())
    )
  of wslBackend:
    when defined(linux):
      ## A pre-relay host is deliberately not probed with an unknown method.
      ## The authenticated ready capability is the compatibility boundary.
      if not window.app.wslSupportsProfileDataClear():
        target.complete(coreFailure(coreError(platformUnavailable,
          "window.clearWebViewProfileData", detail =
            "the connected WSL host does not support browser data clearing")))
        return
      if window.app.state != coreRunning or not window.app.wslUiStarted:
        target.complete(coreFailure(coreError(invalidState,
          "window.clearWebViewProfileData", detail =
            "WSL browser data clearing requires an active UI session")))
        return
      let sent = window.app.wslClient.sendRequest("native.webview.clearBrowsingData", $(%*{
        "webViewId": $window.webViewId,
        "kinds": wslProfileDataKinds(kinds)
      }))
      if not sent.isOk:
        target.complete(coreFailure(mapProtocolError("window.clearWebViewProfileData",
          sent.failure)))
        return
      window.app.pendingWslProfileDataClears.add(PendingWslProfileDataClear(
        requestId: sent.value,
        target: target
      ))
    else:
      target.complete(coreFailure(coreError(platformUnavailable,
        "window.clearWebViewProfileData")))

proc toNativeCookie(cookie: ProfileCookie): native.NativeCookie =
  native.NativeCookie(name: cookie.name, value: cookie.value,
    domain: cookie.domain, path: cookie.path, secure: cookie.secure,
    httpOnly: cookie.httpOnly, expires: cookie.expires)

proc toProfileCookie(cookie: native.NativeCookie): ProfileCookie =
  ProfileCookie(name: cookie.name, value: cookie.value,
    domain: cookie.domain, path: cookie.path, secure: cookie.secure,
    httpOnly: cookie.httpOnly, expires: cookie.expires)

proc webViewCookies*(window: Window; url = ""):
                     Future[CoreResultOf[seq[ProfileCookie]]] =
  ## Read the engine's authoritative cookie store, including HttpOnly cookies.
  ## Profile-file helpers below remain a persistence mirror and never pretend
  ## to be the browser CookieManager.
  let target = newFuture[CoreResultOf[seq[ProfileCookie]]](
    "nimino.core.webViewCookies")
  result = target
  if window.isNil or window.closed or window.app.isNil:
    target.complete(coreFailureOf[seq[ProfileCookie]](coreError(invalidState,
      "window.webViewCookies")))
    return
  case window.app.backend
  of nativeBackend:
    if window.nativeView.isNil:
      target.complete(coreFailureOf[seq[ProfileCookie]](coreError(invalidState,
        "window.webViewCookies")))
      return
    let queried = native.getCookies(window.nativeView, url)
    queried.addCallback(proc(completed:
        Future[native.NativeResultOf[seq[native.NativeCookie]]]) {.gcsafe.} =
      if target.finished:
        return
      if completed.failed:
        target.complete(coreFailureOf[seq[ProfileCookie]](coreError(
          nativeFailure, "window.webViewCookies",
          detail = "native cookie query failed")))
        return
      let outcome = completed.read()
      if not outcome.isOk:
        target.complete(coreFailureOf[seq[ProfileCookie]](
          outcome.failure.mapNativeError()))
        return
      var cookies: seq[ProfileCookie]
      for cookie in outcome.value:
        cookies.add(cookie.toProfileCookie())
      target.complete(coreSuccessOf(cookies))
    )
  of wslBackend:
    when defined(linux):
      if not window.app.wslSupportsCookieManager():
        target.complete(coreFailureOf[seq[ProfileCookie]](coreError(
          platformUnavailable, "window.webViewCookies",
          detail = "the connected WSL host does not expose CookieManager queries")))
        return
      if window.app.state != coreRunning or not window.app.wslUiStarted:
        target.complete(coreFailureOf[seq[ProfileCookie]](coreError(
          invalidState, "window.webViewCookies",
          detail = "WSL CookieManager queries require an active UI session")))
        return
      let response = window.app.wslCall("native.webview.getCookies", $(%*{
        "webViewId": $window.webViewId,
        "url": url
      }))
      if not response.isOk:
        target.complete(coreFailureOf[seq[ProfileCookie]](response.failure))
        return
      try:
        let payload = parseJson(response.value.payload)
        if payload.kind != JObject or not payload.hasKey("cookies") or
            payload["cookies"].kind != JArray:
          raise newException(ValueError, "missing cookies")
        var cookies: seq[ProfileCookie]
        for value in payload["cookies"].items:
          if value.kind != JObject or not value.hasKey("name") or
              not value.hasKey("value") or not value.hasKey("domain") or
              not value.hasKey("path") or not value.hasKey("secure") or
              not value.hasKey("httpOnly") or not value.hasKey("expires") or
              value["name"].kind != JString or value["value"].kind != JString or
              value["domain"].kind != JString or value["path"].kind != JString or
              value["secure"].kind != JBool or value["httpOnly"].kind != JBool or
              value["expires"].kind != JInt:
            raise newException(ValueError, "malformed cookie")
          cookies.add(ProfileCookie(name: value["name"].getStr(),
            value: value["value"].getStr(), domain: value["domain"].getStr(),
            path: value["path"].getStr(), secure: value["secure"].getBool(),
            httpOnly: value["httpOnly"].getBool(),
            expires: int64(value["expires"].getBiggestInt())))
        target.complete(coreSuccessOf(cookies))
      except CatchableError:
        target.complete(coreFailureOf[seq[ProfileCookie]](coreError(
          nativeFailure, "window.webViewCookies",
          detail = "WSL CookieManager response is malformed")))
    else:
      target.complete(coreFailureOf[seq[ProfileCookie]](coreError(
        platformUnavailable, "window.webViewCookies")))

proc setWebViewCookie*(window: Window; cookie: ProfileCookie): Future[CoreResult] =
  ## Set the browser cookie first and persist the same value only after the
  ## engine confirms success. A successful Future therefore means both stores
  ## agree; synchronous profile-only `writeCookie` remains available for
  ## offline profile preparation.
  let target = newFuture[CoreResult]("nimino.core.setWebViewCookie")
  result = target
  if window.isNil or window.closed or window.app.isNil:
    target.complete(coreFailure(coreError(invalidState,
      "window.setWebViewCookie")))
    return
  when defined(linux):
    if window.app.backend == wslBackend:
      if not window.app.wslSupportsCookieManager():
        target.complete(coreFailure(coreError(platformUnavailable,
          "window.setWebViewCookie",
          detail = "the connected WSL host does not expose CookieManager mutation")))
        return
      if window.app.state != coreRunning or not window.app.wslUiStarted:
        target.complete(coreFailure(coreError(invalidState,
          "window.setWebViewCookie",
          detail = "WSL CookieManager mutation requires an active UI session")))
        return
      let response = window.app.wslCall("native.webview.setCookie", $(%*{
        "webViewId": $window.webViewId,
        "cookie": {
          "name": cookie.name, "value": cookie.value,
          "domain": cookie.domain, "path": cookie.path,
          "secure": cookie.secure, "httpOnly": cookie.httpOnly,
          "expires": cookie.expires
        }
      }))
      if not response.isOk:
        target.complete(coreFailure(response.failure))
        return
      let written = writeProfileCookie(window.app.id, window.profileName, cookie)
      target.complete(if written.isOk: coreSuccess() else: coreFailure(coreError(
        osError, "window.setWebViewCookie", detail = written.error)))
      return
  if window.app.backend != nativeBackend or window.nativeView.isNil:
    target.complete(coreFailure(coreError(platformUnavailable,
      "window.setWebViewCookie",
      detail = "the connected WSL host does not yet expose CookieManager mutation")))
    return
  let changed = native.setCookie(window.nativeView, cookie.toNativeCookie())
  changed.addCallback(proc(completed: Future[native.NativeResult]) {.gcsafe.} =
    if target.finished:
      return
    if completed.failed:
      target.complete(coreFailure(coreError(nativeFailure,
        "window.setWebViewCookie", detail = "native cookie mutation failed")))
      return
    let outcome = completed.read()
    if not outcome.isOk:
      target.complete(coreFailure(outcome.failure.mapNativeError()))
      return
    let written = writeProfileCookie(window.app.id, window.profileName, cookie)
    if written.isOk:
      target.complete(coreSuccess())
    else:
      target.complete(coreFailure(coreError(osError, "window.setWebViewCookie",
        detail = written.error)))
  )

proc deleteWebViewCookie*(window: Window; cookie: ProfileCookie): Future[CoreResult] =
  let target = newFuture[CoreResult]("nimino.core.deleteWebViewCookie")
  result = target
  if window.isNil or window.closed or window.app.isNil:
    target.complete(coreFailure(coreError(invalidState,
      "window.deleteWebViewCookie")))
    return
  when defined(linux):
    if window.app.backend == wslBackend:
      if not window.app.wslSupportsCookieManager():
        target.complete(coreFailure(coreError(platformUnavailable,
          "window.deleteWebViewCookie",
          detail = "the connected WSL host does not expose CookieManager mutation")))
        return
      if window.app.state != coreRunning or not window.app.wslUiStarted:
        target.complete(coreFailure(coreError(invalidState,
          "window.deleteWebViewCookie",
          detail = "WSL CookieManager mutation requires an active UI session")))
        return
      let response = window.app.wslCall("native.webview.deleteCookie", $(%*{
        "webViewId": $window.webViewId,
        "cookie": {
          "name": cookie.name, "value": cookie.value,
          "domain": cookie.domain, "path": cookie.path,
          "secure": cookie.secure, "httpOnly": cookie.httpOnly,
          "expires": cookie.expires
        }
      }))
      if not response.isOk:
        target.complete(coreFailure(response.failure))
        return
      let deleted = deleteProfileCookie(window.app.id, window.profileName,
        cookie.domain, cookie.name, cookie.path)
      target.complete(if deleted.isOk: coreSuccess() else: coreFailure(coreError(
        osError, "window.deleteWebViewCookie", detail = deleted.error)))
      return
  if window.app.backend != nativeBackend or window.nativeView.isNil:
    target.complete(coreFailure(coreError(platformUnavailable,
      "window.deleteWebViewCookie",
      detail = "the connected WSL host does not yet expose CookieManager mutation")))
    return
  let changed = native.deleteCookie(window.nativeView, cookie.toNativeCookie())
  changed.addCallback(proc(completed: Future[native.NativeResult]) {.gcsafe.} =
    if target.finished:
      return
    if completed.failed:
      target.complete(coreFailure(coreError(nativeFailure,
        "window.deleteWebViewCookie", detail = "native cookie mutation failed")))
      return
    let outcome = completed.read()
    if not outcome.isOk:
      target.complete(coreFailure(outcome.failure.mapNativeError()))
      return
    let deleted = deleteProfileCookie(window.app.id, window.profileName,
      cookie.domain, cookie.name, cookie.path)
    if deleted.isOk:
      target.complete(coreSuccess())
    else:
      target.complete(coreFailure(coreError(osError,
        "window.deleteWebViewCookie", detail = deleted.error)))
  )

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

proc cookiesForDomain*(window: Window; domain: string): CoreResultOf[seq[ProfileCookie]] =
  ## Return non-expired cookies visible to `domain` from the window profile.
  ## The profile layer applies normalized host matching and expiry filtering;
  ## this facade keeps the storage implementation private to nimino-core.
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[seq[ProfileCookie]](coreError(invalidState, "window.cookiesForDomain"))
  let loaded = profileCookiesForDomain(window.app.id, window.profileName, domain)
  if loaded.isOk:
    coreSuccessOf(loaded.value)
  else:
    coreFailureOf[seq[ProfileCookie]](coreError(invalidArgument,
      "window.cookiesForDomain", detail = loaded.error))

proc cookiesForUrl*(window: Window; url: string): CoreResultOf[seq[ProfileCookie]] =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[seq[ProfileCookie]](coreError(invalidState, "window.cookiesForUrl"))
  let loaded = profileCookiesForUrl(window.app.id, window.profileName, url)
  if loaded.isOk:
    coreSuccessOf(loaded.value)
  else:
    coreFailureOf[seq[ProfileCookie]](coreError(invalidArgument,
      "window.cookiesForUrl", detail = loaded.error))

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

proc evalJavaScript*(window: Window; script: string): Future[CoreResultOf[string]]

proc syncDocumentCookies*(window: Window): Future[CoreResult] =
  ## Mirror the browser engine's CookieManager into the Nimino profile store.
  ## Native Windows/Linux includes HttpOnly cookies; WSL retains the legacy
  ## script-visible fallback until the authenticated host protocol advertises
  ## a cookie-query capability.
  let target = newFuture[CoreResult]("nimino.core.syncDocumentCookies")
  if window.isNil or window.closed or window.app.isNil or window.lastUrl.len == 0:
    target.complete(coreFailure(coreError(invalidState, "window.syncDocumentCookies")))
    return target
  let parsedUrl = parseUri(window.lastUrl)
  if parsedUrl.hostname.len == 0:
    target.complete(coreFailure(coreError(invalidArgument, "window.syncDocumentCookies",
      detail = "current URL has no cookie domain")))
    return target
  var useEngineCookieManager = window.app.backend == nativeBackend
  when defined(linux):
    if window.app.backend == wslBackend and window.app.wslSupportsCookieManager():
      useEngineCookieManager = true
  if useEngineCookieManager:
    let queried = window.webViewCookies(window.lastUrl)
    queried.addCallback(proc(completed:
        Future[CoreResultOf[seq[ProfileCookie]]]) {.gcsafe.} =
      if target.finished:
        return
      if completed.failed:
        target.complete(coreFailure(coreError(webViewError,
          "window.syncDocumentCookies",
          detail = "native cookie query failed")))
        return
      let outcome = completed.read()
      if not outcome.isOk:
        target.complete(coreFailure(outcome.failure))
        return
      for cookie in outcome.value:
        let written = writeProfileCookie(window.app.id, window.profileName,
          cookie)
        if not written.isOk:
          target.complete(coreFailure(coreError(osError,
            "window.syncDocumentCookies", detail = written.error)))
          return
      target.complete(coreSuccess())
    )
    return target
  let evaluation = window.evalJavaScript("document.cookie")
  evaluation.addCallback(proc(completed: Future[CoreResultOf[string]]) {.gcsafe.} =
    if target.finished:
      return
    if completed.failed:
      target.complete(coreFailure(coreError(webViewError, "window.syncDocumentCookies")))
      return
    let evaluated = completed.read()
    if not evaluated.isOk:
      target.complete(coreFailure(evaluated.failure))
      return
    try:
      var cookieHeader = evaluated.value
      if cookieHeader.len >= 2 and cookieHeader[0] == '"' and cookieHeader[^1] == '"':
        let decoded = parseJson(cookieHeader)
        if decoded.kind == JString:
          cookieHeader = decoded.getStr()
      for pair in cookieHeader.split(';'):
        if pair.strip().len == 0:
          continue
        let parsed = parseCookieHeader(pair.strip(), parsedUrl.hostname, "/",
          parsedUrl.scheme.toLowerAscii() == "https")
        if not parsed.isOk:
          target.complete(coreFailure(coreError(invalidArgument,
            "window.syncDocumentCookies", detail = parsed.error)))
          return
        for cookie in parsed.value:
          let written = writeProfileCookie(window.app.id, window.profileName, cookie)
          if not written.isOk:
            target.complete(coreFailure(coreError(osError,
              "window.syncDocumentCookies", detail = written.error)))
            return
      target.complete(coreSuccess())
    except CatchableError as error:
      target.complete(coreFailure(coreError(invalidArgument,
        "window.syncDocumentCookies", detail = error.msg)))
  )
  target

proc clearCookies*(window: Window): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.clearCookies"))
  let cleared = clearProfileCookies(window.app.id, window.profileName)
  if cleared.isOk: coreSuccess()
  else: coreFailure(coreError(invalidArgument, "window.clearCookies", detail = cleared.error))

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

proc onNavigationCompleted*(window: Window;
                            handler: proc(url: string; succeeded: bool)): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onNavigationCompleted"))
  window.navigationCompletedHandler = handler
  coreSuccess()

proc onExternalNavigation*(window: Window;
                           handler: proc(request: NavigationRequest)): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onExternalNavigation"))
  window.externalNavigationHandler = handler
  coreSuccess()

proc openExternally*(window: Window; url: string): CoreResult =
  ## Open a validated HTTP(S) URL with the platform's default browser.
  ## This uses an argument vector rather than a shell command, so URL text
  ## cannot become shell syntax. WSL callers should use onExternalNavigation
  ## when Windows interop is not available in the host environment.
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.openExternally"))
  let parsed = parseUri(url)
  if parsed.scheme.toLowerAscii() notin ["http", "https"] or parsed.hostname.len == 0 or
      url.anyIt(it.isSpaceAscii or it.ord < 0x20):
    return coreFailure(coreError(invalidArgument, "window.openExternally",
      detail = "only absolute HTTP(S) URLs without control characters are allowed"))
  var process: Process
  try:
    when defined(windows):
      let command = "rundll32.exe"
      process = startProcess(command, args = @[
        "url.dll,FileProtocolHandler", url], options = {poUsePath, poStdErrToStdOut})
    elif defined(linux):
      let command = if window.app.backend == wslBackend: "wslview" else: "xdg-open"
      process = startProcess(command, args = @[url], options = {poUsePath, poStdErrToStdOut})
    else:
      return coreFailure(coreError(platformUnavailable, "window.openExternally"))
  except CatchableError as error:
    return coreFailure(coreError(osError, "window.openExternally", detail = error.msg))
  if process.isNil:
    return coreFailure(coreError(osError, "window.openExternally",
      detail = "default browser process could not be started"))
  discard process
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

proc onDownloadEvent*(window: Window;
                      handler: proc(event: DownloadEvent)): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onDownloadEvent"))
  window.downloadEventHandler = handler
  coreSuccess()

proc onNewWindow*(window: Window;
                  handler: proc(request: NewWindowRequest): bool): CoreResult =
  ## Return true to consume the request (typically after `openPopup` or an
  ## explicit deny). Return false only when the application intentionally
  ## delegates to the native WebView popup policy.
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onNewWindow"))
  window.newWindowHandler = handler
  coreSuccess()

proc loadUrl*(window: Window; url: string): CoreResult

proc openPopup*(window: Window; request: NewWindowRequest; title = "Popup";
                width = 900; height = 700; profile = "default"): CoreResultOf[Window] =
  ## Explicitly create a popup in response to an application-approved request.
  ## Native backends never create one implicitly; callers decide when to invoke
  ## this operation from `onNewWindow`.
  if window.isNil or window.closed or window.app.isNil:
    return coreFailureOf[Window](coreError(invalidState, "window.openPopup"))
  if request.url.len == 0:
    return coreFailureOf[Window](coreError(invalidArgument, "window.openPopup",
      detail = "popup URL must not be empty"))
  if not window.applyNavigationDecision(NavigationRequest(url: request.url)):
    return coreFailureOf[Window](coreError(permissionDenied, "window.openPopup",
      detail = "popup URL was rejected by navigation policy"))
  let popup = window.app.newWindow(CoreWindowOptions(
    title: title, width: width, height: height, profile: profile))
  if not popup.isOk:
    return popup
  let loaded = popup.value.loadUrl(request.url)
  if not loaded.isOk:
    discard popup.value.close()
    return coreFailureOf[Window](loaded.failure)
  coreSuccessOf(popup.value)

proc onCloseRequested*(window: Window;
                       handler: proc(): bool): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onCloseRequested"))
  window.closeRequestedHandler = handler
  coreSuccess()

proc onClosed*(window: Window; handler: proc()): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onClosed"))
  window.closedHandler = handler
  coreSuccess()

proc onResize*(window: Window; handler: proc(width, height: int)): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onResize"))
  window.resizeHandler = handler
  coreSuccess()

proc onError*(window: Window; handler: proc(error: WindowError)): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.onError"))
  window.errorHandler = handler
  coreSuccess()

proc loadUrl*(window: Window; url: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.loadUrl"))
  for c in url:
    if c in {' ', '\t', '\r', '\n'} or ord(c) < 0x20 or ord(c) == 0x7f:
      return coreFailure(coreError(webViewError, "window.loadUrl",
        detail = "URL must not contain whitespace/control characters"))
  let bridge = window.configureDocumentStartBridge(url)
  if not bridge.isOk:
    return bridge
  case window.app.backend
  of nativeBackend:
    if window.nativeView.isNil:
      return coreFailure(coreError(invalidState, "window.loadUrl"))
    let loaded = native.loadUrl(window.nativeView, url).fromNative()
    if loaded.isOk:
      window.lastUrl = url
    loaded
  of wslBackend:
    when defined(linux):
      let loaded = window.app.wslCall("native.webview.loadUrl", $(%*{
        "webViewId": $window.webViewId,
        "url": url
      }))
      if loaded.isOk:
        window.app.wslUiStarted = true
        window.lastUrl = url
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

proc setInjection*(window: Window; css, javascript: openArray[string];
                   enabled = true): CoreResult =
  ## Configure application-owned CSS/JavaScript injection.  The sources are
  ## retained in core and installed at document-start; callers must not use
  ## this API to expose arbitrary Nim functions or OS APIs.
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.setInjection"))
  for source in css:
    if source.len == 0:
      return coreFailure(coreError(invalidArgument, "window.setInjection",
        detail = "CSS injection sources must not be empty"))
  for source in javascript:
    if source.len == 0:
      return coreFailure(coreError(invalidArgument, "window.setInjection",
        detail = "JavaScript injection sources must not be empty"))
  window.injectionCss = @css
  window.injectionJavaScript = @javascript
  window.injectionEnabled = enabled
  if window.lastUrl.len == 0:
    return coreSuccess()
  window.configureDocumentStartBridge(window.lastUrl)

proc setDevToolsEnabled*(window: Window; enabled: bool): CoreResult =
  ## Change developer-tools availability for an existing window. The request
  ## is applied to the native WebView settings and is not implemented by
  ## JavaScript injection.
  window.configureDevTools(enabled)

proc assetMime(path: string): string =
  case splitFile(path).ext.toLowerAscii()
  of ".html", ".htm": "text/html"
  of ".xml", ".rss", ".atom": "application/xml"
  of ".txt", ".md", ".markdown": "text/plain"
  of ".csv": "text/csv"
  of ".pdf": "application/pdf"
  of ".css": "text/css"
  of ".js", ".mjs": "text/javascript"
  of ".json", ".map", ".jsonld": "application/ld+json"
  of ".webmanifest": "application/manifest+json"
  of ".yaml", ".yml": "application/yaml"
  of ".wasm": "application/wasm"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".gif": "image/gif"
  of ".ico": "image/x-icon"
  of ".svg": "image/svg+xml"
  of ".webp": "image/webp"
  of ".avif": "image/avif"
  of ".jxl": "image/jxl"
  of ".heic": "image/heic"
  of ".heif": "image/heif"
  of ".cur": "image/x-icon"
  of ".bmp": "image/bmp"
  of ".tif", ".tiff": "image/tiff"
  of ".mp3": "audio/mpeg"
  of ".aac": "audio/aac"
  of ".m4a": "audio/mp4"
  of ".flac": "audio/flac"
  of ".wav": "audio/wav"
  of ".mid", ".midi": "audio/midi"
  of ".ogg": "audio/ogg"
  of ".opus": "audio/opus"
  of ".mp4": "video/mp4"
  of ".m4v": "video/x-m4v"
  of ".webm": "video/webm"
  of ".mov": "video/quicktime"
  of ".avi": "video/x-msvideo"
  of ".mkv": "video/x-matroska"
  of ".m3u8": "application/vnd.apple.mpegurl"
  of ".woff": "font/woff"
  of ".woff2": "font/woff2"
  of ".ttf": "font/ttf"
  of ".otf": "font/otf"
  of ".eot": "application/vnd.ms-fontobject"
  else: ""

proc remoteAssetDataUri(url: string): string

proc inlineWslCssUrls(root, baseDir, css: string; inlineRemoteAssets = false): string =
  result = css
  var cursor = 0
  while true:
    let start = result.find("url(", cursor)
    if start < 0: break
    var valueStart = start + 4
    while valueStart < result.len and result[valueStart].isSpaceAscii: inc valueStart
    let quoted = valueStart < result.len and (result[valueStart] == '\'' or result[valueStart] == '"')
    let quote = if quoted: result[valueStart] else: '\0'
    if quoted: inc valueStart
    let valueEnd = if quoted: result.find(quote, valueStart) else: result.find(')', valueStart)
    if valueEnd < 0:
      break
    let relative = result[valueStart ..< valueEnd].strip()
    let close = if quoted: result.find(')', valueEnd) else: valueEnd
    if close < 0 or relative.len == 0 or relative.startsWith("data:") or relative.startsWith("#"):
      cursor = valueEnd + 1
      continue
    if inlineRemoteAssets and (relative.toLowerAscii().startsWith("http://") or
        relative.toLowerAscii().startsWith("https://")):
      let remote = remoteAssetDataUri(relative)
      if remote.len > 0 and (remote.startsWith("data:image/") or
          remote.startsWith("data:font/")):
        result = result[0 ..< valueStart] & remote & result[valueEnd .. ^1]
        cursor = valueStart + remote.len
        continue
    let assetName = decodeUrl(relative.split({'?', '#'}, maxsplit = 1)[0])
    let candidate = (baseDir / assetName).absolutePath().normalizedPath()
    let relativeCheck = relativePath(candidate, root)
    let mime = assetMime(candidate)
    if relativeCheck == ".." or relativeCheck.startsWith(".." & DirSep) or mime.len == 0 or not fileExists(candidate):
      cursor = valueEnd + 1
      continue
    let dataUri = "data:" & mime & ";base64," & encode(readFile(candidate))
    result = result[0 ..< valueStart] & dataUri & result[valueEnd .. ^1]
    cursor = valueStart + dataUri.len

proc hasStylesheetRel(tag: string): bool =
  let lower = tag.toLowerAscii()
  var relStart = lower.find("rel=")
  while relStart > 0 and lower[relStart - 1] notin {' ', '\t', '\r', '\n', '<'}:
    let next = lower.find("rel=", relStart + 4)
    if next < 0:
      relStart = -1
      break
    relStart = next
  if relStart < 0:
    return false
  let valueStart = relStart + 4
  if valueStart >= lower.len or lower[valueStart] notin {'\'', '"'}:
    return false
  let quote = lower[valueStart]
  let valueEnd = lower.find(quote, valueStart + 1)
  if valueEnd < 0:
    return false
  for token in lower[valueStart + 1 ..< valueEnd].splitWhitespace():
    if token == "stylesheet":
      return true
  false

proc remoteAssetDataUri(url: string): string =
  let parsed = parseUri(url)
  if parsed.scheme.toLowerAscii() notin ["http", "https"] or parsed.hostname.len == 0:
    return ""
  try:
    ## Asset retrieval runs synchronously while the WSL document is prepared;
    ## bound socket inactivity so a dead endpoint cannot stall the UI forever.
    var client = newHttpClient(timeout = 10_000)
    let response = client.get(url)
    if response.code.int < 200 or response.code.int >= 300 or response.body.len > 8 * 1024 * 1024:
      return ""
    var mime = response.headers.getOrDefault("Content-Type").split(';')[0].strip()
    if mime.len == 0:
      mime = assetMime(parsed.path)
    if mime.len == 0:
      return ""
    "data:" & mime & ";base64," & encode(response.body)
  except CatchableError:
    ""

proc remoteAssetText(url: string): string =
  let parsed = parseUri(url)
  if parsed.scheme.toLowerAscii() notin ["http", "https"] or parsed.hostname.len == 0:
    return ""
  try:
    var client = newHttpClient(timeout = 10_000)
    let response = client.get(url)
    if response.code.int < 200 or response.code.int >= 300 or response.body.len > 8 * 1024 * 1024:
      return ""
    let mime = response.headers.getOrDefault("Content-Type").split(';')[0].strip()
    if mime.len > 0 and not (mime == "text/css" or mime == "text/plain" or mime == "text/javascript"):
      return ""
    response.body
  except CatchableError:
    ""

proc inlineWslAssets(root, baseDir, html: string; inlineRemoteAssets = false): string =
  result = html
  var cursor = 0
  while true:
    let start = result.find("<script", cursor)
    if start < 0: break
    let tagEnd = result.find('>', start)
    if tagEnd < 0: break
    let doubleSrcStart = result.find("src=\"", start)
    let singleSrcStart = result.find("src='", start)
    let useSingle = singleSrcStart >= 0 and (doubleSrcStart < 0 or singleSrcStart < doubleSrcStart)
    let srcStart = if useSingle: singleSrcStart else: doubleSrcStart
    if srcStart < 0 or srcStart > tagEnd:
      cursor = tagEnd + 1
      continue
    let valueStart = srcStart + 5
    let valueEnd = result.find(if useSingle: '\'' else: '"', valueStart)
    if valueEnd < 0 or valueEnd > tagEnd:
      cursor = tagEnd + 1
      continue
    let relative = result[valueStart ..< valueEnd]
    if inlineRemoteAssets and (relative.toLowerAscii().startsWith("http://") or
        relative.toLowerAscii().startsWith("https://")):
      let remote = remoteAssetDataUri(relative)
      if remote.len > 0 and remote.startsWith("data:image/"):
        result = result[0 ..< valueStart] & remote & result[valueEnd .. ^1]
        cursor = valueStart + remote.len + 1
        continue
    let assetName = decodeUrl(relative.split({'?', '#'}, maxsplit = 1)[0])
    let candidate = (baseDir / assetName).absolutePath().normalizedPath()
    let relativeCheck = relativePath(candidate, root)
    let closing = result.find("</script>", tagEnd)
    if relativeCheck == ".." or relativeCheck.startsWith(".." & DirSep) or closing < 0 or not fileExists(candidate):
      cursor = tagEnd + 1
      continue
    let body = inlineWslCssUrls(root, splitFile(candidate).dir, readFile(candidate), inlineRemoteAssets)
    let tail = if closing + 9 < result.len: result[closing + 9 .. ^1] else: ""
    result = result[0 ..< start] & "<script>" & body & "</script>" & tail
    cursor = start + body.len + 17
  cursor = 0
  ## Responsive images use a comma-separated `srcset` attribute.  Inline each
  ## local candidate independently while preserving its descriptor (`1x`,
  ## `640w`, …); unresolved candidates remain untouched. Remote candidates
  ## are fetched only when the explicit remote-asset option is enabled.
  while true:
    let start = result.find("srcset=", cursor)
    if start < 0: break
    let quoteStart = start + 7
    if quoteStart >= result.len or (result[quoteStart] != '\"' and result[quoteStart] != '\''):
      cursor = quoteStart
      continue
    let quote = result[quoteStart]
    let valueStart = quoteStart + 1
    let valueEnd = result.find(quote, valueStart)
    if valueEnd < 0:
      break
    let original = result[valueStart ..< valueEnd]
    var rewritten: seq[string]
    for candidateSpec in original.split(','):
      let spec = candidateSpec.strip()
      if spec.len == 0:
        continue
      let parts = spec.splitWhitespace()
      let relative = parts[0]
      if inlineRemoteAssets and (relative.toLowerAscii().startsWith("http://") or
          relative.toLowerAscii().startsWith("https://")):
        let remote = remoteAssetDataUri(relative)
        if remote.len > 0 and remote.startsWith("data:image/"):
          var rendered = remote
          if parts.len > 1:
            rendered.add(" " & parts[1 .. ^1].join(" "))
          rewritten.add(rendered)
          continue
      let assetName = decodeUrl(relative.split({'?', '#'}, maxsplit = 1)[0])
      let candidate = (baseDir / assetName).absolutePath().normalizedPath()
      let relativeCheck = relativePath(candidate, root)
      let mime = assetMime(candidate)
      var rendered = spec
      if relativeCheck != ".." and not relativeCheck.startsWith(".." & DirSep) and
          fileExists(candidate) and mime.startsWith("image/"):
        rendered = "data:" & mime & ";base64," & encode(readFile(candidate))
        if parts.len > 1:
          rendered.add(" " & parts[1 .. ^1].join(" "))
      rewritten.add(rendered)
    let replacement = rewritten.join(", ")
    result = result[0 ..< valueStart] & replacement & result[valueEnd .. ^1]
    cursor = valueStart + replacement.len + 1
  cursor = 0
  while true:
    let start = result.find("<link", cursor)
    if start < 0: break
    let tagEnd = result.find('>', start)
    if tagEnd < 0: break
    let doubleHrefStart = result.find("href=\"", start)
    let singleHrefStart = result.find("href='", start)
    let useSingle = singleHrefStart >= 0 and (doubleHrefStart < 0 or singleHrefStart < doubleHrefStart)
    let hrefStart = if useSingle: singleHrefStart else: doubleHrefStart
    if hrefStart < 0 or hrefStart > tagEnd:
      cursor = tagEnd + 1
      continue
    let valueStart = hrefStart + 6
    let valueEnd = result.find(if useSingle: '\'' else: '"', valueStart)
    let tagMarkup = result[start .. tagEnd]
    let relValue = tagMarkup.hasStylesheetRel()
    if valueEnd < 0 or valueEnd > tagEnd or
        not relValue:
      cursor = tagEnd + 1
      continue
    let assetName = decodeUrl(result[valueStart ..< valueEnd].split({'?', '#'}, maxsplit = 1)[0])
    if inlineRemoteAssets and (assetName.toLowerAscii().startsWith("http://") or
        assetName.toLowerAscii().startsWith("https://")):
      let remote = remoteAssetText(assetName)
      if remote.len > 0:
        let tail = if tagEnd + 1 < result.len: result[tagEnd + 1 .. ^1] else: ""
        result = result[0 ..< start] & "<style>" & remote & "</style>" & tail
        cursor = start + remote.len + 15
        continue
    let candidate = (baseDir / assetName).absolutePath().normalizedPath()
    let relativeCheck = relativePath(candidate, root)
    if relativeCheck == ".." or relativeCheck.startsWith(".." & DirSep) or not fileExists(candidate):
      cursor = tagEnd + 1
      continue
    let body = readFile(candidate)
    let tail = if tagEnd + 1 < result.len: result[tagEnd + 1 .. ^1] else: ""
    result = result[0 ..< start] & "<style>" & body & "</style>" & tail
    cursor = start + body.len + 15
  cursor = 0
  while true:
    let start = result.find("<img", cursor)
    if start < 0: break
    let tagEnd = result.find('>', start)
    if tagEnd < 0: break
    let doubleSrcStart = result.find("src=\"", start)
    let singleSrcStart = result.find("src='", start)
    let useSingle = singleSrcStart >= 0 and (doubleSrcStart < 0 or singleSrcStart < doubleSrcStart)
    let srcStart = if useSingle: singleSrcStart else: doubleSrcStart
    if srcStart < 0 or srcStart > tagEnd:
      cursor = tagEnd + 1
      continue
    let valueStart = srcStart + 5
    let quote = if useSingle: '\'' else: '"'
    let valueEnd = result.find(quote, valueStart)
    if valueEnd < 0 or valueEnd > tagEnd:
      cursor = tagEnd + 1
      continue
    let relative = result[valueStart ..< valueEnd]
    let assetName = decodeUrl(relative.split({'?', '#'}, maxsplit = 1)[0])
    let candidate = (baseDir / assetName).absolutePath().normalizedPath()
    let relativeCheck = relativePath(candidate, root)
    if relativeCheck == ".." or relativeCheck.startsWith(".." & DirSep) or not fileExists(candidate):
      cursor = tagEnd + 1
      continue
    let mime = assetMime(candidate)
    if not mime.startsWith("image/"):
      cursor = tagEnd + 1
      continue
    let encoded = encode(readFile(candidate))
    let dataUri = "data:" & mime & ";base64," & encoded
    result = result[0 ..< valueStart] & dataUri & result[valueEnd .. ^1]
    cursor = valueStart + dataUri.len + 1
  cursor = 0
  while true:
    let start = result.find("<source", cursor)
    if start < 0: break
    let tagEnd = result.find('>', start)
    if tagEnd < 0: break
    let doubleSrcStart = result.find("src=\"", start)
    let singleSrcStart = result.find("src='", start)
    let useSingle = singleSrcStart >= 0 and (doubleSrcStart < 0 or singleSrcStart < doubleSrcStart)
    let srcStart = if useSingle: singleSrcStart else: doubleSrcStart
    if srcStart < 0 or srcStart > tagEnd:
      cursor = tagEnd + 1
      continue
    let valueStart = srcStart + 5
    let quote = if useSingle: '\'' else: '"'
    let valueEnd = result.find(quote, valueStart)
    if valueEnd < 0 or valueEnd > tagEnd:
      cursor = tagEnd + 1
      continue
    let relative = result[valueStart ..< valueEnd]
    let assetName = decodeUrl(relative.split({'?', '#'}, maxsplit = 1)[0])
    let candidate = (baseDir / assetName).absolutePath().normalizedPath()
    let relativeCheck = relativePath(candidate, root)
    let mime = assetMime(candidate)
    if relativeCheck == ".." or relativeCheck.startsWith(".." & DirSep) or
        not fileExists(candidate) or not (mime.startsWith("audio/") or
          mime.startsWith("video/") or mime == "application/vnd.apple.mpegurl"):
      cursor = tagEnd + 1
      continue
    let dataUri = "data:" & mime & ";base64," & encode(readFile(candidate))
    result = result[0 ..< valueStart] & dataUri & result[valueEnd .. ^1]
    cursor = valueStart + dataUri.len + 1
  cursor = 0
  while true:
    let start = result.find("<video", cursor)
    if start < 0: break
    let tagEnd = result.find('>', start)
    if tagEnd < 0: break
    let doublePosterStart = result.find("poster=\"", start)
    let singlePosterStart = result.find("poster='", start)
    let useSingle = singlePosterStart >= 0 and (doublePosterStart < 0 or singlePosterStart < doublePosterStart)
    let posterStart = if useSingle: singlePosterStart else: doublePosterStart
    if posterStart < 0 or posterStart > tagEnd:
      cursor = tagEnd + 1
      continue
    let valueStart = posterStart + 7
    let quote = if useSingle: '\'' else: '"'
    let valueEnd = result.find(quote, valueStart)
    if valueEnd < 0 or valueEnd > tagEnd:
      cursor = tagEnd + 1
      continue
    let relative = result[valueStart ..< valueEnd]
    let assetName = decodeUrl(relative.split({'?', '#'}, maxsplit = 1)[0])
    let candidate = (baseDir / assetName).absolutePath().normalizedPath()
    let relativeCheck = relativePath(candidate, root)
    let mime = assetMime(candidate)
    if relativeCheck == ".." or relativeCheck.startsWith(".." & DirSep) or
        not fileExists(candidate) or not mime.startsWith("image/"):
      cursor = tagEnd + 1
      continue
    let dataUri = "data:" & mime & ";base64," & encode(readFile(candidate))
    result = result[0 ..< valueStart] & dataUri & result[valueEnd .. ^1]
    cursor = valueStart + dataUri.len + 1

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
    if window.app.backend == nativeBackend:
      let normalized = path.replace('\\', '/')
      let prefix = if normalized.len >= 2 and normalized[1] == ':': "file:///" else: "file://"
      let fileUrl = prefix & encodeUrl(
        if prefix == "file:///": normalized[0 .. ^1] else: normalized, false)
      return window.loadUrl(fileUrl)
    var content = readFile(path)
    if window.app.backend == wslBackend:
      content = inlineWslAssets(root, splitFile(path).dir, content, window.inlineRemoteAssets)
    window.loadHtml(content)
  except CatchableError:
    coreFailure(coreError(nativeFailure, "window.loadEntry",
      detail = "asset entry could not be read"))

proc loadHtml*(window: Window; html: string): CoreResult =
  if window.isNil or window.closed or window.app.isNil:
    return coreFailure(coreError(invalidState, "window.loadHtml"))
  window.lastUrl.setLen(0)
  ## Inline documents carry their own bootstrap. Remove any URL-scoped script
  ## before loading so a previous origin guard cannot leak into local HTML.
  let cleared = window.configureDocumentStartBridge("")
  if not cleared.isOk:
    return cleared
  let document = window.bridgeDocument(html)
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
  if script.len == 0:
    target.complete(coreFailureOf[string](coreError(invalidArgument, "window.evalJavaScript",
      detail = "script must not be empty")))
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

proc invokeReady(app: App) =
  if not app.isNil and not app.readyHandler.isNil:
    try: app.readyHandler()
    except CatchableError: discard

when defined(linux):
  proc processWslFileDialogResponse(app: App;
                                    response: ProtocolMessage): CoreResultOf[bool] =
    var index = 0
    while index < app.pendingWslFileDialogs.len:
      let pending = app.pendingWslFileDialogs[index]
      if pending.requestId != response.requestId:
        inc index
        continue
      app.pendingWslFileDialogs.delete(index)
      if response.error.len > 0:
        pending.target.complete(coreFailureOf[seq[string]](coreError(nativeFailure,
          "window.openFileDialog", detail = response.error)))
        return coreSuccessOf(false)
      try:
        let payload = parseJson(response.payload)
        if payload.kind != JObject or not payload.hasKey("ok") or
            payload["ok"].kind != JBool:
          pending.target.complete(coreFailureOf[seq[string]](coreError(nativeFailure,
            "window.openFileDialog", detail = "WSL file dialog response is malformed")))
          return coreSuccessOf(false)
        if not payload["ok"].getBool():
          let kind = if payload.hasKey("kind") and payload["kind"].kind == JString:
            wslNativeErrorKind(payload["kind"].getStr())
          else: nativeFailure
          let detail = if payload.hasKey("detail") and payload["detail"].kind == JString:
            payload["detail"].getStr()
          else: "WSL file dialog failed"
          let code = if payload.hasKey("platformCode") and payload["platformCode"].kind == JInt:
            int32(payload["platformCode"].getInt())
          else: 0'i32
          pending.target.complete(coreFailureOf[seq[string]](coreError(kind,
            "window.openFileDialog", platformCode = code, detail = detail)))
          return coreSuccessOf(false)
        if not payload.hasKey("paths") or payload["paths"].kind != JArray:
          pending.target.complete(coreFailureOf[seq[string]](coreError(nativeFailure,
            "window.openFileDialog", detail = "WSL file dialog paths are malformed")))
          return coreSuccessOf(false)
        var paths: seq[string]
        for item in payload["paths"].items:
          if item.kind != JString:
            pending.target.complete(coreFailureOf[seq[string]](coreError(nativeFailure,
              "window.openFileDialog", detail = "WSL file dialog path is not a string")))
            return coreSuccessOf(false)
          paths.add(item.getStr())
        pending.target.complete(coreSuccessOf(paths))
        return coreSuccessOf(false)
      except CatchableError:
        pending.target.complete(coreFailureOf[seq[string]](coreError(nativeFailure,
          "window.openFileDialog", detail = "WSL file dialog response is malformed")))
        return coreSuccessOf(false)
    coreFailureOf[bool](coreError(nativeFailure, "wsl.response",
      detail = "response does not match a pending file dialog"))

  proc processWslProfileDataClearResponse(app: App;
                                          response: ProtocolMessage): CoreResultOf[bool] =
    var index = 0
    while index < app.pendingWslProfileDataClears.len:
      let pending = app.pendingWslProfileDataClears[index]
      if pending.requestId != response.requestId:
        inc index
        continue
      app.pendingWslProfileDataClears.delete(index)
      if response.error.len > 0:
        pending.target.complete(coreFailure(coreError(nativeFailure,
          "window.clearWebViewProfileData", detail = "WSL host rejected browser data clear")))
        return coreSuccessOf(false)
      try:
        let payload = parseJson(response.payload)
        if payload.kind != JObject or not payload.hasKey("ok") or
            payload["ok"].kind != JBool:
          pending.target.complete(coreFailure(coreError(nativeFailure,
            "window.clearWebViewProfileData", detail =
              "WSL browser data clear response is malformed")))
          return coreSuccessOf(false)
        if payload["ok"].getBool():
          pending.target.complete(coreSuccess())
          return coreSuccessOf(false)
        if not payload.hasKey("kind") or not payload.hasKey("operation") or
            not payload.hasKey("platformCode") or not payload.hasKey("detail") or
            payload["kind"].kind != JString or payload["operation"].kind != JString or
            payload["platformCode"].kind != JInt or payload["detail"].kind != JString:
          pending.target.complete(coreFailure(coreError(nativeFailure,
            "window.clearWebViewProfileData", detail =
              "WSL browser data clear response is malformed")))
          return coreSuccessOf(false)
        pending.target.complete(coreFailure(coreError(
          wslNativeErrorKind(payload["kind"].getStr()),
          "window.clearWebViewProfileData",
          platformCode = int32(payload["platformCode"].getInt()),
          detail = payload["detail"].getStr()
        )))
        return coreSuccessOf(false)
      except CatchableError:
        pending.target.complete(coreFailure(coreError(nativeFailure,
          "window.clearWebViewProfileData", detail =
            "WSL browser data clear response is malformed")))
        return coreSuccessOf(false)
    coreFailureOf[bool](coreError(nativeFailure, "wsl.response",
      detail = "host response does not match a pending browser data clear"))

  proc processWslEvent(app: App; event: ProtocolMessage): CoreResultOf[bool] =
    if event.kind == ProtocolMessageKind.response:
      for pending in app.pendingWslFileDialogs:
        if pending.requestId == event.requestId:
          return app.processWslFileDialogResponse(event)
      return app.processWslProfileDataClearResponse(event)
    if event.kind == ProtocolMessageKind.request and
        event.methodName == "native.webview.policyRequested":
      let policy = parsePolicyRequest(event.payload)
      if not policy.isOk:
        discard app.wslClient.sendResponse(event.requestId, "{}", policy.failure.detail)
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.policy",
          detail = policy.failure.detail))
      var allowed = false
      var customResponse = CustomProtocolResponse(statusCode: 500,
        mimeType: "text/plain", body: "Custom protocol request denied")
      if policy.value.kind == customProtocolPolicy and not app.customProtocolHandler.isNil:
        try:
          customResponse = normalizeCustomProtocolResponse(
            app.customProtocolHandler(CustomProtocolRequest(
            methodName: policy.value.methodName,
            url: policy.value.url,
            path: policy.value.path)))
          allowed = customResponse.statusCode >= 100 and customResponse.statusCode <= 599
        except CatchableError:
          allowed = false
      for window in app.windows:
        if not window.closed and policy.value.kind == closePolicy and
            window.windowId == policy.value.windowId:
          allowed = if window.closeRequestedHandler.isNil: true
                    else:
                      try: window.closeRequestedHandler()
                      except CatchableError: false
          break
        if not window.closed and not window.findWebView(policy.value.webViewId).isNil:
          if policy.value.kind == permissionPolicy:
            var permissionKnown = true
            var permissionKind = microphone
            case policy.value.permissionKind
            of "microphone": permissionKind = microphone
            of "camera": permissionKind = camera
            of "notifications": permissionKind = notifications
            of "geolocation": permissionKind = geolocation
            of "clipboard": permissionKind = clipboard
            of "screenCapture": permissionKind = screenCapture
            else: permissionKnown = false
            ## Unknown host/WebView permission names must never inherit a
            ## known grant.  The native adapter has already fail-closed;
            ## keep the client-side policy equally strict.
            if permissionKnown:
              allowed = window.decidePermission(PermissionRequest(
                kind: permissionKind, url: policy.value.url)) == permissionGrant
          elif policy.value.kind == downloadPolicy:
            allowed = window.decideDownload(DownloadRequest(
              url: policy.value.url,
              suggestedName: policy.value.suggestedName)) == downloadAllow
          else:
            allowed = window.applyNavigationDecision(NavigationRequest(
              url: policy.value.url))
          break
      let sent = app.wslClient.sendResponse(event.requestId,
        policyResponseJson(PolicyResponse(allow: allowed,
          statusCode: customResponse.statusCode,
          mimeType: customResponse.mimeType,
          body: customResponse.body)))
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
    of "native.window.closed":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("windowId") or
            payload["windowId"].kind != JString:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "Window closed event is malformed"))
        let windowId = uint64(parseUInt(payload["windowId"].getStr()))
        for window in app.windows:
          if not window.closed and window.windowId == windowId:
            window.closed = true
            window.rpc.close()
            if not window.closedHandler.isNil:
              try: window.closedHandler()
              except CatchableError: discard
            break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "Window closed event is malformed"))
    of "native.window.resized":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("windowId") or
            not payload.hasKey("width") or not payload.hasKey("height") or
            payload["windowId"].kind != JString or
            payload["width"].kind != JInt or
            payload["height"].kind != JInt:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "Window resized event is malformed"))
        let windowId = uint64(parseUInt(payload["windowId"].getStr()))
        let width = payload["width"].getInt()
        let height = payload["height"].getInt()
        if width <= 0 or height <= 0:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "Window resized event has invalid dimensions"))
        for window in app.windows:
          if not window.closed and window.windowId == windowId:
            if not window.resizeHandler.isNil:
              try: window.resizeHandler(width, height)
              except CatchableError: discard
            break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "Window resized event is malformed"))
    of "native.app.desktopAction":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("kind") or
            not payload.hasKey("itemId") or payload["kind"].kind != JString or
            payload["itemId"].kind != JInt:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "desktop action event is malformed"))
        let itemId = payload["itemId"].getInt()
        if itemId <= 0 or itemId > int64(high(uint32)):
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "desktop action item ID is out of range"))
        let actionKind = payload["kind"].getStr()
        let handler = case actionKind
          of "menu": app.nativeMenuHandler
          of "tray": app.trayMenuHandler
          else: nil
        if handler.isNil:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "desktop action kind has no registered handler"))
        try: handler(uint32(itemId))
        except CatchableError: discard
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "desktop action event is malformed"))
    of "native.app.notificationActivated":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("notificationId") or
            payload["notificationId"].kind != JString or
            payload["notificationId"].getStr().len == 0:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "notification activation event is malformed"))
        if not app.notificationActivatedHandler.isNil:
          try: app.notificationActivatedHandler(payload["notificationId"].getStr())
          except CatchableError: discard
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "notification activation event is malformed"))
    of "native.app.deepLink":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("url") or
            payload["url"].kind != JString:
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "deep-link activation event is malformed"))
        let delivered = app.deliverDeepLink(payload["url"].getStr())
        if not delivered.isOk:
          return coreFailureOf[bool](delivered.failure)
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "deep-link activation event is malformed"))
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
          if not window.closed:
            let view = window.findWebView(webViewId)
            if not view.isNil:
              let message = payload["message"].getStr()
              if not view.messageHandler.isNil:
                try: view.messageHandler(message)
                except CatchableError: discard
              if view == window.webViews[0]:
                discard window.rpc.handleMessage(message)
              break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "WebView message event is malformed"))
    of "native.webview.navigationCompleted":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("webViewId") or
            not payload.hasKey("url") or not payload.hasKey("succeeded"):
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "navigation completed event is malformed"))
        let webViewId = uint64(parseUInt(payload["webViewId"].getStr()))
        for window in app.windows:
          let view = window.findWebView(webViewId)
          if not window.closed and not view.isNil and
              not window.navigationCompletedHandler.isNil:
            let succeeded = payload["succeeded"].getBool()
            if succeeded:
              discard window.syncDocumentCookies()
            try: window.navigationCompletedHandler(payload["url"].getStr(), succeeded)
            except CatchableError: discard
            break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "navigation completed event is malformed"))
    of "native.webview.downloadEvent", "native.webview.downloadStarted":
      try:
        let payload = parseJson(event.payload)
        if payload.kind != JObject or not payload.hasKey("webViewId") or
            not payload.hasKey("url") or
            (not payload.hasKey("state") and not payload.hasKey("succeeded")):
          return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
            detail = "download event is malformed"))
        let webViewId = uint64(parseUInt(payload["webViewId"].getStr()))
        for window in app.windows:
          let view = window.findWebView(webViewId)
          if not window.closed and not view.isNil and
              not window.downloadEventHandler.isNil:
            let state = if payload.hasKey("state"):
              case payload["state"].getStr()
              of "started": downloadStarted
              of "progress": downloadProgress
              of "completed": downloadCompleted
              of "cancelled": downloadCancelled
              else: downloadFailed
            else:
              if payload["succeeded"].getBool(): downloadStarted else: downloadFailed
            let progress = if payload.hasKey("progress"): payload["progress"].getFloat()
                           elif state == downloadFailed: -1.0
                           else: 0.0
            try: window.downloadEventHandler(DownloadEvent(
              request: DownloadRequest(url: payload["url"].getStr(),
                suggestedName: "download"),
              state: state,
              progress: progress))
            except CatchableError: discard
            break
      except CatchableError:
        return coreFailureOf[bool](coreError(nativeFailure, "wsl.event",
          detail = "download event is malformed"))
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
          let view = window.findWebView(webViewId)
          if not window.closed and not view.isNil and
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
          let view = window.findWebView(webViewId)
          if not window.closed and not view.isNil and
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
    app.invokeReady()
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
      let bufferedResponses = app.wslClient.takeResponses()
      for response in bufferedResponses:
        let handled = app.processWslEvent(response)
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
  if not app.beforeQuitHandler.isNil:
    try:
      if not app.beforeQuitHandler():
        return coreFailure(coreError(invalidState, "app.quit", detail = "quit request denied"))
    except CatchableError:
      return coreFailure(coreError(nativeFailure, "app.quit", detail = "before-quit handler failed"))
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

proc invokeExit(app: App) =
  if not app.isNil and not app.exitHandler.isNil:
    try: app.exitHandler()
    except CatchableError: discard

proc dispose(app: App) =
  if app.isNil:
    return
  app.invokeExit()
  for window in app.windows:
    window.closed = true
    if window.rpc != nil:
      window.rpc.close()
    for view in window.webViews:
      if not view.isNil:
        view.closed = true
        view.window = nil
    window.webViews.setLen(0)
    window.nativeView = nil
    window.nativeWindow = nil
    window.app = nil
  app.windows.setLen(0)
  app.nativeApp = nil
  when defined(linux):
    for pending in app.pendingWslFileDialogs:
      if not pending.target.finished:
        pending.target.complete(coreFailureOf[seq[string]](coreError(invalidState,
          "window.openFileDialog", detail = "WSL host session closed")))
    app.pendingWslFileDialogs.setLen(0)
    for pending in app.pendingWslProfileDataClears:
      if not pending.target.finished:
        pending.target.complete(coreFailure(coreError(invalidState,
          "window.clearWebViewProfileData", detail = "WSL host session closed")))
    app.pendingWslProfileDataClears.setLen(0)
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
  app.invokeReady()
  let nativeResult = native.run(app.nativeApp)
  let appResult = nativeResult.fromNative()
  app.dispose()
  appResult
