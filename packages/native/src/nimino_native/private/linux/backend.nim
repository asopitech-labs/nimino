import std/os

proc linuxTrackDownload(view: NativeWebView; download: pointer; url: string)
proc linuxCreateView(view: NativeWebView): NativeResult

proc linuxCustomProtocolRequest(request: ptr WebKitURISchemeRequest;
                                userData: pointer) {.cdecl.} =
  let app = cast[NativeApp](userData)
  if app.isNil or request.isNil or app.customProtocolScheme.len == 0:
    return
  let uri = webkit_uri_scheme_request_get_uri(request)
  let methodName = webkit_uri_scheme_request_get_http_method(request)
  let path = webkit_uri_scheme_request_get_path(request)
  let response = app.dispatchCustomProtocol(NativeCustomProtocolRequest(
    methodName: if methodName.isNil: "GET" else: $methodName,
    url: if uri.isNil: "" else: $uri,
    path: if path.isNil: "/" else: $path))
  let bytes = g_bytes_new(cast[pointer](response.body.cstring), response.body.len.csize_t)
  if bytes.isNil:
    return
  let stream = g_memory_input_stream_new_from_bytes(bytes)
  g_bytes_unref(bytes)
  if stream.isNil:
    return
  let nativeResponse = webkit_uri_scheme_response_new(stream, response.body.len.int64)
  if nativeResponse.isNil:
    g_object_unref(stream)
    return
  let reason = if response.statusCode >= 200 and response.statusCode < 300: "OK" else: "Error"
  webkit_uri_scheme_response_set_status(nativeResponse, response.statusCode.uint32,
    reason.cstring)
  webkit_uri_scheme_response_set_content_type(nativeResponse, response.mimeType.cstring)
  webkit_uri_scheme_request_finish_with_response(request, nativeResponse)
  g_object_unref(nativeResponse)
  g_object_unref(stream)

proc linuxRegisterCustomProtocol(app: NativeApp): NativeResult =
  if app.isNil or app.customProtocolScheme.len == 0 or app.customProtocolHandler.isNil:
    return failure(nativeError(invalidArgument, "app.registerCustomProtocol"))
  let context = webkit_web_context_get_default()
  if context.isNil:
    return failure(nativeError(unsupported, "app.registerCustomProtocol",
      detail = "WebKitWebContext is unavailable"))
  webkit_web_context_register_uri_scheme(context, app.customProtocolScheme.cstring,
    linuxCustomProtocolRequest, cast[pointer](app), nil)
  let security = webkit_web_context_get_security_manager(context)
  if not security.isNil:
    webkit_security_manager_register_uri_scheme_as_secure(security,
      app.customProtocolScheme.cstring)
  success()

proc linuxNativeMenuActionName(itemId: uint32): string {.inline.} =
  "nimino-menu-" & $itemId

proc linuxNativeMenuActionDestroyed(data, closure: pointer) {.cdecl.} =
  let action = cast[NativeMenuAction](data)
  if action != nil:
    GC_unref(action)

proc linuxNativeMenuActionActivated(action, parameter, userData: pointer) {.cdecl.} =
  let menuAction = cast[NativeMenuAction](userData)
  if menuAction != nil:
    menuAction.app.dispatchNativeMenu(menuAction.itemId)

proc linuxRemoveNativeMenuActions(app: NativeApp; actionNames: openArray[string]) =
  if app.isNil or app.platformApp.isNil:
    return
  for actionName in actionNames:
    g_action_map_remove_action(app.platformApp, actionName.cstring)

proc linuxInstallNativeMenu(app: NativeApp): NativeResult =
  ## GtkApplication owns the installed menubar and actions. Temporary GMenu
  ## and GSimpleAction references are released after the ownership transfer.
  if app.isNil or not app.nativeMenuConfigured or app.platformApp.isNil:
    return success()
  let menubar = g_menu_new()
  let submenu = g_menu_new()
  if menubar.isNil or submenu.isNil:
    if submenu != nil:
      g_object_unref(submenu)
    if menubar != nil:
      g_object_unref(menubar)
    return failure(nativeError(osError, "app.configureNativeMenu",
      detail = "GTK menu allocation failed"))

  var addedActions: seq[string]
  for item in app.nativeMenuItems:
    let actionName = linuxNativeMenuActionName(item.id)
    let action = g_simple_action_new(actionName.cstring, nil)
    if action.isNil:
      app.linuxRemoveNativeMenuActions(addedActions)
      g_object_unref(submenu)
      g_object_unref(menubar)
      return failure(nativeError(osError, "app.configureNativeMenu",
        detail = "GTK action allocation failed"))
    let actionData = NativeMenuAction(app: app, itemId: item.id)
    GC_ref(actionData)
    let signal = g_signal_connect_data(action, "activate",
      cast[pointer](linuxNativeMenuActionActivated), cast[pointer](actionData),
      linuxNativeMenuActionDestroyed, 0)
    if signal == 0:
      GC_unref(actionData)
      g_object_unref(action)
      app.linuxRemoveNativeMenuActions(addedActions)
      g_object_unref(submenu)
      g_object_unref(menubar)
      return failure(nativeError(osError, "app.configureNativeMenu",
        detail = "GTK action signal registration failed"))
    g_simple_action_set_enabled(action, if item.enabled: 1 else: 0)
    g_action_map_add_action(app.platformApp, cast[ptr GAction](action))
    g_menu_append(submenu, item.title.cstring, ("app." & actionName).cstring)
    addedActions.add(actionName)
    g_object_unref(action)

  g_menu_append_submenu(menubar, app.nativeMenuTitle.cstring,
    cast[ptr GMenuModel](submenu))
  gtk_application_set_menubar(cast[ptr GtkApplication](app.platformApp),
    cast[ptr GMenuModel](menubar))
  ## The application holds a reference to the menubar. `menubar` holds the
  ## submenu reference, so both construction references can now be dropped.
  g_object_unref(submenu)
  g_object_unref(menubar)
  app.nativeMenuInstalled = true
  success()

