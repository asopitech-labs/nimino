import std/strutils
import ../policy

## Pake event-link-guard parity. These functions are deliberately independent
## of a native WebView so all generated hosts share exactly the same boundary.
doAssert bypassLinkGuard("javascript:void(0)")
doAssert bypassLinkGuard("#captcha-confirm")
doAssert not bypassLinkGuard("https://example.com/account")
doAssert popupLinkDisposition(allowed = true, external = false,
  newWindow = false, authentication = false) == popupLinkExternal
doAssert popupLinkDisposition(allowed = true, external = false,
  newWindow = false, authentication = true) == popupLinkAllow
doAssert popupLinkDisposition(allowed = true, external = false,
  newWindow = true, authentication = false) == popupLinkAllow
doAssert popupLinkDisposition(allowed = false, external = false,
  newWindow = true, authentication = true) == popupLinkDeny
doAssert popupLinkDisposition(allowed = false, external = true,
  newWindow = false, authentication = false) == popupLinkExternal

doAssert safeDownloadLabel("report.pdf") == "report.pdf"
doAssert safeDownloadLabel("blob:https://example.test/123") ==
  "blob:https://example.test/123"
doAssert safeDownloadLabel("data:application/octet-stream;base64,AAAA") ==
  "data:application/octet-stream;base64,AAAA"
doAssert safeDownloadLabel("bad\nname") == "badname"
doAssert safeDownloadLabel("") == "download"
doAssert safeDownloadLabel("x".repeat(200)).len == 128

var sequence = 0
doAssert downloadNotificationId(sequence, "started") == "nimino-download-started-1"
doAssert downloadNotificationId(sequence, "completed") == "nimino-download-completed-2"
