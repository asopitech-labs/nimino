import std/[asyncfutures, locks]

import ./[capabilities, errors]

type
  NativeIdleHandler* = proc() {.closure.}
  NativeUiHandler* = proc() {.closure.}
  NativeMessageHandler* = proc(message: string) {.closure.}
  NativeErrorHandler* = proc(error: NativeError) {.closure.}
  ## Return true when the application consumed the request.  Returning false
  ## explicitly delegates to the WebView engine's default popup behavior.
  NativeNewWindowRequestedHandler* = proc(url: string): bool {.closure.}
  NativeNavigationStartingHandler* = proc(url: string): bool {.closure.}
  NativeNavigationCompletedHandler* = proc(url: string; succeeded: bool) {.closure.}
  ## `kind` is the OS/WebView permission name (for example `microphone`,
  ## `camera`, `notifications`, `geolocation`, `clipboard`, or
  ## `screenCapture`). Unknown OS-specific permissions are reported as
  ## `unknown` and therefore remain denied by higher layers.
  NativePermissionRequestedHandler* = proc(kind, url: string): bool {.closure.}
  NativeDownloadStartingHandler* = proc(url: string): bool {.closure.}
  NativeDownloadState* = enum
    nativeDownloadStarted
    nativeDownloadProgress
    nativeDownloadCompleted
    nativeDownloadFailed
    nativeDownloadCancelled
  NativeDownloadEventHandler* = proc(url: string; state: NativeDownloadState;
                                     progress: float) {.closure.}
  NativeCloseRequestedHandler* = proc(): bool {.closure.}
  NativeClosedHandler* = proc() {.closure.}
  NativeResizeHandler* = proc(width, height: int) {.closure.}
  NativeMenuHandler* = proc(itemId: uint32) {.closure.}

  NativeMenuItem* = object
    ## A command exposed through an operating-system native menu.
    ## ID 0 is reserved as an invalid menu action identifier.
    id*: uint32
    title*: string
    enabled*: bool

  NativeNotification* = object
    ## A request for a desktop notification. Delivery remains under the
    ## desktop shell's control and is never reported as a display guarantee.
    id*: string
    title*: string
    body*: string

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

  NativeBrowsingDataKind* = enum
    ## Data owned by the embedded browser engine.  These values deliberately
    ## describe browser state only; Nimino profile files have separate APIs.
    nativeBrowsingCookies
    nativeBrowsingLocalStorage
    nativeBrowsingCache

  NativeScriptRequest = ref object
    view: NativeWebView
    script: string
    future: Future[NativeResultOf[string]]

  NativeBrowsingDataRequest = ref object
    view: NativeWebView
    kinds: set[NativeBrowsingDataKind]
    future: Future[NativeResult]

  NativeMenuAction = ref object
    app: NativeApp
    itemId: uint32

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
    uiTaskLock: Lock
    uiTasks: seq[NativeUiHandler]
    trayMenuItems: seq[NativeMenuItem]
    trayMenuHandler: NativeMenuHandler
    trayConfigured: bool
    trayVisible: bool
    trayWindow: pointer
    nativeMenuItems: seq[NativeMenuItem]
    nativeMenuHandler: NativeMenuHandler
    nativeMenuTitle: string
    nativeMenuConfigured: bool
    nativeMenuInstalled: bool
    activateHandler: culong
    startupHandler: culong
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
    profilePath*: string
    platformWindow: pointer
    platformContainer: pointer
    views: seq[NativeWebView]
    closeRequestedHandler: NativeCloseRequestedHandler
    closeSignalHandler: culong
    closedHandler: NativeClosedHandler
    resizeHandler: NativeResizeHandler
    resizeSignalHandler: culong
    closedNotified: bool

  NativeWebView* = ref object
    window: NativeWindow
    state: NativeState
    pendingContentKind: NativeContentKind
    pendingUrl: string
    pendingHtml: string
    pendingHtmlBaseUrl: string
    documentStartScript: string
    devToolsEnabled: bool
    documentStartScriptId: string
    documentStartScriptUpdatePending: bool
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
    permissionRequestedHandler: NativePermissionRequestedHandler
    downloadStartingHandler: NativeDownloadStartingHandler
    downloadEventHandler: NativeDownloadEventHandler
    permissionHandlerPointer: pointer
    permissionRegistrationToken: int64
    permissionRegistered: bool
    downloadHandlerPointer: pointer
    downloadRegistrationToken: int64
    downloadRegistered: bool
    downloadOperationPointer: pointer
    downloadOperationHandlerPointer: pointer
    downloadBytesToken: int64
    downloadStateToken: int64
    downloadSignalHandlers: seq[culong]
    activeDownload: pointer
    activeDownloadUrl: string
    pendingScripts: seq[NativeScriptRequest]
    activeScripts: seq[NativeScriptRequest]
    activeBrowsingDataRequests: seq[NativeBrowsingDataRequest]

