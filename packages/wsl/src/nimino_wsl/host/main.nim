## `nimino-wsl-host.exe` entry point.
##
## The host has one UI thread.  Before `NativeApp.run` it accepts only the M1
## setup requests synchronously.  After the UI loop starts, a Win32 timer calls
## the non-blocking stdio poller so shutdown/EOF is handled on that same thread.

import std/[asyncfutures, json, os, streams, sysrand]

import nimino_native except success, successOf, failure, failureOf

import ./[adapter, pipe, session]
import ../client/transport
import ../protocol/[authentication, messages, versioning]

type
  PendingEvaluation = object
    request: ProtocolMessage
    future: Future[NativeResultOf[string]]

  PendingBrowsingDataClear = object
    request: ProtocolMessage
    future: Future[NativeResult]

  PendingFileDialog = object
    request: ProtocolMessage
    future: Future[NativeResultOf[seq[string]]]

  HostState = ref object
    adapter: HostAdapter
    input: HostInput
    output: Stream
    sessionId: string
    pendingEvaluations: seq[PendingEvaluation]
    pendingBrowsingDataClears: seq[PendingBrowsingDataClear]
    pendingFileDialogs: seq[PendingFileDialog]
    nextEventId: uint64
    nextPolicyRequestId: uint64

proc sessionIdFromRandom(): string =
  let bytes = urandom(16)
  if bytes.len != 16:
    return ""
  const hexDigits = "0123456789abcdef"
  result = newStringOfCap(32)
  for value in bytes:
    result.add(hexDigits[int(value shr 4)])
    result.add(hexDigits[int(value and 0x0f)])

proc responseFor(state: HostState; request: ProtocolMessage; payload = "";
                 error = ""): ProtocolMessage =
  ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.response,
    sessionId: state.sessionId,
    requestId: request.requestId,
    payload: payload,
    error: error
  )

proc responseForFailure(state: HostState; request: ProtocolMessage;
                        failure: ProtocolError): ProtocolMessage =
  ## Keep a concise protocol summary for compatibility, while carrying the
  ## native failure as typed metadata for the WSL client/core error mapper.
  ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.response,
    sessionId: state.sessionId,
    requestId: request.requestId,
    error: failure.detail,
    errorKind: failure.nativeKind,
    errorOperation: failure.nativeOperation,
    errorPlatformCode: failure.nativePlatformCode,
    errorDetail: failure.nativeDetail
  )

proc responseForNativeFailure(state: HostState; request: ProtocolMessage;
                              failure: NativeError): ProtocolMessage =
  ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.response,
    sessionId: state.sessionId,
    requestId: request.requestId,
    error: failure.operation,
    errorKind: $failure.kind,
    errorOperation: failure.operation,
    errorPlatformCode: failure.platformCode,
    errorDetail: failure.detail
  )

proc writeMessage(state: HostState; message: ProtocolMessage): bool =
  state.output.writeMessageTo(message).isOk

proc writeEvent(state: HostState; methodName, payload, error: string): bool =
  let eventId = state.nextEventId
  inc state.nextEventId
  state.writeMessage(ProtocolMessage(
    version: ProtocolVersion,
    kind: event,
    sessionId: state.sessionId,
    eventId: eventId,
    methodName: methodName,
    payload: payload,
    error: error
  ))

proc readyCapabilities(state: HostState): string =
  ## The ready frame is the negotiated native capability snapshot for this
  ## authenticated host session.  It is generated before any Window/WebView
  ## exists, so it cannot be affected by application-controlled Web content.
  var capabilities: seq[string]
  for capability in Capability:
    if state.adapter.app.supports(capability):
      capabilities.add($capability)
  ## This names protocol support only. A specific WebView2 runtime can still
  ## reject the browser-engine operation in its structured completion.
  capabilities.add(WebViewProfileDataClearCapability)
  nativeCapabilitiesPayload(capabilities)

proc stopForProtocolError(state: HostState; message: ProtocolMessage; detail: string) =
  discard state.writeMessage(state.responseFor(message, error = detail))
  discard state.adapter.app.close()