proc linuxUninstallNativeMenu(app: NativeApp) =
  if app.isNil or not app.nativeMenuInstalled:
    return
  ## `g_application_run` has already unregistered GtkApplication when this is
  ## called. Calling gtk_application_set_menubar at that point is invalid and
  ## emits a GTK critical. Final GApplication unref immediately below owns the
  ## installed menu and actions and releases their signal closures, so only
  ## clear Nimino's state here.
  app.nativeMenuInstalled = false

proc linuxSendNativeNotification(app: NativeApp;
                                 notification: NativeNotification): NativeResult =
  if app.isNil or app.platformApp.isNil:
    return failure(nativeError(invalidState, "app.sendNativeNotification"))
  let nativeNotification = g_notification_new(notification.title.cstring)
  if nativeNotification.isNil:
    return failure(nativeError(osError, "app.sendNativeNotification",
      detail = "GNotification allocation failed"))
  if notification.body.len > 0:
    g_notification_set_body(nativeNotification, notification.body.cstring)
  ## GIO has no delivery status: a successful call only means the shell was
  ## asked to present it. The caller's notification ID enables replacement.
  g_application_send_notification(cast[ptr GApplication](app.platformApp),
    notification.id.cstring, nativeNotification)
  g_object_unref(nativeNotification)
  success()

proc linuxFileDialogComplete(request: NativeFileDialogRequest;
                             paths: seq[string]; error: ptr GError) =
  if request.isNil:
    return
  var completion: NativeResultOf[seq[string]]
  if error != nil and error.code != GtkDialogErrorCancelled and
      error.code != GtkDialogErrorDismissed:
    completion = failureOf[seq[string]](nativeError(osError, "window.openFileDialog",
      detail = if error.message.isNil: "GTK file dialog failed" else: $error.message))
  else:
    completion = successOf(paths)
  if error != nil:
    g_error_free(error)
  if not request.future.finished:
    request.future.complete(completion)
  GC_unref(request)

proc linuxFileDialogFinished(sourceObject: pointer; asyncResult: ptr GAsyncResult;
                             userData: pointer) {.cdecl.} =
  let request = cast[NativeFileDialogRequest](userData)
  if request.isNil:
    return
  let dialog = cast[ptr GtkFileDialog](sourceObject)
  var error: ptr GError
  if request.options.multiple and not request.options.save:
    let model = gtk_file_dialog_open_multiple_finish(dialog, asyncResult, addr error)
    if model.isNil:
      request.linuxFileDialogComplete(@[], error)
      g_object_unref(dialog)
      return
    var paths: seq[string]
    let count = g_list_model_get_n_items(model)
    for index in 0'u32 ..< count:
      let item = cast[ptr GFile](g_list_model_get_item(model, index))
      if item != nil:
        let path = g_file_get_path(item)
        if not path.isNil:
          paths.add($path)
        g_object_unref(item)
    g_object_unref(model)
    request.linuxFileDialogComplete(paths, nil)
  elif request.options.save:
    let file = gtk_file_dialog_save_finish(dialog, asyncResult, addr error)
    if file.isNil:
      request.linuxFileDialogComplete(@[], error)
      g_object_unref(dialog)
      return
    let path = g_file_get_path(file)
    let paths = if path.isNil: @[] else: @[$path]
    g_object_unref(file)
    request.linuxFileDialogComplete(paths, nil)
  else:
    let file = gtk_file_dialog_open_finish(dialog, asyncResult, addr error)
    if file.isNil:
      request.linuxFileDialogComplete(@[], error)
      g_object_unref(dialog)
      return
    let path = g_file_get_path(file)
    let paths = if path.isNil: @[] else: @[$path]
    g_object_unref(file)
    request.linuxFileDialogComplete(paths, nil)
  g_object_unref(dialog)

proc linuxOpenFileDialog*(window: NativeWindow; options: NativeFileDialogOptions):
                          Future[NativeResultOf[seq[string]]] =
  let target = newFuture[NativeResultOf[seq[string]]]("nimino.native.openFileDialog.linux")
  result = target
  if window.isNil or window.platformWindow.isNil or window.state != ready:
    target.complete(failureOf[seq[string]](nativeError(invalidState,
      "window.openFileDialog")))
    return
  let dialog = gtk_file_dialog_new()
  if dialog.isNil:
    target.complete(failureOf[seq[string]](nativeError(osError, "window.openFileDialog",
      detail = "GTK file dialog allocation failed")))
    return
  gtk_file_dialog_set_modal(dialog, 1)
  gtk_file_dialog_set_title(dialog, options.title.cstring)
  if options.suggestedName.len > 0:
    gtk_file_dialog_set_initial_name(dialog, options.suggestedName.cstring)
  let request = NativeFileDialogRequest(future: target, options: options)
  GC_ref(request)
  if options.multiple and not options.save:
    gtk_file_dialog_open_multiple(dialog, cast[ptr GtkWindow](window.platformWindow), nil,
      linuxFileDialogFinished, cast[pointer](request))
  elif options.save:
    gtk_file_dialog_save(dialog, cast[ptr GtkWindow](window.platformWindow), nil,
      linuxFileDialogFinished, cast[pointer](request))
  else:
    gtk_file_dialog_open(dialog, cast[ptr GtkWindow](window.platformWindow), nil,
      linuxFileDialogFinished, cast[pointer](request))

proc linuxSetDevToolsEnabled(view: NativeWebView; enabled: bool): NativeResult =
  if view.isNil or view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.setDevToolsEnabled"))
  let settings = webkit_web_view_get_settings(
    cast[ptr WebKitWebView](view.platformView))
  if settings.isNil:
    return failure(nativeError(webViewError, "webview.setDevToolsEnabled",
      detail = "WebKitSettings is unavailable"))
  webkit_settings_set_enable_developer_extras(settings, if enabled: 1 else: 0)
  success()