when defined(linux) and not defined(niminoWsl):
  proc linuxCloseRequested(window: pointer; userData: pointer): cint {.cdecl.}
  proc linuxSizeNotify(window, pspec, userData: pointer) {.cdecl.}
  proc linuxCreateWindow(window: NativeWindow): NativeResult
  proc linuxSetDevToolsEnabled(view: NativeWebView; enabled: bool): NativeResult
  proc linuxDisposeView(view: NativeWebView)
  proc linuxEvalJavaScript(view: NativeWebView; request: NativeScriptRequest): NativeResult
  proc linuxClearBrowsingData(view: NativeWebView;
                              request: NativeBrowsingDataRequest): NativeResult
  proc linuxSendNativeNotification(app: NativeApp;
                                   notification: NativeNotification): NativeResult
elif defined(windows):
  proc windowsCreateWindow(window: NativeWindow): NativeResult
  proc windowsEvalJavaScript(view: NativeWebView; request: NativeScriptRequest): NativeResult
  proc windowsClearBrowsingData(view: NativeWebView;
                                request: NativeBrowsingDataRequest): NativeResult
  proc windowsSetDevToolsEnabled(view: NativeWebView; enabled: bool): NativeResult
  proc windowsReplaceDocumentStartScript(view: NativeWebView;
                                          script: string): NativeResult
  proc windowsDisposeView(view: NativeWebView)

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

proc completeBrowsingDataRequest(view: NativeWebView;
                                 request: NativeBrowsingDataRequest;
                                 cleared: NativeResult) {.gcsafe.} =
  if request.isNil:
    return
  if request.future != nil and not request.future.finished:
    request.future.complete(cleared)
  if view != nil and view.activeBrowsingDataRequests.len > 0:
    for index in countdown(view.activeBrowsingDataRequests.high, 0):
      if cast[pointer](view.activeBrowsingDataRequests[index]) == cast[pointer](request):
        view.activeBrowsingDataRequests.delete(index)
        break

proc failOutstandingBrowsingDataRequests(view: NativeWebView;
                                         error: NativeError) {.gcsafe.} =
  if view.isNil:
    return
  for request in view.activeBrowsingDataRequests:
    if request.future != nil and not request.future.finished:
      request.future.complete(failure(error))
  ## Native completion callbacks keep each request GC-referenced until they
  ## return. Do not release them here; callbacks retain responsibility for the
  ## matching GC_unref after a view has closed.
  view.activeBrowsingDataRequests.setLen(0)

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
  view.downloadEventHandler = nil

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

proc dispatchNewWindowRequested(view: NativeWebView; url: string): bool =
  if view.isNil or view.state in {closing, closed} or
      view.newWindowRequestedHandler.isNil:
    return true
  try:
    view.newWindowRequestedHandler(url)
  except CatchableError:
    ## A user callback must not unwind through a native C/COM callback.
    true

