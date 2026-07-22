# ADR 0020: Update authentication and autostart boundary

## Status

Accepted for the Windows, native Linux, and WSL branch.

## Decision

`nimino-core` owns an explicit update lifecycle, but it does not fetch or
execute an installer. An update manifest must contain an HTTPS URL, a SHA-256
digest, a detached signature, and a key ID. The application supplies an
`UpdateSignatureVerifier`; an unverified manifest cannot enter
`updateAvailable`. Downloading and installer execution remain host/packager
responsibilities so a WebView cannot turn an arbitrary URL into an update.

Autostart has one Core entry point, `app.setAutostart(enabled)`, guarded by the
`Capability.autostart` advertisement. Windows, Linux, and WSL currently do not
advertise it and return `platformUnavailable`. No shell command, startup-file
write, or hidden fallback is allowed. A future native implementation must
advertise the capability only after its ownership, uninstall, and failure
semantics are tested on each target.

## Consequences

- Update cryptography and key rotation remain under application control.
- Core can enforce lifecycle and state transitions without pretending to have a
  portable installer format.
- Callers receive an explicit unsupported result instead of a successful no-op.
