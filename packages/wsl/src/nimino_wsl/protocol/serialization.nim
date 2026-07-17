import ./[messages, versioning]

proc encodeFrame*(payload: string): ProtocolResultOf[seq[byte]] =
  if payload.len > MaxFrameBytes:
    return failureOf[seq[byte]](protocolError(frameTooLarge, "frame exceeds maximum size"))

  result = successOf(newSeq[byte](4 + payload.len))
  for index in 0 ..< 4:
    result.value[index] = byte((payload.len shr ((3 - index) * 8)) and 0xff)
  for index, value in payload:
    result.value[4 + index] = byte(ord(value))

proc decodeFrame*(frame: openArray[byte]): ProtocolResultOf[string] =
  if frame.len < 4:
    return failureOf[string](protocolError(invalidFrame, "frame header is incomplete"))

  let length = (int(frame[0]) shl 24) or (int(frame[1]) shl 16) or
    (int(frame[2]) shl 8) or int(frame[3])
  if length > MaxFrameBytes:
    return failureOf[string](protocolError(frameTooLarge, "frame exceeds maximum size"))
  if frame.len != 4 + length:
    return failureOf[string](protocolError(invalidFrame, "frame payload is incomplete"))

  result = successOf(newString(length))
  for index in 0 ..< length:
    result.value[index] = char(frame[4 + index])

proc encodeMessageFrame*(message: ProtocolMessage): ProtocolResultOf[seq[byte]] =
  message.toJson.encodeFrame

proc decodeMessageFrame*(frame: openArray[byte]): ProtocolResultOf[ProtocolMessage] =
  let payload = frame.decodeFrame
  if not payload.isOk:
    return failureOf[ProtocolMessage](payload.failure)
  payload.value.fromJson
