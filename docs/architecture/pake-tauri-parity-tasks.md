# Pake/Tauri parity task list

This checklist covers the Windows, native Linux, WSL, and macOS development branches.
The macOS items below are verified by local AppKit/WKWebView and bundle smoke tests.

## macOS parity follow-up (2026-07-23)

- [x] Apply macOS 14+ WKWebView HTTP CONNECT/SOCKS5 proxy configuration at WebView construction time and reject unsupported runtime changes.
- [x] Restore hidden windows when the application is reopened from the Dock, matching Pake's `hide_on_close` lifecycle.
- [x] Implement Pake's `hide_title_bar` as a native title-bar overlay while preserving traffic-light controls.
- [x] Emit macOS camera/microphone usage metadata and entitlements when permissions are packaged.
- [x] Fail closed for unsupported macOS proxy schemes and set `LSMinimumSystemVersion` to 14.0 when a proxy is used.

## P0 — generated host correctness

- [x] Add an explicit download policy to the generated `nimino-host`.
- [x] Save accepted downloads into the profile download directory with collision-safe names.
- [x] Forward download started/progress/completed/failed/cancelled events to the host policy layer.
- [x] Add download status notifications without logging URLs, cookies, or credentials.
- [x] Add Pake-compatible handling for `target=_blank`, `window.open`, OAuth redirects, and external URLs.
- [x] Add generated-host policy tests for regular, `blob:`, and `data:` download labels; native download event integration remains backend-specific.

## P0 — manifest and navigation contract

- [x] Define a complete JSON schema for Nimino pack configuration.
- [x] Reject unknown JSON fields instead of silently discarding them.
- [x] Apply explicit CLI options over manifest values with deterministic precedence.
- [x] Replace last-two-label site matching with URL-host boundary validation.
- [x] Make `safe-domain` host-aware and resistant to userinfo/path look-alikes.
- [x] Add unit tests for public-suffix-like hosts, subdomains, ports, and redirects.

## P1 — Pake wrapper features

- [x] Add runtime zoom control API. Built-in browser shortcut wiring is explicitly rejected by the generated host until a native menu/shortcut backend exists.
- [x] Add native menu actions; in-page Find remains an explicit unsupported generated-host option.
- [x] Reject unsupported dark-mode, disabled web shortcuts, and activation shortcut options explicitly.
- [x] Reject unsupported minimum window size and custom system-tray icon options explicitly.
- [x] Add explicit `new-window` policy and preserve user-gesture popup semantics.
- [x] Fetch a bounded `https?://<host>/favicon.ico` automatically when no icon is supplied; a site without one remains valid and explicit icon failures remain fatal.

## P1 — packaging and release parity

- [x] Preserve and emit `app-version`, installer language, debug, iterative-build, and keep-binary metadata; `bundle=false` now fails explicitly for installer output instead of silently producing a partial bundle.
- [x] Add Linux zst and architecture-aware target parsing. (zst and unsupported architectures fail with explicit results until their native toolchains are available.)
- [x] Add Windows ARM64 target handling. (The target is recognized and fails closed unless an ARM64 host/signer is supplied.)
- [x] Produce a complete Flatpak/AppImage release path; dependency-closure failures return a precise unsupported/error result.
- [x] Add packaging tests for accepted deb/rpm/flatpak/appimage/zst and Windows nsis/msi targets, including amd64/x64 and explicit arm64 rejection.

## P1 — Tauri-inspired core facilities in Nimino scope

- [x] Persist native window state (size, position, visibility) per profile.
- [x] Add an authenticated update manifest and explicit update lifecycle API.
- [x] Add autostart only through an explicit, capability-checked core API; current backends return `platformUnavailable`.
- [x] Keep arbitrary shell/filesystem/plugin exposure out of the public API; Core exposes only validated HTTP(S) external navigation, profile-scoped files, and explicit RPC registrations.

## Verification gates

- [x] Platform-specific features have unit coverage plus Linux native, WSL fake-host/IPC, and Windows cross/GUI smoke coverage; platform-neutral update/policy APIs are exercised in the same matrix.
- [x] Native unsupported capabilities return explicit errors (including autostart and AppImage dependency closure).
- [x] Generated installers include checksum/SBOM validation and release manifests.
- [x] Windows GUI smoke tests clean up all popup and host processes on timeout via `finally`/`taskkill`.
- [x] Update this checklist and the relevant ADR when a feature is completed or intentionally rejected.
