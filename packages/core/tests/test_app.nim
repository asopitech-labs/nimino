import std/[json, os, strutils]

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
  let cookie = ProfileCookie(name: "sid", value: "abc", domain: "example.com",
    path: "/", secure: true, expires: 123)
  doAssert writeProfileCookie("tech.asopi.profile-test", "work", cookie).isOk
  let loadedCookie = readProfileCookie("tech.asopi.profile-test", "work",
    "example.com", "sid")
  doAssert loadedCookie.isOk
  doAssert loadedCookie.value.value == "abc"
  doAssert listProfileCookies("tech.asopi.profile-test", "work").value == "example.com__sid"
  doAssert deleteProfileCookie("tech.asopi.profile-test", "work", "example.com", "sid").isOk

block windowsOwnIndependentRpcAllowLists:
  let created = newApp(id = "tech.asopi.core-test", name = "Core test")
  doAssert created.isOk
  let app = created.value
  let multipleViews = app.supports(multipleWebViews)
  doAssert multipleViews.isOk

  let invalidSize = app.newWindow(width = 0)
  doAssert not invalidSize.isOk
  doAssert invalidSize.failure.kind == invalidArgument

  let first = app.newWindow(title = "First")
  let second = app.newWindow(title = "Second")
  doAssert first.isOk
  doAssert second.isOk
  doAssert first.value.setTitle("Updated first").isOk
  doAssert first.value.setSize(640, 480).isOk
  doAssert not first.value.setSize(0, 480).isOk
  doAssert first.value.rpc.registerSync("only.first", proc(params: JsonNode): RpcResult =
    rpcSuccess(newJNull())
  )
  doAssert first.value.rpc.isMethodRegistered("only.first")
  doAssert not second.value.rpc.isMethodRegistered("only.first")
  let declarations = first.value.typescriptDeclarations()
  doAssert declarations.isOk
  doAssert declarations.value.find("only.first") >= 0
  doAssert declarations.value.find("unregistered") < 0

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
  let sessionCookie = ProfileCookie(name: "sid", value: "window", domain: "example.com")
  doAssert direct.value.writeCookie(sessionCookie).isOk
  let readCookie = direct.value.readCookie("example.com", "sid")
  doAssert readCookie.isOk
  doAssert readCookie.value.value == "window"
  doAssert direct.value.listCookies().value.len >= 1
  doAssert direct.value.deleteCookie("example.com", "sid").isOk

block localAssetRootRejectsTraversal:
  let created = newApp(id = "tech.asopi.assets-test", name = "Assets test")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Assets").value
  doAssert not window.loadAssets("/path/that/does/not/exist").isOk

block navigationRulesAreExplicit:
  let created = newApp(id = "tech.asopi.navigation-test", name = "Navigation test")
  doAssert created.isOk
  let window = created.value.newWindow(title = "Navigation").value
  doAssert window.setNavigationRules(NavigationRules(
    allow: @["https://example.com/**"], deny: @["https://example.com/private/**"])).isOk
  doAssert not window.setNavigationRules(NavigationRules(allow: @[""], deny: @[])).isOk

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
