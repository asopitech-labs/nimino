import std/[asyncfutures, json, jsonutils, options, strutils]

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

type Settings = object
  theme: string

type
  SyncMode = enum
    manual, automatic
  ThemeSettings = object
    name: string
    enabled: bool
  SaveSettingsRequest = object
    mode: SyncMode
    theme: ThemeSettings
    recentThemes: seq[ThemeSettings]
    retryAfter: Option[int]
    palette: array[2, ThemeSettings]
  SaveSettingsResult = object
    accepted: bool
    activeTheme: ThemeSettings
  VariantPayload = object
    case enabled: bool
    of true:
      path: string
    of false:
      retryCount: int
  VariantContainer = object
    payload: VariantPayload

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

block cancellableHandlerReceivesToken:
  var messages: seq[string]
  var pending: Future[RpcResult]
  var token: RpcCancellationToken
  let registry = newRpcRegistry(proc(message: string) = messages.add(message))
  doAssert registry.registerCancellable("cooperative", proc(params: JsonNode;
      cancellation: RpcCancellationToken): Future[RpcResult] =
    token = cancellation
    pending = newFuture[RpcResult]("nimino.rpc.test.cooperative")
    pending)
  doAssert registry.handleMessage(request("cooperative-one", "cooperative"), 1_000)
  doAssert not token.cancelled
  doAssert registry.handleMessage($(%*{
    "nimino": "rpc", "kind": "cancel", "id": "cooperative-one"
  }), 1_001)
  doAssert token.cancelled
  doAssert messages.response()["error"]["code"].getStr() == "cancelled"
  pending.complete(rpcSuccess(%"ignored"))
  doAssert messages.len == 1

block closeCancelsPendingRequests:
  var messages: seq[string]
  var pending: Future[RpcResult]
  let registry = newRpcRegistry(proc(message: string) = messages.add(message))
  doAssert registry.register("slow", proc(params: JsonNode): Future[RpcResult] =
    pending = newFuture[RpcResult]("nimino.rpc.test.close")
    pending)
  doAssert registry.handleMessage(request("close-one", "slow"), 3_000)
  registry.close()
  doAssert messages.len == 1
  doAssert messages.response()["error"]["code"].getStr() == "cancelled"
  ## Closing drops the registry's ownership before a handler can complete. A
  ## delayed Future therefore must not emit a second response into a closed
  ## Window/WebView callback path.
  pending.complete(rpcSuccess(%"late completion"))
  registry.tick(3_001)
  doAssert messages.len == 1

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

block typedHandlersRemainExplicitAndSerializeJson:
  var messages: seq[string]
  let registry = newRpcRegistry(proc(message: string) = messages.add(message))
  doAssert registry.registerTyped("settings.load", proc(): Settings =
    Settings(theme: "dark")
  )
  doAssert registry.registerTypedAsync("settings.echo",
    proc(settings: Settings): Future[Settings] =
      let completed = newFuture[Settings]("nimino.rpc.test.typed")
      completed.complete(settings)
      completed
  )
  doAssert registry.handleMessage(request("typed-one", "settings.load"), 1_000)
  doAssert messages.response()["result"]["theme"].getStr() == "dark"
  doAssert registry.handleMessage(request("typed-two", "settings.echo",
    %*{"theme": "light"}), 2_000)
  registry.tick(2_000)
  doAssert messages.response(1)["result"]["theme"].getStr() == "light"

block typescriptDeclarationsExposeOnlyRegisteredNames:
  let registry = newRpcRegistry()
  doAssert registry.registerSync("settings.load", proc(params: JsonNode): RpcResult =
    rpcSuccess(newJNull()))
  doAssert registry.registerSync("files.save", proc(params: JsonNode): RpcResult =
    rpcSuccess(newJNull()))
  doAssert registry.registeredMethods() == @["files.save", "settings.load"]
  let declarations = registry.typescriptDeclarations()
  doAssert declarations.find("method: 'files.save'") >= 0
  doAssert declarations.find("method: 'settings.load'") >= 0
  doAssert declarations.find("method: 'unregistered'") < 0

block typedDeclarationsCarryPrimitiveTypes:
  let registry = newRpcRegistry()
  doAssert registry.registerTyped("system.version", proc(): string = "1.0")
  doAssert registry.registerTyped("files.exists", proc(path: string): bool = path.len > 0)
  doAssert registry.registerTyped("files.list", proc(): seq[string] = @[])
  let declarations = registry.typescriptDeclarations()
  doAssert declarations.find("method: 'system.version', params?: void") >= 0
  doAssert declarations.find("Promise<string>") >= 0
  doAssert declarations.find("method: 'files.exists', params?: string") >= 0
  doAssert declarations.find("Promise<boolean>") >= 0
  doAssert declarations.find("Promise<string[]>") >= 0

