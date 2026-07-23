## Cocoa and WebKit bridge used by the macOS native backend.
##
## The public Nim API never exposes Objective-C objects.  This file declares a
## small C ABI implemented in bridge.m so ARC/retain rules stay on the Cocoa
## side and all Nim callbacks cross a single, audited boundary.

{.compile: "bridge.m".}
{.passL: "-framework Cocoa".}
{.passL: "-framework WebKit".}
{.passL: "-framework UserNotifications".}
{.passL: "-framework Network".}

type
  MacCallback* = pointer

proc macosAppCreate*(userData: pointer): pointer {.cdecl, importc: "nimino_macos_app_create".}
proc macosAppRun*(app: pointer; idle: MacCallback): cint {.cdecl, importc: "nimino_macos_app_run".}
proc macosAppStop*(app: pointer) {.cdecl, importc: "nimino_macos_app_stop".}
proc macosAppDispose*(app: pointer) {.cdecl, importc: "nimino_macos_app_dispose".}
proc macosAppPostToUi*(app: pointer; callback: MacCallback) {.cdecl, importc: "nimino_macos_app_post_to_ui".}
proc macosAppInstallMenu*(app: pointer; title: cstring; ids: ptr uint32;
                          titles: ptr cstring; enabled: ptr cint; count: cint;
                          callback: MacCallback) {.cdecl, importc: "nimino_macos_app_install_menu".}