proc linuxBrowsingDataTypes(kinds: set[NativeBrowsingDataKind]): uint32 =
  ## Keep this mapping deliberately narrow: WebKitGTK exposes IndexedDB and
  ## service-worker registrations as independent WebsiteDataTypes, while
  ## Nimino's public API names only cookies, localStorage, and cache.
  for kind in kinds:
    case kind
    of nativeBrowsingCookies:
      result = result or WebKitWebsiteDataCookies
    of nativeBrowsingLocalStorage:
      result = result or WebKitWebsiteDataLocalStorage
    of nativeBrowsingCache:
      ## Match WebView2's CacheStorage + disk-cache intent with all WebKitGTK
      ## data types that are explicitly documented as caches.
      result = result or WebKitWebsiteDataMemoryCache or WebKitWebsiteDataDiskCache or
        WebKitWebsiteDataOfflineApplicationCache or WebKitWebsiteDataDomCache

proc linuxBrowsingDataClearCompleted(sourceObject: pointer;
                                     asyncResult: ptr GAsyncResult;
                                     userData: pointer) {.cdecl.} =
  let request = cast[NativeBrowsingDataRequest](userData)
  if request.isNil:
    return
  var error: ptr GError
  let completed = webkit_website_data_manager_clear_finish(
    cast[ptr WebKitWebsiteDataManager](sourceObject), asyncResult, addr error)
  let outcome =
    if completed != 0:
      success()
    else:
      failure(nativeError(webViewError, "webview.clearBrowsingData",
        detail = "WebKitGTK WebsiteDataManager clear failed"))
  if error != nil:
    g_error_free(error)
  let view = request.view
  if view != nil:
    view.completeBrowsingDataRequest(request, outcome)
  elif request.future != nil and not request.future.finished:
    request.future.complete(failure(nativeError(invalidState, "webview.clearBrowsingData")))
  GC_unref(request)

