## Minimal private Win32 and WebView2 Loader FFI for M1.
##
## WebView2 declarations were checked against Microsoft.Web.WebView2 1.0.3967.48
## (`build/native/include/WebView2.h`).  Keep this module private: it is an
## implementation detail of nimino-native, not a public binding package.

import std/widestrs

type
  HResult* = int32
  HWND* = pointer
  HInstance* = pointer
  HModule* = pointer
  HIcon* = pointer
  HMenu* = pointer
  WParam* = uint
  LParam* = int
  LResult* = int
  WinBool* = int32

  WinGuid* {.bycopy.} = object
    data1*: uint32
    data2*: uint16
    data3*: uint16
    data4*: array[8, uint8]

  WinPoint* {.bycopy.} = object
    x*: int32
    y*: int32

  WinRect* {.bycopy.} = object
    left*: int32
    top*: int32
    right*: int32
    bottom*: int32

  ## OPENFILENAMEW layout from the Windows SDK.  The dialog backend uses the
  ## common-dialog API directly and keeps this binding private.
  OpenFileNameW* {.bycopy.} = object
    structSize*: uint32
    owner*: HWND
    instance*: HInstance
    filter*: WideCString
    customFilter*: WideCString
    maxCustFilter*: uint32
    filterIndex*: uint32
    file*: WideCString
    maxFile*: uint32
    fileTitle*: WideCString
    maxFileTitle*: uint32
    initialDir*: WideCString
    title*: WideCString
    flags*: uint32
    fileOffset*: uint16
    fileExtension*: uint16
    defExt*: WideCString
    custData*: LParam
    hook*: pointer
    templateName*: WideCString
    reservedPtr*: pointer
    reservedInt*: uint32
    flagsEx*: uint32

  ## NOTIFYICONDATAW layout verified against the MinGW Win32 SDK header.
  ## `version` is the uTimeout/uVersion union and must stay at this offset.
  NotifyIconDataW* {.bycopy.} = object
    cbSize*: uint32
    window*: HWND
    identifier*: uint32
    flags*: uint32
    callbackMessage*: uint32
    icon*: HIcon
    tip*: array[128, uint16]
    state*: uint32
    stateMask*: uint32
    info*: array[256, uint16]
    version*: uint32
    infoTitle*: array[64, uint16]
    infoFlags*: uint32
    guidItem*: WinGuid
    balloonIcon*: HIcon

  EventRegistrationToken* {.bycopy.} = object
    value*: int64

  WinMessage* {.bycopy.} = object
    hwnd*: HWND
    message*: uint32
    wParam*: WParam
    lParam*: LParam
    time*: uint32
    point*: WinPoint
    lPrivate*: uint32

  WinWindowProc* = proc(hwnd: HWND; message: uint32; wParam: WParam;
                        lParam: LParam): LResult {.stdcall.}

  WinWindowClassExW* {.bycopy.} = object
    cbSize*: uint32
    style*: uint32
    windowProc*: WinWindowProc
    classExtra*: int32
    windowExtra*: int32
    instance*: HInstance
    icon*: pointer
    cursor*: pointer
    background*: pointer
    menuName*: WideCString
    className*: WideCString
    smallIcon*: pointer

  WinCreateStructW* {.bycopy.} = object
    createParams*: pointer
    instance*: HInstance
    menu*: pointer
    parent*: HWND
    height*: int32
    width*: int32
    y*: int32
    x*: int32
    style*: int32
    name*: WideCString
    className*: WideCString
    extendedStyle*: uint32

  ComInterface* {.bycopy.} = object
    vtable*: ptr UncheckedArray[pointer]

  WebView2CreateEnvironmentWithOptions* = proc(
    browserExecutableFolder: WideCString;
    userDataFolder: WideCString;
    environmentOptions: pointer;
    environmentCreatedHandler: pointer
  ): HResult {.stdcall.}

  WebView2GetAvailableBrowserVersionString* = proc(
    browserExecutableFolder: WideCString;
    versionInfo: ptr WideCString
  ): HResult {.stdcall.}

when defined(windows) and defined(amd64):
  static:
    ## The matching C header assertion is fixed in Makefile's
    ## verify-windows-tray-abi target.
    doAssert sizeof(NotifyIconDataW) == 976
    doAssert sizeof(OpenFileNameW) == 152