proc dispatchCloseRequested(window: NativeWindow): bool =
  if window.isNil or window.state in {closing, closed}:
    return false
  if window.closeRequestedHandler.isNil:
    return true
  try:
    window.closeRequestedHandler()
  except CatchableError:
    false

proc dispatchClosed(window: NativeWindow) =
  if window.isNil or window.closedNotified:
    return
  window.closedNotified = true
  if window.closedHandler.isNil:
    return
  try: window.closedHandler()
  except CatchableError: discard

proc dispatchResized(window: NativeWindow; width, height: int) =
  if window.isNil or window.resizeHandler.isNil or width <= 0 or height <= 0:
    return
  try:
    window.resizeHandler(width, height)
  except CatchableError:
    ## A resize observer must not break the native event callback boundary.
    discard

when defined(windows):
  proc dispatchTrayMenu(app: NativeApp; itemId: uint32) =
    ## Win32 invokes this on the UI thread.  User code must not unwind through
    ## the window procedure.
    if app.isNil or app.trayMenuHandler.isNil:
      return
    try:
      app.trayMenuHandler(itemId)
    except CatchableError:
      discard

when defined(linux) and not defined(niminoWsl):
  proc dispatchNativeMenu(app: NativeApp; itemId: uint32) =
    ## GTK invokes this on its UI thread through a GSimpleAction. User code
    ## must not unwind through the GObject signal trampoline.
    if app.isNil or app.nativeMenuHandler.isNil:
      return
    try:
      app.nativeMenuHandler(itemId)
    except CatchableError:
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

proc dispatchDownloadEvent(view: NativeWebView; url: string;
                           state: NativeDownloadState; progress: float) =
  if view.isNil or view.state in {closing, closed} or view.downloadEventHandler.isNil:
    return
  try:
    view.downloadEventHandler(url, state, progress)
  except CatchableError:
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

proc dispatchPermissionRequested(view: NativeWebView; kind, url: string): bool =
  if view.isNil or view.permissionRequestedHandler.isNil:
    return false
  try: view.permissionRequestedHandler(kind, url)
  except CatchableError: false

proc dispatchDownloadStarting(view: NativeWebView; url: string): bool =
  if view.isNil or view.downloadStartingHandler.isNil:
    return false
  try: view.downloadStartingHandler(url)
  except CatchableError: false

proc hasUiTasks(app: NativeApp): bool =
  if app.isNil:
    return false
  acquire(app.uiTaskLock)
  result = app.uiTasks.len > 0
  release(app.uiTaskLock)

proc removeLastUiTask(app: NativeApp) =
  if app.isNil:
    return
  acquire(app.uiTaskLock)
  if app.uiTasks.len > 0:
    app.uiTasks.setLen(app.uiTasks.len - 1)
  release(app.uiTaskLock)

proc dispatchUiTasks(app: NativeApp): bool =
  if app.isNil:
    return false
  var tasks: seq[NativeUiHandler]
  acquire(app.uiTaskLock)
  swap(tasks, app.uiTasks)
  release(app.uiTaskLock)
  for task in tasks:
    if task.isNil:
      continue
    try:
      task()
    except CatchableError as error:
      app.hasRunError = true
      app.runError = nativeError(osError, "app.postToUi", detail = error.msg)
      app.quitRequested = true
      return false
  true

when defined(linux) and not defined(niminoWsl):
  import ./private/linux/ffi
  include "private/linux/backend"
elif defined(windows):
  import ./private/windows/ffi
  include "private/windows/backend"

proc newNativeApp*(): NativeApp =
  new(result)
  result.state = created
  initLock(result.uiTaskLock)
  result.capabilities = {webPermissionEvents}
  when defined(windows):
    result.capabilities.incl(multipleWebViews)
    result.capabilities.incl(nativeMenu)
    result.capabilities.incl(systemTray)
  elif defined(linux) and not defined(niminoWsl):
    result.capabilities.incl(multipleWebViews)
    result.capabilities.incl(nativeMenu)
    result.capabilities.incl(nativeNotification)

