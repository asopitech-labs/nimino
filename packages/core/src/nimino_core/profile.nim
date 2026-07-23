import std/[algorithm, json, os, strutils, times, uri]

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
    httpOnly*: bool
    expires*: int64

  ProfilePermission* = object
    ## A profile-scoped decision for one normalized web origin and permission
    ## kind.  The strings keep the persistence layer independent from the
    ## public Core enums while still restricting values at the write boundary.
    origin*: string
    kind*: string
    decision*: string

proc validCookieName(name: string): bool =
  ## RFC 6265 cookie-octet token, restricted to path-safe ASCII.
  if name.len == 0:
    return false
  for character in name:
    if not (character in {'!', '#', '$', '%', '&', '\'', '*', '+', '-','.',
        '^', '_', '`', '|', '~'} or character.isAlphaNumeric):
      return false
  true

proc parseCookieHeader*(header, domain, path: string; secure = false):
    ProfileResult[seq[ProfileCookie]] =
  ## Parse a Set-Cookie-style header into validated profile records.  Cookie
  ## attributes that require browser policy (SameSite, HttpOnly, Max-Age and
  ## Expires date parsing) are deliberately not guessed here; callers must
  ## apply those policies before persisting the returned records.
  if domain.len == 0 or path.len == 0 or not path.startsWith("/"):
    return ProfileResult[seq[ProfileCookie]](isOk: false,
      error: "cookie domain and absolute path are required")
  let first = header.split(';', maxsplit = 1)[0].strip()
  let separator = first.find('=')
  if separator <= 0:
    return ProfileResult[seq[ProfileCookie]](isOk: false,
      error: "cookie header must contain a name and value")
  let name = first[0 ..< separator].strip()
  let value = first[separator + 1 .. ^1].strip()
  if not validCookieName(name) or value.find({'\r', '\n', ';'}) >= 0:
    return ProfileResult[seq[ProfileCookie]](isOk: false,
      error: "cookie header contains unsafe characters")
  ProfileResult[seq[ProfileCookie]](isOk: true, value: @[
    ProfileCookie(name: name, value: value, domain: domain, path: path,
      secure: secure)])

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

proc downloadPathInDirectory*(directory, suggestedName: string): ProfilePathResult =
  ## Return a collision-safe path in an OS download directory.
  if directory.len == 0:
    return profileFailure("download directory must not be empty")
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
  var candidate = directory / name
  var suffix = 1
  while fileExists(candidate):
    candidate = directory / (safeParts.name & " (" & $suffix & ")" & safeParts.ext)
    inc suffix
  profileSuccess(candidate)

proc profileDownloadPath*(appId, profile, suggestedName: string): ProfilePathResult =
  ## Return a safe path inside the profile download directory.  The caller
  ## still owns the actual write; an existing file is never selected.
  let directory = profileDirectoryPath(appId, profile, downloads)
  if not directory.isOk:
    return directory
  downloadPathInDirectory(directory.value, suggestedName)

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
  if relative == ".." or relative.startsWith(".." & DirSep) or relative == ".":
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

proc atomicWrite(path, content: string): ProfilePathResult

proc normalizePermissionOrigin*(url: string): ProfileResult[string] =
  ## Persist decisions by origin, never by a full URL.  Query strings, paths,
  ## fragments, user information, and non-web schemes must not split or widen
  ## a permission grant.
  try:
    let parsed = parseUri(url)
    let scheme = parsed.scheme.toLowerAscii()
    if scheme notin ["http", "https"] or parsed.hostname.len == 0 or
        parsed.username.len > 0 or parsed.password.len > 0:
      return ProfileResult[string](isOk: false,
        error: "permission URL must be an absolute HTTP(S) origin")
    let host = if parsed.isIpv6:
        "[" & parsed.hostname.toLowerAscii() & "]"
      else:
        parsed.hostname.toLowerAscii()
    var origin = scheme & "://" & host
    if parsed.port.len > 0 and not
        ((scheme == "http" and parsed.port == "80") or
         (scheme == "https" and parsed.port == "443")):
      for character in parsed.port:
        if not character.isDigit:
          return ProfileResult[string](isOk: false,
            error: "permission URL port is invalid")
      origin.add(":" & parsed.port)
    ProfileResult[string](isOk: true, value: origin)
  except CatchableError:
    ProfileResult[string](isOk: false, error: "permission URL is invalid")

proc permissionStorePath(appId, profile: string): ProfilePathResult =
  let directory = profileDirectoryPath(appId, profile, permissions)
  if not directory.isOk:
    return directory
  profileSuccess(directory.value / "decisions.json")

