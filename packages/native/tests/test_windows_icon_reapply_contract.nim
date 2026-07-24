## Static Windows contract parity for Pake's window-icon-reapply suite.
## It is executed only by NIMINO_TEST_REFERENCE_WINDOWS=1; the source-level
## assertions mirror Pake because the regression is a Win32 taskbar lifecycle
## property rather than a portable GUI behavior.

import std/[os, strutils]

let root = currentSourcePath.parentDir.parentDir.parentDir
let backend = readFile(root / "packages/native/src/nimino_native/private/windows/backend.nim")
let ffi = readFile(root / "packages/native/src/nimino_native/private/windows/ffi.nim")

doAssert ffi.contains("WmSetIcon")
doAssert ffi.contains("IconBig")
doAssert backend.contains("proc windowsApplyWindowIcon")
doAssert backend.contains("sendMessageW(window.platformWindow, WmSetIcon, IconBig")
doAssert backend.contains("sendMessageW(window.platformWindow, WmSetIcon, IconSmall")
let show = backend.find("proc windowsShowWindow")
doAssert show >= 0
doAssert backend[show ..< min(backend.len, show + 500)].contains("windowsApplyWindowIcon")
echo "Windows icon reapply contract passed"
