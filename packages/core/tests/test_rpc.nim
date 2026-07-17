import std/[asyncfutures, json]

import nimino_core

proc request(id, methodName: string; params: JsonNode = newJNull(); timeoutMs = 30_000): string =
  $(%*{
    "nimino": "rpc",
    "kind": "request",
    "id": id,
    "method": methodName,
    "params": params,
    "timeoutMs": timeoutMs
  })

proc response(messages: seq[string]; index = 0): JsonNode =
  doAssert messages.len > index
  parseJson(messages[index])

block explicitAllowListAndSyncResponse:
  var messages: seq[string]
  let registry = newRpcRegistry(proc(message: string) = messages.add(message))
  doAssert registry.registerSync("settings.load", proc(params: JsonNode): RpcResult =
    rpcSuccess(%*{"theme": "dark"})
  )
  doAssert not registry.registerSync("settings.load", proc(params: JsonNode): RpcResult =
    rpcSuccess(newJNull())
  )

  doAssert registry.handleMessage(request("one", "settings.load"), 1_000)
  let replied = messages.response()
  doAssert replied["kind"].getStr() == "response"
  doAssert replied["id"].getStr() == "one"
  doAssert replied["ok"].getBool()
  doAssert replied["result"]["theme"].getStr() == "dark"

block unknownMethodsAreDenied:
  var messages: seq[string]
  let registry = newRpcRegistry(proc(message: string) = messages.add(message))
  doAssert registry.handleMessage(request("two", "system.shell"), 1_000)
  let replied = messages.response()
  doAssert not replied["ok"].getBool()
  doAssert replied["error"]["code"].getStr() == "methodNotAllowed"

block timeoutAndCancelSuppressLateReplies:
  var messages: seq[string]
  var pending: Future[RpcResult]
  let registry = newRpcRegistry(proc(message: string) = messages.add(message))
  doAssert registry.register("slow", proc(params: JsonNode): Future[RpcResult] =
    pending = newFuture[RpcResult]("nimino.rpc.test.slow")
    pending
  )

  doAssert registry.handleMessage(request("slow-one", "slow", timeoutMs = 5), 1_000)
  registry.tick(1_005)
  doAssert messages.response()["error"]["code"].getStr() == "timeout"
  pending.complete(rpcSuccess(%"late"))
  doAssert messages.len == 1

  doAssert registry.handleMessage(request("slow-two", "slow"), 2_000)
  doAssert registry.handleMessage($(%*{
    "nimino": "rpc", "kind": "cancel", "id": "slow-two"
  }), 2_001)
  doAssert messages.response(1)["error"]["code"].getStr() == "cancelled"
  pending.complete(rpcSuccess(%"late again"))
  doAssert messages.len == 2

block notificationsAndMalformedMessagesDoNotExposeHandlers:
  var notifications = 0
  let registry = newRpcRegistry()
  doAssert registry.registerSync("telemetry.record", proc(params: JsonNode): RpcResult =
    inc notifications
    rpcSuccess(newJNull())
  )
  doAssert not registry.handleMessage("not json", 1_000)
  doAssert registry.handleMessage($(%*{
    "nimino": "rpc", "kind": "notification", "method": "telemetry.record"
  }), 1_000)
  doAssert notifications == 1
