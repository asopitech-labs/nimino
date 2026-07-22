## macOS Cocoa/WKWebView backend.
##
## Cocoa objects and delegates live in bridge.m.  Nim owns the public object
## graph and lifecycle state; bridge callbacks only copy values across the
## boundary and dispatch them through the same guards as Linux and Windows.

proc macosIdleTick(data: pointer) {.cdecl.}
proc macosCloseRequested(data: pointer): cint {.cdecl.}
proc macosClosed(data: pointer) {.cdecl.}
proc macosResized(data: pointer; width, height: cint) {.cdecl.}
proc macosFileDropped(data: pointer; path: cstring) {.cdecl.}
proc macosMessage(data: pointer; message: cstring) {.cdecl.}
proc macosError(data: pointer; operation, detail: cstring) {.cdecl.}
proc macosNavigationStarting(data: pointer; url: cstring): cint {.cdecl.}
proc macosNavigationCompleted(data: pointer; url: cstring; succeeded: cint) {.cdecl.}
proc macosNewWindow(data: pointer; url: cstring): cint {.cdecl.}
proc macosEvalCompleted(data, requestData: pointer; value: cstring;
                        succeeded: cint; error: cstring) {.cdecl.}
proc macosBrowsingDataCompleted*(data, requestData: pointer; succeeded: cint) {.cdecl.}
proc macosCookieItem*(data, requestData: pointer; name, value, domain, path: cstring;
                     secure, httpOnly: cint; expires: int64) {.cdecl.}
proc macosCookieCompleted*(data, requestData: pointer; succeeded: cint) {.cdecl.}
proc macosCookieMutationCompleted*(data, requestData: pointer; succeeded: cint) {.cdecl.}
proc macosMenuAction(data: pointer; itemId: cuint) {.cdecl.}
proc macosCustomProtocolRequest(data, task: pointer; methodName, url, path: cstring) {.cdecl.}
proc macosReopen(data: pointer) {.cdecl.}
proc macosQuit(app: NativeApp)
proc macosDisposeView(view: NativeWebView)
proc macosDisposeWindow(window: NativeWindow)
proc macosCreateView(view: NativeWebView): NativeResult
proc macosSetZoom(view: NativeWebView; factor: float): NativeResult
proc macosLoadPendingContent(view: NativeWebView): NativeResult
proc macosShowWindow(window: NativeWindow)
proc macosSetTitleBarOverlay(window: NativeWindow; enabled: bool): NativeResult

proc macosKeepCallbackSymbols() =
  discard cast[pointer](macosBrowsingDataCompleted)
  discard cast[pointer](macosCookieItem)
  discard cast[pointer](macosCookieCompleted)
  discard cast[pointer](macosCookieMutationCompleted)

proc macosNativeFailure(operation, detail: string): NativeResult =
  failure(nativeError(webViewError, operation, detail = detail))

proc macosIdleTick(data: pointer) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app.isNil or app.state != running:
    return
  if not app.dispatchUiTasks():
    app.hasRunError = true
    app.runError = nativeError(osError, "app.postToUi")
    app.quitRequested = true
    app.macosQuit()
    return
  if app.idleHandler != nil:
    try:
      app.idleHandler()
    except CatchableError as error:
      app.hasRunError = true
      app.runError = nativeError(osError, "app.idleHandler", detail = error.msg)
      app.quitRequested = true
      app.macosQuit()
      return
  if app.quitRequested:
    app.macosQuit()

proc macosCloseRequested(data: pointer): cint {.cdecl.} =
  let window = cast[NativeWindow](data)
  if window.dispatchCloseRequested(): 0 else: 1

proc macosClosed(data: pointer) {.cdecl.} =
  let window = cast[NativeWindow](data)
  if window.isNil or window.state == closed:
    return
  window.state = closing
  for view in window.views:
    if not view.isNil and view.state != closed:
      view.macosDisposeView()
  window.state = closed
  window.dispatchClosed()

proc macosResized(data: pointer; width, height: cint) {.cdecl.} =
  let window = cast[NativeWindow](data)
  if window != nil:
    window.dispatchResized(width.int, height.int)

