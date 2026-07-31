## Pure generated-host policy helpers.  No native handles or UI state belong
## here, so download behavior can be tested without opening a window.

import std/strutils

type
  PopupLinkDisposition* = enum
    ## Consume the native popup request by opening an approved in-app window.
    popupLinkAllow
    ## Consume a rejected request without giving the WebView a second chance.
    popupLinkDeny
    ## Consume the request and use the system browser for the target.
    popupLinkExternal
    ## Consume the request and load the target in the requesting window.
    popupLinkNavigate

proc bypassLinkGuard*(href: string): bool =
  ## Pake leaves in-document fragments and JavaScript pseudo-links to the
  ## page.  They are not destinations for Nimino's native navigation policy.
  let normalized = href.strip().toLowerAscii()
  normalized.startsWith("javascript:") or normalized.startsWith("#")

proc popupLinkDisposition*(allowed, external, newWindow, authentication: bool;
                           blankPopup = false):
    PopupLinkDisposition =
  ## Pake's generated-host contract (src-tauri/src/inject/event.js): only an
  ## external target uses the system browser.  An internal target without
  ## `--new-window` navigates the requesting window in place — Pake retargets
  ## `_blank` anchors to `_self` and rewrites `window.open` to
  ## `window.location.href` — because handing an internal target to the
  ## system browser would strand SSO callbacks outside the app.  With
  ## `--new-window`, or for an authentication target, the popup opens as an
  ## explicit in-app window; explicit deny always wins over the WebView's
  ## native popup fallback.
  ## `about:blank` is an inert browser-created child document. It becomes an
  ## authentication popup only after a policy-checked redirect, so it must not
  ## be sent to the system browser merely because it has no hostname.
  if blankPopup:
    return popupLinkAllow
  if external:
    return popupLinkExternal
  if not allowed:
    return popupLinkDeny
  if not newWindow and not authentication:
    return popupLinkNavigate
  popupLinkAllow

proc safeDownloadLabel*(value: string): string =
  ## Notification text is user-visible but must not contain control characters
  ## or unbounded input from a remote Content-Disposition header.
  for character in value:
    if ord(character) >= 0x20 and ord(character) != 0x7f:
      result.add(character)
      if result.len >= 128:
        break
  if result.len == 0:
    result = "download"

proc downloadNotificationId*(sequence: var int; state: string): string =
  inc sequence
  "nimino-download-" & state & "-" & $sequence
