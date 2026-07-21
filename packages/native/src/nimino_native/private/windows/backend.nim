import std/[atomics, os, widestrs]

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

  ClearBrowsingDataCompletedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; errorCode: HResult): HResult {.stdcall.}

  AddScriptToExecuteOnDocumentCreatedCompletedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; errorCode: HResult; scriptId: WideCString): HResult {.stdcall.}

  WebMessageReceivedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; sender, args: pointer): HResult {.stdcall.}

  NavigationCompletedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; sender, args: pointer): HResult {.stdcall.}

  NavigationStartingVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; sender, args: pointer): HResult {.stdcall.}

  NewWindowRequestedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; sender, args: pointer): HResult {.stdcall.}

  PermissionRequestedVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; sender, args: pointer): HResult {.stdcall.}

  DownloadStartingVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; sender, args: pointer): HResult {.stdcall.}

  DownloadOperationVTable = object
    queryInterface: proc(self: pointer; iid: ptr WinGuid; outInstance: ptr pointer): HResult {.stdcall.}
    addRef: proc(self: pointer): uint32 {.stdcall.}
    release: proc(self: pointer): uint32 {.stdcall.}
    invoke: proc(self: pointer; sender, args: pointer): HResult {.stdcall.}

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

  ClearBrowsingDataCompletedHandler = object
    vtable: ptr ClearBrowsingDataCompletedVTable
    references: Atomic[int]
    request: pointer

  AddScriptToExecuteOnDocumentCreatedCompletedHandler = object
    vtable: ptr AddScriptToExecuteOnDocumentCreatedCompletedVTable
    references: Atomic[int]
    view: pointer

  WebMessageReceivedHandler = object
    vtable: ptr WebMessageReceivedVTable
    references: Atomic[int]
    view: pointer

  NavigationCompletedHandler = object
    vtable: ptr NavigationCompletedVTable
    references: Atomic[int]
    view: pointer

  NavigationStartingHandler = object
    vtable: ptr NavigationStartingVTable
    references: Atomic[int]
    view: pointer

  NewWindowRequestedHandler = object
    vtable: ptr NewWindowRequestedVTable
    references: Atomic[int]
    view: pointer

  PermissionRequestedHandler = object
    vtable: ptr PermissionRequestedVTable
    references: Atomic[int]
    view: pointer

  DownloadStartingHandler = object
    vtable: ptr DownloadStartingVTable
    references: Atomic[int]
    view: pointer

  DownloadOperationHandler = object
    vtable: ptr DownloadOperationVTable
    references: Atomic[int]
    view: pointer
    url: string

var downloadOperationVTable: DownloadOperationVTable

proc windowsDisposeWindow(window: NativeWindow)
proc windowsFail(app: NativeApp; error: NativeError)
proc windowsRemoveTray(app: NativeApp)
proc windowsResize(window: NativeWindow): NativeResult
proc windowsLoadUrl(view: NativeWebView): NativeResult
proc windowsFinishWebViewInitialization(view: NativeWebView): NativeResult
proc downloadOperationAddRef(self: pointer): uint32 {.stdcall.}
proc downloadOperationRelease(self: pointer): uint32 {.stdcall.}
proc downloadOperationQueryInterface(self: pointer; iid: ptr WinGuid;
                                     outInstance: ptr pointer): HResult {.stdcall.}
proc downloadOperationInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.}

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

proc clearBrowsingDataAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr ClearBrowsingDataCompletedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc clearBrowsingDataRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr ClearBrowsingDataCompletedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc clearBrowsingDataQueryInterface(self: pointer; iid: ptr WinGuid;
                                     outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidClearBrowsingDataCompletedHandler,
    clearBrowsingDataAddRef)

proc addDocumentStartScriptAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr AddScriptToExecuteOnDocumentCreatedCompletedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc addDocumentStartScriptRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr AddScriptToExecuteOnDocumentCreatedCompletedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc addDocumentStartScriptQueryInterface(self: pointer; iid: ptr WinGuid;
                                           outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidAddScriptToExecuteOnDocumentCreatedCompletedHandler,
    addDocumentStartScriptAddRef)

proc webMessageAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr WebMessageReceivedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc webMessageRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr WebMessageReceivedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc webMessageQueryInterface(self: pointer; iid: ptr WinGuid;
                              outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidWebMessageReceivedEventHandler, webMessageAddRef)

proc navigationCompletedAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr NavigationCompletedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc navigationCompletedRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr NavigationCompletedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc navigationCompletedQueryInterface(self: pointer; iid: ptr WinGuid;
                                       outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidNavigationCompletedEventHandler,
    navigationCompletedAddRef)

proc navigationStartingAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr NavigationStartingHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc navigationStartingRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr NavigationStartingHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc navigationStartingQueryInterface(self: pointer; iid: ptr WinGuid;
                                      outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidNavigationStartingEventHandler,
    navigationStartingAddRef)

proc newWindowRequestedAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr NewWindowRequestedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc newWindowRequestedRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr NewWindowRequestedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    dealloc(handler)
  uint32(remaining)

proc newWindowRequestedQueryInterface(self: pointer; iid: ptr WinGuid;
                                      outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidNewWindowRequestedEventHandler,
    newWindowRequestedAddRef)

