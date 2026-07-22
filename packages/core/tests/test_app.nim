import std/[asyncfutures, json, os, strutils, times]

import nimino_core

block appOptionsAreValidated:
  let missingId = newApp(AppOptions(id: "", name: "Example"))
  doAssert not missingId.isOk
  doAssert missingId.failure.kind == invalidArgument

  let missingName = newApp(AppOptions(id: "tech.asopi.example", name: ""))
  doAssert not missingName.isOk
  doAssert missingName.failure.kind == invalidArgument

block singleInstanceLockLifecycleIsExplicit:
  let first = newApp(AppOptions(id: "tech.asopi.single-instance-test",
    name: "Single instance", multiInstance: false))
  doAssert first.isOk
  let duplicate = newApp(AppOptions(id: "tech.asopi.single-instance-test",
    name: "Single instance", multiInstance: false))
  doAssert not duplicate.isOk
  doAssert duplicate.failure.kind == invalidState
  doAssert duplicate.failure.detail.contains("already")
  let parallel = newApp(AppOptions(id: "tech.asopi.single-instance-test",
    name: "Single instance", multiInstance: true))
  doAssert parallel.isOk
  doAssert first.value.quit().isOk
  let reopened = newApp(AppOptions(id: "tech.asopi.single-instance-test",
    name: "Single instance", multiInstance: false))
  doAssert reopened.isOk
  doAssert reopened.value.quit().isOk
  doAssert parallel.value.quit().isOk

block deepLinkDeliveryIsExplicit:
  let created = newApp(id = "tech.asopi.deep-link-test", name = "Deep link test")
  doAssert created.isOk
  let app = created.value
  var received = ""
  doAssert app.onDeepLink(proc(url: string) = received = url).isOk
  doAssert app.deliverDeepLink("nimino://open/item?id=1").isOk
  doAssert received == "nimino://open/item?id=1"
  doAssert not app.deliverDeepLink("nimino://bad\nvalue").isOk
  doAssert not app.onDeepLink(nil).isOk

