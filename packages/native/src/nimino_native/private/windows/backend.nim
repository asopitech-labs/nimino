import std/[atomics, widestrs]

type
  EnvironmentCompletedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; errorCode: HResult; environment: pointer): HResult {.stdcall.}

  ControllerCompletedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; errorCode: HResult; controller: pointer): HResult {.stdcall.}

  ExecuteScriptCompletedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; errorCode: HResult; jsonResult: WideCString): HResult {.stdcall.}

  EnvironmentCompletedHandler = object
    vtable: ptr EnvironmentCompletedVTable
    references: Atomic[int]
    view: pointer

  ControllerCompletedHandler = object
    vtable: ptr ControllerCompletedVTable
    references: Atomic[int]
    view: pointer

  ExecuteScriptCompletedHandler = object
    vtable: ptr ExecuteScriptCompletedVTable
    references: Atomic[int]
    request: pointer

proc windowsDisposeWindow(window: NativeWindow)
proc windowsFail(app: NativeApp; error: NativeError)
proc windowsResize(window: NativeWindow): NativeResult
proc windowsLoadUrl(view: NativeWebView): NativeResult

proc hresultError(operation: string; status: HResult): NativeError {.inline.} =
  nativeError(webViewError, operation, platformCode = status)

proc windowsError(operation: string; status: uint32): NativeError {.inline.} =
  nativeError(osError, operation, platformCode = cast[int32](status))

proc sameGuid(left, right: WinGuid): bool {.inline.} =
  left.data1 == right.data1 and left.data2 == right.data2 and
    left.data3 == right.data3 and left.data4 == right.data4

proc queryCallback(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer;
                   supported: WinGuid;
                   addReference: proc(self: pointer): uint32 {.stdcall.}): HResult =
  if outInstance.isNil:
    return E_POINTER
  outInstance[] = nil
  if iid.isNil or (not sameGuid(iid[], IidIUnknown) and not sameGuid(iid[], supported)):
    return E_NOINTERFACE
  outInstance[] = self
  discard addReference(self)
  S_OK

proc environmentAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr EnvironmentCompletedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc environmentRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr EnvironmentCompletedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc environmentQueryInterface(self: pointer; iid: ptr WinGuid;
                               outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidEnvironmentCompletedHandler, environmentAddRef)

proc controllerAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr ControllerCompletedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc controllerRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr ControllerCompletedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc controllerQueryInterface(self: pointer; iid: ptr WinGuid;
                              outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidControllerCompletedHandler, controllerAddRef)

proc executeScriptAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr ExecuteScriptCompletedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc executeScriptRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr ExecuteScriptCompletedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc executeScriptQueryInterface(self: pointer; iid: ptr WinGuid;
                                 outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidExecuteScriptCompletedHandler, executeScriptAddRef)

proc environmentInvoke(self: pointer; errorCode: HResult;
                       environment: pointer): HResult {.stdcall.}
proc controllerInvoke(self: pointer; errorCode: HResult;
                      controller: pointer): HResult {.stdcall.}
proc executeScriptInvoke(self: pointer; errorCode: HResult;
                         jsonResult: WideCString): HResult {.stdcall.}

var environmentCompletedVTable = EnvironmentCompletedVTable(
  queryInterface: environmentQueryInterface,
  addRef: environmentAddRef,
  release: environmentRelease,
  invoke: environmentInvoke
)

var controllerCompletedVTable = ControllerCompletedVTable(
  queryInterface: controllerQueryInterface,
  addRef: controllerAddRef,
  release: controllerRelease,
  invoke: controllerInvoke
)

var executeScriptCompletedVTable = ExecuteScriptCompletedVTable(
  queryInterface: executeScriptQueryInterface,
  addRef: executeScriptAddRef,
  release: executeScriptRelease,
  invoke: executeScriptInvoke
)

proc newEnvironmentCompletedHandler(view: NativeWebView): ptr EnvironmentCompletedHandler =
  result = cast[ptr EnvironmentCompletedHandler](alloc0(sizeof(EnvironmentCompletedHandler)))
  result.vtable = addr environmentCompletedVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

proc newControllerCompletedHandler(view: NativeWebView): ptr ControllerCompletedHandler =
  result = cast[ptr ControllerCompletedHandler](alloc0(sizeof(ControllerCompletedHandler)))
  result.vtable = addr controllerCompletedVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

proc newExecuteScriptCompletedHandler(request: NativeScriptRequest): ptr ExecuteScriptCompletedHandler =
  result = cast[ptr ExecuteScriptCompletedHandler](alloc0(sizeof(ExecuteScriptCompletedHandler)))
  result.vtable = addr executeScriptCompletedVTable
  result.references.store(1, moRelaxed)
  result.request = cast[pointer](request)