const
  S_OK* = 0'i32
  E_NOINTERFACE* = -2147467262'i32
  E_POINTER* = -2147467261'i32

  CoInitApartmentThreaded* = 0x2'u32
  ErrorClassAlreadyExists* = 1410'u32

  CwUseDefault* = -2147483648'i32
  WebView2PermissionStateDeny* = 2'i32
  WebView2PermissionStateAllow* = 1'i32
  ## COREWEBVIEW2_PERMISSION_KIND values from WebView2.h 1.0.3967.48.
  WebView2PermissionKindMicrophone* = 1'i32
  WebView2PermissionKindCamera* = 2'i32
  WebView2PermissionKindGeolocation* = 3'i32
  WebView2PermissionKindNotifications* = 4'i32
  WebView2PermissionKindClipboardRead* = 6'i32
  WsOverlappedWindow* = 0x00CF0000'u32
  WsThickFrame* = 0x00040000'u32
  WsMaximizeBox* = 0x00010000'u32
  WsMinimizeBox* = 0x00020000'u32
  GwlStyle* = -16'i32
  SwHide* = 0'i32
  SwMinimize* = 6'i32
  SwMaximize* = 3'i32
  SwRestore* = 9'i32
  SwShow* = 5'i32
  SwpNoSize* = 0x0001'u32
  SwpNoMove* = 0x0002'u32
  SwpNoZOrder* = 0x0004'u32
  OfnAllowMultiSelect* = 0x00000200'u32
  OfnExplorer* = 0x00080000'u32
  OfnFileMustExist* = 0x00001000'u32
  OfnPathMustExist* = 0x00000800'u32
  OfnOverwritePrompt* = 0x00000002'u32

  WmSize* = 0x0005'u32
  WmDestroy* = 0x0002'u32
  WmClose* = 0x0010'u32
  WmNcCreate* = 0x0081'u32
  WmNcDestroy* = 0x0082'u32
  WmTimer* = 0x0113'u32
  WmContextMenu* = 0x007B'u32
  WmUser* = 0x0400'u32
  WmApp* = 0x8000'u32
  WmTrayCallback* = WmApp + 1'u32
  WmUiTask* = WmApp + 2'u32
  NinSelect* = WmUser
  NinKeySelect* = WmUser + 1'u32
  NinBalloonUserClick* = WmUser + 5'u32
  GwlpUserData* = -21'i32

  NimAdd* = 0x00000000'u32
  NimDelete* = 0x00000002'u32
  NimModify* = 0x00000001'u32
  NimSetFocus* = 0x00000003'u32
  NimSetVersion* = 0x00000004'u32
  NotifyIconVersion4* = 4'u32
  NifMessage* = 0x00000001'u32
  NifIcon* = 0x00000002'u32
  NifTip* = 0x00000004'u32
  NifInfo* = 0x00000010'u32
  NiifInfo* = 0x00000001'u32
  MfString* = 0x00000000'u32
  MfGrayed* = 0x00000001'u32
  TpmRightButton* = 0x0002'u32
  TpmReturnCmd* = 0x0100'u32
  IdiApplication* = 32512'u16

  IidIUnknown* = WinGuid(
    data1: 0x00000000'u32, data2: 0x0000'u16, data3: 0x0000'u16,
    data4: [0xC0'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x00'u8, 0x46'u8]
  )
  IidEnvironmentCompletedHandler* = WinGuid(
    data1: 0x4e8a3389'u32, data2: 0xc9d8'u16, data3: 0x4bd2'u16,
    data4: [0xb6'u8, 0xb5'u8, 0x12'u8, 0x4f'u8, 0xee'u8, 0x6c'u8, 0xc1'u8, 0x4d'u8]
  )
  IidControllerCompletedHandler* = WinGuid(
    data1: 0x6c4819f3'u32, data2: 0xc9b7'u16, data3: 0x4260'u16,
    data4: [0x81'u8, 0x27'u8, 0xc9'u8, 0xf5'u8, 0xbd'u8, 0xe7'u8, 0xf6'u8, 0x8c'u8]
  )
  IidAddScriptToExecuteOnDocumentCreatedCompletedHandler* = WinGuid(
    data1: 0xb99369f3'u32, data2: 0x9b11'u16, data3: 0x47b5'u16,
    data4: [0xbc'u8, 0x6f'u8, 0x8e'u8, 0x78'u8, 0x95'u8, 0xfc'u8, 0xea'u8, 0x17'u8]
  )
  IidExecuteScriptCompletedHandler* = WinGuid(
    data1: 0x49511172'u32, data2: 0xcc67'u16, data3: 0x4bca'u16,
    data4: [0x99'u8, 0x23'u8, 0x13'u8, 0x71'u8, 0x12'u8, 0xf4'u8, 0xc4'u8, 0xcc'u8]
  )
  IidWebMessageReceivedEventHandler* = WinGuid(
    data1: 0x57213f19'u32, data2: 0x00e6'u16, data3: 0x49fa'u16,
    data4: [0x8e'u8, 0x07'u8, 0x89'u8, 0x8e'u8, 0xa0'u8, 0x1e'u8, 0xcb'u8, 0xd2'u8]
  )
  IidNavigationCompletedEventHandler* = WinGuid(
    data1: 0xd33a35bf'u32, data2: 0x1c49'u16, data3: 0x4f98'u16,
    data4: [0x93'u8, 0xab'u8, 0x00'u8, 0x6e'u8, 0x05'u8, 0x33'u8, 0xfe'u8, 0x1c'u8]
  )
  IidNavigationStartingEventHandler* = WinGuid(
    data1: 0x9adbe429'u32, data2: 0xf36d'u16, data3: 0x432b'u16,
    data4: [0x9d'u8, 0xdc'u8, 0xf8'u8, 0x88'u8, 0x1f'u8, 0xbd'u8, 0x76'u8, 0xe3'u8]
  )
  IidNewWindowRequestedEventHandler* = WinGuid(
    data1: 0xd4c185fe'u32, data2: 0xc81c'u16, data3: 0x4989'u16,
    data4: [0x97'u8, 0xaf'u8, 0x2d'u8, 0x3f'u8, 0xa7'u8, 0xab'u8, 0x56'u8, 0x51'u8]
  )
  IidPermissionRequestedEventHandler* = WinGuid(
    data1: 0x15e1c6a3'u32, data2: 0xc72a'u16, data3: 0x4df3'u16,
    data4: [0x91'u8, 0xd7'u8, 0xd0'u8, 0x97'u8, 0xfb'u8, 0xec'u8, 0x6b'u8, 0xfd'u8]
  )
  IidDownloadStartingEventHandler* = WinGuid(
    data1: 0xefedc989'u32, data2: 0xc396'u16, data3: 0x41ca'u16,
    data4: [0x83'u8, 0xf7'u8, 0x07'u8, 0xf8'u8, 0x45'u8, 0xa5'u8, 0x57'u8, 0x24'u8]
  )
  IidCoreWebView2_4* = WinGuid(
    data1: 0x20d02d59'u32, data2: 0x6df2'u16, data3: 0x42dc'u16,
    data4: [0xbd'u8, 0x06'u8, 0xf9'u8, 0x8a'u8, 0x69'u8, 0x4b'u8, 0x13'u8, 0x02'u8]
  )
  ## These interfaces are retained for the M4 WebView2 profile-data spike.
  ## Every IID and vtable slot below was checked against the SDK version
  ## recorded at the top of this module.
  IidCoreWebView2_2* = WinGuid(
    data1: 0x9e8f0cf8'u32, data2: 0xe670'u16, data3: 0x4b5e'u16,
    data4: [0xb2'u8, 0xbc'u8, 0x73'u8, 0xe0'u8, 0x61'u8, 0xe3'u8, 0x18'u8, 0x4c'u8]
  )
  IidCoreWebView2_13* = WinGuid(
    data1: 0xf75f09a8'u32, data2: 0x667e'u16, data3: 0x4983'u16,
    data4: [0x88'u8, 0xd6'u8, 0xc8'u8, 0x77'u8, 0x3f'u8, 0x31'u8, 0x5e'u8, 0x84'u8]
  )
  IidCoreWebView2CookieManager* = WinGuid(
    data1: 0x177cd9e7'u32, data2: 0xb6f5'u16, data3: 0x451a'u16,
    data4: [0x94'u8, 0xa0'u8, 0x5d'u8, 0x7a'u8, 0x3a'u8, 0x4c'u8, 0x41'u8, 0x41'u8]
  )
  IidCoreWebView2Profile2* = WinGuid(
    data1: 0xfa740d4b'u32, data2: 0x5eae'u16, data3: 0x4344'u16,
    data4: [0xa8'u8, 0xad'u8, 0x74'u8, 0xbe'u8, 0x31'u8, 0x92'u8, 0x53'u8, 0x97'u8]
  )
  IidClearBrowsingDataCompletedHandler* = WinGuid(
    data1: 0xe9710a06'u32, data2: 0x1d1d'u16, data3: 0x49b2'u16,
    data4: [0x82'u8, 0x34'u8, 0x22'u8, 0x6f'u8, 0x35'u8, 0x84'u8, 0x6a'u8, 0xe5'u8]
  )
  IidWebResourceRequestedEventHandler* = WinGuid(
    data1: 0xab00b74c'u32, data2: 0x15f1'u16, data3: 0x4646'u16,
    data4: [0x80'u8, 0xe8'u8, 0xe7'u8, 0x63'u8, 0x41'u8, 0xd2'u8, 0x5d'u8, 0x71'u8]
  )

  ## Vtable indices include the three IUnknown entries.  Keeping them named
  ## makes header verification and the isolated ABI test explicit.
  Core2GetCookieManagerSlot* = 66
  Core13GetProfileSlot* = 105
  Profile2ClearBrowsingDataSlot* = 10
  CookieManagerDeleteAllCookiesSlot* = 10

  ## COREWEBVIEW2_BROWSING_DATA_KINDS values used by Nimino's profile-data
  ## model.  They are flags, so callers may combine them with `or`.
  WebView2BrowsingDataLocalStorage* = 0x0004'u32
  WebView2BrowsingDataCacheStorage* = 0x0010'u32
  WebView2BrowsingDataCookies* = 0x0040'u32
  WebView2BrowsingDataDiskCache* = 0x0100'u32

proc coInitializeEx*(reserved: pointer; coInit: uint32): HResult
  {.stdcall, importc: "CoInitializeEx", dynlib: "ole32.dll".}
proc coUninitialize*() {.stdcall, importc: "CoUninitialize", dynlib: "ole32.dll".}
proc coTaskMemFree*(memory: pointer)
  {.stdcall, importc: "CoTaskMemFree", dynlib: "ole32.dll".}
proc shCreateMemStream*(data: ptr uint8; length: uint32): pointer
  {.stdcall, importc: "SHCreateMemStream", dynlib: "shlwapi.dll".}

proc getModuleHandleW*(moduleName: WideCString): HModule
  {.stdcall, importc: "GetModuleHandleW", dynlib: "kernel32.dll".}
proc loadLibraryW*(fileName: WideCString): HModule
  {.stdcall, importc: "LoadLibraryW", dynlib: "kernel32.dll".}
proc freeLibrary*(module: HModule): WinBool
  {.stdcall, importc: "FreeLibrary", dynlib: "kernel32.dll".}
proc getProcAddress*(module: HModule; procedureName: cstring): pointer
  {.stdcall, importc: "GetProcAddress", dynlib: "kernel32.dll".}
proc getLastError*(): uint32
  {.stdcall, importc: "GetLastError", dynlib: "kernel32.dll".}

proc registerClassExW*(windowClass: ptr WinWindowClassExW): uint16
  {.stdcall, importc: "RegisterClassExW", dynlib: "user32.dll".}
proc unregisterClassW*(className: WideCString; instance: HInstance): WinBool
  {.stdcall, importc: "UnregisterClassW", dynlib: "user32.dll".}
proc createWindowExW*(extendedStyle: uint32; className, windowName: WideCString;
                      style: uint32; x, y, width, height: int32;
                      parent, menu: pointer; instance: HInstance;
                      parameter: pointer): HWND
  {.stdcall, importc: "CreateWindowExW", dynlib: "user32.dll".}
proc destroyWindow*(window: HWND): WinBool
  {.stdcall, importc: "DestroyWindow", dynlib: "user32.dll".}
proc defWindowProcW*(window: HWND; message: uint32; wParam: WParam;
                     lParam: LParam): LResult
  {.stdcall, importc: "DefWindowProcW", dynlib: "user32.dll".}
proc setWindowLongPtrW*(window: HWND; index: int32; value: int): int
  {.stdcall, importc: "SetWindowLongPtrW", dynlib: "user32.dll".}
proc getWindowLongPtrW*(window: HWND; index: int32): int
  {.stdcall, importc: "GetWindowLongPtrW", dynlib: "user32.dll".}
proc setWindowTextW*(window: HWND; text: WideCString): WinBool
  {.stdcall, importc: "SetWindowTextW", dynlib: "user32.dll".}
proc setWindowPos*(window, insertAfter: HWND; x, y, width, height: int32; flags: uint32): WinBool
  {.stdcall, importc: "SetWindowPos", dynlib: "user32.dll".}
proc showWindow*(window: HWND; command: int32): WinBool
  {.stdcall, importc: "ShowWindow", dynlib: "user32.dll".}
proc updateWindow*(window: HWND): WinBool
  {.stdcall, importc: "UpdateWindow", dynlib: "user32.dll".}
proc setForegroundWindow*(window: HWND): WinBool
  {.stdcall, importc: "SetForegroundWindow", dynlib: "user32.dll".}
proc loadIconW*(instance: HInstance; iconName: WideCString): HIcon
  {.stdcall, importc: "LoadIconW", dynlib: "user32.dll".}
proc createPopupMenu*(): HMenu
  {.stdcall, importc: "CreatePopupMenu", dynlib: "user32.dll".}
proc appendMenuW*(menu: HMenu; flags: uint32; identifier: uint;
                  text: WideCString): WinBool
  {.stdcall, importc: "AppendMenuW", dynlib: "user32.dll".}
proc trackPopupMenu*(menu: HMenu; flags: uint32; x, y: int32; reserved: uint32;
                     window: HWND; reservedRectangle: ptr WinRect): uint32
  {.stdcall, importc: "TrackPopupMenu", dynlib: "user32.dll".}
proc destroyMenu*(menu: HMenu): WinBool
  {.stdcall, importc: "DestroyMenu", dynlib: "user32.dll".}
proc getCursorPos*(point: ptr WinPoint): WinBool
  {.stdcall, importc: "GetCursorPos", dynlib: "user32.dll".}
proc getClientRect*(window: HWND; rectangle: ptr WinRect): WinBool
  {.stdcall, importc: "GetClientRect", dynlib: "user32.dll".}
proc getMessageW*(message: ptr WinMessage; window: HWND; minimum, maximum: uint32): int32
  {.stdcall, importc: "GetMessageW", dynlib: "user32.dll".}
proc translateMessage*(message: ptr WinMessage): WinBool
  {.stdcall, importc: "TranslateMessage", dynlib: "user32.dll".}
proc dispatchMessageW*(message: ptr WinMessage): LResult
  {.stdcall, importc: "DispatchMessageW", dynlib: "user32.dll".}
proc postQuitMessage*(exitCode: int32)
  {.stdcall, importc: "PostQuitMessage", dynlib: "user32.dll".}
proc postMessageW*(window: HWND; message: uint32; wParam: WParam;
                   lParam: LParam): WinBool
  {.stdcall, importc: "PostMessageW", dynlib: "user32.dll".}
proc setTimer*(window: HWND; identifier: uint; intervalMs: uint32;
               callback: pointer): uint
  {.stdcall, importc: "SetTimer", dynlib: "user32.dll".}
proc killTimer*(window: HWND; identifier: uint): WinBool
  {.stdcall, importc: "KillTimer", dynlib: "user32.dll".}
proc shellNotifyIconW*(message: uint32; data: ptr NotifyIconDataW): WinBool
  {.stdcall, importc: "Shell_NotifyIconW", dynlib: "shell32.dll".}
proc getOpenFileNameW*(fileName: ptr OpenFileNameW): WinBool
  {.stdcall, importc: "GetOpenFileNameW", dynlib: "comdlg32.dll".}
proc getSaveFileNameW*(fileName: ptr OpenFileNameW): WinBool
  {.stdcall, importc: "GetSaveFileNameW", dynlib: "comdlg32.dll".}
proc commDlgExtendedError*(): uint32
  {.stdcall, importc: "CommDlgExtendedError", dynlib: "comdlg32.dll".}

proc makeIntResourceW*(identifier: uint16): WideCString {.inline.} =
  ## MAKEINTRESOURCEW without exposing a Win32 macro to public API users.
  cast[WideCString](cast[pointer](cast[uint](identifier)))

proc succeeded*(value: HResult): bool {.inline.} = value >= 0

proc comAddRef*(instance: pointer): uint32 {.inline.} =
  let dispatch = cast[proc(self: pointer): uint32 {.stdcall.}](
    cast[ptr ComInterface](instance).vtable[1]
  )
  dispatch(instance)

proc comRelease*(instance: pointer): uint32 {.inline.} =
  let dispatch = cast[proc(self: pointer): uint32 {.stdcall.}](
    cast[ptr ComInterface](instance).vtable[2]
  )
  dispatch(instance)

proc comQueryInterface*(instance: pointer; iid: ptr WinGuid;
                        outInstance: ptr pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; iid: ptr WinGuid;
                           outInstance: ptr pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](instance).vtable[0]
  )
  dispatch(instance, iid, outInstance)

