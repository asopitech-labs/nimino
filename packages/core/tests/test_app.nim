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
