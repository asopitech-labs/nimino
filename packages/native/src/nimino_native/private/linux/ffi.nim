## Minimal direct FFI surface for GTK 4, GLib, GObject, and WebKitGTK 6.0.
## These declarations are verified against the development headers in the Docker image.

const
  LibGtk = "libgtk-4.so.1"
  LibGlib = "libglib-2.0.so.0"
  LibGio = "libgio-2.0.so.0"
  LibGObject = "libgobject-2.0.so.0"
  LibWebKit = "libwebkitgtk-6.0.so.4"

type
  GApplication* {.incompleteStruct.} = object
  GtkApplication* {.incompleteStruct.} = object
  GtkWindow* {.incompleteStruct.} = object
  GtkApplicationWindow* {.incompleteStruct.} = object
  GMenu* {.incompleteStruct.} = object
  GMenuModel* {.incompleteStruct.} = object
  GSimpleAction* {.incompleteStruct.} = object
  GAction* {.incompleteStruct.} = object
  GNotification* {.incompleteStruct.} = object
  WebKitWebView* {.incompleteStruct.} = object
  WebKitNetworkSession* {.incompleteStruct.} = object
  WebKitWebsiteDataManager* {.incompleteStruct.} = object
  WebKitUserContentManager* {.incompleteStruct.} = object
  WebKitUserScript* {.incompleteStruct.} = object
  WebKitPolicyDecision* {.incompleteStruct.} = object
  WebKitNavigationPolicyDecision* {.incompleteStruct.} = object
  WebKitResponsePolicyDecision* {.incompleteStruct.} = object
  WebKitNavigationAction* {.incompleteStruct.} = object
  WebKitURIRequest* {.incompleteStruct.} = object
  WebKitPermissionRequest* {.incompleteStruct.} = object
  GAsyncResult* {.incompleteStruct.} = object
  GError* {.incompleteStruct.} = object
  JSCValue* {.incompleteStruct.} = object
  JSCContext* {.incompleteStruct.} = object
  JSCException* {.incompleteStruct.} = object
  GClosureNotify* = proc(data: pointer; closure: pointer) {.cdecl.}
  GAsyncReadyCallback* = proc(sourceObject: pointer; asyncResult: ptr GAsyncResult;
                              userData: pointer) {.cdecl.}
  GSourceFunc* = proc(data: pointer): cint {.cdecl.}

  WebKitUserContentInjectedFrames* = cint
  WebKitUserScriptInjectionTime* = cint

const
  WebKitUserContentInjectAllFrames* = 0.cint
  WebKitUserScriptInjectAtDocumentStart* = 0.cint
  ## WebKitWebsiteDataTypes, verified against WebKitWebsiteData.h from the
  ## fixed WebKitGTK 6.0 development package used by the Docker image.
  WebKitWebsiteDataMemoryCache* = 1'u32 shl 0
  WebKitWebsiteDataDiskCache* = 1'u32 shl 1
  WebKitWebsiteDataOfflineApplicationCache* = 1'u32 shl 2
  WebKitWebsiteDataLocalStorage* = 1'u32 shl 4
  WebKitWebsiteDataCookies* = 1'u32 shl 6
  WebKitWebsiteDataDomCache* = 1'u32 shl 11

proc gtk_application_new*(applicationId: cstring; flags: cint): ptr GtkApplication
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_application_window_new*(application: ptr GtkApplication): ptr GtkWindow
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_set_title*(window: ptr GtkWindow; title: cstring)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_set_default_size*(window: ptr GtkWindow; width: cint; height: cint)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_set_resizable*(window: ptr GtkWindow; resizable: cint)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_set_child*(window: ptr GtkWindow; child: pointer)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_present*(window: ptr GtkWindow)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_minimize*(window: ptr GtkWindow)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_maximize*(window: ptr GtkWindow)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_unmaximize*(window: ptr GtkWindow)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_widget_hide*(widget: pointer)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_destroy*(window: ptr GtkWindow)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_application_set_menubar*(application: ptr GtkApplication;
                                  menubar: ptr GMenuModel)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_application_window_set_show_menubar*(window: ptr GtkApplicationWindow;
                                              showMenubar: cint)
  {.cdecl, importc, dynlib: LibGtk.}

proc g_application_run*(application: ptr GApplication; argc: cint; argv: ptr cstring): cint
  {.cdecl, importc, dynlib: LibGio.}
proc g_application_quit*(application: ptr GApplication)
  {.cdecl, importc, dynlib: LibGio.}
proc g_application_send_notification*(application: ptr GApplication; id: cstring;
                                      notification: ptr GNotification)
  {.cdecl, importc, dynlib: LibGio.}

proc g_menu_new*(): ptr GMenu
  {.cdecl, importc, dynlib: LibGio.}
proc g_menu_append*(menu: ptr GMenu; label, detailedAction: cstring)
  {.cdecl, importc, dynlib: LibGio.}
proc g_menu_append_submenu*(menu: ptr GMenu; label: cstring;
                            submenu: ptr GMenuModel)
  {.cdecl, importc, dynlib: LibGio.}
proc g_simple_action_new*(name: cstring; parameterType: pointer): ptr GSimpleAction
  {.cdecl, importc, dynlib: LibGio.}
proc g_simple_action_set_enabled*(action: ptr GSimpleAction; enabled: cint)
  {.cdecl, importc, dynlib: LibGio.}
proc g_action_map_add_action*(actionMap: pointer; action: ptr GAction)
  {.cdecl, importc, dynlib: LibGio.}
proc g_action_map_remove_action*(actionMap: pointer; actionName: cstring)
  {.cdecl, importc, dynlib: LibGio.}
proc g_notification_new*(title: cstring): ptr GNotification
  {.cdecl, importc, dynlib: LibGio.}
