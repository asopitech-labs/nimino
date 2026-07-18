import std/[os, strutils]

type
  ProfilePathResult* = object
    case isOk*: bool
    of true:
      value*: string
    of false:
      error*: string

proc profileSuccess(value: string): ProfilePathResult {.inline.} =
  ProfilePathResult(isOk: true, value: value)

proc profileFailure(detail: string): ProfilePathResult {.inline.} =
  ProfilePathResult(isOk: false, error: detail)

proc validPathComponent(value: string): bool =
  if value.len == 0 or value in [".", ".."]:
    return false
  for character in value:
    if not (character.isAlphaNumeric or character in {'-', '_', '.'}):
      return false
  true

proc profilePath*(appId, profile: string): ProfilePathResult =
  if not validPathComponent(appId):
    return profileFailure("application id contains an unsafe path component")
  if not validPathComponent(profile):
    return profileFailure("profile name contains an unsafe path component")
  let root = getConfigDir() / "nimino"
  profileSuccess(root / appId / profile)
