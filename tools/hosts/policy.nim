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

proc bypassLinkGuard*(href: string): bool =
  ## Pake leaves in-document fragments and JavaScript pseudo-links to the
  ## page.  They are not destinations for Nimino's native navigation policy.
  let normalized = href.strip().toLowerAscii()
  normalized.startsWith("javascript:") or normalized.startsWith("#")

proc popupLinkDisposition*(allowed, external, newWindow, authentication: bool):
    PopupLinkDisposition =
  ## Pake's generated-host contract: an allowed popup stays in-app only when
  ## the user enabled new windows or the target is an authentication flow.
  ## All other allowed `_blank` links use the system browser; explicit deny
  ## always wins over the WebView's native popup fallback.
  if external:
    return popupLinkExternal
  if not allowed:
    return popupLinkDeny
  if not newWindow and not authentication:
    return popupLinkExternal
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
