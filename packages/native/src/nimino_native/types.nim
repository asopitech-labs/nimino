import std/asyncfutures

import ./[capabilities, errors]

type
  NativeIdleHandler* = proc() {.closure.}
  NativeMessageHandler* = proc(message: string) {.closure.}
  NativeErrorHandler* = proc(error: NativeError) {.closure.}
  NativeNewWindowRequestedHandler* = proc(url: string) {.closure.}
  NativeNavigationStartingHandler* = proc(url: string): bool {.closure.}
  NativeNavigationCompletedHandler* = proc(url: string; succeeded: bool) {.closure.}

  NativeState* = enum
    pending
    ready
    closing
    closed

  NativeAppState = enum
    created
    running
    finished

  NativeContentKind = enum
    noContent
    urlContent
    htmlContent

  NativeScriptRequest = ref object
    view: NativeWebView
    script: string
    future: Future[NativeResultOf[string]]

  NativeApp* = ref object
    state: NativeAppState
    capabilities: CapabilitySet
    platformApp: pointer
    platformLoader: pointer
    webView2CreateEnvironment: pointer
    webView2UserDataFolder: string
    platformInstance: pointer
    windowClassName: string
    windowClassRegistered: bool
    idleTimerWindow: pointer
    idleTimerSource: uint32
    idleHandler: NativeIdleHandler
    activateHandler: culong
    quitRequested: bool
    hasRunError: bool
    runError: NativeError
    windows: seq[NativeWindow]

  NativeWindow* = ref object
    app: NativeApp
    state: NativeState
    title: string
    width: int
    height: int
    platformWindow: pointer
    views: seq[NativeWebView]

  NativeWebView* = ref object
    window: NativeWindow
    state: NativeState
    pendingContentKind: NativeContentKind
    pendingUrl: string
    pendingHtml: string
    documentStartScript: string
    platformView: pointer
    platformEnvironment: pointer
    platformController: pointer
    platformMessageManager: pointer
    messageSignalHandler: culong
    policyDecisionSignalHandler: culong
    permissionSignalHandler: culong
    createSignalHandler: culong
    loadChangedSignalHandler: culong
    loadFailedSignalHandler: culong
    messageRegistrationToken: int64
    messageRegistered: bool
    newWindowToken: int64
    newWindowRegistered: bool
    navigationStartingToken: int64
    navigationStartingRegistered: bool
    navigationCompletedToken: int64
    navigationCompletedRegistered: bool
    navigationFailed: bool
    messageHandler: NativeMessageHandler
    errorHandler: NativeErrorHandler
    newWindowRequestedHandler: NativeNewWindowRequestedHandler
    navigationStartingHandler: NativeNavigationStartingHandler
    navigationCompletedHandler: NativeNavigationCompletedHandler
    pendingScripts: seq[NativeScriptRequest]
    activeScripts: seq[NativeScriptRequest]

when defined(linux) and not defined(niminoWsl):
  proc linuxEvalJavaScript(view: NativeWebView; request: NativeScriptRequest): NativeResult
elif defined(windows):
  proc windowsEvalJavaScript(view: NativeWebView; request: NativeScriptRequest): NativeResult

proc completeScriptRequest(view: NativeWebView; request: NativeScriptRequest;
                           evaluation: NativeResultOf[string]) =
  if request.isNil:
    return
  if request.future != nil and not request.future.finished:
    request.future.complete(evaluation)

  if view != nil and view.activeScripts.len > 0:
    for index in countdown(view.activeScripts.high, 0):
      if cast[pointer](view.activeScripts[index]) == cast[pointer](request):
        view.activeScripts.delete(index)
        break

proc failOutstandingScripts(view: NativeWebView; error: NativeError) =
  if view.isNil:
    return
  for request in view.pendingScripts:
    view.completeScriptRequest(request, failureOf[string](error))
    request.view = nil
  view.pendingScripts.setLen(0)
  for request in view.activeScripts:
    if request.future != nil and not request.future.finished:
      request.future.complete(failureOf[string](error))
  ## Native callbacks retain their request with GC_ref until they return. Keep
  ## no Nim-side ownership after closing, but let each callback GC_unref it.
  view.activeScripts.setLen(0)

proc releaseCallbackReferences(view: NativeWebView) =
  ## Native signal/COM registrations are removed by each backend before this
  ## runs.  Clearing Nim closures here prevents a closed WebView from keeping
  ## an owning core Window or application callback cycle alive under ARC.
  if view.isNil:
    return
  view.messageHandler = nil
  view.errorHandler = nil
  view.newWindowRequestedHandler = nil
  view.navigationStartingHandler = nil
  view.navigationCompletedHandler = nil

