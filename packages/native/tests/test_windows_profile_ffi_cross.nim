## Compile-only Windows ABI contract for the Profile/CookieManager spike.
## The executable is not run in Linux CI; the runtime behavior is covered by
## test_webview2_profile_ffi.nim with fake COM vtables.

import ../src/nimino_native/private/windows/ffi

static:
  doAssert Core2GetCookieManagerSlot == 66
  doAssert Core13GetProfileSlot == 105
  doAssert Profile2ClearBrowsingDataSlot == 10
  doAssert CookieManagerDeleteAllCookiesSlot == 10

proc profileApiContract(core2, core13, profile2, cookieManager, handler: pointer) =
  var value: pointer
  discard core2GetCookieManager(core2, addr value)
  discard core13GetProfile(core13, addr value)
  discard profile2ClearBrowsingData(
    profile2,
    WebView2BrowsingDataCookies or WebView2BrowsingDataLocalStorage,
    handler
  )
  discard cookieManagerDeleteAllCookies(cookieManager)

when isMainModule:
  if false:
    ## Keep the call signatures type-checked without attempting COM dispatch
    ## in the compile-only Windows executable.
    profileApiContract(nil, nil, nil, nil, nil)