proc supports*(app: NativeApp; capability: Capability): bool {.inline.} =
  app.capabilities.supports(capability)

proc isReady*(window: NativeWindow): bool {.inline.} =
  not window.isNil and window.state == ready

proc isClosed*(window: NativeWindow): bool {.inline.} =
  window.isNil or window.state == closed

proc isReady*(view: NativeWebView): bool {.inline.} =
  not view.isNil and view.state == ready

proc isClosed*(view: NativeWebView): bool {.inline.} =
  view.isNil or view.state == closed

proc configureSystemTray*(app: NativeApp; items: openArray[NativeMenuItem];
                          handler: NativeMenuHandler): NativeResult =
  ## Configures the initial Windows system-tray context menu.  It is deliberately
  ## limited to the created state so the tray's native owner can be established
  ## and released on the UI thread by `run`.
  if app.isNil or app.state != created:
    return failure(nativeError(invalidState, "app.configureSystemTray"))
  if not app.supports(systemTray):
    return failure(nativeError(unsupported, "app.configureSystemTray"))
  if app.trayConfigured:
    return failure(nativeError(invalidState, "app.configureSystemTray",
      detail = "the system tray can only be configured once"))
  if handler.isNil:
    return failure(nativeError(invalidArgument, "app.configureSystemTray",
      detail = "a menu handler is required"))
  if items.len == 0:
    return failure(nativeError(invalidArgument, "app.configureSystemTray",
      detail = "at least one menu item is required"))

  var copied: seq[NativeMenuItem]
  for item in items:
    if item.id == 0 or item.title.len == 0:
      return failure(nativeError(invalidArgument, "app.configureSystemTray",
        detail = "menu item IDs must be non-zero and titles must not be empty"))
    for existing in copied:
      if existing.id == item.id:
        return failure(nativeError(invalidArgument, "app.configureSystemTray",
          detail = "menu item IDs must be unique"))
    copied.add(item)

  app.trayMenuItems = copied
  app.trayMenuHandler = handler
  app.trayConfigured = true
  success()

proc validNativeDesktopText(value: string): bool {.inline.} =
  '\0' notin value

proc configureNativeMenu*(app: NativeApp; title: string;
                          items: openArray[NativeMenuItem];
                          handler: NativeMenuHandler): NativeResult =
  ## Configure the application's command menu before `run`. Linux creates a
  ## GTK menubar; Windows maps this minimal command menu to its existing tray
  ## context menu. No menu is silently emulated on unsupported platforms.
  if app.isNil or not app.supports(nativeMenu):
    return failure(nativeError(unsupported, "app.configureNativeMenu"))
  if app.state != created:
    return failure(nativeError(invalidState, "app.configureNativeMenu"))
  if title.len == 0 or not validNativeDesktopText(title):
    return failure(nativeError(invalidArgument, "app.configureNativeMenu",
      detail = "a non-empty menu title without NUL is required"))
  if handler.isNil:
    return failure(nativeError(invalidArgument, "app.configureNativeMenu",
      detail = "a menu handler is required"))
  if items.len == 0:
    return failure(nativeError(invalidArgument, "app.configureNativeMenu",
      detail = "at least one menu item is required"))

  var copied: seq[NativeMenuItem]
  for item in items:
    if item.id == 0 or item.title.len == 0 or not validNativeDesktopText(item.title):
      return failure(nativeError(invalidArgument, "app.configureNativeMenu",
        detail = "menu item IDs must be non-zero and titles must not contain NUL"))
    for existing in copied:
      if existing.id == item.id:
        return failure(nativeError(invalidArgument, "app.configureNativeMenu",
          detail = "menu item IDs must be unique"))
    copied.add(item)

  when defined(windows):
    ## The existing Win32 implementation owns only a tray command menu. Keep
    ## one source of validation/ownership rather than inventing a second menu
    ## model solely for this facade.
    app.configureSystemTray(copied, handler)
  elif defined(linux) and not defined(niminoWsl):
    if app.nativeMenuConfigured:
      return failure(nativeError(invalidState, "app.configureNativeMenu",
        detail = "the native menu can only be configured once"))
    app.nativeMenuItems = copied
    app.nativeMenuHandler = handler
    app.nativeMenuTitle = title
    app.nativeMenuConfigured = true
    success()
  else:
    failure(nativeError(unsupported, "app.configureNativeMenu"))

