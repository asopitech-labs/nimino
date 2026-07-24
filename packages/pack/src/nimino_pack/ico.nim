## PNG-in-ICO helpers used for Windows package icons.
##
## Windows picks the first matching directory entry for shell/taskbar/tray
## rendering. Keep every standard size in the ICO instead of relying on the
## shell to downsample one 256px image. The PNG decoder intentionally accepts
## the lossless 8-bit PNG forms emitted by common icon tooling.

import std/[algorithm, os]

type
  IcoPngFrame* = object
    size*: int
    png*: seq[byte]

  ParsedIcoFrame = object
    index: int
    width: int
    height: int
    bitCount: int
    data: seq[byte]

  RgbaImage = object
    width: int
    height: int
    pixels: seq[byte]

const
  IcoHeaderSize = 6
  IcoDirectoryEntrySize = 16
  PngSignature = [137'u8, 80'u8, 78'u8, 71'u8, 13'u8, 10'u8, 26'u8, 10'u8]
  ## Pake's Windows standard ICO set: tray, taskbar, shell, and high-DPI.
  WindowsStandardIcoSizes* = [16, 24, 32, 48, 64, 128, 256]

when defined(windows):
  const ZlibLibrary = "zlib1.dll"
elif defined(macosx):
  const ZlibLibrary = "/usr/lib/libz.1.dylib"
else:
  const ZlibLibrary = "libz.so.1"

proc zUncompress(destination: ptr uint8; destinationLength: ptr culong;
                 source: ptr uint8; sourceLength: culong): cint
  {.importc: "uncompress", cdecl, dynlib: ZlibLibrary.}
proc zCompressBound(sourceLength: culong): culong
  {.importc: "compressBound", cdecl, dynlib: ZlibLibrary.}
proc zCompress2(destination: ptr uint8; destinationLength: ptr culong;
                source: ptr uint8; sourceLength: culong; level: cint): cint
  {.importc: "compress2", cdecl, dynlib: ZlibLibrary.}

proc readU16(data: openArray[byte]; offset: int): int =
  if offset < 0 or offset + 2 > data.len: return -1
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc readU32(data: openArray[byte]; offset: int): int =
  if offset < 0 or offset + 4 > data.len: return -1
  int(data[offset]) or (int(data[offset + 1]) shl 8) or
    (int(data[offset + 2]) shl 16) or (int(data[offset + 3]) shl 24)

proc readBe32(data: openArray[byte]; offset: int): int =
  if offset < 0 or offset + 4 > data.len: return -1
  (int(data[offset]) shl 24) or (int(data[offset + 1]) shl 16) or
    (int(data[offset + 2]) shl 8) or int(data[offset + 3])

proc addU16(data: var seq[byte]; value: int) =
  data.add(byte(value and 0xff))
  data.add(byte((value shr 8) and 0xff))

proc addU32(data: var seq[byte]; value: int) =
  data.add(byte(value and 0xff))
  data.add(byte((value shr 8) and 0xff))
  data.add(byte((value shr 16) and 0xff))
  data.add(byte((value shr 24) and 0xff))

proc addBe32(data: var seq[byte]; value: int) =
  data.add(byte((value shr 24) and 0xff))
  data.add(byte((value shr 16) and 0xff))
  data.add(byte((value shr 8) and 0xff))
  data.add(byte(value and 0xff))

proc pngSignatureAt(data: openArray[byte]; offset = 0): bool =
  if offset < 0 or offset + PngSignature.len > data.len: return false
  for index, value in PngSignature:
    if data[offset + index] != value: return false
  true

proc bytesFromString(value: string): seq[byte] =
  result = newSeqOfCap[byte](value.len)
  for character in value: result.add(byte(ord(character)))

proc stringFromBytes(value: openArray[byte]): string =
  result = newString(value.len)
  for index, character in value: result[index] = char(character)

proc readFileBytes(path: string): seq[byte] =
  bytesFromString(readFile(path))

proc writeFileBytes(path: string; value: openArray[byte]) =
  let directory = parentDir(path)
  if directory.len > 0 and not dirExists(directory): createDir(directory)
  writeFile(path, stringFromBytes(value))

