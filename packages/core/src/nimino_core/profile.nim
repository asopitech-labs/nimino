import std/[algorithm, json, os, strutils, times]

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

proc profileDownloadPath*(appId, profile, suggestedName: string): ProfilePathResult =
  ## Return a safe path inside the profile download directory.  The caller
  ## still owns the actual write; an existing file is never selected.
  let directory = profileDirectoryPath(appId, profile, downloads)
  if not directory.isOk:
    return directory
  var name = suggestedName
  if name.len == 0:
    name = "download"
  name = name.replace('\\', '_').replace('/', '_').replace(':', '_')
  while name.len > 0 and name[^1] in {' ', '.'}:
    name.setLen(name.len - 1)
  while name.len > 1 and name.startsWith("."):
    name = name[1 .. ^1]
  if name.len == 0 or name in [".", ".."]:
    name = "download"
  let parts = splitFile(name)
  if parts.name.toUpperAscii() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4",
      "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5",
      "LPT6", "LPT7", "LPT8", "LPT9"]:
    name = "_" & name
  let safeParts = splitFile(name)
  var candidate = directory.value / name
  var suffix = 1
  while fileExists(candidate):
    candidate = directory.value / (safeParts.name & " (" & $suffix & ")" & safeParts.ext)
    inc suffix
  profileSuccess(candidate)

proc storeProfileDownload*(appId, profile, suggestedName, content: string): ProfilePathResult =
  let destination = profileDownloadPath(appId, profile, suggestedName)
  if not destination.isOk:
    return destination
  try:
    createDir(parentDir(destination.value))
    let temporary = destination.value & ".part"
    if fileExists(temporary): removeFile(temporary)
    writeFile(temporary, content)
    moveFile(temporary, destination.value)
    profileSuccess(destination.value)
  except OSError:
    profileFailure("unable to store profile download")

proc listProfileDownloads*(appId, profile: string): ProfileResult[seq[string]] =
  let directory = profileDirectoryPath(appId, profile, downloads)
  if not directory.isOk:
    return ProfileResult[seq[string]](isOk: false, error: directory.error)
  if not dirExists(directory.value):
    return ProfileResult[seq[string]](isOk: true, value: @[])
  try:
    var entries: seq[string]
    for path in walkDirRec(directory.value):
      if fileExists(path) and not path.endsWith(".part"):
        entries.add(path)
    entries.sort()
    ProfileResult[seq[string]](isOk: true, value: entries)
  except OSError:
    ProfileResult[seq[string]](isOk: false, error: "unable to list profile downloads")

proc deleteProfileDownload*(appId, profile, path: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, downloads)
  if not directory.isOk:
    return directory
  let candidate = absolutePath(path).normalizedPath()
  let root = absolutePath(directory.value).normalizedPath()
  let relative = relativePath(candidate, root)
  if relative == ".." or relative.startsWith(".." & DirSep) or relative.contains(DirSep):
    return profileFailure("download path is outside the profile directory")
  if not fileExists(candidate):
    return profileSuccess(candidate)
  try:
    removeFile(candidate)
    profileSuccess(candidate)
  except OSError:
    profileFailure("unable to delete profile download")

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

proc clearDirectoryContents(path: string) =
  ## Remove files and nested directories while preserving the profile root.
  for kind, entry in walkDir(path):
    case kind
    of pcFile, pcLinkToFile:
      removeFile(entry)
    of pcDir:
      clearDirectoryContents(entry)
      removeDir(entry)
    else:
      discard

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

proc clearProfileSettings*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, settings)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileSuccess(directory.value)
  try:
    for path in walkFiles(directory.value / "*.json"):
      removeFile(path)
    profileSuccess(directory.value)
  except OSError:
    profileFailure("unable to clear profile settings")

proc clearProfileCache*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, cache)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileSuccess(directory.value)
  try:
    clearDirectoryContents(directory.value)
    ## WebView2 stores browser cache below the profile user-data folder.
    ## Only known cache directories are removed; cookies and local storage
    ## remain intact.
    let root = profilePath(appId, profile)
    if not root.isOk:
      return profileFailure(root.error)
    let engineRoot = root.value / "webview2"
    for relative in ["Default" / "Cache", "Default" / "Code Cache",
                     "Default" / "GPUCache", "Default" / "DawnCache"]:
      let engineCache = engineRoot / relative
      if dirExists(engineCache):
        clearDirectoryContents(engineCache)
    profileSuccess(directory.value)
  except OSError:
    profileFailure("unable to clear profile cache")

proc clearProfileDownloads*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, downloads)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileSuccess(directory.value)
  try:
    clearDirectoryContents(directory.value)
    profileSuccess(directory.value)
  except OSError:
    profileFailure("unable to clear profile downloads")

proc clearProfilePermissions*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, permissions)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileSuccess(directory.value)
  try:
    clearDirectoryContents(directory.value)
    profileSuccess(directory.value)
  except OSError:
    profileFailure("unable to clear profile permissions")

proc clearProfileLocalStorage*(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, localStorage)
  if not directory.isOk:
    return directory
  if not dirExists(directory.value):
    return profileSuccess(directory.value)
  try:
    clearDirectoryContents(directory.value)
    profileSuccess(directory.value)
  except OSError:
    profileFailure("unable to clear profile local storage")

proc clearAllProfileData*(appId, profile: string): ProfilePathResult =
  let root = profilePath(appId, profile)
  if not root.isOk:
    return root
  if not dirExists(root.value):
    return profileSuccess(root.value)
  try:
    clearDirectoryContents(root.value)
    let recreated = ensureProfileLayout(appId, profile)
    if not recreated.isOk:
      return profileFailure(recreated.error)
    profileSuccess(root.value)
  except OSError:
    profileFailure("unable to clear profile data")

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
      if (requested == stored or requested.endsWith("." & stored)) and
          (loaded.value.expires <= 0 or loaded.value.expires > int64(epochTime())):
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
