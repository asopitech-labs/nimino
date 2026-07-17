import std/[os, osproc, streams, strutils, strtabs, sysrand]

import ../protocol/[messages, versioning]
import ./transport

type
  WslClient* = ref object
    process: Process
    sessionId*: string
    nextRequestId*: uint64
    events: seq[ProtocolMessage]

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

proc startupFailureDetail(process: Process): string =
  ## The host's own diagnostics are fixed, token-free strings.  Do not relay
  ## arbitrary child stderr into protocol errors or application logs.
  let exitCode = process.peekExitCode()
  if exitCode == -1:
    return "Windows host closed stdout before the ready handshake"
  try:
    let diagnostic = process.errorStream.readAll().strip()
    if diagnostic.startsWith("nimino-wsl-host:"):
      return diagnostic
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

    let readyMessage = process.outputStream.readMessageFrom()
    if not readyMessage.isOk:
      let detail = process.startupFailureDetail()
      osproc.close(process)
      return failureOf[WslClient](protocolError(readyMessage.failure.kind, detail))
    if readyMessage.value.kind != ready:
      osproc.close(process)
      return failureOf[WslClient](protocolError(invalidMessage, "host did not return ready"))
    if not readyMessage.value.version.validateVersion.isOk:
      osproc.close(process)
      return failureOf[WslClient](protocolError(unsupportedVersion, "host version mismatch"))

    client.sessionId = readyMessage.value.sessionId
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

proc receiveResponse*(client: WslClient; requestId: uint64): ProtocolResultOf[ProtocolMessage] =
  if client.isNil or client.process.isNil:
    return failureOf[ProtocolMessage](protocolError(invalidMessage, "WSL client is closed"))

  while true:
    let received = client.process.outputStream.readMessageFrom()
    if not received.isOk:
      return failureOf[ProtocolMessage](received.failure)
    let hostResponse = received.value
    if hostResponse.sessionId != client.sessionId:
      return failureOf[ProtocolMessage](protocolError(invalidMessage, "host response has an unknown session"))
    if not hostResponse.version.validateVersion.isOk:
      return failureOf[ProtocolMessage](protocolError(unsupportedVersion, "host version mismatch"))
    if hostResponse.authenticationToken.len != 0:
      return failureOf[ProtocolMessage](protocolError(authenticationFailed, "host returned authentication material"))
    if hostResponse.kind == event:
      client.events.add(hostResponse)
      continue
    if hostResponse.kind != ProtocolMessageKind.response or hostResponse.requestId != requestId:
      return failureOf[ProtocolMessage](protocolError(invalidMessage, "host response does not match request"))
    if hostResponse.error.len != 0:
      return failureOf[ProtocolMessage](protocolError(invalidMessage, "host rejected request: " & hostResponse.error))
    return successOf(hostResponse)

proc takeEvents*(client: WslClient): seq[ProtocolMessage] =
  if client.isNil:
    return @[]
  result = client.events
  client.events.setLen(0)

proc call*(client: WslClient; methodName: string; payload: string;
           timeoutMs: uint32 = 5_000): ProtocolResultOf[ProtocolMessage] =
  let sent = client.sendRequest(methodName, payload, timeoutMs)
  if not sent.isOk:
    return failureOf[ProtocolMessage](sent.failure)
  client.receiveResponse(sent.value)

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

  let acknowledged = client.receiveResponse(0)
  osproc.close(client.process)
  client.process = nil
  if not acknowledged.isOk:
    return failure(acknowledged.failure)
  success()