proc parseIco(data: seq[byte]): seq[ParsedIcoFrame] =
  if data.len < IcoHeaderSize or readU16(data, 0) != 0 or readU16(data, 2) != 1:
    return @[]
  let count = readU16(data, 4)
  if count <= 0 or count > 4096 or data.len < IcoHeaderSize + count * IcoDirectoryEntrySize:
    return @[]
  for index in 0 ..< count:
    let offset = IcoHeaderSize + index * IcoDirectoryEntrySize
    let width = if data[offset] == 0: 256 else: int(data[offset])
    let height = if data[offset + 1] == 0: 256 else: int(data[offset + 1])
    let bitCount = readU16(data, offset + 6)
    let byteCount = readU32(data, offset + 8)
    let payloadOffset = readU32(data, offset + 12)
    if width <= 0 or height <= 0 or byteCount <= 0 or payloadOffset < 0 or
        payloadOffset > data.len or byteCount > data.len - payloadOffset:
      return @[]
    result.add(ParsedIcoFrame(index: index, width: width, height: height,
      bitCount: bitCount, data: data[payloadOffset ..< payloadOffset + byteCount]))

proc comparePreferred(preferred: int; left, right: ParsedIcoFrame): int =
  let leftSize = max(left.width, left.height)
  let rightSize = max(right.width, right.height)
  let leftExact = if leftSize == preferred: 0 else: 1
  let rightExact = if rightSize == preferred: 0 else: 1
  if leftExact != rightExact: return leftExact - rightExact
  let leftDistance = abs(leftSize - preferred)
  let rightDistance = abs(rightSize - preferred)
  if leftDistance != rightDistance: return leftDistance - rightDistance
  let leftSmaller = if leftSize < preferred: 1 else: 0
  let rightSmaller = if rightSize < preferred: 1 else: 0
  if leftSmaller != rightSmaller: return leftSmaller - rightSmaller
  if left.bitCount != right.bitCount: return right.bitCount - left.bitCount
  if leftSize != rightSize: return rightSize - leftSize
  left.index - right.index

proc buildIcoFromPngBuffers*(frames: openArray[IcoPngFrame]): seq[byte] =
  ## Build a PNG-in-ICO container. PNG alpha remains intact; no BMP mask is
  ## needed on supported Windows versions.
  let tableSize = IcoHeaderSize + frames.len * IcoDirectoryEntrySize
  var payloadSize = 0
  for frame in frames: payloadSize += frame.png.len
  result = newSeqOfCap[byte](tableSize + payloadSize)
  result.addU16(0)
  result.addU16(1)
  result.addU16(frames.len)
  var payloadOffset = tableSize
  for frame in frames:
    let dimension = if frame.size >= 256: 0 else: max(1, frame.size)
    result.add(byte(dimension))
    result.add(byte(dimension))
    result.add(0)
    result.add(0)
    result.addU16(1)
    result.addU16(32)
    result.addU32(frame.png.len)
    result.addU32(payloadOffset)
    payloadOffset += frame.png.len
  for frame in frames:
    result.add(frame.png)

proc writeIcoWithPreferredSize*(sourcePath, outputPath: string;
                                preferredSize: int): bool =
  try:
    let frames = parseIco(readFileBytes(sourcePath))
    if frames.len == 0: return false
    var ordered = frames
    ordered.sort(proc(left, right: ParsedIcoFrame): int =
      comparePreferred(preferredSize, left, right))
    let tableSize = IcoHeaderSize + ordered.len * IcoDirectoryEntrySize
    var payloadSize = 0
    for frame in ordered: payloadSize += frame.data.len
    var output = newSeqOfCap[byte](tableSize + payloadSize)
    output.addU16(0); output.addU16(1); output.addU16(ordered.len)
    var payloadOffset = tableSize
    for frame in ordered:
      let width = if frame.width >= 256: 0 else: frame.width
      let height = if frame.height >= 256: 0 else: frame.height
      output.add(byte(width)); output.add(byte(height)); output.add(0); output.add(0)
      output.addU16(1); output.addU16(frame.bitCount)
      output.addU32(frame.data.len); output.addU32(payloadOffset)
      payloadOffset += frame.data.len
    for frame in ordered: output.add(frame.data)
    writeFileBytes(outputPath, output)
    true
  except CatchableError:
    false