proc g_notification_set_body*(notification: ptr GNotification; body: cstring)
  {.cdecl, importc, dynlib: LibGio.}

proc g_object_ref_sink*(instance: pointer): pointer
  {.cdecl, importc, dynlib: LibGObject.}
proc g_object_unref*(instance: pointer)
  {.cdecl, importc, dynlib: LibGObject.}
proc g_object_new*(objectType: culong; firstPropertyName: cstring): pointer {.varargs, cdecl,
  importc, dynlib: LibGObject.}
proc g_free*(memory: pointer)
  {.cdecl, importc, dynlib: LibGlib.}
proc g_error_free*(error: ptr GError)
  {.cdecl, importc, dynlib: LibGlib.}
proc g_signal_connect_data*(instance: pointer; detailedSignal: cstring;
                            callback: pointer; data: pointer;
                            destroyData: GClosureNotify; connectFlags: cint): culong
  {.cdecl, importc, dynlib: LibGObject.}
proc g_signal_handler_disconnect*(instance: pointer; handlerId: culong)
  {.cdecl, importc, dynlib: LibGObject.}
proc g_timeout_add*(interval: uint32; callback: GSourceFunc; data: pointer): uint32
  {.cdecl, importc, dynlib: LibGlib.}
proc g_source_remove*(tag: uint32): cint
  {.cdecl, importc, dynlib: LibGlib.}

proc webkit_web_view_new*(): ptr WebKitWebView
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_get_type*(): culong
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_network_session_new*(dataDirectory, cacheDirectory: cstring):
    ptr WebKitNetworkSession
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_network_session_get_website_data_manager*(session: ptr WebKitNetworkSession):
    ptr WebKitWebsiteDataManager
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_load_uri*(view: ptr WebKitWebView; uri: cstring)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_load_html*(view: ptr WebKitWebView; content: cstring; baseUri: cstring)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_download_uri*(view: ptr WebKitWebView; uri: cstring): pointer
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_download_get_estimated_progress*(download: pointer): cdouble
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_download_get_request*(download: pointer): ptr WebKitURIRequest
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_get_uri*(view: ptr WebKitWebView): cstring
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_get_network_session*(view: ptr WebKitWebView): ptr WebKitNetworkSession
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_website_data_manager_clear*(manager: ptr WebKitWebsiteDataManager;
                                        types: uint32; timespan: int64;
                                        cancellable: pointer;
                                        callback: GAsyncReadyCallback;
                                        userData: pointer)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_website_data_manager_clear_finish*(manager: ptr WebKitWebsiteDataManager;
                                               asyncResult: ptr GAsyncResult;
                                               error: ptr ptr GError): cint
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_evaluate_javascript*(view: ptr WebKitWebView; script: cstring;
                                           length: int; worldName, sourceUri: cstring;
                                           cancellable: pointer; callback: GAsyncReadyCallback;
                                           userData: pointer)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_evaluate_javascript_finish*(view: ptr WebKitWebView;
                                                  asyncResult: ptr GAsyncResult;
                                                  error: ptr ptr GError): ptr JSCValue
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_get_user_content_manager*(view: ptr WebKitWebView): ptr WebKitUserContentManager
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_user_content_manager_register_script_message_handler*(manager: ptr WebKitUserContentManager;
                                                                   name, worldName: cstring): cint
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_user_content_manager_unregister_script_message_handler*(manager: ptr WebKitUserContentManager;
                                                                     name, worldName: cstring)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_user_content_manager_add_script*(manager: ptr WebKitUserContentManager;
                                             script: ptr WebKitUserScript)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_user_script_new*(source: cstring;
                             injectedFrames: WebKitUserContentInjectedFrames;
                             injectionTime: WebKitUserScriptInjectionTime;
                             allowList, blockList: ptr cstring): ptr WebKitUserScript
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_user_script_unref*(script: ptr WebKitUserScript)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_navigation_policy_decision_get_navigation_action*(decision: ptr WebKitNavigationPolicyDecision): ptr WebKitNavigationAction
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_navigation_action_get_request*(action: ptr WebKitNavigationAction): ptr WebKitURIRequest
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_response_policy_decision_get_request*(decision: ptr WebKitResponsePolicyDecision):
    ptr WebKitURIRequest
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_response_policy_decision_is_mime_type_supported*(
    decision: ptr WebKitResponsePolicyDecision): cint
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_uri_request_get_uri*(request: ptr WebKitURIRequest): cstring
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_policy_decision_use*(decision: ptr WebKitPolicyDecision)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_policy_decision_ignore*(decision: ptr WebKitPolicyDecision)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_permission_request_deny*(request: ptr WebKitPermissionRequest)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_permission_request_allow*(request: ptr WebKitPermissionRequest)
  {.cdecl, importc, dynlib: LibWebKit.}

const LibJavaScriptCore = "libjavascriptcoregtk-6.0.so.1"

proc jsc_value_get_context*(value: ptr JSCValue): ptr JSCContext
  {.cdecl, importc, dynlib: LibJavaScriptCore.}
proc jsc_context_get_exception*(context: ptr JSCContext): ptr JSCException
  {.cdecl, importc, dynlib: LibJavaScriptCore.}
proc jsc_exception_get_message*(exception: ptr JSCException): cstring
  {.cdecl, importc, dynlib: LibJavaScriptCore.}
proc jsc_value_to_json*(value: ptr JSCValue; indent: uint32): cstring
  {.cdecl, importc, dynlib: LibJavaScriptCore.}
proc jsc_value_is_string*(value: ptr JSCValue): cint
  {.cdecl, importc, dynlib: LibJavaScriptCore.}
proc jsc_value_to_string*(value: ptr JSCValue): cstring
  {.cdecl, importc, dynlib: LibJavaScriptCore.}
