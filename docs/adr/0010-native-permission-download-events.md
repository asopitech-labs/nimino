# ADR-0010: Native permission and download event bridge

## Status

Accepted — Linux API surface verified; implementation remains pending.

## Context

`nimino-core` already exposes explicit permission and download decisions with a
default-deny policy. The native backends do not yet expose the corresponding
OS/WebView events. Adding guessed callback names or opaque FFI declarations
would violate the project's direct-official-API requirement.

## Decision

Each backend must first pin and verify the official API surface, then add a
native event carrying the WebView identity, URL, request kind, and a one-shot
decision completion handle. The completion handle must default to deny when
the callback is not invoked, and must reject duplicate completion. Core will
map the event to `PermissionRequest` or `DownloadRequest`, invoke the Window
handler, and return the decision to native code on the UI thread.

Required verification sources:

- WebView2 SDK headers for `PermissionRequested` and download events.
- WebKitGTK headers for permission-requested and download-started signals.
- Backend-specific lifetime rules for event objects and completion callbacks.

The Docker development image currently exposes WebKitGTK 6.0's
`WebKitWebViewClass.permission_request` callback with signature
`gboolean (WebKitWebView*, WebKitPermissionRequest*)`. The request interface
provides the official `webkit_permission_request_allow()` and
`webkit_permission_request_deny()` completion functions. The response-policy
path also exposes `webkit_policy_decision_download()` for forced downloads.
These declarations are now confirmed from the installed headers; the Nim FFI
and lifetime bridge are the remaining implementation work.

The pinned WebView2 SDK header (`1.0.3967.48`) also confirms
`ICoreWebView2::add_PermissionRequested` and
`ICoreWebView2::add_DownloadStarting`, with separate event-handler and
event-argument COM interfaces. These interfaces require explicit COM
reference-counted callback objects; they must not be represented as a raw Nim
closure.

## Consequences

Until those headers are verified and implemented, permission and download
requests remain explicitly denied by the core policy layer. No backend may
silently allow or drop a request. The implementation is complete only after
Windows, Linux, and WSL relay tests prove grant, deny, timeout/default-deny,
and duplicate-completion behavior.