proc permissionAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr PermissionRequestedHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc permissionRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr PermissionRequestedHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0: dealloc(handler)
  uint32(remaining)

proc permissionQueryInterface(self: pointer; iid: ptr WinGuid;
                              outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidPermissionRequestedEventHandler,
    permissionAddRef)

proc permissionInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.} =
  let handler = cast[ptr PermissionRequestedHandler](self)
  var allowed = false
  if not handler.view.isNil:
    var source: WideCString
    if succeeded(coreGetSource(handler.view, addr source)):
      allowed = dispatchPermissionRequested(cast[NativeWebView](handler.view), $source)
      coTaskMemFree(cast[pointer](source))
  if not args.isNil:
    discard permissionArgsPutState(args, if allowed: WebView2PermissionStateAllow else: WebView2PermissionStateDeny)
  S_OK

proc downloadAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr DownloadStartingHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc downloadRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr DownloadStartingHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0: dealloc(handler)
  uint32(remaining)

proc downloadQueryInterface(self: pointer; iid: ptr WinGuid;
                            outInstance: ptr pointer): HResult {.stdcall.} =
  queryCallback(self, iid, outInstance, IidDownloadStartingEventHandler,
    downloadAddRef)

proc downloadInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.} =
  let handler = cast[ptr DownloadStartingHandler](self)
  var allowed = false
  var downloadUrl = ""
  if not handler.view.isNil:
    var source: WideCString
    if succeeded(coreGetSource(handler.view, addr source)):
      downloadUrl = $source
      allowed = dispatchDownloadStarting(cast[NativeWebView](handler.view), downloadUrl)
      coTaskMemFree(cast[pointer](source))
  if not args.isNil:
    if not allowed:
      discard downloadArgsPutCancel(args, 1)
    else:
      dispatchDownloadEvent(cast[NativeWebView](handler.view), downloadUrl,
        nativeDownloadStarted, 0.0)
      var operation: pointer
      if succeeded(downloadArgsGetOperation(args, addr operation)) and operation != nil:
        var received, total: int64
        if succeeded(downloadOperationGetBytesReceived(operation, addr received)) and
            succeeded(downloadOperationGetTotalBytes(operation, addr total)) and total > 0:
          dispatchDownloadEvent(cast[NativeWebView](handler.view), downloadUrl,
            nativeDownloadProgress, float(received) / float(total))
        let operationHandler = cast[ptr DownloadOperationHandler](alloc0(sizeof(DownloadOperationHandler)))
        operationHandler.vtable = addr downloadOperationVTable
        operationHandler.references.store(1, moRelaxed)
        operationHandler.view = handler.view
        operationHandler.url = downloadUrl
        var bytesToken, stateToken: EventRegistrationToken
        let bytesStatus = downloadOperationAddBytesReceivedChanged(operation,
          cast[pointer](operationHandler), addr bytesToken)
        let stateStatus = downloadOperationAddStateChanged(operation,
          cast[pointer](operationHandler), addr stateToken)
        discard downloadOperationRelease(cast[pointer](operationHandler))
        if succeeded(bytesStatus) and succeeded(stateStatus):
          let view = cast[NativeWebView](handler.view)
          view.downloadOperationPointer = operation
          view.downloadOperationHandlerPointer = cast[pointer](operationHandler)
          view.downloadBytesToken = bytesToken.value
          view.downloadStateToken = stateToken.value
        else:
          discard comRelease(operation)
  S_OK

proc downloadOperationAddRef(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr DownloadOperationHandler](self)
  uint32(handler.references.fetchAdd(1, moRelaxed) + 1)

proc downloadOperationRelease(self: pointer): uint32 {.stdcall.} =
  let handler = cast[ptr DownloadOperationHandler](self)
  let remaining = handler.references.fetchSub(1, moAcquireRelease) - 1
  if remaining == 0:
    `=destroy`(handler.url)
    dealloc(handler)
  uint32(remaining)

proc downloadOperationQueryInterface(self: pointer; iid: ptr WinGuid;
                                     outInstance: ptr pointer): HResult {.stdcall.} =
  if outInstance.isNil or iid.isNil:
    return E_POINTER
  ## WebView2 uses distinct IIDs for BytesReceivedChanged and StateChanged.
  ## This callback object implements both typed event-handler contracts.
  outInstance[] = self
  discard downloadOperationAddRef(self)
  S_OK

proc downloadOperationInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.} =
  let handler = cast[ptr DownloadOperationHandler](self)
  if handler.view.isNil or sender.isNil:
    return S_OK
  let view = cast[NativeWebView](handler.view)
  var received, total: int64
  if succeeded(downloadOperationGetBytesReceived(sender, addr received)) and
      succeeded(downloadOperationGetTotalBytes(sender, addr total)) and total > 0:
    view.dispatchDownloadEvent(handler.url, nativeDownloadProgress,
      float(received) / float(total))
  var state: int32
  if succeeded(downloadOperationGetState(sender, addr state)):
    if state == 2:
      view.dispatchDownloadEvent(handler.url, nativeDownloadCompleted, 1.0)
    elif state == 1:
      var reason: int32
      if succeeded(downloadOperationGetInterruptReason(sender, addr reason)) and reason == 26:
        view.dispatchDownloadEvent(handler.url, nativeDownloadCancelled, -1.0)
      else:
        view.dispatchDownloadEvent(handler.url, nativeDownloadFailed, -1.0)
  S_OK

