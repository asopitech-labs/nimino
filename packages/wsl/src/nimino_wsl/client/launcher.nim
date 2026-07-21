import std/[monotimes, options, os, osproc, streams, strutils, strtabs, sysrand]
from std/times import inMilliseconds, initDuration

when defined(posix):
  import std/posix

import ../protocol/[messages, versioning]
import ./transport

type
  WslClient* = ref object
    process: Process
    sessionId*: string
    ## Captured once from the authenticated ready frame.  Native capability
    ## support is static for a host session; retaining the snapshot prevents
    ## callers from treating an unvalidated later response as negotiation.
    capabilities*: seq[string]
    nextRequestId*: uint64
    events: seq[ProtocolMessage]
    responses: seq[ProtocolMessage]

when defined(posix):
  proc readExactly(handle: FileHandle; size: int): ProtocolResultOf[string] =
    ## Read directly from the child stdout descriptor.  We deliberately avoid
    ## `Process.outputStream` here: a buffered Stream can retain a following
    ## frame while `select` reports the descriptor as idle.
    result = successOf(newString(size))
    var offset = 0
    while offset < size:
      let readCount = posix.read(cint(handle), addr result.value[offset], size - offset)
      if readCount <= 0:
        return failureOf[string](protocolError(unexpectedEof,
          "host stdout ended before frame completed"))
      offset += readCount

  proc readMessageFromHandle(handle: FileHandle): ProtocolResultOf[ProtocolMessage] =
    let header = handle.readExactly(4)
    if not header.isOk:
      return failureOf[ProtocolMessage](header.failure)
    let size = (int(byte(header.value[0])) shl 24) or
      (int(byte(header.value[1])) shl 16) or
      (int(byte(header.value[2])) shl 8) or int(byte(header.value[3]))
    if size > MaxFrameBytes:
      return failureOf[ProtocolMessage](protocolError(frameTooLarge,
        "frame exceeds maximum size"))
    let payload = handle.readExactly(size)
    if not payload.isOk:
      return failureOf[ProtocolMessage](payload.failure)
    payload.value.fromJson

proc readHostMessage(client: WslClient): ProtocolResultOf[ProtocolMessage] =
  if client.isNil or client.process.isNil:
    return failureOf[ProtocolMessage](protocolError(invalidMessage, "WSL client is closed"))
  when defined(posix):
    client.process.outputHandle.readMessageFromHandle()
  else:
    client.process.outputStream.readMessageFrom()

proc newAuthenticationToken(): ProtocolResultOf[string] =
  let bytes = urandom(32)
  if bytes.len != 32:
    return failureOf[string](protocolError(authenticationFailed, "OS random source unavailable"))

  const hexDigits = "0123456789abcdef"
  result = successOf(newStringOfCap(AuthenticationTokenHexLength))
  for value in bytes:
    result.value.add(hexDigits[int(value shr 4)])
    result.value.add(hexDigits[int(value and 0x0f)])

proc childEnvironment(token: string): StringTableRef =
  ## WSLENV is the explicit WSL-to-Windows propagation allow-list.  Do not put
  ## the token in args, stdout, stderr, or a persistent parent environment.
  result = newStringTable(modeCaseSensitive)
  for key, value in envPairs():
    result[key] = value

  result["NIMINO_WSL_HOST_TOKEN"] = token
  let currentWslEnv = getEnv("WSLENV")
  var names: seq[string]
  for name in currentWslEnv.split(':'):
    if name.len > 0:
      names.add(name)
  if "NIMINO_WSL_HOST_TOKEN" notin names:
    names.add("NIMINO_WSL_HOST_TOKEN")
  result["WSLENV"] = names.join(":")

proc quoteForCmd(value: string): string =
  ## The command is passed as one `/C` argument.  Quote each component so a
  ## space in the Windows/UNC path cannot change the executable or arguments.
  var safeWithoutQuotes = value.len > 0
  for character in value:
    if not (character.isAlphaNumeric or character in {'\\', '/', '.', '_', '-', ':'}):
      safeWithoutQuotes = false
      break
  if safeWithoutQuotes:
    return value
  "\"" & value.replace("\"", "\"\"") & "\""