proc readPermissionStore(appId, profile: string): ProfileResult[JsonNode] =
  let path = permissionStorePath(appId, profile)
  if not path.isOk:
    return ProfileResult[JsonNode](isOk: false, error: path.error)
  if not fileExists(path.value):
    return ProfileResult[JsonNode](isOk: true, value: %*{
      "version": 1,
      "decisions": {}
    })
  try:
    let document = parseJson(readFile(path.value))
    if document.kind != JObject or not document.hasKey("version") or
        document["version"].kind != JInt or document["version"].getInt() != 1 or
        not document.hasKey("decisions") or document["decisions"].kind != JObject:
      return ProfileResult[JsonNode](isOk: false,
        error: "profile permission store has an unsupported schema")
    ProfileResult[JsonNode](isOk: true, value: document)
  except CatchableError:
    ProfileResult[JsonNode](isOk: false,
      error: "profile permission store is not valid JSON")

proc validPermissionKind(kind: string): bool =
  kind.len > 0 and validSettingKey(kind)

proc writeProfilePermission*(appId, profile, url, kind, decision: string):
    ProfilePathResult =
  if not validPermissionKind(kind) or decision notin ["grant", "deny"]:
    return profileFailure("permission kind or decision is invalid")
  let origin = normalizePermissionOrigin(url)
  if not origin.isOk:
    return profileFailure(origin.error)
  let layout = ensureProfileLayout(appId, profile)
  if not layout.isOk:
    return layout
  let loaded = readPermissionStore(appId, profile)
  if not loaded.isOk:
    return profileFailure(loaded.error)
  var document = loaded.value
  if not document["decisions"].hasKey(origin.value):
    document["decisions"][origin.value] = newJObject()
  document["decisions"][origin.value][kind] = %decision
  let path = permissionStorePath(appId, profile)
  if not path.isOk:
    return path
  atomicWrite(path.value, $document)

proc readProfilePermission*(appId, profile, url, kind: string):
    ProfileResult[ProfilePermission] =
  if not validPermissionKind(kind):
    return ProfileResult[ProfilePermission](isOk: false,
      error: "permission kind is invalid")
  let origin = normalizePermissionOrigin(url)
  if not origin.isOk:
    return ProfileResult[ProfilePermission](isOk: false, error: origin.error)
  let loaded = readPermissionStore(appId, profile)
  if not loaded.isOk:
    return ProfileResult[ProfilePermission](isOk: false, error: loaded.error)
  let decisions = loaded.value["decisions"]
  if not decisions.hasKey(origin.value) or decisions[origin.value].kind != JObject or
      not decisions[origin.value].hasKey(kind) or
      decisions[origin.value][kind].kind != JString:
    return ProfileResult[ProfilePermission](isOk: false,
      error: "profile permission decision does not exist")
  let decision = decisions[origin.value][kind].getStr()
  if decision notin ["grant", "deny"]:
    return ProfileResult[ProfilePermission](isOk: false,
      error: "profile permission decision is invalid")
  ProfileResult[ProfilePermission](isOk: true, value: ProfilePermission(
    origin: origin.value, kind: kind, decision: decision))

proc listProfilePermissions*(appId, profile: string):
    ProfileResult[seq[ProfilePermission]] =
  let loaded = readPermissionStore(appId, profile)
  if not loaded.isOk:
    return ProfileResult[seq[ProfilePermission]](isOk: false, error: loaded.error)
  var entries: seq[ProfilePermission]
  for origin, decisions in loaded.value["decisions"]:
    if decisions.kind != JObject:
      return ProfileResult[seq[ProfilePermission]](isOk: false,
        error: "profile permission decision map is invalid")
    for kind, value in decisions:
      if not validPermissionKind(kind) or value.kind != JString or
          value.getStr() notin ["grant", "deny"]:
        return ProfileResult[seq[ProfilePermission]](isOk: false,
          error: "profile permission decision is invalid")
      entries.add(ProfilePermission(origin: origin, kind: kind,
        decision: value.getStr()))
  entries.sort(proc(left, right: ProfilePermission): int =
    let originOrder = cmp(left.origin, right.origin)
    if originOrder != 0: originOrder else: cmp(left.kind, right.kind))
  ProfileResult[seq[ProfilePermission]](isOk: true, value: entries)