proc environmentInvoke(self: pointer; errorCode: HResult;
                       environment: pointer): HResult {.stdcall.}
proc controllerInvoke(self: pointer; errorCode: HResult;
                      controller: pointer): HResult {.stdcall.}
proc executeScriptInvoke(self: pointer; errorCode: HResult;
                         jsonResult: WideCString): HResult {.stdcall.}
proc clearBrowsingDataInvoke(self: pointer; errorCode: HResult): HResult {.stdcall.}
proc addDocumentStartScriptInvoke(self: pointer; errorCode: HResult;
                                  scriptId: WideCString): HResult {.stdcall.}
proc webMessageInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.}
proc navigationCompletedInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.}
proc navigationStartingInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.}
proc newWindowRequestedInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.}

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

var clearBrowsingDataCompletedVTable = ClearBrowsingDataCompletedVTable(
  queryInterface: clearBrowsingDataQueryInterface,
  addRef: clearBrowsingDataAddRef,
  release: clearBrowsingDataRelease,
  invoke: clearBrowsingDataInvoke
)

var addDocumentStartScriptCompletedVTable = AddScriptToExecuteOnDocumentCreatedCompletedVTable(
  queryInterface: addDocumentStartScriptQueryInterface,
  addRef: addDocumentStartScriptAddRef,
  release: addDocumentStartScriptRelease,
  invoke: addDocumentStartScriptInvoke
)

var webMessageReceivedVTable = WebMessageReceivedVTable(
  queryInterface: webMessageQueryInterface,
  addRef: webMessageAddRef,
  release: webMessageRelease,
  invoke: webMessageInvoke
)

var navigationCompletedVTable = NavigationCompletedVTable(
  queryInterface: navigationCompletedQueryInterface,
  addRef: navigationCompletedAddRef,
  release: navigationCompletedRelease,
  invoke: navigationCompletedInvoke
)

var navigationStartingVTable = NavigationStartingVTable(
  queryInterface: navigationStartingQueryInterface,
  addRef: navigationStartingAddRef,
  release: navigationStartingRelease,
  invoke: navigationStartingInvoke
)

var newWindowRequestedVTable = NewWindowRequestedVTable(
  queryInterface: newWindowRequestedQueryInterface,
  addRef: newWindowRequestedAddRef,
  release: newWindowRequestedRelease,
  invoke: newWindowRequestedInvoke
)

var permissionRequestedVTable = PermissionRequestedVTable(
  queryInterface: permissionQueryInterface,
  addRef: permissionAddRef,
  release: permissionRelease,
  invoke: permissionInvoke
)

var downloadStartingVTable = DownloadStartingVTable(
  queryInterface: downloadQueryInterface,
  addRef: downloadAddRef,
  release: downloadRelease,
  invoke: downloadInvoke
)

downloadOperationVTable = DownloadOperationVTable(
  queryInterface: downloadOperationQueryInterface,
  addRef: downloadOperationAddRef,
  release: downloadOperationRelease,
  invoke: downloadOperationInvoke
)

proc newPermissionRequestedHandler(view: NativeWebView): ptr PermissionRequestedHandler =
  result = cast[ptr PermissionRequestedHandler](alloc0(sizeof(PermissionRequestedHandler)))
  result.vtable = addr permissionRequestedVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

proc newDownloadStartingHandler(view: NativeWebView): ptr DownloadStartingHandler =
  result = cast[ptr DownloadStartingHandler](alloc0(sizeof(DownloadStartingHandler)))
  result.vtable = addr downloadStartingVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

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

proc newClearBrowsingDataCompletedHandler(request: NativeBrowsingDataRequest):
    ptr ClearBrowsingDataCompletedHandler =
  result = cast[ptr ClearBrowsingDataCompletedHandler](
    alloc0(sizeof(ClearBrowsingDataCompletedHandler))
  )
  result.vtable = addr clearBrowsingDataCompletedVTable
  result.references.store(1, moRelaxed)
  result.request = cast[pointer](request)

proc newAddDocumentStartScriptCompletedHandler(view: NativeWebView):
    ptr AddScriptToExecuteOnDocumentCreatedCompletedHandler =
  result = cast[ptr AddScriptToExecuteOnDocumentCreatedCompletedHandler](
    alloc0(sizeof(AddScriptToExecuteOnDocumentCreatedCompletedHandler))
  )
  result.vtable = addr addDocumentStartScriptCompletedVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

proc newWebMessageReceivedHandler(view: NativeWebView): ptr WebMessageReceivedHandler =
  result = cast[ptr WebMessageReceivedHandler](alloc0(sizeof(WebMessageReceivedHandler)))
  result.vtable = addr webMessageReceivedVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

proc newNavigationCompletedHandler(view: NativeWebView): ptr NavigationCompletedHandler =
  result = cast[ptr NavigationCompletedHandler](alloc0(sizeof(NavigationCompletedHandler)))
  result.vtable = addr navigationCompletedVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