proc core2GetCookieManager*(core2: pointer;
                            cookieManager: ptr pointer): HResult {.inline.} =
  ## ICoreWebView2_2::get_CookieManager (vtable slot 66).
  let dispatch = cast[proc(self: pointer; cookieManager: ptr pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](core2).vtable[Core2GetCookieManagerSlot]
  )
  dispatch(core2, cookieManager)

proc core13GetProfile*(core13: pointer; profile: ptr pointer): HResult {.inline.} =
  ## ICoreWebView2_13::get_Profile (vtable slot 105).
  let dispatch = cast[proc(self: pointer; profile: ptr pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](core13).vtable[Core13GetProfileSlot]
  )
  dispatch(core13, profile)

proc profile2ClearBrowsingData*(profile2: pointer; dataKinds: uint32;
                                handler: pointer): HResult {.inline.} =
  ## ICoreWebView2Profile2::ClearBrowsingData (vtable slot 10).
  ## `handler` must implement ICoreWebView2ClearBrowsingDataCompletedHandler
  ## and remain alive until WebView2 invokes it.
  let dispatch = cast[proc(self: pointer; dataKinds: uint32;
                           handler: pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](profile2).vtable[Profile2ClearBrowsingDataSlot]
  )
  dispatch(profile2, dataKinds, handler)