proc flushEvaluations(state: HostState) =
  var index = 0
  while index < state.pendingEvaluations.len:
    let pending = state.pendingEvaluations[index]
    if not pending.future.finished:
      inc index
      continue

    var payload = ""
    var error = ""
    var response: ProtocolMessage
    if pending.future.failed:
      error = "native.webview.evalJavaScript failed"
      response = state.responseFor(pending.request, error = error)
    else:
      let evaluation = pending.future.read()
      if evaluation.isOk:
        payload = $(%*{"result": evaluation.value})
        response = state.responseFor(pending.request, payload = payload)
      else:
        response = state.responseForNativeFailure(pending.request, evaluation.failure)
    if not state.writeMessage(response):
      discard state.adapter.app.close()
      return
    state.pendingEvaluations.delete(index)

proc browsingDataClearPayload(cleared: NativeResult): string =
  if cleared.isOk:
    return $(%*{"ok": true})
  let failure = cleared.failure
  $(%*{
    "ok": false,
    "kind": $failure.kind,
    "operation": failure.operation,
    "platformCode": failure.platformCode,
    "detail": failure.detail
  })

proc flushBrowsingDataClears(state: HostState) =
  var index = 0
  while index < state.pendingBrowsingDataClears.len:
    let pending = state.pendingBrowsingDataClears[index]
    if not pending.future.finished:
      inc index
      continue

    let payload = if pending.future.failed:
      $(%*{
        "ok": false,
        "kind": "webViewError",
        "operation": "webview.clearBrowsingData",
        "platformCode": 0,
        "detail": "native browser data clear did not complete"
      })
    else:
      pending.future.read().browsingDataClearPayload()
    if not state.writeMessage(state.responseFor(pending.request, payload)):
      discard state.adapter.app.close()
      return
    state.pendingBrowsingDataClears.delete(index)

proc flushFileDialogs(state: HostState) =
  var index = 0
  while index < state.pendingFileDialogs.len:
    let pending = state.pendingFileDialogs[index]
    if not pending.future.finished:
      inc index
      continue
    var response: ProtocolMessage
    if pending.future.failed:
      response = state.responseFor(pending.request, payload = $(%*{
        "ok": false,
        "kind": "webViewError",
        "operation": "window.openFileDialog",
        "platformCode": 0,
        "detail": "native file dialog did not complete"
      }))
    else:
      let opened = pending.future.read()
      if opened.isOk:
        response = state.responseFor(pending.request, payload = $(%*{
          "ok": true,
          "paths": opened.value
        }))
      else:
        let failure = opened.failure
        response = state.responseFor(pending.request, payload = $(%*{
          "ok": false,
          "kind": $failure.kind,
          "operation": failure.operation,
          "platformCode": failure.platformCode,
          "detail": failure.detail
        }))
    if not state.writeMessage(response):
      discard state.adapter.app.close()
      return
    state.pendingFileDialogs.delete(index)

proc cancelPending(state: HostState; requestId: uint64) =
  ## Native WebView2 operations may already be in flight and cannot always be
  ## interrupted.  Removing the protocol waiter guarantees that a cancelled
  ## request never emits a stale response; native completion still releases
  ## its own callback resources normally.
  var index = 0
  while index < state.pendingEvaluations.len:
    if state.pendingEvaluations[index].request.requestId == requestId:
      state.pendingEvaluations.delete(index)
    else:
      inc index
  index = 0
  while index < state.pendingFileDialogs.len:
    if state.pendingFileDialogs[index].request.requestId == requestId:
      state.pendingFileDialogs.delete(index)
    else:
      inc index
  index = 0
  while index < state.pendingBrowsingDataClears.len:
    if state.pendingBrowsingDataClears[index].request.requestId == requestId:
      state.pendingBrowsingDataClears.delete(index)
    else:
      inc index

