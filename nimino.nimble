version = "0.1.0"
author = "asopitech-labs"
description = "Nim-native cross-platform Web UI desktop application foundation"
license = "MIT"

requires "nim >= 2.2.0"

task test, "Run Nimino unit tests in ARC mode":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-nimcache --out:/tmp/nimino-test-foundation --path:packages/native packages/native/tests/test_foundation.nim"
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-wsl-nimcache --out:/tmp/nimino-test-protocol --path:packages/wsl packages/wsl/tests/test_protocol.nim"

task testLinuxSmoke, "Run the Linux GTK/WebKitGTK M1 smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-linux-smoke-nimcache --out:/tmp/nimino-linux-smoke --path:packages/native packages/native/tests/test_linux_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-linux-smoke"

task testWindowsCross, "Cross-compile the Windows native M1 smoke target":
  exec "nim c --os:windows --cpu:amd64 --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-windows-cross-nimcache --out:/tmp/nimino-windows-cross.exe --path:packages/native packages/native/tests/test_windows_cross.nim"
  exec "x86_64-w64-mingw32-objdump -f /tmp/nimino-windows-cross.exe | grep -q 'file format pei-x86-64'"