proc newNavigationStartingHandler(view: NativeWebView): ptr NavigationStartingHandler =
  result = cast[ptr NavigationStartingHandler](alloc0(sizeof(NavigationStartingHandler)))
  result.vtable = addr navigationStartingVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

proc newNewWindowRequestedHandler(view: NativeWebView): ptr NewWindowRequestedHandler =
  result = cast[ptr NewWindowRequestedHandler](alloc0(sizeof(NewWindowRequestedHandler)))
  result.vtable = addr newWindowRequestedVTable
  result.references.store(1, moRelaxed)
  result.view = cast[pointer](view)

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
  view.failOutstandingBrowsingDataRequests(nativeError(invalidState,
    "webview.clearBrowsingData", detail = "the WebView closed before clearing completed"))
  if view.messageRegistered and view.platformView != nil:
    let token = EventRegistrationToken(value: view.messageRegistrationToken)
    discard coreRemoveWebMessageReceived(view.platformView, token)
    view.messageRegistered = false
    GC_unref(view)
  if view.newWindowRegistered and view.platformView != nil:
    let token = EventRegistrationToken(value: view.newWindowToken)
    discard coreRemoveNewWindowRequested(view.platformView, token)
    view.newWindowRegistered = false
    GC_unref(view)
  if view.navigationStartingRegistered and view.platformView != nil:
    let token = EventRegistrationToken(value: view.navigationStartingToken)
    discard coreRemoveNavigationStarting(view.platformView, token)
    view.navigationStartingRegistered = false
    GC_unref(view)
  if view.navigationCompletedRegistered and view.platformView != nil:
    let token = EventRegistrationToken(value: view.navigationCompletedToken)
    discard coreRemoveNavigationCompleted(view.platformView, token)
    view.navigationCompletedRegistered = false
    GC_unref(view)
  if view.permissionRegistered and view.platformView != nil:
    let token = EventRegistrationToken(value: view.permissionRegistrationToken)
    discard coreRemovePermissionRequested(view.platformView, token)
    view.permissionRegistered = false
    view.permissionHandlerPointer = nil
    GC_unref(view)
  if view.downloadRegistered and view.platformView != nil:
    var core4: pointer
    if succeeded(comQueryInterface(view.platformView, addr IidCoreWebView2_4, addr core4)) and not core4.isNil:
      let token = EventRegistrationToken(value: view.downloadRegistrationToken)
      discard core4RemoveDownloadStarting(core4, token)
      discard comRelease(core4)
    view.downloadRegistered = false
    view.downloadHandlerPointer = nil
  if view.downloadOperationPointer != nil:
    let operation = view.downloadOperationPointer
    discard downloadOperationRemoveBytesReceivedChanged(operation,
      EventRegistrationToken(value: view.downloadBytesToken))
    discard downloadOperationRemoveStateChanged(operation,
      EventRegistrationToken(value: view.downloadStateToken))
    discard comRelease(operation)
    view.downloadOperationPointer = nil
    view.downloadOperationHandlerPointer = nil
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
  view.releaseCallbackReferences()
  view.state = closed

proc windowsDisposeWindow(window: NativeWindow) =
  if window.isNil or window.state == closed:
    return

  window.state = closing
  window.dispatchClosed()
  if window.app.trayWindow == window.platformWindow:
    ## Shell_NotifyIcon requires the owner HWND while deleting the icon.
    window.app.windowsRemoveTray()
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

  let executableDirectory = splitFile(getAppFilename()).dir
  if executableDirectory.len == 0:
    return failure(nativeError(webViewError, "webview.loader",
      detail = "application executable directory is unavailable"))
  let loaderPath = executableDirectory / "WebView2Loader.dll"
  let loaderName = newWideCString(loaderPath)
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

proc windowsConfigureUserDataFolder(app: NativeApp): NativeResult =
  if app.webView2UserDataFolder.len > 0:
    return success()

  let localAppData = getEnv("LOCALAPPDATA")
  if localAppData.len == 0:
    return failure(nativeError(osError, "webview.userDataFolder",
      detail = "LOCALAPPDATA is unavailable"))
  let executableName = splitFile(getAppFilename()).name
  if executableName.len == 0:
    return failure(nativeError(osError, "webview.userDataFolder",
      detail = "application executable name is unavailable"))
  let folder = localAppData / "Nimino" / "Native" / executableName
  try:
    createDir(folder)
  except OSError:
    return failure(nativeError(osError, "webview.userDataFolder",
      detail = "cannot create the local WebView2 user data folder"))
  app.webView2UserDataFolder = folder
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

proc windowsSetSize(window: NativeWindow): NativeResult =
  if window.platformWindow == nil:
    return success()
  if setWindowPos(window.platformWindow, nil, 0, 0, int32(window.width),
      int32(window.height), SwpNoMove or SwpNoZOrder) == 0:
    return failure(windowsError("window.setSize", getLastError()))
  success()

