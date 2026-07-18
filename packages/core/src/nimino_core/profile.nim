import std/[algorithm, json, os, strutils]

type
  ProfilePathResult* = object
    case isOk*: bool
    of true:
      value*: string
    of false:
      error*: string

  ProfileResult*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      error*: string

  ProfileDirectory* = enum
    cookies
    localStorage
    cache
    permissions
    downloads
    settings

  ProfileCookie* = object
    name*: string
    value*: string
    domain*: string
    path*: string
    secure*: bool
    expires*: int64

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

proc atomicWrite(path, content: string): ProfilePathResult =
  let temporary = path & ".tmp-" & $getCurrentProcessId()
  try:
    writeFile(temporary, content)
    if fileExists(path):
      removeFile(path)
    moveFile(temporary, path)
    profileSuccess(path)
  except CatchableError:
    if fileExists(temporary):
      try: removeFile(temporary)
      except OSError: discard
    profileFailure("unable to atomically write profile data")

proc writeProfileSetting*(appId, profile, key: string;
                         value: JsonNode): ProfilePathResult =
  let layout = ensureProfileLayout(appId, profile)
  if not layout.isOk:
    return layout
  let path = profileSettingPath(appId, profile, key)
  if not path.isOk:
    return path
  atomicWrite(path.value, $value)

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

proc listProfileSettings*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, settings)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileFailure("profile settings directory does not exist")
  try:
    var keys: seq[string]
    for path in walkFiles(directory.value / "*.json"):
      keys.add(path.lastPathPart[0 ..< path.lastPathPart.len - 5])
    keys.sort()
    profileSuccess(keys.join("\n"))
  except OSError:
    profileFailure("unable to list profile settings")

proc deleteProfileSetting*(appId, profile, key: string): ProfilePathResult =
  let path = profileSettingPath(appId, profile, key)
  if not path.isOk:
    return path
  if not fileExists(path.value):
    return profileFailure("profile setting does not exist")
  try:
    removeFile(path.value)
    profileSuccess(path.value)
  except OSError:
    profileFailure("unable to delete profile setting")

proc cookieFileKey(cookie: ProfileCookie): string =
  cookie.domain & "__" & cookie.name

proc cookiePath(appId, profile: string; cookie: ProfileCookie): ProfilePathResult =
  if not validSettingKey(cookie.name) or not validSettingKey(cookie.domain):
    return profileFailure("cookie name or domain contains an unsafe component")
  let directory = profileDirectoryPath(appId, profile, cookies)
  if not directory.isOk:
    return directory
  profileSuccess(directory.value / (cookie.cookieFileKey() & ".json"))

proc writeProfileCookie*(appId, profile: string;
                        cookie: ProfileCookie): ProfilePathResult =
  let layout = ensureProfileLayout(appId, profile)
  if not layout.isOk:
    return layout
  let path = cookiePath(appId, profile, cookie)
  if not path.isOk:
    return path
  atomicWrite(path.value, $(%*cookie))

proc readProfileCookie*(appId, profile, domain, name: string):
    ProfileResult[ProfileCookie] =
  let path = cookiePath(appId, profile, ProfileCookie(domain: domain, name: name))
  if not path.isOk:
    return ProfileResult[ProfileCookie](isOk: false, error: path.error)
  if not fileExists(path.value):
    return ProfileResult[ProfileCookie](isOk: false, error: "profile cookie does not exist")
  try:
    let cookie = to(parseJson(readFile(path.value)), ProfileCookie)
    ProfileResult[ProfileCookie](isOk: true, value: cookie)
  except CatchableError:
    ProfileResult[ProfileCookie](isOk: false, error: "profile cookie is not valid JSON")

proc listProfileCookies*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, cookies)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileFailure("profile cookies directory does not exist")
  try:
    var keys: seq[string]
    for path in walkFiles(directory.value / "*.json"):
      keys.add(path.lastPathPart[0 ..< path.lastPathPart.len - 5])
    keys.sort()
    profileSuccess(keys.join("\n"))
  except OSError:
    profileFailure("unable to list profile cookies")

proc profileCookiesForDomain*(appId, profile, domain: string): ProfileResult[seq[ProfileCookie]] =
  if domain.len == 0:
    return ProfileResult[seq[ProfileCookie]](isOk: false, error: "cookie domain is empty")
  let listed = listProfileCookies(appId, profile)
  if not listed.isOk:
    return ProfileResult[seq[ProfileCookie]](isOk: true, value: @[])
  let requested = domain.toLowerAscii().strip(chars = {'.'})
  var matches: seq[ProfileCookie]
  for key in listed.value.splitLines():
    let separator = key.find("__")
    if separator <= 0:
      continue
    let cookieDomain = key[0 ..< separator]
    let cookieName = key[separator + 2 .. ^1]
    let loaded = readProfileCookie(appId, profile, cookieDomain, cookieName)
    if loaded.isOk:
      let stored = loaded.value.domain.toLowerAscii().strip(chars = {'.'})
      if requested == stored or requested.endsWith("." & stored):
        matches.add(loaded.value)
  ProfileResult[seq[ProfileCookie]](isOk: true, value: matches)

proc deleteProfileCookie*(appId, profile, domain, name: string): ProfilePathResult =
  let path = cookiePath(appId, profile, ProfileCookie(domain: domain, name: name))
  if not path.isOk:
    return path
  if not fileExists(path.value):
    return profileFailure("profile cookie does not exist")
  try:
    removeFile(path.value)
    profileSuccess(path.value)
  except OSError:
    profileFailure("unable to delete profile cookie")

proc clearProfileCookies*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, cookies)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileSuccess(directory.value)
  try:
    for path in walkFiles(directory.value / "*.json"):
      removeFile(path)
    profileSuccess(directory.value)
  except OSError:
    profileFailure("unable to clear profile cookies")
