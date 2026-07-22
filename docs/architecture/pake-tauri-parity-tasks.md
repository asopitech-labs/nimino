# Pake/Tauri parity task list

This checklist is for the Windows, native Linux, and WSL development branch.
macOS work is performed in a separate environment and is intentionally excluded.

## P0 — generated host correctness

- [ ] Add an explicit download policy to the generated `nimino-host`.
- [ ] Save accepted downloads into the profile download directory with collision-safe names.
- [ ] Forward download started/progress/completed/failed/cancelled events to the host policy layer.
- [ ] Add download status notifications without logging URLs, cookies, or credentials.
- [ ] Add Pake-compatible handling for `target=_blank`, `window.open`, OAuth redirects, and external URLs.
- [ ] Add generated-host tests for regular, `blob:`, and `data:` downloads.

## P0 — manifest and navigation contract

- [ ] Define a complete JSON schema for Nimino pack configuration.
- [ ] Reject unknown JSON fields instead of silently discarding them.
- [ ] Apply explicit CLI options over manifest values with deterministic precedence.
- [ ] Replace last-two-label site matching with URL-host boundary validation.
- [ ] Make `safe-domain` host-aware and resistant to userinfo/path look-alikes.
- [ ] Add unit tests for public-suffix-like hosts, subdomains, ports, and redirects.

## P1 — Pake wrapper features

- [ ] Add built-in browser shortcuts and runtime zoom controls.
- [ ] Add optional in-page Find UI and native menu actions.
- [ ] Add dark-mode preference, disabled web shortcuts, and activation shortcut capabilities.
- [ ] Add minimum window size and custom system-tray icon support.
- [ ] Add explicit `new-window` policy and preserve user-gesture popup semantics.
- [ ] Fetch a favicon automatically when no icon is supplied.

## P1 — packaging and release parity

- [ ] Add `app-version`, installer language, debug, iterative-build, keep-binary, and no-bundle controls.
- [ ] Add Linux zst and architecture-aware target parsing.
- [ ] Add Windows ARM64 target handling.
- [ ] Produce a complete Flatpak/AppImage release path or fail with a precise unsupported result.
- [ ] Add packaging tests for every accepted target and architecture.

## P1 — Tauri-inspired core facilities in Nimino scope

- [ ] Persist native window state (size, position, visibility) per profile.
- [ ] Add an authenticated update manifest and explicit update lifecycle API.
- [ ] Add autostart only through an explicit, capability-checked core API.
- [ ] Keep arbitrary shell/filesystem/plugin exposure out of the public API.

## Verification gates

- [ ] Each feature has unit coverage and Windows/Linux/WSL integration coverage.
- [ ] Native unsupported capabilities return explicit errors.
- [ ] Generated installers include checksum/SBOM validation.
- [ ] Windows GUI smoke tests clean up all popup and host processes on timeout.
- [ ] Update this checklist and the relevant ADR when a feature is completed or intentionally rejected.