block deepLinkDeliveryQueuesUntilHandlerRegistration:
  let created = newApp(id = "tech.asopi.deep-link-queue-test", name = "Deep link queue")
  doAssert created.isOk
  let app = created.value
  doAssert app.deliverDeepLink("queue://open/item").isOk
  var received = ""
  doAssert app.onDeepLink(proc(url: string) = received = url).isOk
  doAssert received == "queue://open/item"

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
  let nestedDownloadDir = parentDir(storedPath.value) / "nested"
  createDir(nestedDownloadDir)
  let nestedDownload = nestedDownloadDir / "nested.txt"
  writeFile(nestedDownload, "nested")
  let listedDownloads = listProfileDownloads("tech.asopi.profile-test", "work")
  doAssert listedDownloads.isOk
  doAssert nestedDownload in listedDownloads.value
  doAssert deleteProfileDownload("tech.asopi.profile-test", "work", nestedDownload).isOk
  doAssert not fileExists(nestedDownload)
  doAssert not deleteProfileDownload("tech.asopi.profile-test", "work", getHomeDir() / "outside.txt").isOk
  doAssert deleteProfileDownload("tech.asopi.profile-test", "work", storedPath.value).isOk
  doAssert not fileExists(storedPath.value)
  let cookie = ProfileCookie(name: "sid", value: "abc", domain: "example.com",
    path: "/", secure: true, expires: int64(epochTime()) + 3600)
  let parsedCookie = parseCookieHeader("sid=abc; Path=/; HttpOnly", "example.com", "/", true)
  doAssert parsedCookie.isOk
  doAssert parsedCookie.value[0].name == "sid"
  doAssert parsedCookie.value[0].value == "abc"
  let tokenCookie = parseCookieHeader("$session+id=abc", "example.com", "/")
  doAssert tokenCookie.isOk
  doAssert not parseCookieHeader("bad;value", "example.com", "/").isOk
  doAssert writeProfileCookie("tech.asopi.profile-test", "work", cookie).isOk
  doAssert not writeProfileCookie("tech.asopi.profile-test", "work",
    ProfileCookie(name: "bad", value: "x; secure", domain: "example.com")).isOk
  doAssert not writeProfileCookie("tech.asopi.profile-test", "work",
    ProfileCookie(name: "bad-path", value: "x", domain: "example.com", path: "relative")).isOk
  let loadedCookie = readProfileCookie("tech.asopi.profile-test", "work",
    "example.com", "sid")
  doAssert loadedCookie.isOk
  doAssert loadedCookie.value.value == "abc"
  let cookieDirectory = profileDirectoryPath("tech.asopi.profile-test", "work", cookies)
  doAssert cookieDirectory.isOk
  let cookieFile = cookieDirectory.value / "example.com__sid.json"
  writeFile(cookieFile, $(%*{
    "name": "sid", "value": "legacy", "domain": "example.com",
    "path": "/", "secure": true, "expires": int64(epochTime()) + 3600
  }))
  let legacyCookie = readProfileCookie("tech.asopi.profile-test", "work",
    "example.com", "sid")
  doAssert legacyCookie.isOk
  doAssert legacyCookie.value.value == "legacy"
  doAssert not legacyCookie.value.httpOnly
  doAssert writeProfileCookie("tech.asopi.profile-test", "work", cookie).isOk
  let scopedCookie = ProfileCookie(name: "sid", value: "scoped",
    domain: "example.com", path: "/account", secure: true,
    httpOnly: true, expires: int64(epochTime()) + 3600)
  doAssert writeProfileCookie("tech.asopi.profile-test", "work", scopedCookie).isOk
  let loadedScopedCookie = readProfileCookie("tech.asopi.profile-test", "work",
    "example.com", "sid", "/account")
  doAssert loadedScopedCookie.isOk
  doAssert loadedScopedCookie.value.value == "scoped"
  doAssert loadedScopedCookie.value.httpOnly
  let matchingCookies = profileCookiesForDomain("tech.asopi.profile-test", "work", "sub.example.com")
  doAssert matchingCookies.isOk
  doAssert matchingCookies.value.len == 2
  let matchingUrl = profileCookiesForUrl("tech.asopi.profile-test", "work",
    "https://sub.example.com/app/page")
  doAssert matchingUrl.isOk
  doAssert matchingUrl.value.len == 1
  let scopedUrl = profileCookiesForUrl("tech.asopi.profile-test", "work",
    "https://sub.example.com/account/settings")
  doAssert scopedUrl.isOk
  doAssert scopedUrl.value.len == 2
  let insecureUrl = profileCookiesForUrl("tech.asopi.profile-test", "work",
    "http://sub.example.com/app/page")
  doAssert insecureUrl.isOk
  doAssert insecureUrl.value.len == 0
  let uppercaseScheme = profileCookiesForUrl("tech.asopi.profile-test", "work",
    "HTTPS://sub.example.com/app/page")
  doAssert uppercaseScheme.isOk
  doAssert uppercaseScheme.value.len == 1
  let cookieKeys = listProfileCookies("tech.asopi.profile-test", "work")
  doAssert cookieKeys.isOk
  doAssert cookieKeys.value.splitLines().len == 2
  doAssert "example.com__sid" in cookieKeys.value.splitLines()
  doAssert deleteProfileCookie("tech.asopi.profile-test", "work", "example.com",
    "sid", "/account").isOk
  doAssert deleteProfileCookie("tech.asopi.profile-test", "work", "example.com", "sid").isOk
  doAssert clearProfilePermissions("tech.asopi.profile-test", "work").isOk
  let permissionOrigin = normalizePermissionOrigin("HTTPS://Example.COM:443/private?q=1")
  doAssert permissionOrigin.isOk
  doAssert permissionOrigin.value == "https://example.com"
  doAssert not normalizePermissionOrigin("file:///tmp/index.html").isOk
  doAssert writeProfilePermission("tech.asopi.profile-test", "work",
    "https://example.com/account", "notifications", "grant").isOk
  let loadedPermission = readProfilePermission("tech.asopi.profile-test", "work",
    "https://EXAMPLE.com:443/other", "notifications")
  doAssert loadedPermission.isOk
  doAssert loadedPermission.value.origin == "https://example.com"
  doAssert loadedPermission.value.decision == "grant"
  doAssert writeProfilePermission("tech.asopi.profile-test", "work",
    "https://example.com", "camera", "deny").isOk
  let profilePermissions = listProfilePermissions("tech.asopi.profile-test", "work")
  doAssert profilePermissions.isOk
  doAssert profilePermissions.value.len == 2
  doAssert deleteProfilePermission("tech.asopi.profile-test", "work",
    "https://example.com", "notifications").isOk
  doAssert not readProfilePermission("tech.asopi.profile-test", "work",
    "https://example.com", "notifications").isOk
  doAssert clearProfilePermissions("tech.asopi.profile-test", "work").isOk