proc cookieManagerDeleteAllCookies*(cookieManager: pointer): HResult {.inline.} =
  ## ICoreWebView2CookieManager::DeleteAllCookies (vtable slot 10).
  let dispatch = cast[proc(self: pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](cookieManager).vtable[CookieManagerDeleteAllCookiesSlot]
  )
  dispatch(cookieManager)

proc core4AddDownloadStarting*(core4: pointer; handler: pointer;
                               token: ptr EventRegistrationToken): HResult {.inline.} =
  ## Slot 75 verified from ICoreWebView2_4Vtbl in SDK 1.0.3967.48.
  ## Slots 72--74 are ClearVirtualHostNameToFolderMapping and FrameCreated.
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core4).vtable[75]
  )
  dispatch(core4, handler, token)

proc core4RemoveDownloadStarting*(core4: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core4).vtable[76]
  )
  dispatch(core4, token)

proc environmentCreateController*(environment: pointer; parent: HWND;
                                  handler: pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; parent: HWND; handler: pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](environment).vtable[3]
  )
  dispatch(environment, parent, handler)

proc controllerSetBounds*(controller: pointer; bounds: WinRect): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; bounds: WinRect): HResult {.stdcall.}](
    cast[ptr ComInterface](controller).vtable[6]
  )
  dispatch(controller, bounds)

