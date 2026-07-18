import std/[json, os, strutils, times]

import nimino_core

block appOptionsAreValidated:
  let missingId = newApp(AppOptions(id: "", name: "Example"))
  doAssert not missingId.isOk
  doAssert missingId.failure.kind == invalidArgument

  let missingName = newApp(AppOptions(id: "tech.asopi.example", name: ""))
  doAssert not missingName.isOk
  doAssert missingName.failure.kind == invalidArgument

block profilePathsAreContainedAndSafe:
  let profile = profilePath("tech.asopi.example", "work")
  doAssert profile.isOk
  doAssert profile.value.endsWith("nimino" / "tech.asopi.example" / "work")
  doAssert not profilePath("../escape", "work").isOk
  doAssert not profilePath("tech.asopi.example", "../escape").isOk
  let storage = ensureProfileLayout("tech.asopi.profile-test", "work")
  doAssert storage.isOk
  for directory in ProfileDirectory:
    doAssert dirExists(storage.value / $directory)
  removeDir(storage.value)
  let written = writeProfileSetting("tech.asopi.profile-test", "work", "theme",
    %*{"dark": true})
  doAssert written.isOk
  let loaded = readProfileSetting("tech.asopi.profile-test", "work", "theme")
  doAssert loaded.isOk
  doAssert parseJson(loaded.value)["dark"].getBool()
  let listed = listProfileSettings("tech.asopi.profile-test", "work")
  doAssert listed.isOk
  doAssert listed.value == "theme"
  doAssert deleteProfileSetting("tech.asopi.profile-test", "work", "theme").isOk
  doAssert not readProfileSetting("tech.asopi.profile-test", "work", "theme").isOk
  doAssert not writeProfileSetting("tech.asopi.profile-test", "work", "../escape",
    newJNull()).isOk
  let downloadPath = profileDownloadPath("tech.asopi.profile-test", "work", "../report.txt")
  doAssert downloadPath.isOk
  doAssert downloadPath.value.endsWith("downloads" / "_report.txt")
  createDir(parentDir(downloadPath.value))
  writeFile(downloadPath.value, "existing")
  let collisionPath = profileDownloadPath("tech.asopi.profile-test", "work", "../report.txt")
  doAssert collisionPath.isOk
  doAssert collisionPath.value.endsWith("downloads" / "_report (1).txt")
  removeFile(downloadPath.value)
  let reservedPath = profileDownloadPath("tech.asopi.profile-test", "work", "CON.txt")
  doAssert reservedPath.isOk
  doAssert reservedPath.value.endsWith("downloads" / "_CON.txt")
  let storedPath = storeProfileDownload("tech.asopi.profile-test", "work", "payload.txt", "hello")
  doAssert storedPath.isOk
  doAssert readFile(storedPath.value) == "hello"
  doAssert not deleteProfileDownload("tech.asopi.profile-test", "work", getHomeDir() / "outside.txt").isOk
  doAssert deleteProfileDownload("tech.asopi.profile-test", "work", storedPath.value).isOk
  doAssert not fileExists(storedPath.value)
  let cookie = ProfileCookie(name: "sid", value: "abc", domain: "example.com",
    path: "/", secure: true, expires: int64(epochTime()) + 3600)
  doAssert writeProfileCookie("tech.asopi.profile-test", "work", cookie).isOk
  let loadedCookie = readProfileCookie("tech.asopi.profile-test", "work",
    "example.com", "sid")
  doAssert loadedCookie.isOk
  doAssert loadedCookie.value.value == "abc"
  let matchingCookies = profileCookiesForDomain("tech.asopi.profile-test", "work", "sub.example.com")
  doAssert matchingCookies.isOk
  doAssert matchingCookies.value.len == 1
  doAssert listProfileCookies("tech.asopi.profile-test", "work").value == "example.com__sid"
  doAssert deleteProfileCookie("tech.asopi.profile-test", "work", "example.com", "sid").isOk

