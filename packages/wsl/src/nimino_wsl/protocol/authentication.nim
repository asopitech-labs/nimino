import ./versioning

proc isHexDigit(value: char): bool {.inline.} =
  (value >= '0' and value <= '9') or
  (value >= 'a' and value <= 'f') or
  (value >= 'A' and value <= 'F')

proc isValidAuthenticationToken*(token: string): bool =
  ## The wire form is exactly 32 random bytes represented by 64 hex characters.
  if token.len != AuthenticationTokenHexLength:
    return false

  for value in token:
    if not value.isHexDigit:
      return false

  true

proc redactedToken*(token: string): string =
  ## Never return a token or a token prefix to logs or diagnostics.
  if token.len == 0:
    return "<none>"
  "<redacted>"