proc startScriptRequest(view: NativeWebView; request: NativeScriptRequest) =
  request.view = view
  view.activeScripts.add(request)
  when defined(linux) and not defined(niminoWsl):
    let started = view.linuxEvalJavaScript(request)
    if not started.isOk:
      view.completeScriptRequest(request, failureOf[string](started.failure))
  elif defined(windows):
    let started = view.windowsEvalJavaScript(request)
    if not started.isOk:
      view.completeScriptRequest(request, failureOf[string](started.failure))
  else:
    view.completeScriptRequest(request, failureOf[string](nativeError(
      unsupported, "webview.evalJavaScript", detail = "native backend is unavailable"
    )))

proc dispatchPendingScripts(view: NativeWebView) =
  if view.isNil or view.state != ready or view.platformView.isNil:
    return
  let pending = view.pendingScripts
  view.pendingScripts.setLen(0)
  for request in pending:
    view.startScriptRequest(request)

proc dispatchMessage(view: NativeWebView; message: string) =
  if view.isNil or view.state in {closing, closed} or view.messageHandler.isNil:
    return
  try:
    view.messageHandler(message)
  except CatchableError:
    ## A user callback must not unwind through a native C/COM callback.
    discard

proc dispatchError(view: NativeWebView; error: NativeError) =
  if view.isNil or view.state in {closing, closed} or view.errorHandler.isNil:
    return
  try:
    view.errorHandler(error)
  except CatchableError:
    ## A user callback must not unwind through a native C/COM callback.
    discard

proc dispatchNewWindowRequested(view: NativeWebView; url: string) =
  if view.isNil or view.state in {closing, closed} or
      view.newWindowRequestedHandler.isNil:
    return
  try:
    view.newWindowRequestedHandler(url)
  except CatchableError:
    ## A user callback must not unwind through a native C/COM callback.
    discard

proc dispatchNavigationCompleted(view: NativeWebView; url: string; succeeded: bool) =
  if view.isNil or view.state in {closing, closed} or
      view.navigationCompletedHandler.isNil:
    return
  try:
    view.navigationCompletedHandler(url, succeeded)
  except CatchableError:
    ## A user callback must not unwind through a native C/COM callback.
    discard

proc dispatchNavigationStarting(view: NativeWebView; url: string): bool =
  if view.isNil or view.state in {closing, closed}:
    return false
  if view.navigationStartingHandler.isNil:
    return true
  try:
    view.navigationStartingHandler(url)
  except CatchableError:
    ## A callback failure must not accidentally authorize a navigation.
    false

when defined(linux) and not defined(niminoWsl):
  import ./private/linux/ffi
  include "private/linux/backend"
elif defined(windows):
  import ./private/windows/ffi
  include "private/windows/backend"

proc newNativeApp*(): NativeApp =
  new(result)
  result.state = created
  result.capabilities = {}

proc supports*(app: NativeApp; capability: Capability): bool {.inline.} =
  app.capabilities.supports(capability)

proc newWindow*(app: NativeApp; title = "Nimino"; width = 1200; height = 800):
    NativeResultOf[NativeWindow] =
  if app.isNil or app.state == finished:
    return failureOf[NativeWindow](nativeError(invalidState, "window.create"))
  if width <= 0 or height <= 0:
    return failureOf[NativeWindow](nativeError(invalidState, "window.create", detail = "size must be positive"))

  let window = NativeWindow(
    app: app,
    state: pending,
    title: title,
    width: width,
    height: height
  )
  app.windows.add(window)
  successOf(window)

proc newWebView*(window: NativeWindow): NativeResultOf[NativeWebView] =
  if window.isNil or window.state in {closing, closed}:
    return failureOf[NativeWebView](nativeError(invalidState, "webview.create"))
  if window.views.len > 0:
    return failureOf[NativeWebView](nativeError(unsupported, "webview.create", detail = "M1 supports one view per window"))

  let view = NativeWebView(window: window, state: pending)
  window.views.add(view)
  successOf(view)

proc setTitle*(window: NativeWindow; title: string): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.setTitle"))
  window.title = title
  when defined(linux) and not defined(niminoWsl):
    linuxSetTitle(window)
    return success()
  elif defined(windows):
    return windowsSetTitle(window)
  else:
    return success()