proc deleteProfilePermission*(appId, profile, url, kind: string):
    ProfilePathResult =
  if not validPermissionKind(kind):
    return profileFailure("permission kind is invalid")
  let origin = normalizePermissionOrigin(url)
  if not origin.isOk:
    return profileFailure(origin.error)
  let loaded = readPermissionStore(appId, profile)
  if not loaded.isOk:
    return profileFailure(loaded.error)
  var document = loaded.value
  if not document["decisions"].hasKey(origin.value) or
      document["decisions"][origin.value].kind != JObject or
      not document["decisions"][origin.value].hasKey(kind):
    return profileFailure("profile permission decision does not exist")
  document["decisions"][origin.value].delete(kind)
  if document["decisions"][origin.value].len == 0:
    document["decisions"].delete(origin.value)
  let path = permissionStorePath(appId, profile)
  if not path.isOk:
    return path
  atomicWrite(path.value, $document)

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
  ## This is intentionally limited to Nimino-managed profile directories.
  ## `webview2` is a live WebView2 user-data folder, not a generic cache
  ## directory; clearing it while a controller is active can corrupt the
  ## browser session.  Engine data needs the native Profile API instead.
  let root = profilePath(appId, profile)
  if not root.isOk:
    return root
  if not dirExists(root.value):
    return profileSuccess(root.value)
  try:
    for directory in ProfileDirectory:
      let path = root.value / $directory
      if dirExists(path):
        clearDirectoryContents(path)
    let recreated = ensureProfileLayout(appId, profile)
    if not recreated.isOk:
      return profileFailure(recreated.error)
    profileSuccess(root.value)
  except OSError:
    profileFailure("unable to clear profile data")

proc cookieFileKey(cookie: ProfileCookie): string =
  let normalizedPath = if cookie.path.len == 0: "/" else: cookie.path
  if normalizedPath == "/":
    ## Preserve the original root-path filename so existing profiles and the
    ## public listing remain compatible.
    return cookie.domain & "__" & cookie.name
  var domainHex, nameHex, pathHex: string
  for character in cookie.domain:
    domainHex.add(toHex(ord(character), 2))
  for character in cookie.name:
    nameHex.add(toHex(ord(character), 2))
  for character in normalizedPath:
    pathHex.add(toHex(ord(character), 2))
  ## Cookie identity is (name, domain, path). Hex-encoded length-independent
  ## components avoid path traversal and delimiter collisions.
  "v2_" & domainHex & "_" & nameHex & "_" & pathHex

proc cookiePath(appId, profile: string; cookie: ProfileCookie): ProfilePathResult =
  if not validCookieName(cookie.name) or not validSettingKey(cookie.domain):
    return profileFailure("cookie name or domain contains an unsafe component")
  let directory = profileDirectoryPath(appId, profile, cookies)
  if not directory.isOk:
    return directory
  profileSuccess(directory.value / (cookie.cookieFileKey() & ".json"))

proc writeProfileCookie*(appId, profile: string;
                        cookie: ProfileCookie): ProfilePathResult =
  if cookie.value.find(';') >= 0 or cookie.value.find('\r') >= 0 or
      cookie.value.find('\n') >= 0:
    return profileFailure("cookie value contains unsafe delimiter characters")
  if cookie.path.len > 0 and not cookie.path.startsWith("/"):
    return profileFailure("cookie path must start with '/'")
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
    var document = parseJson(readFile(path.value))
    ## `httpOnly` was added when Core gained a direct browser CookieManager.
    ## Keep profiles written by the earlier document.cookie implementation
    ## readable; absence meant a script-visible, non-HttpOnly cookie.
    if document.kind == JObject and not document.hasKey("httpOnly"):
      document["httpOnly"] = %false
    let cookie = to(document, ProfileCookie)
    ProfileResult[ProfileCookie](isOk: true, value: cookie)
  except CatchableError:
    ProfileResult[ProfileCookie](isOk: false, error: "profile cookie is not valid JSON")

proc readProfileCookie*(appId, profile, domain, name, path: string):
    ProfileResult[ProfileCookie] =
  ## Path-aware overload for the complete RFC cookie identity. The four-
  ## argument overload remains the root-path compatibility API.
  let cookie = ProfileCookie(domain: domain, name: name, path: path)
  let file = cookiePath(appId, profile, cookie)
  if not file.isOk:
    return ProfileResult[ProfileCookie](isOk: false, error: file.error)
  if not fileExists(file.value):
    return ProfileResult[ProfileCookie](isOk: false,
      error: "profile cookie does not exist")
  try:
    var document = parseJson(readFile(file.value))
    if document.kind == JObject and not document.hasKey("httpOnly"):
      document["httpOnly"] = %false
    let loaded = to(document, ProfileCookie)
    ProfileResult[ProfileCookie](isOk: true, value: loaded)
  except CatchableError:
    ProfileResult[ProfileCookie](isOk: false,
      error: "profile cookie is not valid JSON")