proc controllerClose*(controller: pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](controller).vtable[24]
  )
  dispatch(controller)

proc controllerGetCore*(controller: pointer; core: ptr pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; core: ptr pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](controller).vtable[25]
  )
  dispatch(controller, core)

proc coreGetSettings*(core: pointer; settings: ptr pointer): HResult {.inline.} =
  ## ICoreWebView2::get_Settings (vtable slot 3).
  let dispatch = cast[proc(self: pointer; settings: ptr pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[3]
  )
  dispatch(core, settings)

proc settingsPutAreDevToolsEnabled*(settings: pointer;
                                    enabled: WinBool): HResult {.inline.} =
  ## ICoreWebView2Settings::put_AreDevToolsEnabled (vtable slot 12).
  let dispatch = cast[proc(self: pointer; enabled: WinBool): HResult {.stdcall.}](
    cast[ptr ComInterface](settings).vtable[12]
  )
  dispatch(settings, enabled)

proc coreNavigate*(core: pointer; uri: WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; uri: WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[5]
  )
  dispatch(core, uri)

proc coreAddNavigationStarting*(core: pointer; handler: pointer;
                                token: ptr EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[7]
  )
  dispatch(core, handler, token)

proc coreAddPermissionRequested*(core: pointer; handler: pointer;
                                 token: ptr EventRegistrationToken): HResult {.inline.} =
  ## ICoreWebView2 vtable slot verified against WebView2.h 1.0.3967.48.
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[23]
  )
  dispatch(core, handler, token)

