import std/strutils
import ../policy

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