proc windowsAllClosed(app: NativeApp): bool =
  for window in app.windows:
    if window.state != closed:
      return false
  true

proc windowsUnloadLoader(app: NativeApp) =
  app.webView2CreateEnvironment = nil
  if app.platformLoader != nil:
    discard freeLibrary(app.platformLoader)
    app.platformLoader = nil

proc windowsStopIdleTimer(app: NativeApp) =
  if app.idleTimerWindow != nil:
    discard killTimer(app.idleTimerWindow, 1)
    app.idleTimerWindow = nil

proc windowsDisposeView(view: NativeWebView) =
  if view.isNil or view.state == closed:
    return

  view.state = closing
  view.failOutstandingScripts(nativeError(invalidState, "webview.evalJavaScript"))
  if view.platformController != nil:
    discard controllerClose(view.platformController)
  if view.platformView != nil:
    discard comRelease(view.platformView)
    view.platformView = nil
  if view.platformController != nil:
    discard comRelease(view.platformController)
    view.platformController = nil
  if view.platformEnvironment != nil:
    discard comRelease(view.platformEnvironment)
    view.platformEnvironment = nil
  view.state = closed

proc windowsDisposeWindow(window: NativeWindow) =
  if window.isNil or window.state == closed:
    return

  window.state = closing
  if window.app.idleTimerWindow == window.platformWindow:
    window.app.windowsStopIdleTimer()
  for view in window.views:
    view.windowsDisposeView()
  window.platformWindow = nil
  window.state = closed
  if window.app.state == running and window.app.windowsAllClosed():
    postQuitMessage(0)

proc windowsRequestQuit(app: NativeApp) =
  for window in app.windows:
    if window.platformWindow != nil:
      discard destroyWindow(window.platformWindow)
    else:
      window.windowsDisposeWindow()
  if app.windowsAllClosed():
    postQuitMessage(0)

proc windowsFail(app: NativeApp; error: NativeError) =
  if app.isNil:
    return
  if not app.hasRunError:
    app.hasRunError = true
    app.runError = error
  app.quitRequested = true
  if app.state == running:
    app.windowsRequestQuit()

proc windowsLoadLoader(app: NativeApp): NativeResult =
  if app.webView2CreateEnvironment != nil:
    return success()

  let loaderName = newWideCString("WebView2Loader.dll")
  let loader = loadLibraryW(loaderName)
  if loader.isNil:
    return failure(nativeError(webViewError, "webview.loader", platformCode = cast[int32](getLastError()),
      detail = "WebView2Loader.dll is required beside the application executable"))

  let createEnvironment = getProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions")
  let getVersion = getProcAddress(loader, "GetAvailableCoreWebView2BrowserVersionString")
  if createEnvironment.isNil or getVersion.isNil:
    discard freeLibrary(loader)
    return failure(nativeError(webViewError, "webview.loader",
      detail = "WebView2Loader.dll does not expose the required API"))

  app.platformLoader = loader
  app.webView2CreateEnvironment = createEnvironment
  success()

proc windowsCheckRuntime(app: NativeApp): NativeResult =
  let getVersion = cast[WebView2GetAvailableBrowserVersionString](
    getProcAddress(app.platformLoader, "GetAvailableCoreWebView2BrowserVersionString")
  )
  if getVersion.isNil:
    return failure(nativeError(webViewError, "webview.runtime",
      detail = "WebView2Loader.dll does not expose runtime detection"))

  var version: WideCString
  let status = getVersion(nil, addr version)
  if version != nil:
    coTaskMemFree(cast[pointer](version))
  if not succeeded(status) or version == nil:
    return failure(hresultError("webview.runtime", status))
  success()

proc windowsResize(window: NativeWindow): NativeResult =
  if window.isNil or window.platformWindow.isNil:
    return failure(nativeError(invalidState, "window.resize"))
  if window.views.len == 0 or window.views[0].platformController.isNil:
    return success()

  var bounds: WinRect
  if getClientRect(window.platformWindow, addr bounds) == 0:
    return failure(windowsError("window.resize", getLastError()))
  let status = controllerSetBounds(window.views[0].platformController, bounds)
  if not succeeded(status):
    return failure(hresultError("webview.resize", status))
  success()

proc windowsSetTitle(window: NativeWindow): NativeResult =
  if window.platformWindow == nil:
    return success()
  let title = newWideCString(window.title)
  if setWindowTextW(window.platformWindow, title) == 0:
    return failure(windowsError("window.setTitle", getLastError()))
  success()

proc windowsLoadUrl(view: NativeWebView): NativeResult =
  if view.platformView == nil:
    return success()
  let url = newWideCString(view.pendingUrl)
  let status = coreNavigate(view.platformView, url)
  if not succeeded(status):
    return failure(hresultError("webview.loadUrl", status))
  success()