proc profileCookieFiles(appId, profile: string): ProfileResult[seq[string]] =
  let directory = profileDirectoryPath(appId, profile, cookies)
  if not directory.isOk:
    return ProfileResult[seq[string]](isOk: false, error: directory.error)
  if not dirExists(directory.value):
    return ProfileResult[seq[string]](isOk: true, value: @[])
  try:
    var files: seq[string]
    for path in walkFiles(directory.value / "*.json"):
      files.add(path)
    files.sort()
    ProfileResult[seq[string]](isOk: true, value: files)
  except OSError:
    ProfileResult[seq[string]](isOk: false,
      error: "unable to list profile cookies")

proc readProfileCookieFile(path: string): ProfileResult[ProfileCookie] =
  try:
    var document = parseJson(readFile(path))
    if document.kind == JObject and not document.hasKey("httpOnly"):
      document["httpOnly"] = %false
    ProfileResult[ProfileCookie](isOk: true,
      value: to(document, ProfileCookie))
  except CatchableError:
    ProfileResult[ProfileCookie](isOk: false,
      error: "profile cookie is not valid JSON")

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
  let files = profileCookieFiles(appId, profile)
  if not files.isOk:
    return ProfileResult[seq[ProfileCookie]](isOk: true, value: @[])
  let requested = domain.toLowerAscii().strip(chars = {'.'})
  var matches: seq[ProfileCookie]
  for path in files.value:
    let loaded = readProfileCookieFile(path)
    if loaded.isOk:
      let stored = loaded.value.domain.toLowerAscii().strip(chars = {'.'})
      if (requested == stored or requested.endsWith("." & stored)) and
          (loaded.value.expires <= 0 or loaded.value.expires > int64(epochTime())):
        matches.add(loaded.value)
  ProfileResult[seq[ProfileCookie]](isOk: true, value: matches)

proc profileCookiesForUrl*(appId, profile, url: string): ProfileResult[seq[ProfileCookie]] =
  ## Apply domain, path, secure, and expiry rules for an HTTP(S) request URL.
  try:
    let parsed = parseUri(url)
    let scheme = parsed.scheme.toLowerAscii()
    if scheme notin ["http", "https"] or parsed.hostname.len == 0:
      return ProfileResult[seq[ProfileCookie]](isOk: false,
        error: "cookie URL must use http or https")
    let requestedDomain = parsed.hostname.toLowerAscii().strip(chars = {'.'})
    let requestedPath = if parsed.path.len == 0: "/" else: parsed.path
    let files = profileCookieFiles(appId, profile)
    if not files.isOk:
      return ProfileResult[seq[ProfileCookie]](isOk: true, value: @[])
    var matches: seq[ProfileCookie]
    for path in files.value:
      let loaded = readProfileCookieFile(path)
      if not loaded.isOk:
        continue
      let cookie = loaded.value
      let storedDomain = cookie.domain.toLowerAscii().strip(chars = {'.'})
      let domainMatches = requestedDomain == storedDomain or
        requestedDomain.endsWith("." & storedDomain)
      let cookiePath = if cookie.path.len == 0: "/" else: cookie.path
      let pathMatches = requestedPath == cookiePath or
        (requestedPath.len > cookiePath.len and requestedPath.startsWith(cookiePath) and
         (cookiePath.endsWith("/") or requestedPath[cookiePath.len] == '/'))
      if domainMatches and pathMatches and (not cookie.secure or scheme == "https") and
          (cookie.expires <= 0 or cookie.expires > int64(epochTime())):
        matches.add(cookie)
    ProfileResult[seq[ProfileCookie]](isOk: true, value: matches)
  except CatchableError:
    ProfileResult[seq[ProfileCookie]](isOk: false, error: "cookie URL is invalid")

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

proc deleteProfileCookie*(appId, profile, domain, name, path: string):
    ProfilePathResult =
  let file = cookiePath(appId, profile,
    ProfileCookie(domain: domain, name: name, path: path))
  if not file.isOk:
    return file
  if not fileExists(file.value):
    return profileFailure("profile cookie does not exist")
  try:
    removeFile(file.value)
    profileSuccess(file.value)
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