proc sendNativeNotification*(app: NativeApp;
                             notification: NativeNotification): NativeResult =
  ## Ask the desktop shell to display a notification. A successful return
  ## means the request reached the OS API; shells may still suppress display.
  if app.isNil or not app.supports(nativeNotification):
    return failure(nativeError(unsupported, "app.sendNativeNotification"))
  if notification.id.len == 0 or notification.title.len == 0 or
      not validNativeDesktopText(notification.id) or
      not validNativeDesktopText(notification.title) or
      not validNativeDesktopText(notification.body):
    return failure(nativeError(invalidArgument, "app.sendNativeNotification",
      detail = "notification ID and title are required and text must not contain NUL"))
  if app.state != running:
    return failure(nativeError(invalidState, "app.sendNativeNotification",
      detail = "the native application must be running"))
  when defined(linux) and not defined(niminoWsl):
    app.linuxSendNativeNotification(notification)
  else:
    failure(nativeError(unsupported, "app.sendNativeNotification"))

proc newWindow*(app: NativeApp; title = "Nimino"; width = 1200; height = 800;
                profilePath = ""):
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
    height: height,
    profilePath: profilePath
  )
  app.windows.add(window)
  successOf(window)

proc newWebView*(window: NativeWindow): NativeResultOf[NativeWebView] =
  if window.isNil or window.state in {closing, closed}:
    return failureOf[NativeWebView](nativeError(invalidState, "webview.create"))
  let view = NativeWebView(window: window, state: pending, devToolsEnabled: true)
  window.views.add(view)
  if window.app.state == running:
    when defined(linux) and not defined(niminoWsl):
      let created = view.linuxCreateView()
      if not created.isOk:
        window.views.setLen(window.views.len - 1)
        return failureOf[NativeWebView](created.failure)
    elif defined(windows):
      let created = view.windowsStartWebView()
      if not created.isOk:
        window.views.setLen(window.views.len - 1)
        return failureOf[NativeWebView](created.failure)
  successOf(view)

proc close*(view: NativeWebView): NativeResult =
  if view.isNil or view.window.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.close"))
  when (defined(linux) and not defined(niminoWsl)) or defined(windows):
    let window = view.window
    when defined(linux) and not defined(niminoWsl):
      view.linuxDisposeView()
    elif defined(windows):
      view.windowsDisposeView()
    for index in countdown(window.views.high, 0):
      if cast[pointer](window.views[index]) == cast[pointer](view):
        window.views.delete(index)
        break
    success()
  else:
    return failure(nativeError(unsupported, "webview.close"))

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

proc close*(window: NativeWindow): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.close"))
  when defined(linux) and not defined(niminoWsl):
    linuxDisposeWindow(window)
    return success()
  elif defined(windows):
    return windowsCloseWindow(window)
  else:
    failure(nativeError(unsupported, "window.close"))

proc onCloseRequested*(window: NativeWindow;
                       handler: NativeCloseRequestedHandler): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.onCloseRequested"))
  window.closeRequestedHandler = handler
  when defined(linux) and not defined(niminoWsl):
    if window.platformWindow != nil and window.closeSignalHandler == 0:
      let signal = g_signal_connect_data(window.platformWindow, "close-request",
        cast[pointer](linuxCloseRequested), cast[pointer](window), nil, 0)
      if signal == 0:
        return failure(nativeError(webViewError, "window.onCloseRequested"))
      window.closeSignalHandler = signal
  success()