proc setSize*(window: NativeWindow; width, height: int): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.setSize"))
  if width <= 0 or height <= 0 or width > int(high(int32)) or height > int(high(int32)):
    return failure(nativeError(invalidState, "window.setSize", detail = "size must be positive"))
  window.width = width
  window.height = height
  when defined(linux) and not defined(niminoWsl):
    linuxSetSize(window)
    return success()
  elif defined(windows):
    return windowsSetSize(window)
  else:
    return success()

proc loadUrl*(view: NativeWebView; url: string): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.loadUrl"))
  if url.len == 0:
    let error = nativeError(webViewError, "webview.loadUrl", detail = "URL must not be empty")
    view.dispatchError(error)
    return failure(error)
  view.pendingUrl = url
  view.pendingHtml.setLen(0)
  view.pendingContentKind = urlContent
  when defined(linux) and not defined(niminoWsl):
    linuxLoadPendingContent(view)
    return success()
  elif defined(windows):
    return windowsLoadPendingContent(view)
  else:
    return success()

proc loadHtml*(view: NativeWebView; html: string): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.loadHtml"))
  view.pendingHtml = html
  view.pendingUrl.setLen(0)
  view.pendingContentKind = htmlContent
  when defined(linux) and not defined(niminoWsl):
    linuxLoadPendingContent(view)
    return success()
  elif defined(windows):
    return windowsLoadPendingContent(view)
  else:
    return success()

proc setDocumentStartScript*(view: NativeWebView; script: string): NativeResult =
  ## Queue one replacement script for the first document creation.  It is a
  ## low-level primitive; policy and origin checks belong to nimino-core.
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.setDocumentStartScript"))
  if view.state != pending:
    return failure(nativeError(invalidState, "webview.setDocumentStartScript",
      detail = "document-start scripts must be configured before WebView creation"))
  if script.len == 0:
    return failure(nativeError(invalidState, "webview.setDocumentStartScript",
      detail = "script must not be empty"))
  view.documentStartScript = script
  success()

proc evalJavaScript*(view: NativeWebView; script: string): Future[NativeResultOf[string]] =
  let request = NativeScriptRequest(
    script: script,
    future: newFuture[NativeResultOf[string]]("nimino.native.evalJavaScript")
  )
  result = request.future
  if view.isNil or view.state in {closing, closed}:
    result.complete(failureOf[string](nativeError(invalidState, "webview.evalJavaScript")))
    return

  if view.state != ready or view.platformView.isNil:
    view.pendingScripts.add(request)
    return
  view.startScriptRequest(request)

proc onMessage*(view: NativeWebView; handler: NativeMessageHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onMessage"))
  view.messageHandler = handler
  success()

proc onError*(view: NativeWebView; handler: NativeErrorHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onError"))
  view.errorHandler = handler
  success()

proc onNewWindowRequested*(view: NativeWebView;
                           handler: NativeNewWindowRequestedHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onNewWindowRequested"))
  view.newWindowRequestedHandler = handler
  success()

proc onNavigationCompleted*(view: NativeWebView;
                            handler: NativeNavigationCompletedHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onNavigationCompleted"))
  view.navigationCompletedHandler = handler
  success()

proc onNavigationStarting*(view: NativeWebView;
                           handler: NativeNavigationStartingHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onNavigationStarting"))
  view.navigationStartingHandler = handler
  success()

proc quit*(app: NativeApp): NativeResult =
  if app.isNil or app.state == finished:
    return failure(nativeError(invalidState, "app.quit"))
  app.quitRequested = true
  when defined(linux) and not defined(niminoWsl):
    if app.state == running:
      linuxQuit(app)
    return success()
  elif defined(windows):
    if app.state == running:
      return windowsQuit(app)
    return success()
  else:
    return success()

proc close*(app: NativeApp): NativeResult =
  app.quit()

proc setIdleHandler*(app: NativeApp; handler: NativeIdleHandler): NativeResult =
  if app.isNil or app.state != created:
    return failure(nativeError(invalidState, "app.setIdleHandler"))
  when defined(windows) or (defined(linux) and not defined(niminoWsl)):
    app.idleHandler = handler
    return success()
  else:
    return failure(nativeError(unsupported, "app.setIdleHandler"))

proc run*(app: NativeApp): NativeResult =
  if app.isNil or app.state != created:
    return failure(nativeError(invalidState, "app.run"))
  if app.windows.len == 0:
    return failure(nativeError(invalidState, "app.run", detail = "at least one window is required"))

  when defined(linux) and not defined(niminoWsl):
    return linuxRun(app)
  elif defined(windows):
    return windowsRun(app)
  else:
    failure(nativeError(unsupported, "app.run", detail = "native backend is unavailable"))