proc windowsInteropWorkingDirectory(): string =
  ## Starting cmd.exe from a WSL UNC current directory makes cmd emit its
  ## "UNC paths are not supported" diagnostic on stdout, corrupting frames.
  for candidate in ["/mnt/c/Windows", "/mnt/c"]:
    if dirExists(candidate):
      return candidate
  getCurrentDir()

proc startHostProcess(hostExecutable: string; hostArgs: openArray[string];
                      token: string): Process =
  let environment = childEnvironment(token)
  if existsEnv("WSL_INTEROP"):
    var command = hostExecutable.quoteForCmd()
    for argument in hostArgs:
      command.add(' ')
      command.add(argument.quoteForCmd())
    return startProcess(
      "cmd.exe",
      workingDir = windowsInteropWorkingDirectory(),
      args = ["/D", "/S", "/C", command],
      env = environment,
      options = {poUsePath}
    )
  startProcess(hostExecutable, args = hostArgs, env = environment, options = {poUsePath})

proc sanitizeStartupDiagnostic*(diagnostic: string): string =
  ## stderr is diagnostic-only, but it must not become a back channel for
  ## authentication material.  Keep only host messages whose complete text is
  ## fixed by this implementation; all other child stderr is intentionally
  ## replaced by the generic exit-status error below.
  case diagnostic
  of "nimino-wsl-host: authentication is unavailable",
     "nimino-wsl-host: standard streams are unavailable",
     "nimino-wsl-host: handshake frame is invalid",
     "nimino-wsl-host: authentication failed",
     "nimino-wsl-host: random source is unavailable",
     "nimino-wsl-host: cannot write handshake response":
    diagnostic
  else:
    ""

proc startupFailureDetail(process: Process): string =
  ## The host's own diagnostics are fixed, token-free strings.  Do not relay
  ## arbitrary child stderr into protocol errors or application logs.
  let exitCode = process.peekExitCode()
  if exitCode == -1:
    return "Windows host closed stdout before the ready handshake"
  try:
    let diagnostic = process.errorStream.readAll().strip()
    let sanitized = diagnostic.sanitizeStartupDiagnostic()
    if sanitized.len > 0:
      return sanitized
  except CatchableError:
    discard
  "Windows host exited before the ready handshake (exit code " & $exitCode & ")"

proc launchHost*(hostExecutable: string; hostArgs: openArray[string] = []):
    ProtocolResultOf[WslClient] =
  if hostExecutable.len == 0:
    return failureOf[WslClient](protocolError(invalidMessage, "host executable is required"))

  let token = newAuthenticationToken()
  if not token.isOk:
    return failureOf[WslClient](token.failure)

  try:
    let process = startHostProcess(hostExecutable, hostArgs, token.value)
    let client = WslClient(process: process, nextRequestId: 1)
    let hello = ProtocolMessage(
      version: ProtocolVersion,
      kind: hello,
      authenticationToken: token.value,
      timeoutMs: 5_000
    )
    let written = process.inputStream.writeMessageTo(hello)
    if not written.isOk:
      osproc.close(process)
      return failureOf[WslClient](written.failure)

    let readyMessage = client.readHostMessage()
    if not readyMessage.isOk:
      let detail = process.startupFailureDetail()
      osproc.close(process)
      return failureOf[WslClient](protocolError(readyMessage.failure.kind, detail))
    let ready = readyMessage.value.validateReady()
    if not ready.isOk:
      osproc.close(process)
      return failureOf[WslClient](ready.failure)
    let capabilities = readyMessage.value.payload.parseNativeCapabilities()
    if not capabilities.isOk:
      osproc.close(process)
      return failureOf[WslClient](capabilities.failure)

    client.sessionId = readyMessage.value.sessionId
    client.capabilities = capabilities.value
    successOf(client)
  except CatchableError:
    failureOf[WslClient](protocolError(invalidMessage, "unable to launch Windows host"))

