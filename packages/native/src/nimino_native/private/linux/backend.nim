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

proc linuxDisposeWindow(window: NativeWindow) =
  if window.state == closed:
    return

  window.state = closing
  for view in window.views:
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
  gtk_window_set_child(gtkWindow, cast[pointer](webView))
  view.linuxLoadPendingContent()
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
