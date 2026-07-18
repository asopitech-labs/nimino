proc linuxSetTitle(window: NativeWindow) =
  if window.platformWindow != nil:
    let title = window.title
    gtk_window_set_title(cast[ptr GtkWindow](window.platformWindow), cstring(title))

proc linuxSetSize(window: NativeWindow) =
  if window.platformWindow != nil:
    gtk_window_set_default_size(cast[ptr GtkWindow](window.platformWindow),
      cint(window.width), cint(window.height))

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
    webkit_web_view_load_html(cast[ptr WebKitWebView](view.platformView), cstring(html), nil)

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
  if view.documentStartScript.len == 0:
    return success()
  let manager = webkit_web_view_get_user_content_manager(cast[ptr WebKitWebView](view.platformView))
  if manager.isNil:
    return failure(nativeError(webViewError, "webview.setDocumentStartScript",
      detail = "WebKitGTK user content manager is unavailable"))
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
  let navigation = cast[ptr WebKitNavigationPolicyDecision](policyDecision)
  let action = webkit_navigation_policy_decision_get_navigation_action(navigation)
  let decision = cast[ptr WebKitPolicyDecision](policyDecision)
  let request = if action.isNil: nil else: webkit_navigation_action_get_request(action)
  let uri = if request.isNil: nil else: webkit_uri_request_get_uri(request)
  let copiedUri = if uri.isNil: "" else: $uri
  case decisionType
  of 0: # WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION
    if view.dispatchNavigationStarting(copiedUri):
      webkit_policy_decision_use(decision)
    else:
      webkit_policy_decision_ignore(decision)
  of 1: # WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION
    view.dispatchNewWindowRequested(copiedUri)
    webkit_policy_decision_ignore(decision)
  of 2: # WEBKIT_POLICY_DECISION_TYPE_RESPONSE
    if view.dispatchDownloadStarting(copiedUri):
      ## A response policy is a download, not a navigable document.  Starting
      ## it explicitly prevents WebKitGTK from treating the response as a
      ## failed page navigation.  Destination/progress management remains a
      ## higher-level Core concern.
      discard webkit_web_view_download_uri(cast[ptr WebKitWebView](webView), copiedUri.cstring)
      webkit_policy_decision_ignore(decision)
    else:
      webkit_policy_decision_ignore(decision)
  else:
    return 0
  ## The decision was handled explicitly above.
  1

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

proc linuxPermissionRequested(webView: pointer; request: ptr WebKitPermissionRequest;
                              userData: pointer): cint {.cdecl.} =
  let view = cast[NativeWebView](userData)
  let uri = webkit_web_view_get_uri(cast[ptr WebKitWebView](webView))
  let allowed = if uri.isNil: false else: view.dispatchPermissionRequested($uri)
  if not allowed and not request.isNil:
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
    view.dispatchNewWindowRequested(if uri.isNil: "" else: $uri)
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

proc linuxDisposeWindow(window: NativeWindow) =
  if window.state == closed:
    return

  window.state = closing
  for view in window.views:
    view.failOutstandingScripts(nativeError(invalidState, "webview.evalJavaScript"))
    view.linuxDisposeMessageBridge()
    view.linuxDisposeLoadEvents()
    view.releaseCallbackReferences()
    if view.platformView != nil:
      g_object_unref(view.platformView)
      view.platformView = nil
    view.state = closed

  if window.platformWindow != nil:
    gtk_window_destroy(cast[ptr GtkWindow](window.platformWindow))
    g_object_unref(window.platformWindow)
    window.platformWindow = nil
  window.state = closed

proc linuxCreateWindow(window: NativeWindow): NativeResult =
  let gtkWindow = gtk_application_window_new(cast[ptr GtkApplication](window.app.platformApp))
  if gtkWindow.isNil:
    return failure(nativeError(osError, "window.create", detail = "GTK Window creation failed"))

  window.platformWindow = g_object_ref_sink(cast[pointer](gtkWindow))
  let title = window.title
  gtk_window_set_title(gtkWindow, cstring(title))
  gtk_window_set_default_size(gtkWindow, cint(window.width), cint(window.height))

  if window.views.len == 0:
    return failure(nativeError(invalidState, "window.create", detail = "WebView is required"))

  let view = window.views[0]
  let webView = webkit_web_view_new()
  if webView.isNil:
    return failure(nativeError(webViewError, "webview.create", detail = "WebKitWebView creation failed"))

  view.platformView = g_object_ref_sink(cast[pointer](webView))
  view.state = ready
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
  gtk_window_set_child(gtkWindow, cast[pointer](webView))
  view.linuxLoadPendingContent()
  view.dispatchPendingScripts()
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
  if app.idleHandler != nil:
    try:
      app.idleHandler()
    except CatchableError:
      app.hasRunError = true
      app.runError = nativeError(osError, "app.idleHandler")
      app.quitRequested = true
      app.linuxQuit()
      return 0
  if app.quitRequested:
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

proc linuxRun(app: NativeApp): NativeResult =
  if app.platformApp.isNil:
    app.platformApp = cast[pointer](gtk_application_new("tech.asopi.nimino.native", 0))
  if app.platformApp.isNil:
    return failure(nativeError(osError, "app.run", detail = "GTK application creation failed"))

  app.state = running
  if app.idleHandler != nil:
    app.idleTimerSource = g_timeout_add(10, linuxIdleTick, cast[pointer](app))
    if app.idleTimerSource == 0:
      app.state = finished
      return failure(nativeError(osError, "app.setIdleHandler",
        detail = "GLib timeout source creation failed"))
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

  for window in app.windows:
    window.linuxDisposeWindow()

  if app.idleTimerSource != 0:
    discard g_source_remove(app.idleTimerSource)
    app.idleTimerSource = 0

  g_object_unref(app.platformApp)
  app.platformApp = nil
  app.state = finished

  if app.hasRunError:
    return failure(app.runError)
  if status == 0:
    success()
  else:
    failure(nativeError(osError, "app.run", platformCode = int32(status)))
