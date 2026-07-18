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

block windowsOwnIndependentRpcAllowLists:
  let created = newApp(id = "tech.asopi.core-test", name = "Core test")
  doAssert created.isOk
  let app = created.value

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
