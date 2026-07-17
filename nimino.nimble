version = "0.1.0"
author = "asopitech-labs"
description = "Nim-native cross-platform Web UI desktop application foundation"
license = "MIT"

requires "nim >= 2.2.0"

task test, "Run Nimino unit tests in ARC mode":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-nimcache --out:/tmp/nimino-test-foundation --path:packages/native packages/native/tests/test_foundation.nim"