proc sendRequest*(client: WslClient; methodName: string; payload: string;
                  timeoutMs: uint32 = 5_000): ProtocolResultOf[uint64] =
  if client.isNil or client.process.isNil:
    return failureOf[uint64](protocolError(invalidMessage, "WSL client is closed"))
  if methodName.len == 0:
    return failureOf[uint64](protocolError(invalidMessage, "method is required"))

  let requestId = client.nextRequestId
  inc client.nextRequestId
  let request = ProtocolMessage(
    version: ProtocolVersion,
    kind: request,
    sessionId: client.sessionId,
    requestId: requestId,
    methodName: methodName,
    payload: payload,
    timeoutMs: timeoutMs
  )
  let written = client.process.inputStream.writeMessageTo(request)
  if not written.isOk:
    return failureOf[uint64](written.failure)
  successOf(requestId)

proc receiveNext*(client: WslClient): ProtocolResultOf[ProtocolMessage] =
  ## Read one validated host message.  Event-loop adapters use this instead of
  ## `receiveResponse` when the host owns the GUI loop and emits unsolicited
  ## lifecycle or WebView events.
  if client.isNil or client.process.isNil:
    return failureOf[ProtocolMessage](protocolError(invalidMessage, "WSL client is closed"))
  let received = client.readHostMessage()
  if not received.isOk:
    return failureOf[ProtocolMessage](received.failure)
  let message = received.value
  if message.sessionId != client.sessionId:
    return failureOf[ProtocolMessage](protocolError(invalidMessage, "host response has an unknown session"))
  if not message.version.validateVersion.isOk:
    return failureOf[ProtocolMessage](protocolError(unsupportedVersion, "host version mismatch"))
  if message.authenticationToken.len != 0:
    return failureOf[ProtocolMessage](protocolError(authenticationFailed, "host returned authentication material"))
  successOf(message)

proc sendResponse*(client: WslClient; requestId: uint64; payload: string;
                   error = ""): ProtocolResult =
  ## Reply to a host-initiated request (for example a policy decision).
  if client.isNil or client.process.isNil:
    return failure(protocolError(invalidMessage, "WSL client is closed"))
  let response = ProtocolMessage(
    version: ProtocolVersion,
    kind: ProtocolMessageKind.response,
    sessionId: client.sessionId,
    requestId: requestId,
    payload: payload,
    error: error
  )
  client.process.inputStream.writeMessageTo(response)

proc sendCancel*(client: WslClient; requestId: uint64): ProtocolResult =
  if client.isNil or client.process.isNil:
    return failure(protocolError(invalidMessage, "WSL client is closed"))
  if requestId == 0:
    return failure(protocolError(invalidMessage, "cancel request ID is required"))
  client.process.inputStream.writeMessageTo(ProtocolMessage(
    version: ProtocolVersion,
    kind: cancel,
    sessionId: client.sessionId,
    requestId: requestId
  ))

proc receiveNextWithin*(client: WslClient; timeoutMs: int):
    ProtocolResultOf[Option[ProtocolMessage]] =
  ## Wait for at most `timeoutMs` for one host frame.  The WSL core loop uses
  ## this to advance RPC deadlines even while the Windows host has no events.
  if client.isNil or client.process.isNil:
    return failureOf[Option[ProtocolMessage]](
      protocolError(invalidMessage, "WSL client is closed"))
  if timeoutMs < 0:
    return failureOf[Option[ProtocolMessage]](
      protocolError(invalidMessage, "timeout must not be negative"))

  when defined(posix):
    let handle = cint(client.process.outputHandle)
    var readable: TFdSet
    FD_ZERO(readable)
    FD_SET(handle, readable)
    var timeout = Timeval(
      tv_sec: Time(timeoutMs div 1_000),
      tv_usec: Suseconds((timeoutMs mod 1_000) * 1_000)
    )
    let selected = posix.select(handle + 1, addr readable, nil, nil, addr timeout)
    if selected < 0:
      return failureOf[Option[ProtocolMessage]](
        protocolError(invalidFrame, "unable to poll Windows host output"))
    if selected == 0:
      return successOf(none(ProtocolMessage))
    let received = client.receiveNext()
    if not received.isOk:
      return failureOf[Option[ProtocolMessage]](received.failure)
    successOf(some(received.value))
  else:
    ## The adapter is only selected on Linux/WSL.  Keep a conservative
    ## fallback for callers that compile this module for another platform.
    if timeoutMs == 0:
      return successOf(none(ProtocolMessage))
    let received = client.receiveNext()
    if not received.isOk:
      return failureOf[Option[ProtocolMessage]](received.failure)
    successOf(some(received.value))