block typedDeclarationsExtractSupportedCompositeJsonShapes:
  var messages: seq[string]
  let registry = newRpcRegistry(proc(message: string) = messages.add(message))
  doAssert registry.registerTyped("settings.save", proc(request: SaveSettingsRequest): SaveSettingsResult =
    SaveSettingsResult(accepted: request.mode == automatic,
      activeTheme: request.theme)
  )
  doAssert registry.registerTypedAsync("settings.saveAsync",
    proc(request: SaveSettingsRequest): Future[SaveSettingsResult] =
      let completed = newFuture[SaveSettingsResult]("nimino.rpc.test.complex")
      completed.complete(SaveSettingsResult(accepted: request.mode == automatic,
        activeTheme: request.theme))
      completed
  )
  doAssert registry.registerTypedNotification("settings.changed",
    proc(request: SaveSettingsRequest) = discard)
  doAssert registry.registerTyped("settings.variant",
    proc(request: VariantContainer): VariantContainer = request)
  doAssert registry.registeredMethods() == @[
    "settings.changed", "settings.save", "settings.saveAsync", "settings.variant"
  ]
  let declarations = registry.typescriptDeclarations()
  let requestType = "{ 'mode': number; 'theme': { 'name': string; 'enabled': boolean }; " &
    "'recentThemes': { 'name': string; 'enabled': boolean }[]; 'retryAfter': number | null; " &
    "'palette': { 'name': string; 'enabled': boolean }[] }"
  let resultType = "{ 'accepted': boolean; 'activeTheme': { 'name': string; 'enabled': boolean } }"
  doAssert declarations.find("method: 'settings.save', params?: " & requestType) >= 0
  doAssert declarations.find("Promise<" & resultType & ">") >= 0
  doAssert declarations.find("method: 'settings.saveAsync', params?: " & requestType) >= 0
  doAssert declarations.find("notify(method: 'settings.changed', params?: " & requestType & ")") >= 0
  ## Variant records remain conservative because their field set depends on a
  ## discriminator. The macro must never add a method outside this allow-list.
  doAssert declarations.find("method: 'settings.variant', params?: { 'payload': unknown }") >= 0
  doAssert declarations.find("method: 'unregistered'") < 0
  let settingsParams = parseJson("""{
    "mode": 1,
    "theme": {"name": "night", "enabled": true},
    "recentThemes": [],
    "retryAfter": null,
    "palette": [
      {"name": "night", "enabled": true},
      {"name": "day", "enabled": false}
    ]
  }""")
  doAssert registry.handleMessage(request("complex", "settings.save", settingsParams), 1_000)
  doAssert messages.response()["result"]["accepted"].getBool()
  doAssert messages.response()["result"]["activeTheme"]["name"].getStr() == "night"

block fireAndForgetNotificationRegistration:
  let registry = newRpcRegistry()
  var received = ""
  doAssert registry.registerNotification("status.changed", proc(params: JsonNode) =
    received = params["value"].getStr())
  doAssert registry.handleMessage($(%*{
    "nimino": "rpc", "kind": "notification", "method": "status.changed",
    "params": {"value": "ready"}
  }))
  doAssert received == "ready"
  let declarations = registry.typescriptDeclarations()
  doAssert declarations.find("notify(method: 'status.changed'") >= 0
  doAssert declarations.find("invoke(method: 'status.changed'") < 0

block typedFireAndForgetNotification:
  let registry = newRpcRegistry()
  var received = 0
  doAssert registry.registerTypedNotification("counter.changed", proc(value: int) =
    received = value)
  doAssert registry.handleMessage($(%*{
    "nimino": "rpc", "kind": "notification", "method": "counter.changed",
    "params": 7
  }))
  doAssert received == 7
  let typedDeclarations = registry.typescriptDeclarations()
  doAssert typedDeclarations.find("notify(method: 'counter.changed', params?: number)") >= 0
  var called = false
  doAssert registry.registerTypedNotification("heartbeat", proc() = called = true)
  doAssert registry.handleMessage($(%*{
    "nimino": "rpc", "kind": "notification", "method": "heartbeat"}))
  doAssert called
  let noArgDeclarations = registry.typescriptDeclarations()
  doAssert noArgDeclarations.find("notify(method: 'heartbeat', params?: void)") >= 0

block unregisterRemovesNotificationSchema:
  let registry = newRpcRegistry()
  doAssert registry.registerTypedNotification("transient", proc(value: int) = discard)
  doAssert registry.unregister("transient")
  doAssert registry.typescriptDeclarations().find("transient") < 0

block explicitTypeScriptSchemaIsBoundToRegisteredMethod:
  let registry = newRpcRegistry()
  doAssert not registry.registerTypeScriptSchema("missing", "Input", "Output")
  doAssert registry.registerSync("settings.load", proc(params: JsonNode): RpcResult =
    rpcSuccess(%*{"theme": "dark"}))
  doAssert registry.registerTypeScriptSchema("settings.load", "SettingsRequest", "Settings")
  let declarations = registry.typescriptDeclarations()
  doAssert declarations.find("params?: SettingsRequest") >= 0
  doAssert declarations.find("Promise<Settings>") >= 0
  doAssert not registry.registerTypeScriptSchema("settings.load", "Bad\nType", "Settings")
  doAssert not registry.registerTypeScriptSchema("settings.load", "Bad/*x*/", "Settings")
