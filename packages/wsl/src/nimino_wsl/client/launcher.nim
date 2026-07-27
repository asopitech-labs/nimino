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

const
  HostHandshakeTimeoutMs = 5_000
  HostFrameTimeoutMs = 5_000
  HostShutdownTimeoutMs = 5_000

when defined(posix):
  proc readExactly(handle: FileHandle; size: int): ProtocolResultOf[string] =
    ## Read directly from the child stdout descriptor.  We deliberately avoid
    ## `Process.outputStream` here: a buffered Stream can retain a following
    ## frame while `select` reports the descriptor as idle.
    result = successOf(newString(size))
    var offset = 0
    while offset < size:
      let readCount = posix.read(cint(handle), addr result.value[offset], size - offset)
      if readCount < 0 and osLastError() == OSErrorCode(EINTR):
        continue
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

  proc waitUntilReadable(handle: FileHandle; timeoutMs: int):
      ProtocolResultOf[bool] =
    let deadline = getMonoTime() +
      initDuration(milliseconds = int64(timeoutMs))
    while true:
      let remaining = max(0'i64,
        (deadline - getMonoTime()).inMilliseconds)
      var readable: TFdSet
      FD_ZERO(readable)
      FD_SET(cint(handle), readable)
      var timeout = Timeval(
        tv_sec: Time(remaining div 1_000),
        tv_usec: Suseconds((remaining mod 1_000) * 1_000)
      )
      let selected = posix.select(cint(handle) + 1, addr readable, nil, nil,
        addr timeout)
      if selected >= 0:
        return successOf(selected > 0)
      if osLastError() != OSErrorCode(EINTR):
        return failureOf[bool](
          protocolError(invalidFrame, "unable to poll Windows host output"))
      if getMonoTime() >= deadline:
        return successOf(false)

  proc readExactlyBefore(handle: FileHandle; size: int; deadline: MonoTime):
      ProtocolResultOf[string] =
    result = successOf(newString(size))
    var offset = 0
    while offset < size:
      let remaining = (deadline - getMonoTime()).inMilliseconds
      if remaining <= 0:
        return failureOf[string](
          protocolError(timedOut, "host frame timed out"))
      let readable = handle.waitUntilReadable(
        int(min(remaining, int64(high(int)))))
      if not readable.isOk:
        return failureOf[string](readable.failure)
      if not readable.value:
        return failureOf[string](
          protocolError(timedOut, "host frame timed out"))
      let readCount = posix.read(cint(handle), addr result.value[offset],
        size - offset)
      if readCount < 0 and osLastError() == OSErrorCode(EINTR):
        continue
      if readCount <= 0:
        return failureOf[string](protocolError(unexpectedEof,
          "host stdout ended before frame completed"))
      offset += readCount

  proc readMessageFromHandleWithin(handle: FileHandle;
      availabilityTimeoutMs, frameTimeoutMs: int):
      ProtocolResultOf[Option[ProtocolMessage]] =
    let deadline = getMonoTime() +
      initDuration(milliseconds = int64(frameTimeoutMs))
    let firstByte = handle.waitUntilReadable(availabilityTimeoutMs)
    if not firstByte.isOk:
      return failureOf[Option[ProtocolMessage]](firstByte.failure)
    if not firstByte.value:
      return successOf(none(ProtocolMessage))

    ## `availabilityTimeoutMs` is an event-loop poll interval. The separate
    ## frame deadline is measured from this call's start, so a 10 ms idle poll
    ## can accept a split frame without extending a 5 second handshake/request.
    let header = handle.readExactlyBefore(4, deadline)
    if not header.isOk:
      return failureOf[Option[ProtocolMessage]](header.failure)
    let size = (int(byte(header.value[0])) shl 24) or
      (int(byte(header.value[1])) shl 16) or
      (int(byte(header.value[2])) shl 8) or int(byte(header.value[3]))
    if size > MaxFrameBytes:
      return failureOf[Option[ProtocolMessage]](
        protocolError(frameTooLarge, "frame exceeds maximum size"))
    let payload = handle.readExactlyBefore(size, deadline)
    if not payload.isOk:
      return failureOf[Option[ProtocolMessage]](payload.failure)
    let decoded = payload.value.fromJson()
    if not decoded.isOk:
      return failureOf[Option[ProtocolMessage]](decoded.failure)
    successOf(some(decoded.value))

proc readHostMessage(client: WslClient): ProtocolResultOf[ProtocolMessage] =
  if client.isNil or client.process.isNil:
    return failureOf[ProtocolMessage](protocolError(invalidMessage, "WSL client is closed"))
  when defined(posix):
    client.process.outputHandle.readMessageFromHandle()
  else:
    client.process.outputStream.readMessageFrom()

proc readHostMessageWithin(client: WslClient;
    availabilityTimeoutMs, frameTimeoutMs: int):
    ProtocolResultOf[Option[ProtocolMessage]] =
  if client.isNil or client.process.isNil:
    return failureOf[Option[ProtocolMessage]](
      protocolError(invalidMessage, "WSL client is closed"))
  if availabilityTimeoutMs < 0 or frameTimeoutMs < 0:
    return failureOf[Option[ProtocolMessage]](
      protocolError(invalidMessage, "timeout must not be negative"))
  when defined(posix):
    client.process.outputHandle.readMessageFromHandleWithin(
      availabilityTimeoutMs, frameTimeoutMs)
  else:
    if availabilityTimeoutMs == 0:
      return successOf(none(ProtocolMessage))
    let received = client.readHostMessage()
    if not received.isOk:
      return failureOf[Option[ProtocolMessage]](received.failure)
    successOf(some(received.value))