proc macosAppRemoveMenu*(app: pointer) {.cdecl, importc: "nimino_macos_app_remove_menu".}
proc macosAppInstallTray*(app: pointer; ids: ptr uint32; titles: ptr cstring;
                          enabled: ptr cint; count: cint; callback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_app_install_tray".}
proc macosAppRemoveTray*(app: pointer) {.cdecl, importc: "nimino_macos_app_remove_tray".}
proc macosAppSetActivationShortcut*(app: pointer; shortcut: cstring;
                                    callback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_app_set_activation_shortcut".}
proc macosAppRemoveActivationShortcut*(app: pointer) {.cdecl,
  importc: "nimino_macos_app_remove_activation_shortcut".}
proc macosAppSetTrayIcon*(app: pointer; path: cstring): cint
  {.cdecl, importc: "nimino_macos_app_set_tray_icon".}
proc macosAppSetNotificationCallback*(app: pointer; callback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_app_set_notification_callback".}
proc macosAppSetDeepLinkCallback*(app: pointer; callback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_app_set_deep_link_callback".}
proc macosAppSetReopenCallback*(app: pointer; callback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_app_set_reopen_callback".}
proc macosAppSendNotification*(app: pointer; id, title, body: cstring): cint
  {.cdecl, importc: "nimino_macos_app_send_notification".}
proc macosAppRegisterScheme*(app: pointer; scheme: cstring; callback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_app_register_scheme".}
proc macosSchemeRespond*(app, task: pointer; status: cint; mimeType, body: cstring)
  {.cdecl, importc: "nimino_macos_scheme_respond".}

proc macosWindowCreate*(app: pointer; userData: pointer; title: cstring;
                        width, height: cint; closeCallback, closedCallback,
                        resizeCallback, moveCallback, fileDropCallback: MacCallback): pointer
  {.cdecl, importc: "nimino_macos_window_create".}
proc macosWindowDispose*(window: pointer) {.cdecl, importc: "nimino_macos_window_dispose".}
proc macosWindowShow*(window: pointer) {.cdecl, importc: "nimino_macos_window_show".}
proc macosWindowHide*(window: pointer) {.cdecl, importc: "nimino_macos_window_hide".}
proc macosWindowMinimize*(window: pointer) {.cdecl, importc: "nimino_macos_window_minimize".}
proc macosWindowMaximize*(window: pointer) {.cdecl, importc: "nimino_macos_window_maximize"}
proc macosWindowRestore*(window: pointer) {.cdecl, importc: "nimino_macos_window_restore"}
proc macosWindowFocus*(window: pointer) {.cdecl, importc: "nimino_macos_window_focus"}
proc macosWindowSetTitle*(window: pointer; title: cstring): cint
  {.cdecl, importc: "nimino_macos_window_set_title".}
proc macosWindowSetSize*(window: pointer; width, height: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_size".}
proc macosWindowSetPosition*(window: pointer; x, y: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_position".}
proc macosWindowSetResizable*(window: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_resizable".}
proc macosWindowSetDecorated*(window: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_decorated".}
proc macosWindowSetTitleBarOverlay*(window: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_title_bar_overlay".}
proc macosWindowSetMinimumSize*(window: pointer; width, height: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_minimum_size".}
proc macosWindowSetFullscreen*(window: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_fullscreen".}
proc macosWindowSetAlwaysOnTop*(window: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_always_on_top".}
proc macosWindowSetDarkMode*(window: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_window_set_dark_mode".}

proc macosViewCreate*(window: pointer; userData: pointer; userAgent, profilePath,
                      scheme, documentStartScript, proxyUrl: cstring; incognito,
                      devTools, ignoreCertificateErrors: cint; messageCallback,
                      errorCallback, newWindowCallback, navigationStartingCallback,
                      navigationCompletedCallback, evalCallback, fileDropCallback,
                      permissionCallback, downloadStartingCallback,
                      downloadPathCallback, downloadEventCallback: MacCallback): pointer
  {.cdecl, importc: "nimino_macos_view_create".}
proc macosViewDispose*(view: pointer) {.cdecl, importc: "nimino_macos_view_dispose".}
proc macosViewSetUserAgent*(view: pointer; value: cstring): cint
  {.cdecl, importc: "nimino_macos_view_set_user_agent".}
proc macosViewSetZoom*(view: pointer; factor: cdouble): cint
  {.cdecl, importc: "nimino_macos_view_set_zoom".}
proc macosViewSetIgnoreCertificateErrors*(view: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_view_set_ignore_certificate_errors".}
proc macosViewSetDevToolsEnabled*(view: pointer; enabled: cint): cint
  {.cdecl, importc: "nimino_macos_view_set_devtools_enabled".}
proc macosViewLoadUrl*(view: pointer; url: cstring): cint
  {.cdecl, importc: "nimino_macos_view_load_url".}
proc macosViewLoadHtml*(view: pointer; html, baseUrl: cstring): cint
  {.cdecl, importc: "nimino_macos_view_load_html".}
proc macosViewSetDocumentStartScript*(view: pointer; script: cstring): cint
  {.cdecl, importc: "nimino_macos_view_set_document_start_script".}
proc macosViewEvalJavaScript*(view: pointer; script: cstring; request: pointer): cint
  {.cdecl, importc: "nimino_macos_view_eval_javascript".}
proc macosViewClearBrowsingData*(view: pointer; kinds: uint32; request: pointer;
                                 doneCallback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_view_clear_browsing_data".}
proc macosViewGetCookies*(view: pointer; url: cstring; request: pointer;
                          itemCallback, doneCallback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_view_get_cookies".}
proc macosViewSetCookie*(view: pointer; name, value, domain, path: cstring;
                         secure, httpOnly: cint; expires: int64; request: pointer;
                         doneCallback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_view_set_cookie".}
proc macosViewDeleteCookie*(view: pointer; name, value, domain, path: cstring;
                            secure, httpOnly: cint; expires: int64; request: pointer;
                            doneCallback: MacCallback): cint
  {.cdecl, importc: "nimino_macos_view_delete_cookie".}

proc macosOpenFileDialog*(window: pointer; title, suggestedName: cstring;
                          save, multiple: cint; paths: ptr cstring; capacity: cint): cint
  {.cdecl, importc: "nimino_macos_open_file_dialog".}
proc macosFreeCString*(value: cstring) {.cdecl, importc: "nimino_macos_free_string".}
