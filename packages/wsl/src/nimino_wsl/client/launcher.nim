import std/[os, osproc, strutils, strtabs, sysrand]

import ../protocol/[messages, versioning]
import ./transport

type
  WslClient* = ref object
    process: Process
    sessionId*: string
    nextRequestId*: uint64

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
  var names = if currentWslEnv.len == 0: @[] else: currentWslEnv.split(':')
  if "NIMINO_WSL_HOST_TOKEN" notin names:
    names.add("NIMINO_WSL_HOST_TOKEN")
  result["WSLENV"] = names.join(":")

proc launchHost*(hostExecutable: string; hostArgs: openArray[string] = []):
    ProtocolResultOf[WslClient] =
  if hostExecutable.len == 0:
    return failureOf[WslClient](protocolError(invalidMessage, "host executable is required"))

  let token = newAuthenticationToken()
  if not token.isOk:
    return failureOf[WslClient](token.failure)

  try:
    let process = startProcess(
      hostExecutable,
      args = hostArgs,
      env = childEnvironment(token.value),
      options = {poUsePath}
    )
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
      osproc.close(process)
      return failureOf[WslClient](readyMessage.failure)
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
  osproc.close(client.process)
  client.process = nil
  written