proc flushMessages(state: HostState) =
  for message in state.adapter.takeMessages():
    let payload = $(%*{
      "webViewId": $message.webViewId,
      "message": message.message
    })
    if not state.writeEvent("native.webview.message", payload, ""):
      discard state.adapter.app.close()
      return

proc flushErrors(state: HostState) =
  for nativeError in state.adapter.takeErrors():
    let payload = $(%*{
      "webViewId": $nativeError.webViewId,
      "kind": $nativeError.error.kind,
      "operation": nativeError.error.operation,
      "platformCode": nativeError.error.platformCode,
      "detail": nativeError.error.detail
    })
    if not state.writeEvent("native.webview.error", payload, ""):
      discard state.adapter.app.close()
      return

proc flushNewWindowRequests(state: HostState) =
  for requested in state.adapter.takeNewWindowRequests():
    let payload = $(%*{
      "webViewId": $requested.webViewId,
      "url": requested.url
    })
    if not state.writeEvent("native.webview.newWindowRequested", payload, ""):
      discard state.adapter.app.close()
      return

proc flushNavigationStarts(state: HostState) =
  for started in state.adapter.takeNavigationStarts():
    let payload = $(%*{
      "webViewId": $started.webViewId,
      "url": started.url
    })
    if not state.writeEvent("native.webview.navigationStarting", payload, ""):
      discard state.adapter.app.close()
      return

proc flushNavigationCompletions(state: HostState) =
  for completed in state.adapter.takeNavigationCompletions():
    let payload = $(%*{
      "webViewId": $completed.webViewId,
      "url": completed.url,
      "succeeded": completed.succeeded
    })
    if not state.writeEvent("native.webview.navigationCompleted", payload, ""):
      discard state.adapter.app.close()
      return

proc flushDownloadEvents(state: HostState) =
  for event in state.adapter.takeDownloadEvents():
    let stateName = case event.state
      of nativeDownloadStarted: "started"
      of nativeDownloadProgress: "progress"
      of nativeDownloadCompleted: "completed"
      of nativeDownloadFailed: "failed"
      of nativeDownloadCancelled: "cancelled"
    let payload = $(%*{
      "webViewId": $event.webViewId,
      "url": event.url,
      "state": stateName,
      "progress": event.progress
    })
    if not state.writeEvent("native.webview.downloadEvent", payload, ""):
      discard state.adapter.app.close()
      return

proc flushWindowClosed(state: HostState) =
  for windowId in state.adapter.takeWindowClosed():
    if not state.writeEvent("native.window.closed", $(%*{"windowId": $windowId}), ""):
      discard state.adapter.app.close()
      return

proc flushWindowResized(state: HostState) =
  for resized in state.adapter.takeWindowResized():
    let payload = $(%*{
      "windowId": $resized.windowId,
      "width": resized.width,
      "height": resized.height
    })
    if not state.writeEvent("native.window.resized", payload, ""):
      discard state.adapter.app.close()
      return

proc flushDesktopActions(state: HostState) =
  for action in state.adapter.takeDesktopActions():
    let methodName = if action.kind == "notification":
      "native.app.notificationActivated"
    else: "native.app.desktopAction"
    let payload = if action.kind == "notification":
      $(%*{"notificationId": action.notificationId})
    else:
      $(%*{"kind": action.kind, "itemId": action.itemId})
    if not state.writeEvent(methodName, payload, ""):
      discard state.adapter.app.close()
      return

proc requestPolicy(state: HostState; request: PolicyRequest): bool =
  ## The native callback runs on the UI thread.  Keep the relay synchronous so
  ## WebView2/GTK receives a decision before the callback returns; every error
  ## path is deny-by-default.
  let requestId = state.nextPolicyRequestId
  inc state.nextPolicyRequestId
  if not state.writeMessage(ProtocolMessage(
      version: ProtocolVersion, kind: ProtocolMessageKind.request,
      sessionId: state.sessionId, requestId: requestId,
      methodName: "native.webview.policyRequested",
      payload: request.policyRequestJson(), timeoutMs: 5_000)):
    return false
  let received = state.input.next(5_000)
  if not received.isOk:
    return false
  let response = received.value
  let validated = state.sessionId.validatePolicyResponse(requestId, response)
  if not validated.isOk:
    ## A malformed policy response must not be left in the input stream for a
    ## later command.  Deny the current WebView request and tear down the
    ## authenticated session.
    discard state.adapter.app.close()
    return false
  if response.error.len != 0:
    return false
  let decision = response.payload.parsePolicyResponse()
  if not decision.isOk or not decision.value.allow:
    return false
  true