proc coreRemovePermissionRequested*(core: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}] (
    cast[ptr ComInterface](core).vtable[24]
  )
  dispatch(core, token)

proc permissionArgsPutState*(args: pointer; state: int32): HResult {.inline.} =
  ## ICoreWebView2PermissionRequestedEventArgs::put_State (vtable slot 7).
  let dispatch = cast[proc(self: pointer; state: int32): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[7]
  )
  dispatch(args, state)

proc permissionArgsGetPermissionKind*(args: pointer; kind: ptr int32): HResult {.inline.} =
  ## ICoreWebView2PermissionRequestedEventArgs::get_PermissionKind
  ## (vtable slot 4).
  let dispatch = cast[proc(self: pointer; kind: ptr int32): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[4]
  )
  dispatch(args, kind)

proc downloadArgsPutCancel*(args: pointer; cancel: WinBool): HResult {.inline.} =
  ## ICoreWebView2DownloadStartingEventArgs::put_Cancel (vtable slot 5).
  let dispatch = cast[proc(self: pointer; cancel: WinBool): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[5]
  )
  dispatch(args, cancel)

proc downloadArgsGetOperation*(args: pointer; operation: ptr pointer): HResult {.inline.} =
  ## ICoreWebView2DownloadStartingEventArgs::get_DownloadOperation (slot 3).
  let dispatch = cast[proc(self: pointer; operation: ptr pointer): HResult {.stdcall.}] (
    cast[ptr ComInterface](args).vtable[3]
  )
  dispatch(args, operation)