block windowsOwnIndependentRpcAllowLists:
  let created = newApp(id = "tech.asopi.core-test", name = "Core test")
  doAssert created.isOk
  let app = created.value
  doAssert not app.isRunning()
  let closeAllowed = app.windows()
  doAssert closeAllowed.len == 0
  let multipleViews = app.supports(multipleWebViews)
  doAssert multipleViews.isOk

  let desktopItem = DesktopMenuItem(id: 1, title: "Quit", enabled: true)
  when defined(linux) and not defined(niminoWsl):
    doAssert app.configureNativeMenu("File", @[desktopItem],
      proc(itemId: uint32) = doAssert itemId == 1).isOk
    doAssert not app.configureSystemTray(@[desktopItem],
      proc(itemId: uint32) = discard).isOk
  doAssert not app.sendNotification(DesktopNotification(
    id: "before-run", title: "Not ready", body: "")).isOk

  let invalidSize = app.newWindow(width = 0)
  doAssert not invalidSize.isOk
  doAssert invalidSize.failure.kind == invalidArgument

  let first = app.newWindow(title = "First")
  let second = app.newWindow(title = "Second")
  doAssert first.isOk
  doAssert second.isOk
  let invalidDialog = first.value.openFileDialog(FileDialogOptions(title: ""))
  doAssert invalidDialog.finished
  let invalidDialogResult = invalidDialog.read()
  doAssert not invalidDialogResult.isOk
  doAssert invalidDialogResult.failure.kind == invalidArgument
  doAssert first.value.onCloseRequested(proc(): bool = true).isOk
  doAssert first.value.onClosed(proc() = discard).isOk
  doAssert first.value.onResize(proc(width, height: int) = discard).isOk
  let extraView = first.value.newWebView()
  doAssert extraView.isOk
  doAssert extraView.value.onMessage(proc(message: string) = discard).isOk
  doAssert extraView.value.close().isOk
  let popup = first.value.openPopup(NewWindowRequest(url: "data:text/html,<p>popup</p>"),
    title = "Popup", profile = "popup")
  doAssert popup.isOk
  doAssert popup.value.profilePath.endsWith("/popup") or popup.value.profilePath.endsWith("\\popup")
  first.value.navigationPolicy = proc(request: NavigationRequest): NavigationDecision =
    if request.url == "https://popup.example/allowed": navigationAllow
    else: navigationDeny
  let policyPopup = first.value.openPopup(NewWindowRequest(
    url: "https://popup.example/allowed"), profile = "popup-policy")
  doAssert policyPopup.isOk
  doAssert policyPopup.value.applyNavigationDecision(NavigationRequest(
    url: "https://popup.example/allowed"))
  doAssert not policyPopup.value.applyNavigationDecision(NavigationRequest(
    url: "https://evil.example/login"))
  doAssert app.windowCount() == 4
  doAssert app.windows().len == 4
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
  doAssert app.windowCount() == 3
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
  createDir(cachePath.value / "nested")
  writeFile(cachePath.value / "nested" / "entry.bin", "cache")
  doAssert direct.value.clearCache().isOk
  doAssert not fileExists(cachePath.value / "entry")
  doAssert not fileExists(cachePath.value / "nested" / "entry.bin")
  let profileRoot = profilePath("tech.asopi.profile-window-test", "direct")
  doAssert profileRoot.isOk
  let engineCache = profileRoot.value / "webview2" / "Default" / "Cache"
  createDir(engineCache)
  writeFile(engineCache / "engine-entry", "engine cache")
  doAssert direct.value.clearCache().isOk
  doAssert fileExists(engineCache / "engine-entry")
  let downloadPath = profileDirectoryPath("tech.asopi.profile-window-test", "direct", ProfileDirectory.downloads)
  doAssert downloadPath.isOk
  writeFile(downloadPath.value / "download.tmp", "partial")
  createDir(downloadPath.value / "nested")
  writeFile(downloadPath.value / "nested" / "partial.bin", "partial")
  doAssert direct.value.clearDownloads().isOk
  doAssert not fileExists(downloadPath.value / "download.tmp")
  doAssert not fileExists(downloadPath.value / "nested" / "partial.bin")
  let permissionPath = profileDirectoryPath("tech.asopi.profile-window-test", "direct", ProfileDirectory.permissions)
  doAssert permissionPath.isOk
  writeFile(permissionPath.value / "example.com.json", "{\"notifications\":\"deny\"}")
  createDir(permissionPath.value / "nested")
  writeFile(permissionPath.value / "nested" / "permission.json", "{}")
  doAssert direct.value.clearPermissions().isOk
  doAssert not fileExists(permissionPath.value / "example.com.json")
  doAssert not fileExists(permissionPath.value / "nested" / "permission.json")
  let storagePath = profileDirectoryPath("tech.asopi.profile-window-test", "direct", ProfileDirectory.localStorage)
  doAssert storagePath.isOk
  writeFile(storagePath.value / "origin.json", "{}")
  createDir(storagePath.value / "nested")
  writeFile(storagePath.value / "nested" / "origin.db", "{}")
  doAssert direct.value.clearLocalStorage().isOk
  doAssert not fileExists(storagePath.value / "origin.json")
  doAssert not fileExists(storagePath.value / "nested" / "origin.db")
  doAssert direct.value.writeSetting("reset", %*{"ok": true}).isOk
  doAssert direct.value.clearProfileData().isOk
  doAssert direct.value.listSettings().value.len == 0
  doAssert fileExists(engineCache / "engine-entry")
  let engineClear = direct.value.clearWebViewProfileData({webViewCookies,
    webViewLocalStorage, webViewCache})
  doAssert engineClear.finished
  let engineClearResult = engineClear.read()
  doAssert not engineClearResult.isOk
  ## The native Linux backend now owns a WebKitWebsiteDataManager.  This
  ## window has not entered the GTK main loop yet, so clearing must fail as an
  ## invalid state rather than silently reporting the feature unsupported.
  ## The dedicated `-d:niminoWsl` adapter test below retains the WSL boundary.
  when defined(linux) and not defined(niminoWsl):
    doAssert engineClearResult.failure.kind == invalidState
  else:
    doAssert engineClearResult.failure.kind == platformUnavailable
  let missingKinds = direct.value.clearWebViewProfileData({})
  doAssert missingKinds.finished
  let missingKindsResult = missingKinds.read()
  doAssert not missingKindsResult.isOk
  doAssert missingKindsResult.failure.kind == invalidArgument
  let sessionCookie = ProfileCookie(name: "sid", value: "window", domain: "example.com")
  doAssert direct.value.writeCookie(sessionCookie).isOk
  let readCookie = direct.value.readCookie("example.com", "sid")
  doAssert readCookie.isOk
  doAssert readCookie.value.value == "window"
  let visibleCookies = direct.value.cookiesForDomain("sub.example.com")
  doAssert visibleCookies.isOk
  doAssert visibleCookies.value.len == 1
  doAssert visibleCookies.value[0].name == "sid"
  let visibleUrlCookies = direct.value.cookiesForUrl("https://sub.example.com/app/page")
  doAssert visibleUrlCookies.isOk
  doAssert visibleUrlCookies.value.len == 1
  doAssert direct.value.listCookies().value.len >= 1
  doAssert direct.value.deleteCookie("example.com", "sid").isOk
  doAssert direct.value.writeCookie(sessionCookie).isOk
  let engineCookies = direct.value.webViewCookies("https://example.com/")
  doAssert engineCookies.finished
  doAssert not engineCookies.read().isOk
  let engineSet = direct.value.setWebViewCookie(sessionCookie)
  doAssert engineSet.finished
  doAssert not engineSet.read().isOk
  let engineDelete = direct.value.deleteWebViewCookie(sessionCookie)
  doAssert engineDelete.finished
  doAssert not engineDelete.read().isOk
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
  writeFile(assetRoot / "index.html", "<script src='app.js'></script><img src='sample.m4a'><a href='font.eot'>font</a>")
  writeFile(assetRoot / "app.js", "window.assetLoaded = true")
  writeFile(assetRoot / "sample.m4a", "audio")
  writeFile(assetRoot / "font.eot", "font")
  doAssert window.loadAssets(assetRoot).isOk
  doAssert window.loadEntry().isOk
  removeDir(assetRoot)