proc linuxClearBrowsingData(view: NativeWebView;
                            request: NativeBrowsingDataRequest): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.clearBrowsingData"))
  let session = webkit_web_view_get_network_session(
    cast[ptr WebKitWebView](view.platformView))
  if session.isNil:
    return failure(nativeError(webViewError, "webview.clearBrowsingData",
      detail = "WebKitGTK network session is unavailable"))
  let manager = webkit_network_session_get_website_data_manager(session)
  if manager.isNil:
    return failure(nativeError(webViewError, "webview.clearBrowsingData",
      detail = "WebKitGTK website data manager is unavailable"))
  ## `timespan = 0` is the API-defined all-data value; a nonzero timespan does
  ## not reliably remove cookies according to the WebKitGTK reference.
  GC_ref(request)
  webkit_website_data_manager_clear(manager, linuxBrowsingDataTypes(request.kinds),
    0'i64, nil, linuxBrowsingDataClearCompleted, cast[pointer](request))
  success()

proc linuxCloseRequested(window: pointer; userData: pointer): cint {.cdecl.} =
  let nativeWindow = cast[NativeWindow](userData)
  ## GTK close-request returns TRUE to stop the close emission.
  if nativeWindow.dispatchCloseRequested(): 0 else: 1

proc linuxSizeNotify(window, pspec, userData: pointer) {.cdecl.} =
  discard window
  discard pspec
  let nativeWindow = cast[NativeWindow](userData)
  if nativeWindow != nil and nativeWindow.platformWindow != nil:
    nativeWindow.dispatchResized(
      gtk_widget_get_width(nativeWindow.platformWindow),
      gtk_widget_get_height(nativeWindow.platformWindow))

proc linuxSetTitle(window: NativeWindow) =
  if window.platformWindow != nil:
    let title = window.title
    gtk_window_set_title(cast[ptr GtkWindow](window.platformWindow), cstring(title))

proc linuxSetSize(window: NativeWindow) =
  if window.platformWindow != nil:
    gtk_window_set_default_size(cast[ptr GtkWindow](window.platformWindow),
      cint(window.width), cint(window.height))
    if window.app.state == running:
      window.dispatchResized(window.width, window.height)

proc linuxSetResizable(window: NativeWindow; resizable: bool) =
  if window.platformWindow != nil:
    gtk_window_set_resizable(cast[ptr GtkWindow](window.platformWindow),
      if resizable: 1 else: 0)

proc linuxShowWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    gtk_window_present(cast[ptr GtkWindow](window.platformWindow))

proc linuxHideWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    gtk_widget_hide(window.platformWindow)

proc linuxFocusWindow(window: NativeWindow) =
  linuxShowWindow(window)

proc linuxMinimizeWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    gtk_window_minimize(cast[ptr GtkWindow](window.platformWindow))

proc linuxMaximizeWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    gtk_window_maximize(cast[ptr GtkWindow](window.platformWindow))

proc linuxRestoreWindow(window: NativeWindow) =
  if window.platformWindow != nil:
    gtk_window_unmaximize(cast[ptr GtkWindow](window.platformWindow))

proc linuxLoadUrl(view: NativeWebView) =
  if view.platformView != nil and view.pendingUrl.len > 0:
    let url = view.pendingUrl
    webkit_web_view_load_uri(cast[ptr WebKitWebView](view.platformView), cstring(url))

proc linuxLoadHtml(view: NativeWebView) =
  if view.platformView != nil:
    let html = view.pendingHtml
    let baseUri =
      if view.pendingHtmlBaseUrl.len == 0:
        nil
      else:
        cstring(view.pendingHtmlBaseUrl)
    webkit_web_view_load_html(cast[ptr WebKitWebView](view.platformView),
      cstring(html), baseUri)

proc linuxLoadPendingContent(view: NativeWebView) =
  case view.pendingContentKind
  of urlContent:
    view.linuxLoadUrl()
  of htmlContent:
    view.linuxLoadHtml()
  of noContent:
    discard

proc linuxScriptMessageReceived(manager: pointer; value: ptr JSCValue;
                                userData: pointer) {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view.isNil or value.isNil or jsc_value_is_string(value) == 0:
    return
  let text = jsc_value_to_string(value)
  if text.isNil:
    return
  let message = $text
  g_free(cast[pointer](text))
  view.dispatchMessage(message)

proc linuxConfigureMessageBridge(view: NativeWebView): NativeResult =
  let manager = webkit_web_view_get_user_content_manager(cast[ptr WebKitWebView](view.platformView))
  if manager.isNil:
    return failure(nativeError(webViewError, "webview.onMessage",
      detail = "WebKitGTK user content manager is unavailable"))
  let signal = g_signal_connect_data(
    manager,
    "script-message-received::nimino",
    cast[pointer](linuxScriptMessageReceived),
    cast[pointer](view),
    nil,
    0
  )
  if signal == 0:
    return failure(nativeError(webViewError, "webview.onMessage",
      detail = "WebKitGTK message signal registration failed"))
  if webkit_user_content_manager_register_script_message_handler(manager, "nimino", nil) == 0:
    g_signal_handler_disconnect(manager, signal)
    return failure(nativeError(webViewError, "webview.onMessage",
      detail = "WebKitGTK message handler registration failed"))
  view.platformMessageManager = manager
  view.messageSignalHandler = signal
  view.messageRegistered = true
  success()

proc linuxConfigureDocumentStartScript(view: NativeWebView): NativeResult =
  let manager = webkit_web_view_get_user_content_manager(cast[ptr WebKitWebView](view.platformView))
  if manager.isNil:
    return failure(nativeError(webViewError, "webview.setDocumentStartScript",
      detail = "WebKitGTK user content manager is unavailable"))
  ## WebKitGTK exposes remove-all rather than a per-script removal API.  The
  ## manager currently owns only Nimino's document-start bridge, so replacing
  ## that managed set is deterministic and keeps navigation-time updates safe.
  webkit_user_content_manager_remove_all_scripts(manager)
  if view.documentStartScript.len == 0:
    return success()
  let source = view.documentStartScript
  let script = webkit_user_script_new(
    cstring(source),
    WebKitUserContentInjectedFrames(WebKitUserContentInjectAllFrames),
    WebKitUserScriptInjectionTime(WebKitUserScriptInjectAtDocumentStart),
    nil,
    nil
  )
  if script.isNil:
    return failure(nativeError(webViewError, "webview.setDocumentStartScript",
      detail = "WebKitGTK user script creation failed"))
  webkit_user_content_manager_add_script(manager, script)
  webkit_user_script_unref(script)
  success()

proc linuxLoadChanged(webView: pointer; loadEvent: cint; userData: pointer) {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view.isNil or view.state in {closing, closed}:
    return
  case loadEvent
  of 0: # WEBKIT_LOAD_STARTED
    view.navigationFailed = false
  of 3: # WEBKIT_LOAD_FINISHED
    let uri = webkit_web_view_get_uri(cast[ptr WebKitWebView](webView))
    let copiedUri = if uri.isNil: "" else: $uri
    view.dispatchNavigationCompleted(copiedUri, not view.navigationFailed)
  else:
    discard

proc linuxLoadFailed(webView: pointer; loadEvent: cint; failingUri: cstring;
                     error: ptr GError; userData: pointer): cint {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view != nil and view.state notin {closing, closed}:
    view.navigationFailed = true
    view.dispatchError(nativeError(webViewError, "webview.navigate",
      detail = "WebKitGTK navigation failed"))
  ## Returning false preserves WebKitGTK's default error-page handling.
  0

proc linuxConfigureLoadEvents(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.onNavigationCompleted"))
  let webView = cast[ptr WebKitWebView](view.platformView)
  let changed = g_signal_connect_data(
    webView,
    "load-changed",
    cast[pointer](linuxLoadChanged),
    cast[pointer](view),
    nil,
    0
  )
  if changed == 0:
    return failure(nativeError(webViewError, "webview.onNavigationCompleted",
      detail = "WebKitGTK load-changed signal registration failed"))
  let failed = g_signal_connect_data(
    webView,
    "load-failed",
    cast[pointer](linuxLoadFailed),
    cast[pointer](view),
    nil,
    0
  )
  if failed == 0:
    g_signal_handler_disconnect(webView, changed)
    return failure(nativeError(webViewError, "webview.onNavigationCompleted",
      detail = "WebKitGTK load-failed signal registration failed"))
  view.loadChangedSignalHandler = changed
  view.loadFailedSignalHandler = failed
  success()

proc linuxDecidePolicy(webView: pointer; policyDecision: pointer;
                       decisionType: cint; userData: pointer): cint {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view.isNil or view.state in {closing, closed}:
    return 0
  let decision = cast[ptr WebKitPolicyDecision](policyDecision)
  case decisionType
  of 0: # WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION
    let navigation = cast[ptr WebKitNavigationPolicyDecision](policyDecision)
    let action = webkit_navigation_policy_decision_get_navigation_action(navigation)
    let request = if action.isNil: nil else: webkit_navigation_action_get_request(action)
    let uri = if request.isNil: nil else: webkit_uri_request_get_uri(request)
    let copiedUri = if uri.isNil: "" else: $uri
    if view.dispatchNavigationStarting(copiedUri):
      webkit_policy_decision_use(decision)
    else:
      webkit_policy_decision_ignore(decision)
  of 1: # WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION
    let navigation = cast[ptr WebKitNavigationPolicyDecision](policyDecision)
    let action = webkit_navigation_policy_decision_get_navigation_action(navigation)
    let request = if action.isNil: nil else: webkit_navigation_action_get_request(action)
    let uri = if request.isNil: nil else: webkit_uri_request_get_uri(request)
    let copiedUri = if uri.isNil: "" else: $uri
    if view.dispatchNewWindowRequested(copiedUri):
      webkit_policy_decision_ignore(decision)
    else:
      ## A false application decision delegates to WebKitGTK's normal policy
      ## path. The create signal still returns nil unless the application
      ## supplies a managed WebView through the higher-level API.
      webkit_policy_decision_use(decision)
  of 2: # WEBKIT_POLICY_DECISION_TYPE_RESPONSE
    let response = cast[ptr WebKitResponsePolicyDecision](policyDecision)
    if webkit_response_policy_decision_is_mime_type_supported(response) != 0:
      ## A normal response must continue to load. Only unsupported MIME types
      ## are download candidates.
      webkit_policy_decision_use(decision)
    else:
      let request = webkit_response_policy_decision_get_request(response)
      let uri = if request.isNil: nil else: webkit_uri_request_get_uri(request)
      let copiedUri = if uri.isNil: "" else: $uri
      if view.dispatchDownloadStarting(copiedUri):
        ## A response policy is a download, not a navigable document. Starting
        ## it explicitly prevents WebKitGTK from treating the response as a
        ## failed page navigation. Destination/progress management remains a
        ## higher-level Core concern.
        let download = webkit_web_view_download_uri(cast[ptr WebKitWebView](webView), copiedUri.cstring)
        if not download.isNil:
          let destination = view.dispatchDownloadPath(copiedUri)
          if destination.len > 0:
            var conversionError: ptr GError
            let fileUri = g_filename_to_uri(destination.cstring, nil, addr conversionError)
            if fileUri.isNil:
              if conversionError != nil:
                g_error_free(conversionError)
              view.dispatchError(nativeError(osError, "webview.downloadPath",
                detail = "unable to convert download path to a file URI"))
            else:
              webkit_download_set_destination(download, fileUri)
              g_free(cast[pointer](fileUri))
        view.linuxTrackDownload(download, copiedUri)
        view.dispatchDownloadEvent(copiedUri, nativeDownloadStarted, 0.0)
      webkit_policy_decision_ignore(decision)
  else:
    return 0
  ## The decision was handled explicitly above.
  1

proc linuxClearDownloadSignals(view: NativeWebView) =
  if view.isNil or view.platformView.isNil:
    return
  for handler in view.downloadSignalHandlers:
    g_signal_handler_disconnect(view.activeDownload, handler)
  view.downloadSignalHandlers.setLen(0)
  view.activeDownload = nil
  view.activeDownloadUrl.setLen(0)

proc linuxDownloadProgress(download, pspec, userData: pointer) {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view.isNil or view.activeDownload != download:
    return
  let progress = float(webkit_download_get_estimated_progress(download))
  view.dispatchDownloadEvent(view.activeDownloadUrl, nativeDownloadProgress, progress)

proc linuxDownloadFinished(download, userData: pointer) {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view.isNil or view.activeDownload != download:
    return
  let url = view.activeDownloadUrl
  view.linuxClearDownloadSignals()
  view.dispatchDownloadEvent(url, nativeDownloadCompleted, 1.0)

proc linuxDownloadFailed(download, error, userData: pointer) {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view.isNil or view.activeDownload != download:
    return
  let url = view.activeDownloadUrl
  view.linuxClearDownloadSignals()
  view.dispatchDownloadEvent(url, nativeDownloadFailed, -1.0)

proc linuxTrackDownload(view: NativeWebView; download: pointer; url: string) =
  if view.isNil or download.isNil:
    return
  view.linuxClearDownloadSignals()
  view.activeDownload = download
  view.activeDownloadUrl = url
  view.downloadSignalHandlers.add(g_signal_connect_data(download,
    "notify::estimated-progress", cast[pointer](linuxDownloadProgress),
    cast[pointer](view), nil, 0))
  view.downloadSignalHandlers.add(g_signal_connect_data(download, "finished",
    cast[pointer](linuxDownloadFinished), cast[pointer](view), nil, 0))
  view.downloadSignalHandlers.add(g_signal_connect_data(download, "failed",
    cast[pointer](linuxDownloadFailed), cast[pointer](view), nil, 0))

proc linuxConfigureNavigationStarting(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.onNavigationStarting"))
  let signal = g_signal_connect_data(
    view.platformView,
    "decide-policy",
    cast[pointer](linuxDecidePolicy),
    cast[pointer](view),
    nil,
    0
  )
  if signal == 0:
    return failure(nativeError(webViewError, "webview.onNavigationStarting",
      detail = "WebKitGTK decide-policy signal registration failed"))
  view.policyDecisionSignalHandler = signal
  success()

proc linuxPermissionKind(request: ptr WebKitPermissionRequest): string =
  if request.isNil:
    return "unknown"
  let raw = cast[pointer](request)
  if g_type_check_instance_is_a(raw, webkit_user_media_permission_request_get_type()) != 0:
    ## A WebKitGTK user-media request may contain multiple device classes. A
    ## combined request cannot be represented by one PermissionKind, so fail
    ## closed instead of turning a camera+microphone request into an implicit
    ## grant for only one class.
    let audio = webkit_user_media_permission_is_for_audio_device(raw) != 0
    let video = webkit_user_media_permission_is_for_video_device(raw) != 0
    let display = webkit_user_media_permission_is_for_display_device(raw) != 0
    if (audio and video) or (audio and display) or (video and display):
      return "unknown"
    if video:
      return "camera"
    if audio:
      return "microphone"
    if display:
      return "screenCapture"
  if g_type_check_instance_is_a(raw, webkit_geolocation_permission_request_get_type()) != 0:
    return "geolocation"
  if g_type_check_instance_is_a(raw, webkit_notification_permission_request_get_type()) != 0:
    return "notifications"
  if g_type_check_instance_is_a(raw, webkit_clipboard_permission_request_get_type()) != 0:
    return "clipboard"
  "unknown"

proc linuxPermissionRequested(webView: pointer; request: ptr WebKitPermissionRequest;
                              userData: pointer): cint {.cdecl.} =
  let view = cast[NativeWebView](userData)
  let uri = webkit_web_view_get_uri(cast[ptr WebKitWebView](webView))
  let allowed = if uri.isNil: false else: view.dispatchPermissionRequested(
    linuxPermissionKind(request), $uri)
  if not request.isNil:
    if allowed:
      webkit_permission_request_allow(request)
    else:
      webkit_permission_request_deny(request)
  1

proc linuxConfigurePermissionRequests(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.permissionRequested"))
  let signal = g_signal_connect_data(
    view.platformView,
    "permission-request",
    cast[pointer](linuxPermissionRequested),
    cast[pointer](view),
    nil,
    0
  )
  if signal == 0:
    return failure(nativeError(webViewError, "webview.permissionRequested",
      detail = "WebKitGTK permission-request signal registration failed"))
  view.permissionSignalHandler = signal
  success()

proc linuxCreateRequested(webView: pointer; action: ptr WebKitNavigationAction;
                          userData: pointer): pointer {.cdecl.} =
  let view = cast[NativeWebView](userData)
  if view != nil and view.state notin {closing, closed}:
    let request = if action.isNil: nil else: webkit_navigation_action_get_request(action)
    let uri = if request.isNil: nil else: webkit_uri_request_get_uri(request)
    discard view.dispatchNewWindowRequested(if uri.isNil: "" else: $uri)
  ## Nimino does not create an implicit Window/WebView for window.open().
  nil

proc linuxConfigureNewWindowRequested(view: NativeWebView): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.onNewWindowRequested"))
  let signal = g_signal_connect_data(
    view.platformView,
    "create",
    cast[pointer](linuxCreateRequested),
    cast[pointer](view),
    nil,
    0
  )
  if signal == 0:
    return failure(nativeError(webViewError, "webview.onNewWindowRequested",
      detail = "WebKitGTK create signal registration failed"))
  view.createSignalHandler = signal
  success()

proc linuxDisposeMessageBridge(view: NativeWebView) =
  if view.platformMessageManager.isNil:
    return
  let manager = cast[ptr WebKitUserContentManager](view.platformMessageManager)
  if view.messageSignalHandler != 0:
    g_signal_handler_disconnect(manager, view.messageSignalHandler)
    view.messageSignalHandler = 0
  if view.messageRegistered:
    webkit_user_content_manager_unregister_script_message_handler(manager, "nimino", nil)
    view.messageRegistered = false
  view.platformMessageManager = nil

proc linuxDisposeLoadEvents(view: NativeWebView) =
  if view.platformView.isNil:
    return
  let webView = cast[ptr WebKitWebView](view.platformView)
  if view.loadChangedSignalHandler != 0:
    g_signal_handler_disconnect(webView, view.loadChangedSignalHandler)
    view.loadChangedSignalHandler = 0
  if view.loadFailedSignalHandler != 0:
    g_signal_handler_disconnect(webView, view.loadFailedSignalHandler)
    view.loadFailedSignalHandler = 0
  if view.policyDecisionSignalHandler != 0:
    g_signal_handler_disconnect(webView, view.policyDecisionSignalHandler)
    view.policyDecisionSignalHandler = 0
  if view.permissionSignalHandler != 0:
    g_signal_handler_disconnect(webView, view.permissionSignalHandler)
    view.permissionSignalHandler = 0
  if view.createSignalHandler != 0:
    g_signal_handler_disconnect(webView, view.createSignalHandler)
    view.createSignalHandler = 0

proc linuxEvaluationCompleted(sourceObject: pointer; asyncResult: ptr GAsyncResult;
                              userData: pointer) {.cdecl.} =
  let request = cast[NativeScriptRequest](userData)
  if request.isNil:
    return
  if request.view.isNil:
    GC_unref(request)
    return
  let view = request.view
  var error: ptr GError
  let value = webkit_web_view_evaluate_javascript_finish(
    cast[ptr WebKitWebView](sourceObject), asyncResult, addr error
  )
  if value.isNil:
    if error != nil:
      g_error_free(error)
    view.completeScriptRequest(request, failureOf[string](nativeError(
      webViewError, "webview.evalJavaScript", detail = "WebKitGTK evaluation failed"
    )))
    GC_unref(request)
    return

  let context = jsc_value_get_context(value)
  let exception =
    if context.isNil: nil
    else: jsc_context_get_exception(context)
  if exception != nil:
    let message = jsc_exception_get_message(exception)
    let detail = if message.isNil: "JavaScript evaluation failed" else: $message
    view.completeScriptRequest(request, failureOf[string](nativeError(
      webViewError, "webview.evalJavaScript", detail = detail
    )))
  else:
    let json = jsc_value_to_json(value, 0)
    if json.isNil:
      view.completeScriptRequest(request, failureOf[string](nativeError(
        webViewError, "webview.evalJavaScript", detail = "JavaScript result is not JSON serializable"
      )))
    else:
      let serialized = $json
      g_free(cast[pointer](json))
      view.completeScriptRequest(request, successOf(serialized))
  g_object_unref(value)
  GC_unref(request)

proc linuxEvalJavaScript(view: NativeWebView; request: NativeScriptRequest): NativeResult =
  if view.platformView.isNil:
    return failure(nativeError(invalidState, "webview.evalJavaScript"))
  GC_ref(request)
  let script = request.script
  webkit_web_view_evaluate_javascript(
    cast[ptr WebKitWebView](view.platformView),
    cstring(script),
    -1,
    nil,
    nil,
    nil,
    linuxEvaluationCompleted,
    cast[pointer](request)
  )
  success()

proc linuxDisposeView(view: NativeWebView) =
  if view.isNil or view.state == closed:
    return
  view.state = closing
  view.failOutstandingScripts(nativeError(invalidState, "webview.evalJavaScript"))
  view.failOutstandingBrowsingDataRequests(nativeError(invalidState,
    "webview.clearBrowsingData", detail = "the WebView closed before clearing completed"))
  view.linuxDisposeMessageBridge()
  view.linuxDisposeLoadEvents()
  view.linuxClearDownloadSignals()
  view.releaseCallbackReferences()
  if view.window.platformContainer != nil and view.platformView != nil:
    gtk_box_remove(view.window.platformContainer, view.platformView)
  if view.platformView != nil:
    g_object_unref(view.platformView)
    view.platformView = nil
  view.state = closed

proc linuxDisposeWindow(window: NativeWindow) =
  if window.state == closed:
    return

  window.state = closing
  window.dispatchClosed()
  for view in window.views:
    view.linuxDisposeView()

  if window.platformWindow != nil:
    if window.closeSignalHandler != 0:
      g_signal_handler_disconnect(window.platformWindow, window.closeSignalHandler)
      window.closeSignalHandler = 0
    if window.resizeSignalHandler != 0:
      g_signal_handler_disconnect(window.platformWindow, window.resizeSignalHandler)
      window.resizeSignalHandler = 0
    gtk_window_destroy(cast[ptr GtkWindow](window.platformWindow))
    g_object_unref(window.platformWindow)
    window.platformWindow = nil
  if window.platformContainer != nil:
    g_object_unref(window.platformContainer)
    window.platformContainer = nil
  window.state = closed

proc linuxCreateView(view: NativeWebView): NativeResult =
  if view.isNil or view.window.isNil or view.window.platformContainer.isNil:
    return failure(nativeError(invalidState, "webview.create"))
  var webView: ptr WebKitWebView
  var session: ptr WebKitNetworkSession
  if view.window.profilePath.len > 0:
    let dataDir = view.window.profilePath / "webkit-data"
    let cacheDir = view.window.profilePath / "cache"
    try:
      createDir(dataDir)
      createDir(cacheDir)
    except OSError:
      return failure(nativeError(osError, "webview.profile",
        detail = "unable to create WebKit profile directories"))
    session = webkit_network_session_new(cstring(dataDir), cstring(cacheDir))
    if session.isNil:
      return failure(nativeError(webViewError, "webview.profile",
        detail = "WebKitNetworkSession creation failed"))
    webView = cast[ptr WebKitWebView](g_object_new(webkit_web_view_get_type(),
      "network-session", cast[pointer](session), nil))
    g_object_unref(cast[pointer](session))
  else:
    webView = webkit_web_view_new()
  if webView.isNil:
    return failure(nativeError(webViewError, "webview.create",
      detail = "WebKitWebView creation failed"))

  view.platformView = g_object_ref_sink(cast[pointer](webView))
  view.state = ready
  let devTools = view.linuxSetDevToolsEnabled(view.devToolsEnabled)
  if not devTools.isOk: return devTools
  let messaging = view.linuxConfigureMessageBridge()
  if not messaging.isOk: return messaging
  let documentStartScript = view.linuxConfigureDocumentStartScript()
  if not documentStartScript.isOk: return documentStartScript
  let navigationEvents = view.linuxConfigureLoadEvents()
  if not navigationEvents.isOk: return navigationEvents
  let navigationStarting = view.linuxConfigureNavigationStarting()
  if not navigationStarting.isOk: return navigationStarting
  let permissionEvents = view.linuxConfigurePermissionRequests()
  if not permissionEvents.isOk: return permissionEvents
  let newWindowEvents = view.linuxConfigureNewWindowRequested()
  if not newWindowEvents.isOk: return newWindowEvents
  gtk_box_append(view.window.platformContainer, cast[pointer](webView))
  view.linuxLoadPendingContent()
  view.dispatchPendingScripts()
  success()

proc linuxCreateWindow(window: NativeWindow): NativeResult =
  let gtkWindow = gtk_application_window_new(cast[ptr GtkApplication](window.app.platformApp))
  if gtkWindow.isNil:
    return failure(nativeError(osError, "window.create", detail = "GTK Window creation failed"))

  window.platformWindow = g_object_ref_sink(cast[pointer](gtkWindow))
  let title = window.title
  gtk_window_set_title(gtkWindow, cstring(title))
  gtk_window_set_default_size(gtkWindow, cint(window.width), cint(window.height))
  if window.closeRequestedHandler != nil:
    let closeSignal = g_signal_connect_data(window.platformWindow, "close-request",
      cast[pointer](linuxCloseRequested), cast[pointer](window), nil, 0)
    if closeSignal == 0:
      return failure(nativeError(webViewError, "window.onCloseRequested"))
    window.closeSignalHandler = closeSignal
  if window.resizeHandler != nil:
    let resizeSignal = g_signal_connect_data(window.platformWindow, "notify::width",
      cast[pointer](linuxSizeNotify), cast[pointer](window), nil, 0)
    if resizeSignal == 0:
      return failure(nativeError(webViewError, "window.onResize"))
    window.resizeSignalHandler = resizeSignal
  if window.app.nativeMenuInstalled:
    ## GtkApplicationWindow only displays the model in-window when the shell
    ## does not export it. This makes the configured menu visible in ordinary
    ## GTK desktop sessions as well as in the Xvfb smoke environment.
    gtk_application_window_set_show_menubar(
      cast[ptr GtkApplicationWindow](gtkWindow), 1)

  let container = gtk_box_new(1, 0)
  if container.isNil:
    return failure(nativeError(osError, "window.create",
      detail = "GTK container creation failed"))
  window.platformContainer = g_object_ref_sink(container)
  gtk_window_set_child(gtkWindow, window.platformContainer)

  if window.views.len == 0:
    return failure(nativeError(invalidState, "window.create", detail = "WebView is required"))

  let view = window.views[0]
  var webView: ptr WebKitWebView
  var session: ptr WebKitNetworkSession
  if view.window.profilePath.len > 0:
    let dataDir = view.window.profilePath / "webkit-data"
    let cacheDir = view.window.profilePath / "cache"
    try:
      createDir(dataDir)
      createDir(cacheDir)
    except OSError:
      return failure(nativeError(osError, "webview.profile",
        detail = "unable to create WebKit profile directories"))
    session = webkit_network_session_new(cstring(dataDir), cstring(cacheDir))
    if session.isNil:
      return failure(nativeError(webViewError, "webview.profile",
        detail = "WebKitNetworkSession creation failed"))
    webView = cast[ptr WebKitWebView](g_object_new(webkit_web_view_get_type(),
      "network-session", cast[pointer](session), nil))
    g_object_unref(cast[pointer](session))
  else:
    webView = webkit_web_view_new()
  if webView.isNil:
    return failure(nativeError(webViewError, "webview.create", detail = "WebKitWebView creation failed"))

  view.platformView = g_object_ref_sink(cast[pointer](webView))
  view.state = ready
  let devTools = view.linuxSetDevToolsEnabled(view.devToolsEnabled)
  if not devTools.isOk:
    return devTools
  let messaging = view.linuxConfigureMessageBridge()
  if not messaging.isOk:
    return messaging
  let documentStartScript = view.linuxConfigureDocumentStartScript()
  if not documentStartScript.isOk:
    return documentStartScript
  let navigationEvents = view.linuxConfigureLoadEvents()
  if not navigationEvents.isOk:
    return navigationEvents
  let navigationStarting = view.linuxConfigureNavigationStarting()
  if not navigationStarting.isOk:
    return navigationStarting
  let permissionEvents = view.linuxConfigurePermissionRequests()
  if not permissionEvents.isOk:
    return permissionEvents
  let newWindowEvents = view.linuxConfigureNewWindowRequested()
  if not newWindowEvents.isOk:
    return newWindowEvents
  gtk_box_append(window.platformContainer, cast[pointer](webView))
  view.linuxLoadPendingContent()
  view.dispatchPendingScripts()
  if window.views.len > 1:
    for index in 1 ..< window.views.len:
      let created = window.views[index].linuxCreateView()
      if not created.isOk:
        return created
  window.state = ready
  gtk_window_present(gtkWindow)
  success()

proc linuxQuit(app: NativeApp) =
  for window in app.windows:
    window.linuxDisposeWindow()
  if app.platformApp != nil:
    g_application_quit(cast[ptr GApplication](app.platformApp))

proc linuxIdleTick(data: pointer): cint {.cdecl.} =
  let app = cast[NativeApp](data)
  if app.isNil or app.state != running:
    return 0
  if not app.dispatchUiTasks():
    app.linuxQuit()
    app.idleTimerSource = 0
    return 0
  if app.idleHandler != nil:
    try:
      app.idleHandler()
    except CatchableError:
      app.hasRunError = true
      app.runError = nativeError(osError, "app.idleHandler")
      app.quitRequested = true
      app.linuxQuit()
      app.idleTimerSource = 0
      return 0
  if app.quitRequested:
    app.idleTimerSource = 0
    return 0
  if app.idleHandler == nil and not app.hasUiTasks():
    app.idleTimerSource = 0
    return 0
  1

proc linuxActivate(application: pointer; data: pointer) {.cdecl.} =
  let app = cast[NativeApp](data)
  for window in app.windows:
    if window.state == pending:
      let createdWindow = window.linuxCreateWindow()
      if not createdWindow.isOk:
        app.quitRequested = true

  if app.quitRequested:
    app.linuxQuit()

proc linuxStartup(application: pointer; data: pointer) {.cdecl.} =
  let app = cast[NativeApp](data)
  if app.isNil or app.state != running:
    return
  let installed = app.linuxInstallNativeMenu()
  if not installed.isOk:
    app.hasRunError = true
    app.runError = installed.failure
    app.quitRequested = true
    g_application_quit(cast[ptr GApplication](application))

proc linuxRun(app: NativeApp): NativeResult =
  if app.platformApp.isNil:
    app.platformApp = cast[pointer](gtk_application_new(app.appId.cstring, 0))
  if app.platformApp.isNil:
    return failure(nativeError(osError, "app.run", detail = "GTK application creation failed"))

  app.state = running
  if app.idleHandler != nil or app.hasUiTasks():
    app.idleTimerSource = g_timeout_add(10, linuxIdleTick, cast[pointer](app))
    if app.idleTimerSource == 0:
      app.state = finished
      return failure(nativeError(osError, "app.setIdleHandler",
        detail = "GLib timeout source creation failed"))
  if app.nativeMenuConfigured:
    app.startupHandler = g_signal_connect_data(
      app.platformApp,
      "startup",
      cast[pointer](linuxStartup),
      cast[pointer](app),
      nil,
      0
    )
    if app.startupHandler == 0:
      if app.idleTimerSource != 0:
        discard g_source_remove(app.idleTimerSource)
        app.idleTimerSource = 0
      g_object_unref(app.platformApp)
      app.platformApp = nil
      app.state = finished
      return failure(nativeError(osError, "app.configureNativeMenu",
        detail = "GTK startup signal registration failed"))
  app.activateHandler = g_signal_connect_data(
    app.platformApp,
    "activate",
    cast[pointer](linuxActivate),
    cast[pointer](app),
    nil,
    0
  )

  let status = g_application_run(cast[ptr GApplication](app.platformApp), 0, nil)
  if app.activateHandler != 0:
    g_signal_handler_disconnect(app.platformApp, app.activateHandler)
    app.activateHandler = 0
  if app.startupHandler != 0:
    g_signal_handler_disconnect(app.platformApp, app.startupHandler)
    app.startupHandler = 0

  for window in app.windows:
    window.linuxDisposeWindow()

  if app.idleTimerSource != 0:
    discard g_source_remove(app.idleTimerSource)
    app.idleTimerSource = 0

  app.linuxUninstallNativeMenu()
  g_object_unref(app.platformApp)
  app.platformApp = nil
  app.nativeMenuItems.setLen(0)
  app.nativeMenuHandler = nil
  app.nativeMenuTitle.setLen(0)
  app.state = finished

  if app.hasRunError:
    return failure(app.runError)
  if status == 0:
    success()
  else:
    failure(nativeError(osError, "app.run", platformCode = int32(status)))