block windowsOwnIndependentRpcAllowLists:
  let created = newApp(id = "tech.asopi.core-test", name = "Core test")
  doAssert created.isOk
  let app = created.value
  doAssert not app.isRunning()
  let multipleViews = app.supports(multipleWebViews)
  doAssert multipleViews.isOk

  let invalidSize = app.newWindow(width = 0)
  doAssert not invalidSize.isOk
  doAssert invalidSize.failure.kind == invalidArgument

  let first = app.newWindow(title = "First")
  let second = app.newWindow(title = "Second")
  doAssert first.isOk
  doAssert second.isOk
  doAssert app.windowCount() == 2
  doAssert app.windows().len == 2
  doAssert first.value.setTitle("Updated first").isOk
  doAssert first.value.setSize(640, 480).isOk
  doAssert not first.value.setSize(0, 480).isOk
  doAssert first.value.show().isOk
  doAssert first.value.focus().isOk
  doAssert first.value.hide().isOk
  doAssert first.value.minimize().isOk
  doAssert first.value.maximize().isOk
  doAssert first.value.restore().isOk
  doAssert first.value.setResizable(false).isOk
  doAssert first.value.setResizable(true).isOk
  doAssert not first.value.setPosition(10, 20).isOk
  doAssert not first.value.reload().isOk
  doAssert first.value.close().isOk
  doAssert not first.value.close().isOk
  doAssert first.value.isClosed()
  doAssert app.windowCount() == 1
  doAssert not first.value.rpc.registerSync("only.first", proc(params: JsonNode): RpcResult =
    rpcSuccess(newJNull())
  )
  doAssert not first.value.rpc.isMethodRegistered("only.first")
  doAssert not second.value.rpc.isMethodRegistered("only.first")
  let declarations = first.value.typescriptDeclarations()
  doAssert not declarations.isOk

block windowsCanSelectIndependentProfiles:
  let created = newApp(id = "tech.asopi.profile-window-test", name = "Profiles")
  doAssert created.isOk
  let work = created.value.newWindow(CoreWindowOptions(width: 1200, height: 800,
    profile: "work"))
  let personal = created.value.newWindow(CoreWindowOptions(width: 1200, height: 800,
    profile: "personal"))
  doAssert work.isOk, work.failure.detail
  doAssert personal.isOk, personal.failure.detail
  doAssert work.value.profilePath != personal.value.profilePath
  doAssert work.value.profilePath.endsWith("/work") or work.value.profilePath.endsWith("\\work")
  let direct = created.value.newWindow(profile = "direct", width = 1200, height = 800)
  doAssert direct.isOk
  doAssert direct.value.profilePath.endsWith("/direct") or direct.value.profilePath.endsWith("\\direct")
  doAssert direct.value.writeSetting("launch", %*{"count": 1}).isOk
  let launch = direct.value.readSetting("launch")
  doAssert launch.isOk
  doAssert launch.value["count"].getInt() == 1
  doAssert direct.value.listSettings().value.len >= 1
  doAssert direct.value.deleteSetting("launch").isOk
  doAssert direct.value.writeSetting("launch", %*{"count": 2}).isOk
  doAssert direct.value.clearSettings().isOk
  doAssert direct.value.listSettings().value.len == 0
  let cachePath = profileDirectoryPath("tech.asopi.profile-window-test", "direct", ProfileDirectory.cache)
  doAssert cachePath.isOk
  writeFile(cachePath.value / "entry", "cache")
  doAssert direct.value.clearCache().isOk
  doAssert not fileExists(cachePath.value / "entry")
  let downloadPath = profileDirectoryPath("tech.asopi.profile-window-test", "direct", ProfileDirectory.downloads)
  doAssert downloadPath.isOk
  writeFile(downloadPath.value / "download.tmp", "partial")
  doAssert direct.value.clearDownloads().isOk
  doAssert not fileExists(downloadPath.value / "download.tmp")
  let permissionPath = profileDirectoryPath("tech.asopi.profile-window-test", "direct", ProfileDirectory.permissions)
  doAssert permissionPath.isOk
  writeFile(permissionPath.value / "example.com.json", "{\"notifications\":\"deny\"}")
  doAssert direct.value.clearPermissions().isOk
  doAssert not fileExists(permissionPath.value / "example.com.json")
  let storagePath = profileDirectoryPath("tech.asopi.profile-window-test", "direct", ProfileDirectory.localStorage)
  doAssert storagePath.isOk
  writeFile(storagePath.value / "origin.json", "{}")
  doAssert direct.value.clearLocalStorage().isOk
  doAssert not fileExists(storagePath.value / "origin.json")
  doAssert direct.value.writeSetting("reset", %*{"ok": true}).isOk
  doAssert direct.value.clearProfileData().isOk
  doAssert direct.value.listSettings().value.len == 0
  let sessionCookie = ProfileCookie(name: "sid", value: "window", domain: "example.com")
  doAssert direct.value.writeCookie(sessionCookie).isOk
  let readCookie = direct.value.readCookie("example.com", "sid")
  doAssert readCookie.isOk
  doAssert readCookie.value.value == "window"
  doAssert direct.value.listCookies().value.len >= 1
  doAssert direct.value.deleteCookie("example.com", "sid").isOk
  doAssert direct.value.writeCookie(sessionCookie).isOk
  doAssert direct.value.clearCookies().isOk
  doAssert direct.value.listCookies().value.len == 0