proc handleRunningMessage(state: HostState; message: ProtocolMessage) =
  let session = state.sessionId.validateSessionMessage(message)
  if not session.isOk:
    state.stopForProtocolError(message, session.failure.detail)
    return

  case message.kind
  of request:
    let action = state.adapter.handleRequest(message)
    if not action.isOk:
      if not state.writeMessage(state.responseForFailure(message, action.failure)):
        discard state.adapter.app.close()
      return
    if action.value.kind == deferredResponse:
      state.pendingEvaluations.add(PendingEvaluation(request: message, future: action.value.evaluation))
    elif action.value.kind == deferredBrowsingDataClear:
      state.pendingBrowsingDataClears.add(PendingBrowsingDataClear(
        request: message, future: action.value.browsingDataClear))
    elif action.value.kind == deferredFileDialog:
      state.pendingFileDialogs.add(PendingFileDialog(
        request: message, future: action.value.fileDialog))
    else:
      discard state.writeMessage(state.responseFor(message, payload = action.value.payload))
      if action.value.kind in {shutdownHost, restartHostForProfileReset}:
        discard state.adapter.closeAllWindows()
        discard state.adapter.app.close()
  of shutdown:
    discard state.writeMessage(state.responseFor(message, payload = "{}"))
    discard state.adapter.closeAllWindows()
    discard state.adapter.app.close()
  of heartbeat:
    discard state.writeMessage(state.responseFor(message, payload = "{}"))
  of cancel:
    state.cancelPending(message.requestId)
  else:
    state.stopForProtocolError(message, "message kind is not allowed after handshake")

proc pollHost(state: HostState) =
  let polled = state.input.poll()
  if not polled.isOk:
    ## Protocol diagnostics never include frame contents, session IDs, or
    ## authentication material.  Keeping the category visible avoids turning
    ## a malformed client frame into an unexplained UI shutdown.
    stderr.writeLine("nimino-wsl-host: input rejected: " & polled.failure.detail)
    discard state.adapter.app.close()
    return
  if state.input.closed:
    discard state.adapter.app.close()
    return
  for message in state.input.takePending():
    state.handleRunningMessage(message)
  state.flushEvaluations()
  state.flushBrowsingDataClears()
  state.flushFileDialogs()
  state.flushMessages()
  state.flushErrors()
  state.flushNewWindowRequests()
  state.flushNavigationStarts()
  state.flushNavigationCompletions()
  state.flushDownloadEvents()
  state.flushWindowResized()
  state.flushWindowClosed()
  state.flushDesktopActions()