proc onClosed*(window: NativeWindow; handler: NativeClosedHandler): NativeResult =
  if window.isNil or window.state == closed:
    return failure(nativeError(invalidState, "window.onClosed"))
  window.closedHandler = handler
  success()

proc onResize*(window: NativeWindow; handler: NativeResizeHandler): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.onResize"))
  window.resizeHandler = handler
  when defined(linux) and not defined(niminoWsl):
    if window.platformWindow != nil and window.resizeSignalHandler == 0:
      let signal = g_signal_connect_data(window.platformWindow, "notify::width",
        cast[pointer](linuxSizeNotify), cast[pointer](window), nil, 0)
      if signal == 0:
        return failure(nativeError(webViewError, "window.onResize"))
      window.resizeSignalHandler = signal
  success()

proc show*(window: NativeWindow): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.show"))
  when defined(linux) and not defined(niminoWsl):
    linuxShowWindow(window)
    success()
  elif defined(windows):
    windowsShowWindow(window)
    success()
  else:
    failure(nativeError(unsupported, "window.show"))

proc hide*(window: NativeWindow): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.hide"))
  when defined(linux) and not defined(niminoWsl):
    linuxHideWindow(window)
    success()
  elif defined(windows):
    windowsHideWindow(window)
    success()
  else:
    failure(nativeError(unsupported, "window.hide"))

proc minimize*(window: NativeWindow): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.minimize"))
  when defined(linux) and not defined(niminoWsl):
    linuxMinimizeWindow(window)
    success()
  elif defined(windows):
    windowsMinimizeWindow(window)
    success()
  else:
    failure(nativeError(unsupported, "window.minimize"))

proc maximize*(window: NativeWindow): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.maximize"))
  when defined(linux) and not defined(niminoWsl):
    linuxMaximizeWindow(window)
    success()
  elif defined(windows):
    windowsMaximizeWindow(window)
    success()
  else:
    failure(nativeError(unsupported, "window.maximize"))

proc restore*(window: NativeWindow): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.restore"))
  when defined(linux) and not defined(niminoWsl):
    linuxRestoreWindow(window)
    success()
  elif defined(windows):
    windowsRestoreWindow(window)
    success()
  else:
    failure(nativeError(unsupported, "window.restore"))

proc setResizable*(window: NativeWindow; resizable: bool): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.setResizable"))
  when defined(linux) and not defined(niminoWsl):
    linuxSetResizable(window, resizable)
    success()
  elif defined(windows):
    windowsSetResizable(window, resizable)
  else:
    failure(nativeError(unsupported, "window.setResizable"))

proc setPosition*(window: NativeWindow; x, y: int): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.setPosition"))
  when defined(windows):
    windowsSetPosition(window, x, y)
  else:
    failure(nativeError(unsupported, "window.setPosition",
      detail = "the current Linux backend cannot move GTK4 windows"))

proc focus*(window: NativeWindow): NativeResult =
  if window.isNil or window.state in {closing, closed}:
    return failure(nativeError(invalidState, "window.focus"))
  when defined(windows):
    windowsFocusWindow(window)
  elif defined(linux) and not defined(niminoWsl):
    linuxFocusWindow(window)
    success()
  else:
    failure(nativeError(unsupported, "window.focus"))

proc loadUrl*(view: NativeWebView; url: string): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.loadUrl"))
  var invalidInput = url.len == 0
  if not invalidInput:
    for c in url:
      if c in {' ', '\t', '\r', '\n'} or ord(c) < 0x20 or ord(c) == 0x7f:
        invalidInput = true
        break
  if invalidInput:
    let error = nativeError(webViewError, "webview.loadUrl",
      detail = "URL must not be empty or contain whitespace/control characters")
    view.dispatchError(error)
    return failure(error)
  view.pendingUrl = url
  view.pendingHtml.setLen(0)
  view.pendingHtmlBaseUrl.setLen(0)
  view.pendingContentKind = urlContent
  when defined(linux) and not defined(niminoWsl):
    linuxLoadPendingContent(view)
    return success()
  elif defined(windows):
    return windowsLoadPendingContent(view)
  else:
    return success()

