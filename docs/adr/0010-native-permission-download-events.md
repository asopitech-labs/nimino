# ADR-0010: Native permission and download event bridge

## Status

Accepted — implementation pending official-header verification.

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

## Consequences

Until those headers are verified and implemented, permission and download
requests remain explicitly denied by the core policy layer. No backend may
silently allow or drop a request. The implementation is complete only after
Windows, Linux, and WSL relay tests prove grant, deny, timeout/default-deny,
and duplicate-completion behavior.