proc paeth(left, above, upperLeft: int): int =
  let estimate = left + above - upperLeft
  let dl = abs(estimate - left)
  let da = abs(estimate - above)
  let du = abs(estimate - upperLeft)
  if dl <= da and dl <= du: left elif da <= du: above else: upperLeft

proc decodePng(png: seq[byte]): RgbaImage =
  if not png.pngSignatureAt() or png.len < 33: return
  var position = PngSignature.len
  var width = 0
  var height = 0
  var colorType = -1
  var compressed: seq[byte]
  while position + 12 <= png.len:
    let length = png.readBe32(position)
    if length < 0 or position + 12 + length > png.len: return RgbaImage()
    let kind = stringFromBytes(png[position + 4 ..< position + 8])
    let payload = png[position + 8 ..< position + 8 + length]
    case kind
    of "IHDR":
      if payload.len != 13: return RgbaImage()
      width = payload.readBe32(0); height = payload.readBe32(4)
      if width <= 0 or height <= 0 or width > 4096 or height > 4096 or
          payload[8] != 8 or payload[12] != 0: return RgbaImage()
      colorType = int(payload[9])
      if colorType notin [0, 2, 6]: return RgbaImage()
    of "IDAT": compressed.add(payload)
    of "IEND": break
    else: discard
    position += length + 12
  if width <= 0 or height <= 0 or compressed.len == 0: return RgbaImage()
  let channels = case colorType
    of 0: 1
    of 2: 3
    else: 4
  let stride = width * channels
  let expected = (stride + 1) * height
  var inflated = newSeq[byte](expected)
  var inflatedLength = culong(expected)
  if zUncompress(addr inflated[0], addr inflatedLength, addr compressed[0], culong(compressed.len)) != 0 or
      inflatedLength.int != expected: return RgbaImage()
  var decoded = newSeq[byte](width * height * 4)
  var previous = newSeq[byte](stride)
  var current = newSeq[byte](stride)
  var sourceOffset = 0
  for y in 0 ..< height:
    let filter = int(inflated[sourceOffset]); inc sourceOffset
    for x in 0 ..< stride:
      let raw = int(inflated[sourceOffset + x])
      let left = if x >= channels: int(current[x - channels]) else: 0
      let above = int(previous[x])
      let upperLeft = if x >= channels: int(previous[x - channels]) else: 0
      let value = case filter
        of 0: raw
        of 1: (raw + left) and 0xff
        of 2: (raw + above) and 0xff
        of 3: (raw + ((left + above) div 2)) and 0xff
        of 4: (raw + paeth(left, above, upperLeft)) and 0xff
        else: return RgbaImage()
      current[x] = byte(value)
    for x in 0 ..< width:
      let source = x * channels
      let target = (y * width + x) * 4
      case colorType
      of 0:
        decoded[target] = current[source]; decoded[target + 1] = current[source]
        decoded[target + 2] = current[source]; decoded[target + 3] = 255
      of 2:
        decoded[target] = current[source]; decoded[target + 1] = current[source + 1]
        decoded[target + 2] = current[source + 2]; decoded[target + 3] = 255
      else:
        for channel in 0 ..< 4: decoded[target + channel] = current[source + channel]
    previous = current
    current = newSeq[byte](stride)
    sourceOffset += stride
  RgbaImage(width: width, height: height, pixels: decoded)

proc crc32(data: openArray[byte]): uint32 =
  result = 0xffffffff'u32
  for value in data:
    result = result xor uint32(value)
    for _ in 0 ..< 8:
      result = if (result and 1) != 0: (result shr 1) xor 0xedb88320'u32 else: result shr 1
  result = not result

proc addPngChunk(output: var seq[byte]; kind: string; payload: openArray[byte]) =
  output.addBe32(payload.len)
  for character in kind: output.add(byte(character))
  output.add(payload)
  var crcInput = newSeqOfCap[byte](4 + payload.len)
  for character in kind: crcInput.add(byte(character))
  crcInput.add(payload)
  output.addBe32(int(crcInput.crc32))