proc validHtmlBaseUrl(baseUrl: string): bool =
  ## WebKitGTK accepts a URI here. Keep policy out of native, but reject text
  ## that would be truncated or interpreted differently at the C boundary.
  for c in baseUrl:
    if c in {' ', '\t', '\r', '\n'} or ord(c) < 0x20 or ord(c) == 0x7f:
      return false
  true

proc loadHtml*(view: NativeWebView; html: string; baseUrl = ""): NativeResult =
  ## A non-empty base URL is available only on the WebKitGTK backend. WebView2
  ## NavigateToString has no base-URI parameter and always creates about:blank.
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.loadHtml"))
  if not validHtmlBaseUrl(baseUrl):
    let error = nativeError(invalidArgument, "webview.loadHtml",
      detail = "base URL must not contain whitespace/control characters")
    view.dispatchError(error)
    return failure(error)
  if baseUrl.len > 0:
    when defined(linux) and not defined(niminoWsl):
      discard
    elif defined(windows):
      let error = nativeError(unsupported, "webview.loadHtml",
        detail = "WebView2 NavigateToString cannot set a base URL")
      view.dispatchError(error)
      return failure(error)
    else:
      let error = nativeError(unsupported, "webview.loadHtml",
        detail = "HTML base URLs are unavailable through the WSL adapter")
      view.dispatchError(error)
      return failure(error)
  view.pendingHtml = html
  view.pendingHtmlBaseUrl = baseUrl
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
  ## Replace the script that runs at document creation.  Policy and origin
  ## checks belong to nimino-core.  A replacement may happen after the view is
  ## ready; the Windows backend defers the next navigation until WebView2 has
  ## installed the new script.
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.setDocumentStartScript"))
  if view.documentStartScript == script:
    return success()
  view.documentStartScript = script
  if view.state == pending:
    return success()
  when defined(linux) and not defined(niminoWsl):
    return view.linuxConfigureDocumentStartScript()
  elif defined(windows):
    return view.windowsReplaceDocumentStartScript(script)
  else:
    failure(nativeError(unsupported, "webview.setDocumentStartScript"))

proc setDevToolsEnabled*(view: NativeWebView; enabled: bool): NativeResult =
  ## Configure the browser engine's developer tools at the native settings
  ## layer. This remains effective before the first document is loaded.
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.setDevToolsEnabled"))
  view.devToolsEnabled = enabled
  if view.state == pending:
    return success()
  when defined(linux) and not defined(niminoWsl):
    view.linuxSetDevToolsEnabled(enabled)
  elif defined(windows):
    view.windowsSetDevToolsEnabled(enabled)
  else:
    failure(nativeError(unsupported, "webview.setDevToolsEnabled"))

proc evalJavaScript*(view: NativeWebView; script: string): Future[NativeResultOf[string]] =
  let request = NativeScriptRequest(
    script: script,
    future: newFuture[NativeResultOf[string]]("nimino.native.evalJavaScript")
  )
  result = request.future
  if view.isNil or view.state in {closing, closed}:
    result.complete(failureOf[string](nativeError(invalidState, "webview.evalJavaScript")))
    return
  if script.len == 0:
    result.complete(failureOf[string](nativeError(invalidArgument, "webview.evalJavaScript",
      detail = "script must not be empty")))
    return

  if view.state != ready or view.platformView.isNil:
    view.pendingScripts.add(request)
    return
  view.startScriptRequest(request)