block navigationRulesAreExplicit:
  doAssert isAuthenticationNavigation("https://accounts.google.com/o/oauth2/auth")
  doAssert isAuthenticationNavigation("https://tenant.okta.com/login/login.htm")
  doAssert not isAuthenticationNavigation("https://example.invalid/oauth/callback")
  doAssert defaultNavigationDecision("https://mail.google.com/mail/u/0/",
    "https://accounts.google.com/signin/v2/identifier") == navigationAllow
  doAssert defaultNavigationDecision("https://mail.google.com/mail/u/0/",
    "https://mail.google.com/mail/u/0/#inbox") == navigationAllow
  doAssert defaultNavigationDecision("https://mail.google.com/mail/u/0/",
    "https://support.example.invalid/help") == navigationExternal
  doAssert matchesNavigationPattern("https://*.discord.com/**", "https://canary.discord.com/channels")
  doAssert not matchesNavigationPattern("https://*.discord.com/**", "https://discord.net/channels")
  let created = newApp(id = "tech.asopi.navigation-test", name = "Navigation test")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Navigation").value
  doAssert window.setNavigationRules(NavigationRules(
    allow: @["https://example.com/**"], deny: @["https://example.com/private/**"])).isOk
  doAssert window.onNavigationCompleted(proc(url: string; succeeded: bool) = discard).isOk
  doAssert not window.setNavigationRules(NavigationRules(allow: @[""], deny: @[])).isOk
  doAssert not window.openExternally("javascript:alert(1)").isOk
  doAssert not window.openExternally("https://example.com/line\nfeed").isOk
  doAssert window.setNavigationPolicy(proc(request: NavigationRequest): NavigationDecision =
    navigationExternal).isOk
  doAssert not window.applyNavigationDecision(NavigationRequest(url: "javascript:blocked"))
  var externalUrl = ""
  doAssert window.onExternalNavigation(proc(request: NavigationRequest) =
    externalUrl = request.url).isOk
  window.navigationPolicy = proc(request: NavigationRequest): NavigationDecision =
    navigationExternal
  doAssert window.applyNavigationDecision(NavigationRequest(url: "https://outside.example")) == false
  doAssert externalUrl == "https://outside.example"
  doAssert not window.openPopup(NewWindowRequest(url: "https://outside.example")).isOk

