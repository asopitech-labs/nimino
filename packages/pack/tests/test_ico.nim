## Pake ICO suite parity. This is Windows-targeted packaging behavior and is
## intentionally run only through NIMINO_TEST_REFERENCE_WINDOWS=1.

import std/[base64, os, sequtils]

import nimino_pack

const HeaderSize = 6
const EntrySize = 16

proc u16(data: openArray[byte]; offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8)

proc u32(data: openArray[byte]; offset: int): int =
  int(data[offset]) or (int(data[offset + 1]) shl 8) or
    (int(data[offset + 2]) shl 16) or (int(data[offset + 3]) shl 24)

proc icoSizes(data: seq[byte]): seq[int] =
  doAssert u16(data, 0) == 0
  doAssert u16(data, 2) == 1
  for index in 0 ..< u16(data, 4):
    let width = if data[HeaderSize + index * EntrySize] == 0: 256 else:
      int(data[HeaderSize + index * EntrySize])
    result.add(width)

proc bytes(value: string): seq[byte] =
  for character in value: result.add(byte(ord(character)))

proc readBytes(path: string): seq[byte] = bytes(readFile(path))

proc writeBytes(path: string; value: openArray[byte]) =
  writeFile(path, value.stringFromBytes)

proc stringFromBytes(value: openArray[byte]): string =
  result = newString(value.len)
  for index, character in value: result[index] = char(character)

let png1x1 = bytes(decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL9xQAAAABJRU5ErkJggg=="))

block buildIcoLayout:
  let one = buildIcoFromPngBuffers([IcoPngFrame(size: 16, png: @[1'u8, 2, 3])])
  doAssert one.len == HeaderSize + EntrySize + 3
  doAssert icoSizes(one) == @[16]
  doAssert u32(one, HeaderSize + 8) == 3
  doAssert u32(one, HeaderSize + 12) == HeaderSize + EntrySize
  doAssert one[HeaderSize + EntrySize .. ^1] == @[1'u8, 2, 3]
  let large = buildIcoFromPngBuffers([IcoPngFrame(size: 256, png: @[4'u8])])
  doAssert icoSizes(large) == @[256]
  let many = buildIcoFromPngBuffers([
    IcoPngFrame(size: 16, png: @[1'u8]),
    IcoPngFrame(size: 32, png: @[2'u8, 2]),
    IcoPngFrame(size: 64, png: @[3'u8, 3, 3])])
  doAssert icoSizes(many) == @[16, 32, 64]
  doAssert u32(many, HeaderSize + EntrySize + 12) == HeaderSize + 3 * EntrySize + 1
  doAssert buildIcoFromPngBuffers([]).len == HeaderSize

let root = getTempDir() / "nimino-pake-ico-parity"
if dirExists(root): removeDir(root)
createDir(root)
defer: removeDir(root)

block reorderAndMalformedInput:
  let source = root / "source.ico"
  let output = root / "reordered.ico"
  writeBytes(source, buildIcoFromPngBuffers([
    IcoPngFrame(size: 32, png: @[1'u8]),
    IcoPngFrame(size: 16, png: @[2'u8]),
    IcoPngFrame(size: 64, png: @[3'u8])
  ]))
  doAssert writeIcoWithPreferredSize(source, output, 16)
  doAssert icoSizes(readBytes(output))[0] == 16
  doAssert not writeIcoWithPreferredSize(root / "missing.ico", output, 32)
  let malformed = root / "malformed.ico"
  writeFile(malformed, "\0\0")
  doAssert not writeIcoWithPreferredSize(malformed, output, 32)

block multiResolutionAndExactFramePreservation:
  let source = root / "source.ico"
  let output = root / "multi.ico"
  writeBytes(source, buildIcoFromPngBuffers([
    IcoPngFrame(size: 256, png: png1x1)
  ]))
  doAssert ensureMultiResolutionIco(source, output)
  let sizes = icoSizes(readBytes(output))
  for expected in WindowsStandardIcoSizes:
    doAssert expected in sizes
  doAssert ensureMultiResolutionIco(source, output, preferredSize = 32)
  doAssert icoSizes(readBytes(output))[0] == 32
  let preserved = root / "preserved.ico"
  let preservedOutput = root / "preserved-multi.ico"
  writeBytes(preserved, buildIcoFromPngBuffers([
    IcoPngFrame(size: 16, png: png1x1),
    IcoPngFrame(size: 256, png: png1x1)
  ]))
  doAssert ensureMultiResolutionIco(preserved, preservedOutput)
  doAssert icoSizes(readBytes(preservedOutput)).contains(16)
  let malformed = root / "bad.ico"
  writeFile(malformed, "\0\0")
  doAssert not ensureMultiResolutionIco(malformed, root / "bad-out.ico")

echo "Pake ICO parity tests passed"