proc stopHostProcess(process: Process) =
  if process.isNil:
    return
  try:
    if process.peekExitCode() == -1:
      process.terminate()
      discard process.waitForExit(2_000)
  except CatchableError:
    discard
  try:
    osproc.close(process)
  except CatchableError:
    discard

proc waitForHostExit(process: Process; timeoutMs: int): int =
  let deadline = getMonoTime() + initDuration(milliseconds = int64(timeoutMs))
  while getMonoTime() < deadline:
    try:
      let exitCode = process.peekExitCode()
      if exitCode != -1:
        osproc.close(process)
        return exitCode
    except CatchableError:
      process.stopHostProcess()
      return -1
    sleep(10)
  process.stopHostProcess()
  -1

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

  var process: Process
  try:
    process = startHostProcess(hostExecutable, hostArgs, token.value)
    let client = WslClient(process: process, nextRequestId: 1)
    let hello = ProtocolMessage(
      version: ProtocolVersion,
      kind: hello,
      authenticationToken: token.value,
      timeoutMs: HostHandshakeTimeoutMs
    )
    let written = process.inputStream.writeMessageTo(hello)
    if not written.isOk:
      process.stopHostProcess()
      return failureOf[WslClient](written.failure)

    let readyWithin = client.readHostMessageWithin(
      HostHandshakeTimeoutMs, HostHandshakeTimeoutMs)
    if not readyWithin.isOk:
      let failure = readyWithin.failure
      let detail =
        if failure.kind == unexpectedEof:
          process.startupFailureDetail()
        else:
          failure.detail
      process.stopHostProcess()
      return failureOf[WslClient](protocolError(failure.kind, detail))
    if readyWithin.value.isNone:
      process.stopHostProcess()
      return failureOf[WslClient](
        protocolError(timedOut, "Windows host ready handshake timed out"))
    let readyMessage = readyWithin.value.get()
    let ready = readyMessage.validateReady()
    if not ready.isOk:
      process.stopHostProcess()
      return failureOf[WslClient](ready.failure)
    let capabilities = readyMessage.payload.parseNativeCapabilities()
    if not capabilities.isOk:
      process.stopHostProcess()
      return failureOf[WslClient](capabilities.failure)

    client.sessionId = readyMessage.sessionId
    client.capabilities = capabilities.value
    successOf(client)
  except CatchableError:
    process.stopHostProcess()
    failureOf[WslClient](
      protocolError(invalidMessage, "unable to launch Windows host"))

proc validateHostMessage(client: WslClient; message: ProtocolMessage):
    ProtocolResultOf[ProtocolMessage] =
  if message.sessionId != client.sessionId:
    return failureOf[ProtocolMessage](
      protocolError(invalidMessage, "host response has an unknown session"))
  if not message.version.validateVersion.isOk:
    return failureOf[ProtocolMessage](
      protocolError(unsupportedVersion, "host version mismatch"))
  if message.authenticationToken.len != 0:
    return failureOf[ProtocolMessage](
      protocolError(authenticationFailed,
        "host returned authentication material"))
  successOf(message)

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
  client.validateHostMessage(received.value)

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

proc receiveNextWithin(client: WslClient;
    availabilityTimeoutMs, frameTimeoutMs: int):
    ProtocolResultOf[Option[ProtocolMessage]] =
  ## Separate the idle-poll budget from the completion budget for a frame that
  ## has already started.
  if client.isNil or client.process.isNil:
    return failureOf[Option[ProtocolMessage]](
      protocolError(invalidMessage, "WSL client is closed"))
  if availabilityTimeoutMs < 0 or frameTimeoutMs < 0:
    return failureOf[Option[ProtocolMessage]](
      protocolError(invalidMessage, "timeout must not be negative"))

  let received = client.readHostMessageWithin(
    availabilityTimeoutMs, frameTimeoutMs)
  if not received.isOk:
    return failureOf[Option[ProtocolMessage]](received.failure)
  if received.value.isNone:
    return successOf(none(ProtocolMessage))
  let validated = client.validateHostMessage(received.value.get())
  if not validated.isOk:
    return failureOf[Option[ProtocolMessage]](validated.failure)
  successOf(some(validated.value))

proc receiveNextWithin*(client: WslClient; timeoutMs: int):
    ProtocolResultOf[Option[ProtocolMessage]] =
  ## Poll for a new frame for at most `timeoutMs`. A frame that has begun gets
  ## its own bounded completion interval, so a short UI/RPC poll does not
  ## reject a valid frame merely because the pipe write was split.
  client.receiveNextWithin(timeoutMs, HostFrameTimeoutMs)

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
    let remainingMs = int(min(remaining, int64(high(int))))
    let received = client.receiveNextWithin(remainingMs, remainingMs)
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
    client.process.stopHostProcess()
    client.process = nil
    return written

  let acknowledged = client.receiveResponse(0, HostShutdownTimeoutMs)
  if not acknowledged.isOk:
    client.process.stopHostProcess()
    client.process = nil
    return failure(acknowledged.failure)

  let exitCode = client.process.waitForHostExit(HostShutdownTimeoutMs)
  client.process = nil
  if exitCode == -1:
    return failure(protocolError(timedOut,
      "Windows host did not exit after shutdown acknowledgement"))
  if exitCode != 0:
    return failure(protocolError(invalidMessage,
      "Windows host exited with status " & $exitCode))
  success()