proc windowsLoadHtml(view: NativeWebView): NativeResult =
  if view.platformView == nil:
    return success()
  let html = newWideCString(view.pendingHtml)
  let status = coreNavigateToString(view.platformView, html)
  if not succeeded(status):
    return failure(hresultError("webview.loadHtml", status))
  success()

proc windowsLoadPendingContent(view: NativeWebView): NativeResult =
  case view.pendingContentKind
  of urlContent:
    view.windowsLoadUrl()
  of htmlContent:
    view.windowsLoadHtml()
  of noContent:
    success()

proc windowsEvalJavaScript(view: NativeWebView; request: NativeScriptRequest): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.evalJavaScript"))
  let handler = newExecuteScriptCompletedHandler(request)
  GC_ref(request)
  let script = newWideCString(request.script)
  let status = coreExecuteScript(view.platformView, script, cast[pointer](handler))
  discard executeScriptRelease(handler)
  if not succeeded(status):
    GC_unref(request)
    return failure(hresultError("webview.evalJavaScript", status))
  success()

proc windowsStartWebView(view: NativeWebView): NativeResult =
  let loader = view.window.app.windowsLoadLoader()
  if not loader.isOk:
    return loader
  let runtime = view.window.app.windowsCheckRuntime()
  if not runtime.isOk:
    return runtime

  let handler = newEnvironmentCompletedHandler(view)
  let createEnvironment = cast[WebView2CreateEnvironmentWithOptions](
    view.window.app.webView2CreateEnvironment
  )
  let status = createEnvironment(nil, nil, nil, cast[pointer](handler))
  discard environmentRelease(handler)
  if not succeeded(status):
    return failure(hresultError("webview.environment", status))
  success()

proc windowsCreateWindow(window: NativeWindow): NativeResult =
  let className = newWideCString(window.app.windowClassName)
  let title = newWideCString(window.title)
  let hwnd = createWindowExW(
    0, className, title, WsOverlappedWindow,
    CwUseDefault, CwUseDefault, int32(window.width), int32(window.height),
    nil, nil, window.app.platformInstance, cast[pointer](window)
  )
  if hwnd.isNil:
    return failure(windowsError("window.create", getLastError()))

  window.platformWindow = hwnd
  window.state = ready
  discard showWindow(hwnd, SwShow)
  discard updateWindow(hwnd)
  if window.views.len == 0:
    return failure(nativeError(invalidState, "window.create", detail = "WebView is required"))

  let started = window.views[0].windowsStartWebView()
  if not started.isOk:
    discard destroyWindow(hwnd)
    return started
  success()

proc windowsWindowProc(hwnd: HWND; message: uint32; wParam: WParam;
                       lParam: LParam): LResult {.stdcall.} =
  if message == WmNcCreate:
    let create = cast[ptr WinCreateStructW](cast[pointer](lParam))
    if create != nil and create.createParams != nil:
      discard setWindowLongPtrW(hwnd, GwlpUserData, cast[int](create.createParams))

  let window = cast[NativeWindow](cast[pointer](getWindowLongPtrW(hwnd, GwlpUserData)))
  if window != nil:
    case message
    of WmSize:
      let resized = window.windowsResize()
      if not resized.isOk:
        window.app.windowsFail(resized.failure)
      return 0
    of WmTimer:
      if window.app.idleHandler != nil:
        window.app.idleHandler()
      return 0
    of WmClose:
      discard destroyWindow(hwnd)
      return 0
    of WmDestroy:
      window.windowsDisposeWindow()
      return 0
    of WmNcDestroy:
      discard setWindowLongPtrW(hwnd, GwlpUserData, 0)
    else:
      discard
  defWindowProcW(hwnd, message, wParam, lParam)

proc windowsRegisterWindowClass(app: NativeApp): NativeResult =
  app.platformInstance = getModuleHandleW(nil)
  if app.platformInstance.isNil:
    return failure(windowsError("app.run", getLastError()))

  app.windowClassName = "Nimino.Native." & $(cast[uint](cast[pointer](app)))
  let className = newWideCString(app.windowClassName)
  var windowClass = WinWindowClassExW(
    cbSize: uint32(sizeof(WinWindowClassExW)),
    windowProc: windowsWindowProc,
    instance: app.platformInstance,
    className: className
  )
  if registerClassExW(addr windowClass) == 0:
    return failure(windowsError("app.run", getLastError()))
  app.windowClassRegistered = true
  success()

proc windowsUnregisterWindowClass(app: NativeApp) =
  if app.windowClassRegistered:
    let className = newWideCString(app.windowClassName)
    discard unregisterClassW(className, app.platformInstance)
    app.windowClassRegistered = false

