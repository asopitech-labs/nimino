import std/streams

import ../protocol/[messages, serialization, versioning]

proc bytesToString(bytes: openArray[byte]): string =
  result = newString(bytes.len)
  for index, value in bytes:
    result[index] = char(value)

proc readExactly(stream: Stream; size: int): ProtocolResultOf[string] =
  result = successOf(newString(size))
  var offset = 0
  while offset < size:
    let read = stream.readData(addr result.value[offset], size - offset)
    if read <= 0:
      return failureOf[string](protocolError(unexpectedEof, "stream ended before frame completed"))
    offset += read

proc writeFrameTo*(stream: Stream; payload: string): ProtocolResult =
  let frame = payload.encodeFrame
  if not frame.isOk:
    return failure(frame.failure)

  try:
    stream.write(frame.value.bytesToString)
    stream.flush()
    success()
  except CatchableError:
    failure(protocolError(invalidFrame, "unable to write protocol frame"))

proc readFrameFrom*(stream: Stream): ProtocolResultOf[string] =
  try:
    let header = stream.readExactly(4)
    if not header.isOk:
      return failureOf[string](header.failure)

    let size = (int(byte(header.value[0])) shl 24) or
      (int(byte(header.value[1])) shl 16) or
      (int(byte(header.value[2])) shl 8) or int(byte(header.value[3]))
    if size > MaxFrameBytes:
      return failureOf[string](protocolError(frameTooLarge, "frame exceeds maximum size"))

    let payload = stream.readExactly(size)
    if not payload.isOk:
      return failureOf[string](payload.failure)
    successOf(payload.value)
  except CatchableError:
    failureOf[string](protocolError(invalidFrame, "unable to read protocol frame"))

proc writeMessageTo*(stream: Stream; message: ProtocolMessage): ProtocolResult =
  stream.writeFrameTo(message.toJson)

proc readMessageFrom*(stream: Stream): ProtocolResultOf[ProtocolMessage] =
  let payload = stream.readFrameFrom()
  if not payload.isOk:
    return failureOf[ProtocolMessage](payload.failure)
  payload.value.fromJson
