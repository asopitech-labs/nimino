proc linuxSetTitle(window: NativeWindow) =
  if window.platformWindow != nil:
    let title = window.title
    gtk_window_set_title(cast[ptr GtkWindow](window.platformWindow), cstring(title))

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

  g_object_unref(app.platformApp)
  app.platformApp = nil
  app.state = finished

  if status == 0:
    success()
  else:
    failure(nativeError(osError, "app.run", platformCode = int32(status)))
