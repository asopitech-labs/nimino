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

const
  S_OK* = 0'i32
  E_NOINTERFACE* = -2147467262'i32
  E_POINTER* = -2147467261'i32

  CoInitApartmentThreaded* = 0x2'u32
  ErrorClassAlreadyExists* = 1410'u32

  CwUseDefault* = -2147483648'i32
  WsOverlappedWindow* = 0x00CF0000'u32
  SwShow* = 5'i32
  SwpNoSize* = 0x0001'u32
  SwpNoMove* = 0x0002'u32
  SwpNoZOrder* = 0x0004'u32

  WmSize* = 0x0005'u32
  WmDestroy* = 0x0002'u32
  WmClose* = 0x0010'u32
  WmNcCreate* = 0x0081'u32
  WmNcDestroy* = 0x0082'u32
  WmTimer* = 0x0113'u32
  GwlpUserData* = -21'i32

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

proc coInitializeEx*(reserved: pointer; coInit: uint32): HResult
  {.stdcall, importc: "CoInitializeEx", dynlib: "ole32.dll".}
proc coUninitialize*() {.stdcall, importc: "CoUninitialize", dynlib: "ole32.dll".}
proc coTaskMemFree*(memory: pointer)
  {.stdcall, importc: "CoTaskMemFree", dynlib: "ole32.dll".}

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

proc coreRemoveNavigationStarting*(core: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[8]
  )
  dispatch(core, token)

proc coreAddNewWindowRequested*(core: pointer; handler: pointer;
                                token: ptr EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; handler: pointer;
                           token: ptr EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[45]
  )
  dispatch(core, handler, token)

proc coreRemoveNewWindowRequested*(core: pointer; token: EventRegistrationToken): HResult {.inline.} =
  let dispatch = cast[proc(self: pointer; token: EventRegistrationToken): HResult {.stdcall.}](
    cast[ptr ComInterface](core).vtable[46]
  )
  dispatch(core, token)

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