proc environmentInvoke(self: pointer; errorCode: HResult;
                       environment: pointer): HResult {.stdcall.} =
  let view = cast[NativeWebView](cast[ptr EnvironmentCompletedHandler](self).view)
  if view.isNil or view.window.app.state != running or view.state in {closing, closed}:
    return S_OK
  if not succeeded(errorCode) or environment.isNil:
    view.window.app.windowsFail(hresultError("webview.environment", errorCode))
    return S_OK

  discard comAddRef(environment)
  view.platformEnvironment = environment
  let handler = newControllerCompletedHandler(view)
  let status = environmentCreateController(environment, view.window.platformWindow, cast[pointer](handler))
  discard controllerRelease(handler)
  if not succeeded(status):
    view.window.app.windowsFail(hresultError("webview.controller", status))
  S_OK

proc controllerInvoke(self: pointer; errorCode: HResult;
                      controller: pointer): HResult {.stdcall.} =
  let view = cast[NativeWebView](cast[ptr ControllerCompletedHandler](self).view)
  if view.isNil or view.window.app.state != running or view.state in {closing, closed}:
    return S_OK
  if not succeeded(errorCode) or controller.isNil:
    view.window.app.windowsFail(hresultError("webview.controller", errorCode))
    return S_OK

  discard comAddRef(controller)
  view.platformController = controller
  var core: pointer
  let status = controllerGetCore(controller, addr core)
  if not succeeded(status) or core.isNil:
    view.window.app.windowsFail(hresultError("webview.core", status))
    return S_OK

  view.platformView = core
  view.state = ready
  let resized = view.window.windowsResize()
  if not resized.isOk:
    view.window.app.windowsFail(resized.failure)
    return S_OK
  let loaded = view.windowsLoadPendingContent()
  if not loaded.isOk:
    view.window.app.windowsFail(loaded.failure)
    return S_OK
  view.dispatchPendingScripts()
  S_OK

proc executeScriptInvoke(self: pointer; errorCode: HResult;
                         jsonResult: WideCString): HResult {.stdcall.} =
  let handler = cast[ptr ExecuteScriptCompletedHandler](self)
  let request = cast[NativeScriptRequest](handler.request)
  if request.isNil:
    return S_OK
  if request.view.isNil:
    GC_unref(request)
    return S_OK
  let view = request.view
  if not succeeded(errorCode):
    view.completeScriptRequest(request, failureOf[string](hresultError(
      "webview.evalJavaScript", errorCode
    )))
  else:
    let serialized = if jsonResult.isNil: "null" else: $jsonResult
    view.completeScriptRequest(request, successOf(serialized))
  GC_unref(request)
  S_OK

proc windowsQuit(app: NativeApp): NativeResult =
  for window in app.windows:
    if window.platformWindow != nil:
      if postMessageW(window.platformWindow, WmClose, 0, 0) == 0:
        return failure(windowsError("app.quit", getLastError()))
  success()

proc windowsRun(app: NativeApp): NativeResult =
  if app.quitRequested:
    for window in app.windows:
      window.windowsDisposeWindow()
    app.state = finished
    return success()

  let initialized = coInitializeEx(nil, CoInitApartmentThreaded)
  if not succeeded(initialized):
    app.state = finished
    return failure(hresultError("app.run", initialized))

  app.state = running
  let registered = app.windowsRegisterWindowClass()
  if not registered.isOk:
    app.hasRunError = true
    app.runError = registered.failure
    app.quitRequested = true
  else:
    for window in app.windows:
      if app.quitRequested:
        break
      let created = window.windowsCreateWindow()
      if not created.isOk:
        app.windowsFail(created.failure)
        break

  if app.quitRequested:
    app.windowsRequestQuit()

  if not app.quitRequested and app.idleHandler != nil:
    for window in app.windows:
      if window.platformWindow != nil:
        if setTimer(window.platformWindow, 1, 10, nil) == 0:
          app.windowsFail(windowsError("app.setIdleHandler", getLastError()))
        else:
          app.idleTimerWindow = window.platformWindow
        break

  var message: WinMessage
  var messageResult = 1'i32
  while messageResult > 0:
    messageResult = getMessageW(addr message, nil, 0, 0)
    if messageResult > 0:
      discard translateMessage(addr message)
      discard dispatchMessageW(addr message)

  if messageResult < 0 and not app.hasRunError:
    app.hasRunError = true
    app.runError = windowsError("app.run", getLastError())

  for window in app.windows:
    if window.state != closed:
      if window.platformWindow != nil:
        discard destroyWindow(window.platformWindow)
      else:
        window.windowsDisposeWindow()
  app.windowsStopIdleTimer()
  app.windowsUnloadLoader()
  app.windowsUnregisterWindowClass()
  coUninitialize()
  app.state = finished

  if app.hasRunError:
    failure(app.runError)
  else:
    success()