proc windowsSetResizable(window: NativeWindow; resizable: bool): NativeResult =
  if window.platformWindow == nil:
    return failure(nativeError(invalidState, "window.setResizable"))
  var style = uint32(getWindowLongPtrW(window.platformWindow, GwlStyle))
  if resizable:
    style = style or WsThickFrame or WsMaximizeBox or WsMinimizeBox
  else:
    style = style and not (WsThickFrame or WsMaximizeBox or WsMinimizeBox)
  discard setWindowLongPtrW(window.platformWindow, GwlStyle, int(style))
  discard setWindowPos(window.platformWindow, nil, 0, 0, 0, 0,
    SwpNoMove or SwpNoSize or SwpNoZOrder or 0x0020'u32)
  success()

proc windowsSetPosition(window: NativeWindow; x, y: int): NativeResult =
  if window.platformWindow == nil:
    return failure(nativeError(invalidState, "window.setPosition"))
  if setWindowPos(window.platformWindow, nil, int32(x), int32(y), 0, 0,
      SwpNoSize or SwpNoZOrder) == 0:
    return failure(windowsError("window.setPosition", getLastError()))
  success()

proc windowsCopyTrayTip(destination: var array[128, uint16]; value: string) =
  let wide = newWideCString(value)
  for index in 0 ..< destination.high:
    let character = uint16(wide[index])
    destination[index] = character
    if character == 0'u16:
      return
  destination[destination.high] = 0'u16

proc windowsRemoveTray(app: NativeApp) =
  if app.isNil or not app.trayVisible:
    return
  if app.trayWindow != nil:
    var notification = NotifyIconDataW(
      cbSize: uint32(sizeof(NotifyIconDataW)),
      window: app.trayWindow,
      identifier: 1
    )
    discard shellNotifyIconW(NimDelete, addr notification)
  app.trayVisible = false
  app.trayWindow = nil

proc windowsInstallTray(app: NativeApp; owner: NativeWindow): NativeResult =
  if app.isNil or owner.isNil or owner.platformWindow.isNil:
    return failure(nativeError(invalidState, "app.configureSystemTray"))
  if app.trayVisible:
    return success()

  let icon = loadIconW(nil, makeIntResourceW(IdiApplication))
  if icon.isNil:
    return failure(windowsError("app.configureSystemTray", getLastError()))

  var notification = NotifyIconDataW(
    cbSize: uint32(sizeof(NotifyIconDataW)),
    window: owner.platformWindow,
    identifier: 1,
    flags: NifMessage or NifIcon or NifTip,
    callbackMessage: WmTrayCallback,
    icon: icon
  )
  windowsCopyTrayTip(notification.tip, owner.title)
  if shellNotifyIconW(NimAdd, addr notification) == 0:
    return failure(windowsError("app.configureSystemTray", getLastError()))

  notification.version = NotifyIconVersion4
  if shellNotifyIconW(NimSetVersion, addr notification) == 0:
    discard shellNotifyIconW(NimDelete, addr notification)
    return failure(windowsError("app.configureSystemTray", getLastError()))

  app.trayWindow = owner.platformWindow
  app.trayVisible = true
  success()

proc windowsShowTrayMenu(app: NativeApp; owner: NativeWindow) =
  if app.isNil or owner.isNil or owner.platformWindow.isNil or
      not app.trayVisible or app.trayMenuItems.len == 0:
    return

  let menu = createPopupMenu()
  if menu.isNil:
    return
  defer:
    discard destroyMenu(menu)

  for item in app.trayMenuItems:
    let title = newWideCString(item.title)
    let flags = if item.enabled: MfString else: MfString or MfGrayed
    if appendMenuW(menu, flags, uint(item.id), title) == 0:
      return

  var point: WinPoint
  if getCursorPos(addr point) == 0:
    return
  discard setForegroundWindow(owner.platformWindow)
  let selected = trackPopupMenu(menu, TpmRightButton or TpmReturnCmd,
    point.x, point.y, 0'u32, owner.platformWindow, nil)
  if selected != 0:
    app.dispatchTrayMenu(selected)

  ## Required by Shell_NotifyIcon after a context menu is dismissed so keyboard
  ## focus returns to the notification area.
  if not app.trayVisible or app.trayWindow.isNil:
    return
  var notification = NotifyIconDataW(
    cbSize: uint32(sizeof(NotifyIconDataW)),
    window: app.trayWindow,
    identifier: 1
  )
  discard shellNotifyIconW(NimSetFocus, addr notification)

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

proc windowsFinishWebViewInitialization(view: NativeWebView): NativeResult =
  let resized = view.window.windowsResize()
  if not resized.isOk:
    return resized
  let loaded = view.windowsLoadPendingContent()
  if not loaded.isOk:
    return loaded
  view.dispatchPendingScripts()
  success()

proc windowsConfigureDocumentStartScript(view: NativeWebView): NativeResult =
  if view.documentStartScript.len == 0:
    return success()
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.setDocumentStartScript"))
  let handler = newAddDocumentStartScriptCompletedHandler(view)
  let script = newWideCString(view.documentStartScript)
  let status = coreAddScriptToExecuteOnDocumentCreated(
    view.platformView,
    script,
    cast[pointer](handler)
  )
  discard addDocumentStartScriptRelease(handler)
  if not succeeded(status):
    return failure(hresultError("webview.setDocumentStartScript", status))
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

proc browsingDataMask(kinds: set[NativeBrowsingDataKind]): uint32 =
  for kind in kinds:
    case kind
    of nativeBrowsingCookies:
      result = result or WebView2BrowsingDataCookies
    of nativeBrowsingLocalStorage:
      result = result or WebView2BrowsingDataLocalStorage
    of nativeBrowsingCache:
      result = result or WebView2BrowsingDataCacheStorage or WebView2BrowsingDataDiskCache

proc unavailableWebView2Interface(operation, interfaceName: string;
                                  status: HResult): NativeError {.inline.} =
  if status == E_NOINTERFACE:
    nativeError(unsupported, operation, platformCode = status,
      detail = interfaceName & " is unavailable in the installed WebView2 Runtime")
  elif succeeded(status):
    nativeError(webViewError, operation, platformCode = status,
      detail = interfaceName & " returned a nil interface pointer")
  else:
    hresultError(operation, status)

proc windowsClearBrowsingData(view: NativeWebView;
                              request: NativeBrowsingDataRequest): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.clearBrowsingData"))

  if request.kinds == {nativeBrowsingCookies}:
    ## CookieManager is synchronous and avoids requiring Profile2 on older
    ## WebView2 runtimes when the caller only asked to remove cookies.
    var core2: pointer
    let queried = comQueryInterface(view.platformView, addr IidCoreWebView2_2,
      addr core2)
    if not succeeded(queried) or core2.isNil:
      return failure(unavailableWebView2Interface("webview.clearBrowsingData",
        "ICoreWebView2_2", queried))
    var cookieManager: pointer
    let managerStatus = core2GetCookieManager(core2, addr cookieManager)
    discard comRelease(core2)
    if not succeeded(managerStatus) or cookieManager.isNil:
      return failure(hresultError("webview.clearBrowsingData", managerStatus))
    let deleted = cookieManagerDeleteAllCookies(cookieManager)
    discard comRelease(cookieManager)
    if not succeeded(deleted):
      return failure(hresultError("webview.clearBrowsingData", deleted))
    view.completeBrowsingDataRequest(request, success())
    return success()

  var core13: pointer
  let queried = comQueryInterface(view.platformView, addr IidCoreWebView2_13,
    addr core13)
  if not succeeded(queried) or core13.isNil:
    return failure(unavailableWebView2Interface("webview.clearBrowsingData",
      "ICoreWebView2_13", queried))

  var profile: pointer
  let profileStatus = core13GetProfile(core13, addr profile)
  discard comRelease(core13)
  if not succeeded(profileStatus) or profile.isNil:
    return failure(hresultError("webview.clearBrowsingData", profileStatus))

  var profile2: pointer
  let profile2Status = comQueryInterface(profile, addr IidCoreWebView2Profile2,
    addr profile2)
  discard comRelease(profile)
  if not succeeded(profile2Status) or profile2.isNil:
    return failure(unavailableWebView2Interface("webview.clearBrowsingData",
      "ICoreWebView2Profile2", profile2Status))

  let handler = newClearBrowsingDataCompletedHandler(request)
  ## The completion handler is owned by WebView2 after successful submission.
  ## Keep the Nim request alive until that callback returns, including while a
  ## closing view has already completed its Future with invalidState.
  GC_ref(request)
  let cleared = profile2ClearBrowsingData(profile2, browsingDataMask(request.kinds),
    cast[pointer](handler))
  discard clearBrowsingDataRelease(handler)
  discard comRelease(profile2)
  if not succeeded(cleared):
    GC_unref(request)
    return failure(hresultError("webview.clearBrowsingData", cleared))
  success()

proc windowsConfigureMessageBridge(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.onMessage"))
  let handler = newWebMessageReceivedHandler(view)
  var token: EventRegistrationToken
  GC_ref(view)
  let status = coreAddWebMessageReceived(view.platformView, cast[pointer](handler), addr token)
  discard webMessageRelease(handler)
  if not succeeded(status):
    GC_unref(view)
    return failure(hresultError("webview.onMessage", status))
  view.messageRegistrationToken = token.value
  view.messageRegistered = true
  success()

proc windowsConfigureNavigationCompleted(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.onNavigationCompleted"))
  let handler = newNavigationCompletedHandler(view)
  var token: EventRegistrationToken
  GC_ref(view)
  let status = coreAddNavigationCompleted(view.platformView, cast[pointer](handler), addr token)
  discard navigationCompletedRelease(handler)
  if not succeeded(status):
    GC_unref(view)
    return failure(hresultError("webview.onNavigationCompleted", status))
  view.navigationCompletedToken = token.value
  view.navigationCompletedRegistered = true
  success()

proc windowsConfigureNavigationStarting(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.onNavigationStarting"))
  let handler = newNavigationStartingHandler(view)
  var token: EventRegistrationToken
  GC_ref(view)
  let status = coreAddNavigationStarting(view.platformView, cast[pointer](handler), addr token)
  discard navigationStartingRelease(handler)
  if not succeeded(status):
    GC_unref(view)
    return failure(hresultError("webview.onNavigationStarting", status))
  view.navigationStartingToken = token.value
  view.navigationStartingRegistered = true
  success()

proc windowsConfigurePermissionRequested(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.permissionRequested"))
  let handler = newPermissionRequestedHandler(view)
  var token: EventRegistrationToken
  let status = coreAddPermissionRequested(view.platformView, cast[pointer](handler), addr token)
  discard permissionRelease(cast[pointer](handler))
  if not succeeded(status):
    return failure(hresultError("webview.permissionRequested", status))
  view.permissionHandlerPointer = cast[pointer](handler)
  view.permissionRegistrationToken = token.value
  view.permissionRegistered = true
  success()

proc windowsConfigureDownloadStarting(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.downloadStarting"))
  var core4: pointer
  let queried = comQueryInterface(view.platformView, addr IidCoreWebView2_4, addr core4)
  if not succeeded(queried) or core4.isNil:
    return failure(nativeError(unsupported, "webview.downloadStarting",
      detail = "WebView2 v4 interface is unavailable"))
  let handler = newDownloadStartingHandler(view)
  var token: EventRegistrationToken
  let status = core4AddDownloadStarting(core4, cast[pointer](handler), addr token)
  discard downloadRelease(cast[pointer](handler))
  discard comRelease(core4)
  if not succeeded(status):
    return failure(hresultError("webview.downloadStarting", status))
  view.downloadHandlerPointer = cast[pointer](handler)
  view.downloadRegistrationToken = token.value
  view.downloadRegistered = true
  success()

proc windowsConfigureNewWindowRequested(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.onNewWindowRequested"))
  let handler = newNewWindowRequestedHandler(view)
  var token: EventRegistrationToken
  GC_ref(view)
  let status = coreAddNewWindowRequested(view.platformView, cast[pointer](handler), addr token)
  discard newWindowRequestedRelease(handler)
  if not succeeded(status):
    GC_unref(view)
    return failure(hresultError("webview.onNewWindowRequested", status))
  view.newWindowToken = token.value
  view.newWindowRegistered = true
  success()

proc windowsStartWebView(view: NativeWebView): NativeResult =
  let loader = view.window.app.windowsLoadLoader()
  if not loader.isOk:
    return loader
  let runtime = view.window.app.windowsCheckRuntime()
  if not runtime.isOk:
    return runtime
  if view.window.profilePath.len == 0:
    let userDataFolder = view.window.app.windowsConfigureUserDataFolder()
    if not userDataFolder.isOk:
      return userDataFolder
  else:
    view.window.app.webView2UserDataFolder = view.window.profilePath / "webview2"
    try:
      createDir(view.window.app.webView2UserDataFolder)
    except OSError:
      return failure(nativeError(osError, "webview.userDataFolder",
        detail = "cannot create the profile WebView2 user data folder"))

  let handler = newEnvironmentCompletedHandler(view)
  let createEnvironment = cast[WebView2CreateEnvironmentWithOptions](
    view.window.app.webView2CreateEnvironment
  )
  let folder = newWideCString(view.window.app.webView2UserDataFolder)
  let status = createEnvironment(nil, folder, nil, cast[pointer](handler))
  discard environmentRelease(handler)
  if not succeeded(status):
    return failure(hresultError("webview.environment", status))
  success()

proc windowsShowWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    discard showWindow(window.platformWindow, SwShow)
    discard updateWindow(window.platformWindow)

proc windowsHideWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    discard showWindow(window.platformWindow, SwHide)

proc windowsMinimizeWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    discard showWindow(window.platformWindow, SwMinimize)

proc windowsMaximizeWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    discard showWindow(window.platformWindow, SwMaximize)

proc windowsRestoreWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    discard showWindow(window.platformWindow, SwRestore)

proc windowsFocusWindow(window: NativeWindow): NativeResult =
  if window.platformWindow == nil:
    return failure(nativeError(invalidState, "window.focus"))
  if setForegroundWindow(window.platformWindow) == 0:
    return failure(windowsError("window.focus", getLastError()))
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
    of WmTrayCallback:
      let notification = uint32(cast[uint](lParam) and 0xffff'u)
      if notification == WmContextMenu or notification == NinSelect or
          notification == NinKeySelect:
        window.app.windowsShowTrayMenu(window)
      return 0
    of WmClose:
      if not window.dispatchCloseRequested():
        return 0
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
  let navigationStarting = view.windowsConfigureNavigationStarting()
  if not navigationStarting.isOk:
    view.window.app.windowsFail(navigationStarting.failure)
    return S_OK
  let permissionEvents = view.windowsConfigurePermissionRequested()
  if not permissionEvents.isOk:
    view.window.app.windowsFail(permissionEvents.failure)
    return S_OK
  let downloadEvents = view.windowsConfigureDownloadStarting()
  if not downloadEvents.isOk:
    view.window.app.windowsFail(downloadEvents.failure)
    return S_OK
  let newWindowEvents = view.windowsConfigureNewWindowRequested()
  if not newWindowEvents.isOk:
    view.window.app.windowsFail(newWindowEvents.failure)
    return S_OK
  let navigationEvents = view.windowsConfigureNavigationCompleted()
  if not navigationEvents.isOk:
    view.window.app.windowsFail(navigationEvents.failure)
    return S_OK
  let messaging = view.windowsConfigureMessageBridge()
  if not messaging.isOk:
    view.window.app.windowsFail(messaging.failure)
    return S_OK
  let documentStartScript = view.windowsConfigureDocumentStartScript()
  if not documentStartScript.isOk:
    view.window.app.windowsFail(documentStartScript.failure)
    return S_OK
  if view.documentStartScript.len == 0:
    let initialized = view.windowsFinishWebViewInitialization()
    if not initialized.isOk:
      view.window.app.windowsFail(initialized.failure)
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

proc clearBrowsingDataInvoke(self: pointer; errorCode: HResult): HResult {.stdcall.} =
  let handler = cast[ptr ClearBrowsingDataCompletedHandler](self)
  let request = cast[NativeBrowsingDataRequest](handler.request)
  if request.isNil:
    return S_OK
  let view = request.view
  if view != nil:
    if succeeded(errorCode):
      view.completeBrowsingDataRequest(request, success())
    else:
      view.completeBrowsingDataRequest(request, failure(hresultError(
        "webview.clearBrowsingData", errorCode
      )))
  elif request.future != nil and not request.future.finished:
    request.future.complete(failure(nativeError(invalidState, "webview.clearBrowsingData")))
  GC_unref(request)
  S_OK

proc addDocumentStartScriptInvoke(self: pointer; errorCode: HResult;
                                  scriptId: WideCString): HResult {.stdcall.} =
  let handler = cast[ptr AddScriptToExecuteOnDocumentCreatedCompletedHandler](self)
  let view = cast[NativeWebView](handler.view)
  if view.isNil or view.window.app.state != running or view.state in {closing, closed}:
    return S_OK
  if not succeeded(errorCode):
    view.window.app.windowsFail(hresultError("webview.setDocumentStartScript", errorCode))
    return S_OK
  let initialized = view.windowsFinishWebViewInitialization()
  if not initialized.isOk:
    view.window.app.windowsFail(initialized.failure)
  S_OK

proc webMessageInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.} =
  let handler = cast[ptr WebMessageReceivedHandler](self)
  let view = cast[NativeWebView](handler.view)
  if view.isNil or view.state in {closing, closed} or args.isNil:
    return S_OK
  var message: WideCString
  let status = webMessageTryGetAsString(args, addr message)
  if succeeded(status) and message != nil:
    let copied = $message
    coTaskMemFree(cast[pointer](message))
    view.dispatchMessage(copied)
  elif message != nil:
    coTaskMemFree(cast[pointer](message))
  S_OK

proc navigationCompletedInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.} =
  let handler = cast[ptr NavigationCompletedHandler](self)
  let view = cast[NativeWebView](handler.view)
  if view.isNil or view.state in {closing, closed} or args.isNil:
    return S_OK
  var isSuccess: WinBool
  let successStatus = navigationCompletedGetIsSuccess(args, addr isSuccess)
  var source: WideCString
  let sourceStatus = coreGetSource(view.platformView, addr source)
  let copiedSource = if succeeded(sourceStatus) and source != nil: $source else: ""
  if source != nil:
    coTaskMemFree(cast[pointer](source))
  let navigationSucceeded = succeeded(successStatus) and isSuccess != 0
  if not navigationSucceeded:
    let error =
      if not succeeded(successStatus):
        hresultError("webview.navigate", successStatus)
      else:
        nativeError(webViewError, "webview.navigate", detail = "WebView2 navigation failed")
    view.dispatchError(error)
  view.dispatchNavigationCompleted(copiedSource, navigationSucceeded)
  S_OK

proc navigationStartingInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.} =
  let handler = cast[ptr NavigationStartingHandler](self)
  let view = cast[NativeWebView](handler.view)
  if view.isNil or view.state in {closing, closed} or args.isNil:
    return S_OK
  var uri: WideCString
  let uriStatus = navigationStartingGetUri(args, addr uri)
  let copiedUri = if succeeded(uriStatus) and uri != nil: $uri else: ""
  if uri != nil:
    coTaskMemFree(cast[pointer](uri))
  if not view.dispatchNavigationStarting(copiedUri):
    discard navigationStartingSetCancel(args, 1)
  S_OK

proc newWindowRequestedInvoke(self: pointer; sender, args: pointer): HResult {.stdcall.} =
  let handler = cast[ptr NewWindowRequestedHandler](self)
  let view = cast[NativeWebView](handler.view)
  if view.isNil or view.state in {closing, closed} or args.isNil:
    return S_OK
  var uri: WideCString
  let uriStatus = newWindowRequestedGetUri(args, addr uri)
  let copiedUri = if succeeded(uriStatus) and uri != nil: $uri else: ""
  if uri != nil:
    coTaskMemFree(cast[pointer](uri))
  view.dispatchNewWindowRequested(copiedUri)
  ## A new native Window/WebView is never created implicitly at this layer.
  discard newWindowRequestedSetHandled(args, 1)
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

  if not app.quitRequested and app.trayMenuItems.len > 0:
    for window in app.windows:
      if window.platformWindow != nil:
        let installed = app.windowsInstallTray(window)
        if not installed.isOk:
          app.windowsFail(installed.failure)
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
  app.windowsRemoveTray()
  app.trayMenuItems.setLen(0)
  app.trayMenuHandler = nil
  app.windowsStopIdleTimer()
  app.windowsUnloadLoader()
  app.windowsUnregisterWindowClass()
  coUninitialize()
  app.state = finished

  if app.hasRunError:
    failure(app.runError)
  else:
    success()