block permissionsAndDownloadsDefaultToDeny:
  let created = newApp(id = "tech.asopi.policy-test", name = "Policy test")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Policy").value
  doAssert window.clearPermissions().isOk
  doAssert window.decidePermission(PermissionRequest(
    kind: microphone, url: "https://example.com")) == permissionDeny
  doAssert window.decideDownload(DownloadRequest(
    url: "https://example.com/file", suggestedName: "file")) == downloadDeny
  window.permissionHandler = proc(request: PermissionRequest): PermissionDecision =
    if request.kind == notifications: permissionGrant else: permissionDeny
  window.downloadHandler = proc(request: DownloadRequest): DownloadDecision = downloadAllow
  doAssert window.decidePermission(PermissionRequest(
    kind: notifications, url: "https://example.com")) == permissionGrant
  let remembered = window.readPermission(PermissionRequest(
    kind: notifications, url: "https://EXAMPLE.com:443/another/path"))
  doAssert remembered.isOk
  doAssert remembered.value == permissionGrant
  window.permissionHandler = proc(request: PermissionRequest): PermissionDecision =
    permissionDeny
  ## Stored grants are origin-scoped and take precedence over a later handler.
  doAssert window.decidePermission(PermissionRequest(
    kind: notifications, url: "https://example.com/new")) == permissionGrant
  doAssert window.decidePermission(PermissionRequest(
    kind: camera, url: "https://example.com")) == permissionDeny
  let permissions = window.listPermissions()
  doAssert permissions.isOk
  doAssert permissions.value.len == 2
  doAssert window.deletePermission(PermissionRequest(
    kind: notifications, url: "https://example.com" )).isOk
  doAssert window.decidePermission(PermissionRequest(
    kind: notifications, url: "https://example.com")) == permissionDeny
  doAssert window.clearPermissions().isOk
  doAssert not window.readPermission(PermissionRequest(
    kind: notifications, url: "https://example.com")).isOk
  doAssert window.decideDownload(DownloadRequest(
    url: "https://example.com/file", suggestedName: "file")) == downloadAllow

block loadUrlRejectsUnsafeInput:
  let created = newApp(id = "tech.asopi.url-validation-test", name = "URL validation")
  doAssert created.isOk
  let window = created.value.newWindow(title = "URL validation").value
  let rejected = window.loadUrl("https://example.com/has space")
  doAssert not rejected.isOk
  doAssert rejected.failure.kind == webViewError

block injectionConfigurationIsValidated:
  let created = newApp(id = "tech.asopi.injection-test", name = "Injection")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Injection").value
  doAssert window.setInjection(["body { color: red; }"],
    ["globalThis.niminoInjected = true;"]).isOk
  doAssert not window.setInjection([""], @[]).isOk
  doAssert window.setInjection(@[], @[], enabled = false).isOk
