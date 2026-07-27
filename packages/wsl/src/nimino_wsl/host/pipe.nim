## Non-blocking stdin reader for the Windows host.  It is polled from the
## Win32 UI thread, so no second Nim thread can touch native objects.

import ../protocol/[messages, versioning]

type
  WinHandle = pointer

  HostInput* = ref object
    handle: WinHandle
    buffer: string
    pending: seq[ProtocolMessage]
    closed*: bool

const
  StdInputHandle = -10'i32
  ErrorBrokenPipe = 109'u32

proc getStdHandle(identifier: int32): WinHandle
  {.stdcall, importc: "GetStdHandle", dynlib: "kernel32.dll".}
proc peekNamedPipe(handle: WinHandle; buffer: pointer; bytesToRead: uint32;
                   bytesRead, bytesAvailable, bytesLeft: ptr uint32): int32
  {.stdcall, importc: "PeekNamedPipe", dynlib: "kernel32.dll".}
proc readFile(handle: WinHandle; buffer: pointer; bytesToRead: uint32;
              bytesRead: ptr uint32; overlapped: pointer): int32
  {.stdcall, importc: "ReadFile", dynlib: "kernel32.dll".}
proc getLastError(): uint32
  {.stdcall, importc: "GetLastError", dynlib: "kernel32.dll".}
proc sleep(milliseconds: uint32)
  {.stdcall, importc: "Sleep", dynlib: "kernel32.dll".}
proc getTickCount64(): uint64
  {.stdcall, importc: "GetTickCount64", dynlib: "kernel32.dll".}

proc newHostInput*(): ProtocolResultOf[HostInput] =
  let handle = getStdHandle(StdInputHandle)
  if handle.isNil or handle == cast[WinHandle](-1):
    return failureOf[HostInput](protocolError(invalidFrame, "stdin handle is unavailable"))
  successOf(HostInput(handle: handle))

proc readAvailableChunk(input: HostInput): ProtocolResultOf[bool] =
  ## Read one bounded chunk at a time. `poll` decodes between chunks so the
  ## frame-size limit is enforced before a continuously-writing peer can grow
  ## `buffer` without bound.
  var available: uint32
  if peekNamedPipe(input.handle, nil, 0, nil, addr available, nil) == 0:
    if getLastError() == ErrorBrokenPipe:
      input.closed = true
      return successOf(false)
    return failureOf[bool](
      protocolError(invalidFrame, "cannot inspect host stdin"))
  if available == 0:
    return successOf(false)

  let requested = min(int(available), 8_192)
  var chunk = newString(requested)
  var read: uint32
  if readFile(input.handle, addr chunk[0], uint32(requested), addr read, nil) == 0:
    if getLastError() == ErrorBrokenPipe:
      input.closed = true
      return successOf(false)
    return failureOf[bool](
      protocolError(invalidFrame, "cannot read host stdin"))
  if read == 0:
    return successOf(false)
  chunk.setLen(int(read))
  input.buffer.add(chunk)
  successOf(true)

proc decodeBuffered(input: HostInput): ProtocolResult =
  while input.buffer.len >= 4:
    let size = (int(byte(input.buffer[0])) shl 24) or
      (int(byte(input.buffer[1])) shl 16) or
      (int(byte(input.buffer[2])) shl 8) or int(byte(input.buffer[3]))
    if size > MaxFrameBytes:
      input.buffer.setLen(0)
      return failure(protocolError(frameTooLarge, "frame exceeds maximum size"))
    let frameLength = 4 + size
    if input.buffer.len < frameLength:
      return success()

    let decoded = input.buffer[4 ..< frameLength].fromJson()
    if not decoded.isOk:
      ## A malformed frame is a fatal protocol error. Do not retain and
      ## repeatedly re-parse the same attacker-controlled bytes while the UI
      ## loop processes its close request.
      input.buffer.setLen(0)
      return failure(decoded.failure)
    input.pending.add(decoded.value)
    if input.buffer.len == frameLength:
      input.buffer.setLen(0)
    else:
      input.buffer = input.buffer[frameLength .. ^1]
  success()

proc poll*(input: HostInput): ProtocolResult =
  while true:
    let readChunk = input.readAvailableChunk()
    if not readChunk.isOk:
      return failure(readChunk.failure)
    let decoded = input.decodeBuffered()
    if not decoded.isOk:
      return decoded
    if not readChunk.value or input.pending.len > 0:
      return success()

proc next*(input: HostInput; timeoutMs: uint32): ProtocolResultOf[ProtocolMessage] =
  let started = getTickCount64()
  while true:
    let polled = input.poll()
    if not polled.isOk:
      return failureOf[ProtocolMessage](polled.failure)
    if input.pending.len > 0:
      result = successOf(input.pending[0])
      input.pending.delete(0)
      return
    if input.closed:
      return failureOf[ProtocolMessage](protocolError(unexpectedEof, "host stdin closed"))
    if getTickCount64() - started >= uint64(timeoutMs):
      return failureOf[ProtocolMessage](protocolError(timedOut, "host message timed out"))
    sleep(10)

proc takePending*(input: HostInput): seq[ProtocolMessage] =
  result = input.pending
  input.pending.setLen(0)