proc downloadArgsPutResultFilePath*(args: pointer; path: WideCString): HResult {.inline.} =
  ## ICoreWebView2DownloadStartingEventArgs::put_ResultFilePath (slot 7).
  let dispatch = cast[proc(self: pointer; path: WideCString): HResult {.stdcall.}] (
    cast[ptr ComInterface](args).vtable[7]
  )
  dispatch(args, path)

proc downloadOperationGetBytesReceived*(operation: pointer; value: ptr int64): HResult {.inline.} =
  ## ICoreWebView2DownloadOperation::get_BytesReceived (slot 13).
  let dispatch = cast[proc(self: pointer; value: ptr int64): HResult {.stdcall.}] (
    cast[ptr ComInterface](operation).vtable[13]
  )
  dispatch(operation, value)

proc downloadOperationGetTotalBytes*(operation: pointer; value: ptr int64): HResult {.inline.} =
  ## ICoreWebView2DownloadOperation::get_TotalBytesToReceive (slot 12).
  let dispatch = cast[proc(self: pointer; value: ptr int64): HResult {.stdcall.}] (
    cast[ptr ComInterface](operation).vtable[12]
  )
  dispatch(operation, value)

proc downloadOperationGetUri*(operation: pointer; value: ptr WideCString): HResult {.inline.} =
  ## ICoreWebView2DownloadOperation::get_Uri (slot 9).
  let dispatch = cast[proc(self: pointer; value: ptr WideCString): HResult {.stdcall.}] (
    cast[ptr ComInterface](operation).vtable[9]
  )
  dispatch(operation, value)

proc downloadOperationGetState*(operation: pointer; value: ptr int32): HResult {.inline.} =
  ## ICoreWebView2DownloadOperation::get_State (slot 16).
  let dispatch = cast[proc(self: pointer; value: ptr int32): HResult {.stdcall.}] (
    cast[ptr ComInterface](operation).vtable[16]
  )
  dispatch(operation, value)

proc downloadOperationGetInterruptReason*(operation: pointer; value: ptr int32): HResult {.inline.} =
  ## ICoreWebView2DownloadOperation::get_InterruptReason (slot 17).
  let dispatch = cast[proc(self: pointer; value: ptr int32): HResult {.stdcall.}] (
    cast[ptr ComInterface](operation).vtable[17]
  )
  dispatch(operation, value)

proc downloadOperationAddBytesReceivedChanged*(operation, handler: pointer;
                                                token: ptr EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](operation).vtable[3]
  )
  dispatch(operation, handler, token)

proc downloadOperationRemoveBytesReceivedChanged*(operation: pointer;
                                                   token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](operation).vtable[4]
  )
  dispatch(operation, token)

proc downloadOperationAddStateChanged*(operation, handler: pointer;
                                       token: ptr EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](operation).vtable[7]
  )
  dispatch(operation, handler, token)

proc downloadOperationRemoveStateChanged*(operation: pointer;
                                          token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](operation).vtable[8]
  )
  dispatch(operation, token)