proc hostResponseFailure(response: ProtocolMessage): ProtocolError =
  let summary = if response.error.len > 0: response.error
                elif response.errorDetail.len > 0: response.errorDetail
                else: "host rejected request"
  protocolNativeError(invalidMessage, summary, response.errorKind,
    response.errorOperation, response.errorDetail,
    response.errorPlatformCode)

proc receiveResponse*(client: WslClient; requestId: uint64;
                      timeoutMs: uint32 = 5_000): ProtocolResultOf[ProtocolMessage] =
  if client.isNil or client.process.isNil:
    return failureOf[ProtocolMessage](protocolError(invalidMessage, "WSL client is closed"))

  let deadline = getMonoTime() + initDuration(milliseconds = int64(timeoutMs))
  while true:
    var bufferedIndex = 0
    while bufferedIndex < client.responses.len:
      let buffered = client.responses[bufferedIndex]
      if buffered.requestId != requestId:
        inc bufferedIndex
        continue
      client.responses.delete(bufferedIndex)
      if buffered.error.len != 0 or buffered.errorKind.len != 0 or
          buffered.errorOperation.len != 0 or buffered.errorDetail.len != 0:
        return failureOf[ProtocolMessage](buffered.hostResponseFailure())
      return successOf(buffered)
    let remaining = (deadline - getMonoTime()).inMilliseconds
    if remaining <= 0:
      discard client.sendCancel(requestId)
      return failureOf[ProtocolMessage](protocolError(timedOut,
        "host response timed out"))
    let received = client.receiveNextWithin(int(min(remaining, int64(high(int)))))
    if not received.isOk:
      return failureOf[ProtocolMessage](received.failure)
    if received.value.isNone:
      discard client.sendCancel(requestId)
      return failureOf[ProtocolMessage](protocolError(timedOut,
        "host response timed out"))
    let hostResponse = received.value.get()
    if hostResponse.kind == event:
      client.events.add(hostResponse)
      continue
    if hostResponse.kind != ProtocolMessageKind.response:
      return failureOf[ProtocolMessage](protocolError(invalidMessage, "host response does not match request"))
    if hostResponse.requestId != requestId:
      ## A UI-loop request may complete while a synchronous setup/RPC request
      ## is waiting. Preserve it for the core request-ID dispatcher instead of
      ## turning valid concurrent completions into a protocol failure.
      client.responses.add(hostResponse)
      continue
    if hostResponse.error.len != 0 or hostResponse.errorKind.len != 0 or
        hostResponse.errorOperation.len != 0 or hostResponse.errorDetail.len != 0:
      return failureOf[ProtocolMessage](hostResponse.hostResponseFailure())
    return successOf(hostResponse)

proc takeEvents*(client: WslClient): seq[ProtocolMessage] =
  if client.isNil:
    return @[]
  result = client.events
  client.events.setLen(0)

proc takeResponses*(client: WslClient): seq[ProtocolMessage] =
  ## Returns authenticated responses parked while another request waited for
  ## its own completion. Callers must still validate request IDs locally.
  if client.isNil:
    return @[]
  result = client.responses
  client.responses.setLen(0)

proc call*(client: WslClient; methodName: string; payload: string;
           timeoutMs: uint32 = 5_000): ProtocolResultOf[ProtocolMessage] =
  let sent = client.sendRequest(methodName, payload, timeoutMs)
  if not sent.isOk:
    return failureOf[ProtocolMessage](sent.failure)
  client.receiveResponse(sent.value, timeoutMs)

proc close*(client: WslClient): ProtocolResult =
  if client.isNil or client.process.isNil:
    return failure(protocolError(invalidMessage, "WSL client is closed"))

  let shutdown = ProtocolMessage(
    version: ProtocolVersion,
    kind: shutdown,
    sessionId: client.sessionId,
    timeoutMs: 5_000
  )
  let written = client.process.inputStream.writeMessageTo(shutdown)
  if not written.isOk:
    osproc.close(client.process)
    client.process = nil
    return written

  let acknowledged = client.receiveResponse(0, 5_000)
  osproc.close(client.process)
  client.process = nil
  if not acknowledged.isOk:
    return failure(acknowledged.failure)
  success()
