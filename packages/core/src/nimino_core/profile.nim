import std/[json, os, strutils]

type
  ProfilePathResult* = object
    case isOk*: bool
    of true:
      value*: string
    of false:
      error*: string

  ProfileDirectory* = enum
    cookies
    localStorage
    cache
    permissions
    downloads
    settings

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

proc profileDirectoryPath*(appId, profile: string;
                           directory: ProfileDirectory): ProfilePathResult =
  let root = profilePath(appId, profile)
  if not root.isOk:
    return root
  profileSuccess(root.value / $directory)

proc ensureProfileLayout*(appId, profile: string): ProfilePathResult =
  ## Create the complete persistent profile layout in an idempotent manner.
  let root = profilePath(appId, profile)
  if not root.isOk:
    return root
  try:
    for directory in ProfileDirectory:
      createDir(root.value / $directory)
    profileSuccess(root.value)
  except OSError:
    profileFailure("unable to create profile storage")

proc validSettingKey(key: string): bool =
  if key.len == 0 or key in [".", ".."]:
    return false
  for character in key:
    if not (character.isAlphaNumeric or character in {'-', '_', '.'}):
      return false
  true

proc profileSettingPath(appId, profile, key: string): ProfilePathResult =
  if not validSettingKey(key):
    return profileFailure("setting key contains an unsafe path component")
  let directory = profileDirectoryPath(appId, profile, settings)
  if not directory.isOk:
    return directory
  profileSuccess(directory.value / (key & ".json"))

proc writeProfileSetting*(appId, profile, key: string;
                         value: JsonNode): ProfilePathResult =
  let layout = ensureProfileLayout(appId, profile)
  if not layout.isOk:
    return layout
  let path = profileSettingPath(appId, profile, key)
  if not path.isOk:
    return path
  try:
    writeFile(path.value, $value)
    profileSuccess(path.value)
  except CatchableError:
    profileFailure("unable to write profile setting")

proc readProfileSetting*(appId, profile, key: string): ProfilePathResult =
  let path = profileSettingPath(appId, profile, key)
  if not path.isOk:
    return path
  if not fileExists(path.value):
    return profileFailure("profile setting does not exist")
  try:
    discard parseJson(readFile(path.value))
    profileSuccess(readFile(path.value))
  except CatchableError:
    profileFailure("profile setting is not valid JSON")