proc macosFileDropped(data: pointer; path: cstring) {.cdecl.} =
  let window = cast[NativeWindow](data)
  if window != nil and not path.isNil:
    window.dispatchFileDrop(@[$path])

proc macosMessage(data: pointer; message: cstring) {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view != nil and not message.isNil:
    view.dispatchMessage($message)

proc macosError(data: pointer; operation, detail: cstring) {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view != nil:
    view.dispatchError(nativeError(webViewError, if operation.isNil: "webview" else: $operation,
      detail = if detail.isNil: "WKWebView operation failed" else: $detail))

proc macosNavigationStarting(data: pointer; url: cstring): cint {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view.isNil:
    return 0
  if view.dispatchNavigationStarting(if url.isNil: "" else: $url): 1 else: 0

proc macosNavigationCompleted(data: pointer; url: cstring; succeeded: cint) {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view != nil:
    view.dispatchNavigationCompleted(if url.isNil: "" else: $url, succeeded != 0)

proc macosNewWindow(data: pointer; url: cstring): cint {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view.isNil:
    return 1
  if view.dispatchNewWindowRequested(if url.isNil: "" else: $url): 1 else: 0

proc macosEvalCompleted(data, requestData: pointer; value: cstring;
                        succeeded: cint; error: cstring) {.cdecl.} =
  let view = cast[NativeWebView](data)
  let request = cast[NativeScriptRequest](requestData)
  if view.isNil or request.isNil:
    return
  if succeeded != 0:
    view.completeScriptRequest(request, successOf(if value.isNil: "" else: $value))
  else:
    view.completeScriptRequest(request, failureOf[string](nativeError(webViewError,
      "webview.evalJavaScript", detail = if error.isNil: "JavaScript evaluation failed" else: $error)))

proc macosBrowsingDataCompleted*(data, requestData: pointer; succeeded: cint) {.cdecl.} =
  let view = cast[NativeWebView](data)
  let request = cast[NativeBrowsingDataRequest](requestData)
  if view.isNil or request.isNil:
    return
  view.completeBrowsingDataRequest(request,
    if succeeded != 0: success() else: failure(nativeError(webViewError,
      "webview.clearBrowsingData", detail = "WKWebsiteDataStore failed")))

proc macosCookieItem*(data, requestData: pointer; name, value, domain, path: cstring;
                     secure, httpOnly: cint; expires: int64) {.cdecl.} =
  let request = cast[NativeCookieQueryRequest](requestData)
  if request.isNil:
    return
  request.cookies.add(NativeCookie(
    name: if name.isNil: "" else: $name,
    value: if value.isNil: "" else: $value,
    domain: if domain.isNil: "" else: $domain,
    path: if path.isNil: "" else: $path,
    secure: secure != 0, httpOnly: httpOnly != 0, expires: expires))

proc macosCookieCompleted*(data, requestData: pointer; succeeded: cint) {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view.isNil:
    return
  let request = cast[NativeCookieQueryRequest](requestData)
  view.completeCookieQuery(request,
    if succeeded != 0: successOf(request.cookies) else:
      failureOf[seq[NativeCookie]](nativeError(webViewError, "webview.getCookies")))

proc macosCookieMutationCompleted*(data, requestData: pointer; succeeded: cint) {.cdecl.} =
  let view = cast[NativeWebView](data)
  let request = cast[NativeCookieMutationRequest](requestData)
  if view.isNil or request.isNil:
    return
  view.completeCookieMutation(request,
    if succeeded != 0: success() else: failure(nativeError(webViewError,
      if request.kind == nativeCookieSet: "webview.setCookie" else: "webview.deleteCookie")))

proc macosMenuAction(data: pointer; itemId: cuint) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app != nil:
    app.dispatchNativeMenu(itemId.uint32)

proc macosTrayAction(data: pointer; itemId: cuint) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app != nil:
    app.dispatchTrayMenu(itemId.uint32)

proc macosNotificationActivated(data: pointer; notificationId: cstring) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app != nil and not app.notificationActivatedHandler.isNil:
    try:
      app.notificationActivatedHandler(if notificationId.isNil: "" else: $notificationId)
    except CatchableError:
      discard

proc macosDeepLink(data: pointer; url: cstring) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app != nil:
    app.dispatchDeepLink(if url.isNil: "" else: $url)

proc macosReopen(data: pointer) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app.isNil:
    return
  ## Restore all live hidden windows when the Dock icon is activated.
  for window in app.windows:
    if not window.isNil and window.state == ready and window.hidden:
      macosShowWindow(window)

proc macosPermission(data: pointer; kind, url: cstring): cint {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view.isNil: return 0
  if view.dispatchPermissionRequested(if kind.isNil: "unknown" else: $kind,
      if url.isNil: "" else: $url): 1 else: 0

proc macosDownloadStarting(data: pointer; url: cstring): cint {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view.isNil: return 0
  if view.dispatchDownloadStarting(if url.isNil: "" else: $url): 1 else: 0

proc macosDownloadPath(data: pointer; url: cstring): cstring {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view.isNil: return "".cstring
  view.activeDownloadPath = view.dispatchDownloadPath(if url.isNil: "" else: $url)
  view.activeDownloadPath.cstring

proc macosDownloadEvent(data: pointer; url: cstring; state: cint; progress: cdouble) {.cdecl.} =
  let view = cast[NativeWebView](data)
  if view.isNil: return
  let eventState = case state
    of 0: nativeDownloadStarted
    of 1: nativeDownloadProgress
    of 2: nativeDownloadCompleted
    of 3: nativeDownloadFailed
    else: nativeDownloadCancelled
  view.dispatchDownloadEvent(if url.isNil: "" else: $url, eventState, progress.float)

proc macosCustomProtocolRequest(data, task: pointer; methodName, url, path: cstring) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app.isNil:
    return
  let response = app.dispatchCustomProtocol(NativeCustomProtocolRequest(
    methodName: if methodName.isNil: "GET" else: $methodName,
    url: if url.isNil: "" else: $url,
    path: if path.isNil: "/" else: $path))
  macosSchemeRespond(task, response.statusCode.cint, response.mimeType.cstring,
    response.body.cstring)

proc macosCreateView(view: NativeWebView): NativeResult =
  if view.isNil or view.window.isNil or view.window.platformWindow.isNil:
    return failure(nativeError(invalidState, "webview.create"))
  let context = macosViewCreate(view.window.platformWindow, cast[pointer](view),
    view.userAgent.cstring, view.window.profilePath.cstring,
    view.window.app.customProtocolScheme.cstring, view.documentStartScript.cstring,
    view.proxyUrl.cstring,
    if view.incognito: 1 else: 0, if view.devToolsEnabled: 1 else: 0,
    if view.ignoreCertificateErrors: 1 else: 0,
    cast[MacCallback](macosMessage), cast[MacCallback](macosError),
    cast[MacCallback](macosNewWindow), cast[MacCallback](macosNavigationStarting),
    cast[MacCallback](macosNavigationCompleted), cast[MacCallback](macosEvalCompleted),
    cast[MacCallback](macosFileDropped), cast[MacCallback](macosPermission),
    cast[MacCallback](macosDownloadStarting), cast[MacCallback](macosDownloadPath),
    cast[MacCallback](macosDownloadEvent))
  if context.isNil:
    return macosNativeFailure("webview.create", "WKWebView creation failed")
  view.platformView = context
  view.state = ready
  if view.zoomFactor != 1.0:
    let configured = view.macosSetZoom(view.zoomFactor)
    if not configured.isOk: return configured
  let loaded = view.macosLoadPendingContent()
  if not loaded.isOk:
    return loaded
  view.dispatchPendingScripts()
  success()

proc macosCreateWindow(window: NativeWindow): NativeResult =
  if window.isNil or window.app.isNil or window.app.platformApp.isNil:
    return failure(nativeError(invalidState, "window.create"))
  let nativeWindow = macosWindowCreate(window.app.platformApp, cast[pointer](window),
    window.title.cstring, window.width.cint, window.height.cint,
    cast[MacCallback](macosCloseRequested), cast[MacCallback](macosClosed),
    cast[MacCallback](macosResized), cast[MacCallback](macosFileDropped))
  if nativeWindow.isNil:
    return macosNativeFailure("window.create", "NSWindow creation failed")
  window.platformWindow = nativeWindow
  window.platformContainer = nativeWindow
  if window.titleBarOverlay:
    let configured = window.macosSetTitleBarOverlay(true)
    if not configured.isOk:
      return configured
  for view in window.views:
    let created = view.macosCreateView()
    if not created.isOk:
      return created
  window.state = ready
  if not window.hidden:
    macosWindowShow(nativeWindow)
  success()

proc macosDisposeView(view: NativeWebView) =
  if view.isNil or view.state == closed:
    return
  view.state = closing
  view.failOutstandingScripts(nativeError(invalidState, "webview.evalJavaScript"))
  view.failOutstandingBrowsingDataRequests(nativeError(invalidState,
    "webview.clearBrowsingData", detail = "the WebView closed before clearing completed"))
  view.failOutstandingCookieQueries(nativeError(invalidState,
    "webview.getCookies", detail = "the WebView closed before the cookie query completed"))
  view.failOutstandingCookieMutations(nativeError(invalidState,
    "webview.setCookie", detail = "the WebView closed before the cookie mutation completed"))
  if view.platformView != nil:
    macosViewDispose(view.platformView)
    view.platformView = nil
  view.releaseCallbackReferences()
  view.state = closed

proc macosDisposeWindow(window: NativeWindow) =
  if window.isNil:
    return
  if window.state == closed and window.platformWindow.isNil:
    return
  window.state = closing
  for view in window.views:
    view.macosDisposeView()
  if window.platformWindow != nil:
    macosWindowDispose(window.platformWindow)
    window.platformWindow = nil
    window.platformContainer = nil
  window.state = closed
  window.dispatchClosed()

proc macosSetTitle(window: NativeWindow): NativeResult =
  if window.platformWindow.isNil: return success()
  if macosWindowSetTitle(window.platformWindow, window.title.cstring) == 0:
    return macosNativeFailure("window.setTitle", "NSWindow title update failed")
  success()

proc macosSetSize(window: NativeWindow): NativeResult =
  if window.platformWindow.isNil: return success()
  if macosWindowSetSize(window.platformWindow, window.width.cint, window.height.cint) == 0:
    return macosNativeFailure("window.setSize", "NSWindow resize failed")
  success()

proc macosSetPosition(window: NativeWindow; x, y: int): NativeResult =
  if window.platformWindow.isNil: return failure(nativeError(invalidState, "window.setPosition"))
  if macosWindowSetPosition(window.platformWindow, x.cint, y.cint) == 0:
    return macosNativeFailure("window.setPosition", "NSWindow position update failed")
  success()

proc macosSetResizable(window: NativeWindow; enabled: bool): NativeResult =
  if window.platformWindow.isNil: return success()
  if macosWindowSetResizable(window.platformWindow, if enabled: 1 else: 0) == 0:
    return macosNativeFailure("window.setResizable", "NSWindow style update failed")
  success()

proc macosSetDecorated(window: NativeWindow; enabled: bool): NativeResult =
  if window.platformWindow.isNil: return success()
  if macosWindowSetDecorated(window.platformWindow, if enabled: 1 else: 0) == 0:
    return macosNativeFailure("window.setDecorated", "NSWindow style update failed")
  success()

proc macosSetTitleBarOverlay(window: NativeWindow; enabled: bool): NativeResult =
  if window.platformWindow.isNil: return success()
  if macosWindowSetTitleBarOverlay(window.platformWindow, if enabled: 1 else: 0) == 0:
    return macosNativeFailure("window.setTitleBarOverlay", "NSWindow title bar style update failed")
  success()

proc macosSetFullscreen(window: NativeWindow; enabled: bool): NativeResult =
  if macosWindowSetFullscreen(window.platformWindow, if enabled: 1 else: 0) == 0:
    return macosNativeFailure("window.setFullscreen", "NSWindow fullscreen transition failed")
  window.fullscreenActive = enabled
  success()

proc macosSetAlwaysOnTop(window: NativeWindow; enabled: bool): NativeResult =
  if macosWindowSetAlwaysOnTop(window.platformWindow, if enabled: 1 else: 0) == 0:
    return macosNativeFailure("window.setAlwaysOnTop", "NSWindow level update failed")
  window.alwaysOnTop = enabled
  success()

proc macosShowWindow(window: NativeWindow) =
  window.hidden = false
  if window.platformWindow != nil: macosWindowShow(window.platformWindow)
proc macosHideWindow(window: NativeWindow) =
  window.hidden = true
  if window.platformWindow != nil: macosWindowHide(window.platformWindow)
proc macosMinimizeWindow(window: NativeWindow) = macosWindowMinimize(window.platformWindow)
proc macosMaximizeWindow(window: NativeWindow) = macosWindowMaximize(window.platformWindow)
proc macosRestoreWindow(window: NativeWindow) = macosWindowRestore(window.platformWindow)
proc macosFocusWindow(window: NativeWindow) = macosWindowFocus(window.platformWindow)

proc macosSetUserAgent(view: NativeWebView; value: string): NativeResult =
  if view.platformView.isNil: return failure(nativeError(invalidState, "webview.setUserAgent"))
  if macosViewSetUserAgent(view.platformView, value.cstring) == 0:
    return macosNativeFailure("webview.setUserAgent", "WKWebView user-agent update failed")
  success()

proc macosSetZoom(view: NativeWebView; factor: float): NativeResult =
  if view.platformView.isNil: return failure(nativeError(invalidState, "webview.setZoom"))
  if macosViewSetZoom(view.platformView, factor.cdouble) == 0:
    return macosNativeFailure("webview.setZoom", "WKWebView zoom update failed")
  success()

proc macosSetIgnoreCertificateErrors(view: NativeWebView; enabled: bool): NativeResult =
  if view.state == pending:
    return success()
  if macosViewSetIgnoreCertificateErrors(view.platformView, if enabled: 1 else: 0) == 0:
    return macosNativeFailure("webview.setIgnoreCertificateErrors", "WKWebView challenge policy update failed")
  success()

proc macosSetDevToolsEnabled(view: NativeWebView; enabled: bool): NativeResult =
  if macosViewSetDevToolsEnabled(view.platformView, if enabled: 1 else: 0) == 0:
    return macosNativeFailure("webview.setDevToolsEnabled", "WKWebView preferences update failed")
  success()

proc macosLoadPendingContent(view: NativeWebView): NativeResult =
  if view.platformView.isNil: return success()
  case view.pendingContentKind
  of urlContent:
    if macosViewLoadUrl(view.platformView, view.pendingUrl.cstring) == 0:
      return macosNativeFailure("webview.loadUrl", "WKWebView rejected the URL")
  of htmlContent:
    if macosViewLoadHtml(view.platformView, view.pendingHtml.cstring,
        view.pendingHtmlBaseUrl.cstring) == 0:
      return macosNativeFailure("webview.loadHtml", "WKWebView rejected the HTML")
  of noContent:
    discard
  success()

proc macosConfigureDocumentStartScript(view: NativeWebView): NativeResult =
  if macosViewSetDocumentStartScript(view.platformView, view.documentStartScript.cstring) == 0:
    return macosNativeFailure("webview.setDocumentStartScript", "WKUserScript update failed")
  success()

proc macosEvalJavaScript(view: NativeWebView; request: NativeScriptRequest): NativeResult =
  if macosViewEvalJavaScript(view.platformView, request.script.cstring,
      cast[pointer](request)) == 0:
    return macosNativeFailure("webview.evalJavaScript", "WKWebView evaluation could not start")
  success()

proc macosClearBrowsingData(view: NativeWebView;
                            request: NativeBrowsingDataRequest): NativeResult =
  var kinds: uint32
  if nativeBrowsingCookies in request.kinds: kinds = kinds or 1
  if nativeBrowsingLocalStorage in request.kinds: kinds = kinds or 2
  if nativeBrowsingCache in request.kinds: kinds = kinds or 4
  if macosViewClearBrowsingData(view.platformView, kinds, cast[pointer](request),
      cast[MacCallback](macosBrowsingDataCompleted)) == 0:
    return macosNativeFailure("webview.clearBrowsingData", "WKWebsiteDataStore operation could not start")
  success()

proc macosGetCookies(view: NativeWebView; request: NativeCookieQueryRequest): NativeResult =
  if macosViewGetCookies(view.platformView, request.url.cstring, cast[pointer](request),
      cast[MacCallback](macosCookieItem), cast[MacCallback](macosCookieCompleted)) == 0:
    return macosNativeFailure("webview.getCookies", "WKHTTPCookieStore query could not start")
  success()

proc macosMutateCookie(view: NativeWebView;
                       request: NativeCookieMutationRequest): NativeResult =
  let cookie = request.cookie
  let path = if cookie.path.len == 0: "/" else: cookie.path
  let started = if request.kind == nativeCookieSet:
    macosViewSetCookie(view.platformView, cookie.name.cstring, cookie.value.cstring,
      cookie.domain.cstring, path.cstring, if cookie.secure: 1 else: 0,
      if cookie.httpOnly: 1 else: 0, cookie.expires, cast[pointer](request),
      cast[MacCallback](macosCookieMutationCompleted))
  else:
    macosViewDeleteCookie(view.platformView, cookie.name.cstring, cookie.value.cstring,
      cookie.domain.cstring, path.cstring, if cookie.secure: 1 else: 0,
      if cookie.httpOnly: 1 else: 0, cookie.expires, cast[pointer](request),
      cast[MacCallback](macosCookieMutationCompleted))
  if started == 0:
    return macosNativeFailure(if request.kind == nativeCookieSet: "webview.setCookie" else: "webview.deleteCookie",
      "WKHTTPCookieStore mutation could not start")
  success()

proc macosOpenFileDialog*(window: NativeWindow; options: NativeFileDialogOptions):
    NativeResultOf[seq[string]] =
  var nativePaths = newSeq[cstring](64)
  let count = macosOpenFileDialog(window.platformWindow, options.title.cstring,
    options.suggestedName.cstring, if options.save: 1 else: 0,
    if options.multiple: 1 else: 0, addr nativePaths[0], nativePaths.len.cint)
  if count < 0:
    return failureOf[seq[string]](nativeError(osError, "window.openFileDialog"))
  var paths: seq[string]
  for index in 0 ..< count:
    if not nativePaths[index].isNil:
      paths.add($nativePaths[index])
      macosFreeCString(nativePaths[index])
  successOf(paths)

proc macosInstallNativeMenu(app: NativeApp): NativeResult =
  if app.isNil or not app.nativeMenuConfigured:
    return success()
  var ids = newSeq[uint32](app.nativeMenuItems.len)
  var titles = newSeq[cstring](app.nativeMenuItems.len)
  var enabled = newSeq[cint](app.nativeMenuItems.len)
  for index, item in app.nativeMenuItems:
    ids[index] = item.id
    titles[index] = item.title.cstring
    enabled[index] = if item.enabled: 1 else: 0
  macosAppInstallMenu(app.platformApp, app.nativeMenuTitle.cstring, addr ids[0],
    addr titles[0], addr enabled[0], ids.len.cint, cast[MacCallback](macosMenuAction))
  app.nativeMenuInstalled = true
  success()

proc macosUninstallNativeMenu(app: NativeApp) =
  if app.isNil or not app.nativeMenuInstalled:
    return
  macosAppRemoveMenu(app.platformApp)
  app.nativeMenuInstalled = false

proc macosInstallSystemTray(app: NativeApp): NativeResult =
  if app.isNil or not app.trayConfigured:
    return success()
  var ids = newSeq[uint32](app.trayMenuItems.len)
  var titles = newSeq[cstring](app.trayMenuItems.len)
  var enabled = newSeq[cint](app.trayMenuItems.len)
  for index, item in app.trayMenuItems:
    ids[index] = item.id
    titles[index] = item.title.cstring
    enabled[index] = if item.enabled: 1 else: 0
  if macosAppInstallTray(app.platformApp, addr ids[0], addr titles[0],
      addr enabled[0], ids.len.cint, cast[MacCallback](macosTrayAction)) == 0:
    return macosNativeFailure("app.configureSystemTray", "NSStatusItem creation failed")
  app.trayVisible = true
  success()

proc macosUninstallSystemTray(app: NativeApp) =
  if app.isNil or not app.trayVisible or app.platformApp.isNil:
    return
  macosAppRemoveTray(app.platformApp)
  app.trayVisible = false

proc macosSetNotificationActivated(app: NativeApp;
                                   handler: NativeNotificationActivatedHandler): NativeResult =
  if app.platformApp.isNil:
    app.platformApp = macosAppCreate(cast[pointer](app))
  if app.platformApp.isNil or macosAppSetNotificationCallback(app.platformApp,
      cast[MacCallback](macosNotificationActivated)) == 0:
    return macosNativeFailure("app.onNotificationActivated", "NSUserNotificationCenter delegate setup failed")
  success()

proc macosSetDeepLinkHandler(app: NativeApp; handler: NativeDeepLinkHandler): NativeResult =
  if app.platformApp.isNil:
    app.platformApp = macosAppCreate(cast[pointer](app))
  if app.platformApp.isNil or macosAppSetDeepLinkCallback(app.platformApp,
      cast[MacCallback](macosDeepLink)) == 0:
    return macosNativeFailure("app.onDeepLink", "NSApplication delegate setup failed")
  success()

proc macosSendNativeNotification*(app: NativeApp;
                                  notification: NativeNotification): NativeResult =
  if macosAppSendNotification(app.platformApp, notification.id.cstring,
      notification.title.cstring, notification.body.cstring) == 0:
    return macosNativeFailure("app.sendNativeNotification", "NSUserNotification delivery failed")
  success()

proc macosRegisterCustomProtocol(app: NativeApp): NativeResult =
  if app.platformApp.isNil:
    app.platformApp = macosAppCreate(cast[pointer](app))
  if app.platformApp.isNil:
    return macosNativeFailure("app.registerCustomProtocol", "NSApplication creation failed")
  if macosAppRegisterScheme(app.platformApp, app.customProtocolScheme.cstring,
      cast[MacCallback](macosCustomProtocolRequest)) == 0:
    return macosNativeFailure("app.registerCustomProtocol", "WKWebView scheme registration failed")
  success()

proc macosQuit(app: NativeApp) =
  if app.isNil: return
  ## WKWebView callbacks can arrive while WebKit is unwinding its delegate
  ## call.  Defer Cocoa object disposal until macosRun returns on the main
  ## thread; stopping the application itself is safe to request asynchronously.
  if app.platformApp != nil:
    macosAppStop(app.platformApp)

proc macosDisposeApp(app: NativeApp) =
  if app.isNil or app.platformApp.isNil:
    return
  macosAppDispose(app.platformApp)
  app.platformApp = nil

proc macosPostToUi(app: NativeApp): NativeResult =
  if app.platformApp.isNil:
    return success()
  macosAppPostToUi(app.platformApp, cast[MacCallback](macosIdleTick))
  success()

proc macosRun(app: NativeApp): NativeResult =
  macosKeepCallbackSymbols()
  if app.platformApp.isNil:
    app.platformApp = macosAppCreate(cast[pointer](app))
  if app.platformApp.isNil:
    return macosNativeFailure("app.run", "NSApplication creation failed")
  if macosAppSetReopenCallback(app.platformApp, cast[MacCallback](macosReopen)) == 0:
    return macosNativeFailure("app.run", "NSApplication reopen delegate setup failed")
  app.state = running
  for window in app.windows:
    if window.state == pending:
      let created = window.macosCreateWindow()
      if not created.isOk:
        app.hasRunError = true
        app.runError = created.failure
        app.quitRequested = true
        break
  if not app.quitRequested and app.nativeMenuConfigured:
    let menu = app.macosInstallNativeMenu()
    if not menu.isOk:
      app.hasRunError = true
      app.runError = menu.failure
      app.quitRequested = true
  if not app.quitRequested and app.trayConfigured:
    let tray = app.macosInstallSystemTray()
    if not tray.isOk:
      app.hasRunError = true
      app.runError = tray.failure
      app.quitRequested = true
  if app.quitRequested:
    app.macosQuit()
  let status = if app.quitRequested: 0 else:
    macosAppRun(app.platformApp, cast[MacCallback](macosIdleTick))
  for window in app.windows:
    if window.state != closed:
      window.macosDisposeWindow()
  app.macosUninstallNativeMenu()
  app.macosUninstallSystemTray()
  app.macosDisposeApp()
  app.platformApp = nil
  app.state = finished
  if app.hasRunError: return failure(app.runError)
  if status == 0: success() else: failure(nativeError(osError, "app.run", platformCode = status.int32))
