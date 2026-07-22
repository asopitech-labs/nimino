## Pure generated-host policy helpers.  No native handles or UI state belong
## here, so download behavior can be tested without opening a window.

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