proc clearBrowsingData*(view: NativeWebView;
                        kinds: set[NativeBrowsingDataKind]): Future[NativeResult] =
  ## Clear live browser-engine data without deleting the active user-data
  ## folder. WebView2 and WebKitGTK complete this operation asynchronously, so
  ## the low-level API always returns a Future.
  let request = NativeBrowsingDataRequest(
    kinds: kinds,
    future: newFuture[NativeResult]("nimino.native.clearBrowsingData")
  )
  result = request.future
  if view.isNil or view.state in {closing, closed}:
    result.complete(failure(nativeError(invalidState, "webview.clearBrowsingData")))
    return
  if kinds == {}:
    result.complete(failure(nativeError(invalidArgument, "webview.clearBrowsingData",
      detail = "at least one browsing data kind is required")))
    return

  when defined(windows):
    if view.state != ready or view.platformView.isNil:
      result.complete(failure(nativeError(invalidState, "webview.clearBrowsingData",
        detail = "WebView2 must be ready before browser data can be cleared")))
      return
    request.view = view
    view.activeBrowsingDataRequests.add(request)
    let started = view.windowsClearBrowsingData(request)
    if not started.isOk:
      view.completeBrowsingDataRequest(request, started)
  elif defined(linux) and not defined(niminoWsl):
    if view.state != ready or view.platformView.isNil:
      result.complete(failure(nativeError(invalidState, "webview.clearBrowsingData",
        detail = "WebKitGTK must be ready before browser data can be cleared")))
      return
    request.view = view
    view.activeBrowsingDataRequests.add(request)
    let started = view.linuxClearBrowsingData(request)
    if not started.isOk:
      view.completeBrowsingDataRequest(request, started)
  else:
    result.complete(failure(nativeError(unsupported, "webview.clearBrowsingData",
      detail = "live browser data clearing is unavailable on this platform")))

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

proc onPermissionRequested*(view: NativeWebView;
                            handler: NativePermissionRequestedHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onPermissionRequested"))
  view.permissionRequestedHandler = handler
  success()

proc onDownloadStarting*(view: NativeWebView;
                         handler: NativeDownloadStartingHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onDownloadStarting"))
  view.downloadStartingHandler = handler
  success()

proc onDownloadEvent*(view: NativeWebView;
                      handler: NativeDownloadEventHandler): NativeResult =
  if view.isNil or view.state in {closing, closed}:
    return failure(nativeError(invalidState, "webview.onDownloadEvent"))
  view.downloadEventHandler = handler
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

proc postToUi*(app: NativeApp; callback: NativeUiHandler): NativeResult =
  ## Queues a callback for execution on the native UI thread.  The callback
  ## is never run inline, including when called from that thread.
  when defined(windows) or (defined(linux) and not defined(niminoWsl)):
    if app.isNil or app.state == finished:
      return failure(nativeError(invalidState, "app.postToUi"))
    if callback.isNil:
      return failure(nativeError(invalidArgument, "app.postToUi",
        detail = "callback must not be nil"))
    acquire(app.uiTaskLock)
    app.uiTasks.add(callback)
    release(app.uiTaskLock)
    when defined(windows):
      if app.state == running:
        for window in app.windows:
          if window.platformWindow != nil:
            if postMessageW(window.platformWindow, WmUiTask, 0, 0) == 0:
              app.removeLastUiTask()
              return failure(windowsError("app.postToUi", getLastError()))
            return success()
        app.removeLastUiTask()
        return failure(nativeError(invalidState, "app.postToUi",
          detail = "no native window is available"))
    elif defined(linux) and not defined(niminoWsl):
      if app.state == running and app.idleTimerSource == 0:
        app.idleTimerSource = g_timeout_add(1, linuxIdleTick, cast[pointer](app))
        if app.idleTimerSource == 0:
          app.removeLastUiTask()
          return failure(nativeError(osError, "app.postToUi",
            detail = "GLib timeout source creation failed"))
    success()
  else:
    failure(nativeError(unsupported, "app.postToUi"))

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