proc runHost(): int =
  let expectedToken = getEnv("NIMINO_WSL_HOST_TOKEN")
  delEnv("NIMINO_WSL_HOST_TOKEN")
  if not expectedToken.isValidAuthenticationToken:
    stderr.writeLine("nimino-wsl-host: authentication is unavailable")
    return 2

  let input = newHostInput()
  let output = newFileStream(stdout)
  if not input.isOk or output.isNil:
    stderr.writeLine("nimino-wsl-host: standard streams are unavailable")
    return 2

  let hello = input.value.next(5_000)
  if not hello.isOk:
    stderr.writeLine("nimino-wsl-host: handshake frame is invalid")
    return 2
  let authenticated = expectedToken.authenticateHello(hello.value)
  if not authenticated.isOk:
    stderr.writeLine("nimino-wsl-host: authentication failed")
    return 2

  let sessionId = sessionIdFromRandom()
  if sessionId.len == 0:
    stderr.writeLine("nimino-wsl-host: random source is unavailable")
    return 2

  let state {.cursor.} = HostState(
    adapter: newHostAdapter(),
    input: input.value,
    output: output,
    sessionId: sessionId,
    nextEventId: 1,
    nextPolicyRequestId: 1
  )
  let statePointer = cast[pointer](state)
  state.adapter.policyDecision = proc(request: PolicyRequest): bool =
    cast[HostState](statePointer).requestPolicy(request)
  state.adapter.navigationDecisionHook = proc(webViewId: uint64; url: string): bool =
    cast[HostState](statePointer).requestPolicy(PolicyRequest(kind: navigationPolicy,
      webViewId: webViewId, url: url))
  if not state.writeMessage(ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.ready,
    sessionId: sessionId,
    payload: state.readyCapabilities()
  )):
    stderr.writeLine("nimino-wsl-host: cannot write handshake response")
    return 2

  while true:
    let received = state.input.next(60_000)
    if not received.isOk:
      discard state.adapter.app.close()
      return 0
    let message = received.value
    let session = state.sessionId.validateSessionMessage(message)
    if not session.isOk:
      state.stopForProtocolError(message, session.failure.detail)
      return 2

    if message.kind == shutdown:
      discard state.writeMessage(state.responseFor(message, payload = "{}"))
      discard state.adapter.closeAllWindows()
      discard state.adapter.app.close()
      return 0
    if message.kind == heartbeat:
      discard state.writeMessage(state.responseFor(message, payload = "{}"))
      continue
    if message.kind == cancel:
      ## No deferred operation exists before the UI loop starts.  Accept the
      ## authenticated cancellation as an idempotent no-op.
      continue
    if message.kind != request:
      state.stopForProtocolError(message, "message kind is not allowed after handshake")
      return 2

    let action = state.adapter.handleRequest(message)
    if not action.isOk:
      discard state.writeMessage(state.responseForFailure(message, action.failure))
      continue
    if action.value.kind == deferredResponse:
      discard state.writeMessage(state.responseFor(message,
        error = "JavaScript evaluation requires the UI loop"))
      continue
    if action.value.kind == deferredBrowsingDataClear:
      discard state.writeMessage(state.responseFor(message,
        error = "browser data clearing requires the UI loop"))
      continue
    if action.value.kind == deferredFileDialog:
      discard state.writeMessage(state.responseFor(message,
        error = "file dialogs require the UI loop"))
      continue
    if not state.writeMessage(state.responseFor(message, payload = action.value.payload)):
      discard state.adapter.app.close()
      return 2
    case action.value.kind
    of noHostAction:
      discard
    of deferredResponse:
      discard
    of deferredBrowsingDataClear:
      discard
    of deferredFileDialog:
      discard
    of shutdownHost, restartHostForProfileReset:
      discard state.adapter.closeAllWindows()
      discard state.adapter.app.close()
      return 0
    of startUiLoop:
      let configured = state.adapter.app.setIdleHandler(proc() = state.pollHost())
      if not configured.isOk:
        discard state.writeEvent("app.error", "", configured.failure.operation)
        return 2
      let finished = state.adapter.app.run()
      state.flushEvaluations()
      state.flushBrowsingDataClears()
      state.flushFileDialogs()
      state.flushMessages()
      state.flushErrors()
      state.flushNewWindowRequests()
      state.flushNavigationStarts()
      state.flushNavigationCompletions()
      state.flushDownloadEvents()
      state.flushWindowResized()
      state.flushWindowClosed()
      state.flushDesktopActions()
      if not finished.isOk:
        stderr.writeLine("nimino-wsl-host: native UI loop failed: " &
          finished.failure.operation & " (code=" & $finished.failure.platformCode & ")")
        if not state.writeEvent("app.error", "", finished.failure.operation):
          stderr.writeLine("nimino-wsl-host: cannot report native UI loop failure")
        return 2
      discard state.writeEvent("app.closed", "{}", "")
      return 0

when isMainModule:
  quit(runHost())
