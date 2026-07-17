## Minimal direct FFI surface for GTK 4, GLib, GObject, and WebKitGTK 6.0.
## These declarations are verified against the development headers in the Docker image.

const
  LibGtk = "libgtk-4.so.1"
  LibGio = "libgio-2.0.so.0"
  LibGObject = "libgobject-2.0.so.0"
  LibWebKit = "libwebkitgtk-6.0.so.4"

type
  GApplication* {.incompleteStruct.} = object
  GtkApplication* {.incompleteStruct.} = object
  GtkWindow* {.incompleteStruct.} = object
  WebKitWebView* {.incompleteStruct.} = object
  GClosureNotify* = proc(data: pointer; closure: pointer) {.cdecl.}

proc gtk_application_new*(applicationId: cstring; flags: cint): ptr GtkApplication
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_application_window_new*(application: ptr GtkApplication): ptr GtkWindow
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_set_title*(window: ptr GtkWindow; title: cstring)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_set_default_size*(window: ptr GtkWindow; width: cint; height: cint)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_set_child*(window: ptr GtkWindow; child: pointer)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_present*(window: ptr GtkWindow)
  {.cdecl, importc, dynlib: LibGtk.}
proc gtk_window_destroy*(window: ptr GtkWindow)
  {.cdecl, importc, dynlib: LibGtk.}

proc g_application_run*(application: ptr GApplication; argc: cint; argv: ptr cstring): cint
  {.cdecl, importc, dynlib: LibGio.}
proc g_application_quit*(application: ptr GApplication)
  {.cdecl, importc, dynlib: LibGio.}

proc g_object_ref_sink*(instance: pointer): pointer
  {.cdecl, importc, dynlib: LibGObject.}
proc g_object_unref*(instance: pointer)
  {.cdecl, importc, dynlib: LibGObject.}
proc g_signal_connect_data*(instance: pointer; detailedSignal: cstring;
                            callback: pointer; data: pointer;
                            destroyData: GClosureNotify; connectFlags: cint): culong
  {.cdecl, importc, dynlib: LibGObject.}
proc g_signal_handler_disconnect*(instance: pointer; handlerId: culong)
  {.cdecl, importc, dynlib: LibGObject.}

proc webkit_web_view_new*(): ptr WebKitWebView
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_load_uri*(view: ptr WebKitWebView; uri: cstring)
  {.cdecl, importc, dynlib: LibWebKit.}
proc webkit_web_view_load_html*(view: ptr WebKitWebView; content: cstring; baseUri: cstring)
  {.cdecl, importc, dynlib: LibWebKit.}
