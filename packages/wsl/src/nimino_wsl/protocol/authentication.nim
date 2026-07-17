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

proc secureEquals*(expected: string; actual: string): bool =
  ## Compare the complete wire token without returning at the first mismatch.
  var difference = expected.len xor actual.len
  let limit = max(expected.len, actual.len)
  for index in 0 ..< limit:
    let left = if index < expected.len: uint8(expected[index]) else: 0'u8
    let right = if index < actual.len: uint8(actual[index]) else: 0'u8
    difference = difference or int(left xor right)
  difference == 0