proc encodePng(image: RgbaImage): seq[byte] =
  if image.width <= 0 or image.height <= 0 or image.pixels.len != image.width * image.height * 4:
    return @[]
  let stride = image.width * 4
  var raw = newSeq[byte]((stride + 1) * image.height)
  for y in 0 ..< image.height:
    let target = y * (stride + 1)
    raw[target] = 0
    for x in 0 ..< stride: raw[target + 1 + x] = image.pixels[y * stride + x]
  var compressedLength = zCompressBound(culong(raw.len))
  var compressed = newSeq[byte](compressedLength.int)
  if zCompress2(addr compressed[0], addr compressedLength, addr raw[0], culong(raw.len), 9) != 0:
    return @[]
  compressed.setLen(compressedLength.int)
  result.add(PngSignature)
  var header: seq[byte]
  header.addBe32(image.width); header.addBe32(image.height)
  header.add(8); header.add(6); header.add(0); header.add(0); header.add(0)
  result.addPngChunk("IHDR", header)
  result.addPngChunk("IDAT", compressed)
  result.addPngChunk("IEND", newSeq[byte]())

proc resizeContain(source: RgbaImage; size: int): RgbaImage =
  if source.width <= 0 or source.height <= 0 or size <= 0: return
  result.width = size; result.height = size; result.pixels = newSeq[byte](size * size * 4)
  let scale = min(float(size) / float(source.width), float(size) / float(source.height))
  let drawWidth = max(1, int(float(source.width) * scale))
  let drawHeight = max(1, int(float(source.height) * scale))
  let offsetX = (size - drawWidth) div 2
  let offsetY = (size - drawHeight) div 2
  for y in 0 ..< drawHeight:
    let sourceY = min(source.height - 1, int(float(y) / scale))
    for x in 0 ..< drawWidth:
      let sourceX = min(source.width - 1, int(float(x) / scale))
      let sourceIndex = (sourceY * source.width + sourceX) * 4
      let targetIndex = ((offsetY + y) * size + offsetX + x) * 4
      for channel in 0 ..< 4:
        result.pixels[targetIndex + channel] = source.pixels[sourceIndex + channel]

proc ensureMultiResolutionIco*(sourcePath, outputPath: string;
                               preferredSize = 256;
                               desiredSizes: openArray[int] = WindowsStandardIcoSizes): bool =
  ## Preserve hand-tuned exact PNG frames, resize only missing dimensions, and
  ## put the preferred image first as a Windows shell quality hint.
  try:
    let source = readFileBytes(sourcePath)
    let entries = parseIco(source)
    if entries.len == 0: return false
    var largest = RgbaImage()
    for entry in entries:
      if entry.data.pngSignatureAt():
        let decoded = entry.data.decodePng()
        if decoded.width * decoded.height > largest.width * largest.height: largest = decoded
    if largest.width == 0:
      return sourcePath.writeIcoWithPreferredSize(outputPath, preferredSize)
    var frames: seq[IcoPngFrame]
    for size in desiredSizes:
      var exact: seq[byte]
      for entry in entries:
        if entry.width == size and entry.height == size and entry.data.pngSignatureAt():
          exact = entry.data
          break
      if exact.len > 0: frames.add(IcoPngFrame(size: size, png: exact))
      else:
        let rendered = largest.resizeContain(size).encodePng()
        if rendered.len == 0: return sourcePath.writeIcoWithPreferredSize(outputPath, preferredSize)
        frames.add(IcoPngFrame(size: size, png: rendered))
    frames.sort(proc(left, right: IcoPngFrame): int =
      if (left.size == preferredSize) != (right.size == preferredSize):
        return if left.size == preferredSize: -1 else: 1
      right.size - left.size)
    writeFileBytes(outputPath, buildIcoFromPngBuffers(frames))
    true
  except CatchableError:
    sourcePath.writeIcoWithPreferredSize(outputPath, preferredSize)
