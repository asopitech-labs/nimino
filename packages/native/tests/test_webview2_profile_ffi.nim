## ABI-only WebView2 Profile/CookieManager spike.
##
## This is deliberately independent of a Windows runtime: fake COM vtables
## prove that each private FFI dispatcher uses the header-verified slot and
## preserves the argument layout.  It does not claim that profile clearing is
## integrated into nimino-native or nimino-core yet.

import ../src/nimino_native/private/windows/ffi

var expectedProfile: pointer
var expectedCookieManager: pointer
var observedDataKinds: uint32
var observedHandler: pointer
var deleteAllCalls: int

proc fakeCore13GetProfile(self: pointer; profile: ptr pointer): HResult {.stdcall.} =
  discard self
  profile[] = expectedProfile
  result = S_OK

proc fakeCore2GetCookieManager(self: pointer;
                                cookieManager: ptr pointer): HResult {.stdcall.} =
  discard self
  cookieManager[] = expectedCookieManager
  result = S_OK

proc fakeProfile2ClearBrowsingData(self: pointer; dataKinds: uint32;
                                   handler: pointer): HResult {.stdcall.} =
  discard self
  observedDataKinds = dataKinds
  observedHandler = handler
  result = S_OK

proc fakeCookieManagerDeleteAllCookies(self: pointer): HResult {.stdcall.} =
  discard self
  inc deleteAllCalls
  result = S_OK

proc fakeCom(vtable: var openArray[pointer]): ComInterface =
  ComInterface(vtable: cast[ptr UncheckedArray[pointer]](addr vtable[0]))

block profileAndCookieManagerSlotsAreCallable:
  var core13Vtable: array[Core13GetProfileSlot + 1, pointer]
  var core2Vtable: array[Core2GetCookieManagerSlot + 1, pointer]
  var profile2Vtable: array[Profile2ClearBrowsingDataSlot + 1, pointer]
  var cookieManagerVtable: array[CookieManagerDeleteAllCookiesSlot + 1, pointer]

  core13Vtable[Core13GetProfileSlot] = cast[pointer](fakeCore13GetProfile)
  core2Vtable[Core2GetCookieManagerSlot] = cast[pointer](fakeCore2GetCookieManager)
  profile2Vtable[Profile2ClearBrowsingDataSlot] = cast[pointer](fakeProfile2ClearBrowsingData)
  cookieManagerVtable[CookieManagerDeleteAllCookiesSlot] = cast[pointer](fakeCookieManagerDeleteAllCookies)

  var core13 = fakeCom(core13Vtable)
  var core2 = fakeCom(core2Vtable)
  var profile2 = fakeCom(profile2Vtable)
  var cookieManager = fakeCom(cookieManagerVtable)
  var profile: pointer
  var manager: pointer

  expectedProfile = cast[pointer](addr profile2)
  expectedCookieManager = cast[pointer](addr cookieManager)

  doAssert core13GetProfile(addr core13, addr profile) == S_OK
  doAssert profile == expectedProfile
  doAssert core2GetCookieManager(addr core2, addr manager) == S_OK
  doAssert manager == expectedCookieManager

  let dataKinds = WebView2BrowsingDataCookies or
    WebView2BrowsingDataLocalStorage or
    WebView2BrowsingDataCacheStorage or
    WebView2BrowsingDataDiskCache
  let handler = cast[pointer](addr core13)
  doAssert profile2ClearBrowsingData(profile, dataKinds, handler) == S_OK
  doAssert observedDataKinds == dataKinds
  doAssert observedHandler == handler
  doAssert cookieManagerDeleteAllCookies(manager) == S_OK
  doAssert deleteAllCalls == 1

block profileDataFlagsStayNarrow:
  doAssert WebView2BrowsingDataLocalStorage == 0x0004'u32
  doAssert WebView2BrowsingDataCacheStorage == 0x0010'u32
  doAssert WebView2BrowsingDataCookies == 0x0040'u32
  doAssert WebView2BrowsingDataDiskCache == 0x0100'u32
