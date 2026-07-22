const
  ## Version 2 makes the authenticated `ready` payload a required capability
  ## snapshot.  A client must not assume that a Windows host has a native
  ## feature merely because it completed the transport handshake.
  ProtocolVersion* = 2'u16
  MaxFrameBytes* = 1_048_576
  AuthenticationTokenHexLength* = 64
  ## This is a host protocol capability, not a public native Capability.
  ## It means the host understands the asynchronous browser-profile-clear
  ## request/response lifecycle. The underlying WebView runtime can still
  ## reject a particular request as unsupported.
  WebViewProfileDataClearCapability* = "webViewProfileDataClear"
  ## Host support for authenticated asynchronous CookieManager get/set/delete
  ## relays. The installed WebView2 Runtime remains the final authority.
  WebViewCookieManagerCapability* = "webViewCookieManager"
  NativeCapabilityNames* = [
    "multipleWebViews",
    "transparentWindow",
    "nativeMenu",
    "systemTray",
    "nativeNotification",
    "customProtocol",
    "webPermissionEvents",
    WebViewProfileDataClearCapability,
    WebViewCookieManagerCapability
  ]