proc coreRemoveNavigationStarting*(core: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[8]
  )
  dispatch(core, token)

proc coreAddNewWindowRequested*(core: pointer; handler: pointer;
                                token: ptr EventRegistrationToken): HResult {.inline.} =
  ## ICoreWebView2::add_NewWindowRequested is vtable slot 44 in
  ## WebView2.h 1.0.3967.48; slot 45 removes the registration.
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[44]
  )
  dispatch(core, handler, token)

proc coreRemoveNewWindowRequested*(core: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[45]
  )
  dispatch(core, token)

proc coreAddWebResourceRequested*(core: pointer; handler: pointer;
                                  token: ptr EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[55]
  )
  dispatch(core, handler, token)

proc coreRemoveWebResourceRequested*(core: pointer;
                                     token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[56]
  )
  dispatch(core, token)

proc coreAddWebResourceRequestedFilter*(core: pointer; uri: WideCString;
                                        context: uint32): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; uri: WideCString;
                           context: uint32): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[57]
  )
  dispatch(core, uri, context)

proc environmentCreateWebResourceResponse*(environment: pointer; content: pointer;
                                           statusCode: int32; reason, headers: WideCString;
                                           response: ptr pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; content: pointer; statusCode: int32;
                           reason, headers: WideCString; response: ptr pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](environment).vtable[4]
  )
  dispatch(environment, content, statusCode, reason, headers, response)

proc webResourceArgsGetRequest*(args: pointer; request: ptr pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; request: ptr pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[3]
  )
  dispatch(args, request)

proc webResourceArgsPutResponse*(args: pointer; response: pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; response: pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[5]
  )
  dispatch(args, response)

proc webResourceRequestGetUri*(request: pointer; uri: ptr WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; uri: ptr WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](request).vtable[3]
  )
  dispatch(request, uri)

proc webResourceRequestGetMethod*(request: pointer; methodName: ptr WideCString): HResult {.inline.} =
  ## ICoreWebView2WebResourceRequest::get_Method (vtable slot 5), verified
  ## against the pinned WebView2 SDK header.
  let dispatch = cast[proc(self: pointer; methodName: ptr WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](request).vtable[5]
  )
  dispatch(request, methodName)

proc coreGetSource*(core: pointer; source: ptr WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; source: ptr WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[4]
  )
  dispatch(core, source)

proc coreNavigateToString*(core: pointer; html: WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; html: WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[6]
  )
  dispatch(core, html)

proc coreAddScriptToExecuteOnDocumentCreated*(core: pointer; script: WideCString;
                                               handler: pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; script: WideCString;
                           handler: pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[27]
  )
  dispatch(core, script, handler)

proc coreRemoveScriptToExecuteOnDocumentCreated*(core: pointer;
                                                  scriptId: WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; scriptId: WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[28]
  )
  dispatch(core, scriptId)

proc coreAddNavigationCompleted*(core: pointer; handler: pointer;
                                 token: ptr EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[15]
  )
  dispatch(core, handler, token)

proc coreRemoveNavigationCompleted*(core: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[16]
  )
  dispatch(core, token)

proc coreExecuteScript*(core: pointer; script: WideCString; handler: pointer): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; script: WideCString; handler: pointer): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[29]
  )
  dispatch(core, script, handler)

proc coreAddWebMessageReceived*(core: pointer; handler: pointer;
                                token: ptr EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[34]
  )
  dispatch(core, handler, token)

proc coreRemoveWebMessageReceived*(core: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[35]
  )
  dispatch(core, token)

proc webMessageTryGetAsString*(args: pointer; value: ptr WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; value: ptr WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[5]
  )
  dispatch(args, value)

proc navigationCompletedGetIsSuccess*(args: pointer; value: ptr WinBool): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; value: ptr WinBool): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[3]
  )
  dispatch(args, value)

proc navigationStartingGetUri*(args: pointer; value: ptr WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; value: ptr WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[3]
  )
  dispatch(args, value)

proc navigationStartingSetCancel*(args: pointer; value: WinBool): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; value: WinBool): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[8]
  )
  dispatch(args, value)

proc newWindowRequestedGetUri*(args: pointer; value: ptr WideCString): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; value: ptr WideCString): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[3]
  )
  dispatch(args, value)

proc newWindowRequestedSetHandled*(args: pointer; value: WinBool): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; value: WinBool): HResult {.stdcall.}](
    cast[ptr ComInterface](args).vtable[6]
  )
  dispatch(args, value)
