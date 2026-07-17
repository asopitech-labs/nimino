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

  HostState = ref object
    adapter: HostAdapter
    input: HostInput
    output: Stream
    sessionId: string
    pendingEvaluations: seq[PendingEvaluation]
    nextEventId: uint64

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
    if pending.future.failed:
      error = "native.webview.evalJavaScript failed"
    else:
      let evaluation = pending.future.read()
      if evaluation.isOk:
        payload = $(%*{"result": evaluation.value})
      else:
        error = "native.webview.evalJavaScript failed: " & evaluation.failure.operation
    if not state.writeMessage(state.responseFor(pending.request, payload, error)):
      discard state.adapter.app.close()
      return
    state.pendingEvaluations.delete(index)

proc flushMessages(state: HostState) =
  for message in state.adapter.takeMessages():
    let payload = $(%*{
      "webViewId": $message.webViewId,
      "message": message.message
    })
    if not state.writeEvent("native.webview.message", payload, ""):
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

proc handleRunningMessage(state: HostState; message: ProtocolMessage) =
  let session = state.sessionId.validateSessionMessage(message)
  if not session.isOk:
    state.stopForProtocolError(message, session.failure.detail)
    return

  case message.kind
  of request:
    let action = state.adapter.handleRequest(message)
    if not action.isOk:
      if not state.writeMessage(state.responseFor(message, error = action.failure.detail)):
        discard state.adapter.app.close()
      return
    if action.value.kind == deferredResponse:
      state.pendingEvaluations.add(PendingEvaluation(request: message, future: action.value.evaluation))
    else:
      discard state.writeMessage(state.responseFor(message, payload = action.value.payload))
      if action.value.kind == shutdownHost:
        discard state.adapter.app.close()
  of shutdown:
    discard state.writeMessage(state.responseFor(message, payload = "{}"))
    discard state.adapter.app.close()
  of heartbeat:
    discard state.writeMessage(state.responseFor(message, payload = "{}"))
  else:
    state.stopForProtocolError(message, "message kind is not allowed after handshake")

proc pollHost(state: HostState) =
  let polled = state.input.poll()
  if not polled.isOk or state.input.closed:
    discard state.adapter.app.close()
    return
  for message in state.input.takePending():
    state.handleRunningMessage(message)
  state.flushEvaluations()
  state.flushMessages()
  state.flushNavigationStarts()
  state.flushNavigationCompletions()

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

  let state = HostState(
    adapter: newHostAdapter(),
    input: input.value,
    output: output,
    sessionId: sessionId,
    nextEventId: 1
  )
  if not state.writeMessage(ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.ready,
    sessionId: sessionId
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
      discard state.adapter.app.close()
      return 0
    if message.kind == heartbeat:
      discard state.writeMessage(state.responseFor(message, payload = "{}"))
      continue
    if message.kind != request:
      state.stopForProtocolError(message, "message kind is not allowed after handshake")
      return 2

    let action = state.adapter.handleRequest(message)
    if not action.isOk:
      discard state.writeMessage(state.responseFor(message, error = action.failure.detail))
      continue
    if action.value.kind == deferredResponse:
      discard state.writeMessage(state.responseFor(message,
        error = "JavaScript evaluation requires the UI loop"))
      continue
    if not state.writeMessage(state.responseFor(message, payload = action.value.payload)):
      discard state.adapter.app.close()
      return 2
    case action.value.kind
    of noHostAction:
      discard
    of deferredResponse:
      discard
    of shutdownHost:
      discard state.adapter.app.close()
      return 0
    of startUiLoop:
      let configured = state.adapter.app.setIdleHandler(proc() = state.pollHost())
      if not configured.isOk:
        discard state.writeEvent("app.error", "", configured.failure.operation)
        return 2
      let finished = state.adapter.app.run()
      state.flushEvaluations()
      state.flushMessages()
      state.flushNavigationStarts()
      state.flushNavigationCompletions()
      if not finished.isOk:
        discard state.writeEvent("app.error", "", finished.failure.operation)
        return 2
      discard state.writeEvent("app.closed", "{}", "")
      return 0

when isMainModule:
  quit(runHost())