block localAssetRootRejectsTraversal:
  let created = newApp(id = "tech.asopi.assets-test", name = "Assets test")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Assets").value
  doAssert not window.loadAssets("/path/that/does/not/exist").isOk
  doAssert window.loadHtml("<p>local</p>").isOk
  doAssert not window.reload().isOk
  let assetRoot = getTempDir() / "nimino-core-asset-entry"
  createDir(assetRoot)
  writeFile(assetRoot / "index.html", "<script src='app.js'></script>")
  writeFile(assetRoot / "app.js", "window.assetLoaded = true")
  doAssert window.loadAssets(assetRoot).isOk
  doAssert window.loadEntry().isOk
  removeDir(assetRoot)

block navigationRulesAreExplicit:
  doAssert matchesNavigationPattern("https://*.discord.com/**", "https://canary.discord.com/channels")
  doAssert not matchesNavigationPattern("https://*.discord.com/**", "https://discord.net/channels")
  let created = newApp(id = "tech.asopi.navigation-test", name = "Navigation test")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Navigation").value
  doAssert window.setNavigationRules(NavigationRules(
    allow: @["https://example.com/**"], deny: @["https://example.com/private/**"])).isOk
  doAssert window.onNavigationCompleted(proc(url: string; succeeded: bool) = discard).isOk
  doAssert not window.setNavigationRules(NavigationRules(allow: @[""], deny: @[])).isOk
  var externalUrl = ""
  doAssert window.onExternalNavigation(proc(request: NavigationRequest) =
    externalUrl = request.url).isOk
  window.navigationPolicy = proc(request: NavigationRequest): NavigationDecision =
    navigationExternal
  doAssert window.applyNavigationDecision(NavigationRequest(url: "https://outside.example")) == false
  doAssert externalUrl == "https://outside.example"

block permissionsAndDownloadsDefaultToDeny:
  let created = newApp(id = "tech.asopi.policy-test", name = "Policy test")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Policy").value
  doAssert window.decidePermission(PermissionRequest(
    kind: microphone, url: "https://example.com")) == permissionDeny
  doAssert window.decideDownload(DownloadRequest(
    url: "https://example.com/file", suggestedName: "file")) == downloadDeny
  window.permissionHandler = proc(request: PermissionRequest): PermissionDecision =
    if request.kind == notifications: permissionGrant else: permissionDeny
  window.downloadHandler = proc(request: DownloadRequest): DownloadDecision = downloadAllow
  doAssert window.decidePermission(PermissionRequest(
    kind: notifications, url: "https://example.com")) == permissionGrant
  doAssert window.decidePermission(PermissionRequest(
    kind: camera, url: "https://example.com")) == permissionDeny
  doAssert window.decideDownload(DownloadRequest(
    url: "https://example.com/file", suggestedName: "file")) == downloadAllow
