version = "0.1.0"
author = "asopitech-labs"
description = "Nim-native cross-platform Web UI desktop application foundation"
license = "MIT"

requires "nim >= 2.2.0"

task test, "Run Nimino unit tests in ARC mode":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-nimcache --out:/tmp/nimino-test-foundation --path:packages/native packages/native/tests/test_foundation.nim"
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-core-nimcache --out:/tmp/nimino-test-core-rpc --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_rpc.nim"
  exec "nim c --mm:arc --nimcache:/tmp/nimino-core-app-nimcache --out:/tmp/nimino-test-core-app --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_app.nim"
  exec "NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 /tmp/nimino-test-core-app"
  exec "nim c --mm:arc --nimcache:/tmp/nimino-wsl-core-fake-host-nimcache --out:/tmp/nimino-wsl-core-fake-host --path:packages/wsl packages/wsl/tests/fake_core_host.nim"
  exec "nim c -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-test-wsl-core-adapter-nimcache --out:/tmp/nimino-test-wsl-core-adapter --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_wsl_core_adapter.nim"
  exec "NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 /tmp/nimino-test-wsl-core-adapter /tmp/nimino-wsl-core-fake-host"
  exec "nim c --mm:arc --nimcache:/tmp/nimino-wsl-core-async-fake-host-nimcache --out:/tmp/nimino-wsl-core-async-fake-host --path:packages/wsl packages/wsl/tests/fake_core_async_host.nim"
  exec "nim c -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-test-wsl-core-async-adapter-nimcache --out:/tmp/nimino-test-wsl-core-async-adapter --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_wsl_core_async_adapter.nim"
  exec "NIMINO_TEST_ALLOW_NATIVE_IN_WSL=1 /tmp/nimino-test-wsl-core-async-adapter /tmp/nimino-wsl-core-async-fake-host"
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-wsl-nimcache --out:/tmp/nimino-test-protocol --path:packages/wsl --path:packages/native packages/wsl/tests/test_protocol.nim"
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-wsl-launcher-nimcache --out:/tmp/nimino-test-launcher --path:packages/wsl --path:packages/native packages/wsl/tests/test_launcher.nim"
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-wsl-host-nimcache --out:/tmp/nimino-test-host-adapter --path:packages/wsl --path:packages/native packages/wsl/tests/test_host_adapter.nim"

task testLinuxSmoke, "Run the Linux GTK/WebKitGTK M1 smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-linux-smoke-nimcache --out:/tmp/nimino-linux-smoke --path:packages/native packages/native/tests/test_linux_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-linux-smoke"

task testCoreLinuxRpcSmoke, "Run the Linux core RPC smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-core-linux-rpc-smoke-nimcache --out:/tmp/nimino-core-linux-rpc-smoke --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_linux_rpc_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-core-linux-rpc-smoke"

task testPackManifest, "Run nimino-pack manifest tests":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-pack-manifest-nimcache --path:packages/pack packages/pack/tests/test_manifest.nim"

task testCoreLinuxRpcUrlSmoke, "Run the Linux URL document-start RPC smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-core-linux-rpc-url-smoke-nimcache --out:/tmp/nimino-core-linux-rpc-url-smoke --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_linux_rpc_url_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-core-linux-rpc-url-smoke"

task testCoreLinuxRpcAsyncSmoke, "Run the Linux async and timeout core RPC smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-core-linux-rpc-async-smoke-nimcache --out:/tmp/nimino-core-linux-rpc-async-smoke --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_linux_rpc_async_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-core-linux-rpc-async-smoke"

task testWindowsCross, "Cross-compile the Windows native M1 smoke target":
  exec "nim c --os:windows --cpu:amd64 --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-windows-cross-nimcache --out:/tmp/nimino-windows-cross.exe --path:packages/native packages/native/tests/test_windows_cross.nim"
  exec "x86_64-w64-mingw32-objdump -f /tmp/nimino-windows-cross.exe | grep -q 'file format pei-x86-64'"

task testCoreWindowsCross, "Cross-compile the Windows core RPC facade target":
  exec "nim c --os:windows --cpu:amd64 --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-core-windows-cross-nimcache --out:/tmp/nimino-core-windows-cross.exe --path:packages/core --path:packages/native packages/core/tests/test_app.nim"
  exec "x86_64-w64-mingw32-objdump -f /tmp/nimino-core-windows-cross.exe | grep -q 'file format pei-x86-64'"

task buildWslHost, "Cross-compile the Windows WSL host executable":
  exec "nim c --os:windows --cpu:amd64 --threads:on --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-wsl-host-nimcache --out:/tmp/nimino-wsl-host.exe --path:packages/wsl --path:packages/native packages/wsl/src/nimino_wsl/host/main.nim"
  exec "x86_64-w64-mingw32-objdump -f /tmp/nimino-wsl-host.exe | grep -q 'file format pei-x86-64'"

task buildWslHostArtifact, "Build a disposable Windows WSL host smoke-test artifact":
  exec "mkdir -p /workspace/.tmp"
  exec "nim c --os:windows --cpu:amd64 --threads:on --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-wsl-host-artifact-nimcache --out:/workspace/.tmp/nimino-wsl-host.exe --path:packages/wsl --path:packages/native packages/wsl/src/nimino_wsl/host/main.nim"
  exec "install -m 0644 /opt/nimino/webview2/x64/WebView2Loader.dll /workspace/.tmp/WebView2Loader.dll"
  exec "install -m 0644 /opt/nimino/webview2/LICENSE.txt /workspace/.tmp/WebView2Loader.LICENSE.txt"
  exec "install -m 0644 /opt/nimino/webview2/NOTICE.txt /workspace/.tmp/WebView2Loader.NOTICE.txt"

task buildWslClientArtifact, "Build a disposable WSL client smoke-test artifact":
  exec "mkdir -p /workspace/.tmp"
  exec "nim c --mm:arc --nimcache:/tmp/nimino-wsl-client-artifact-nimcache --out:/workspace/.tmp/nimino-wsl-client-smoke --path:packages/wsl --path:packages/native tools/ci/wsl_client_smoke.nim"

task buildWslCoreClientArtifact, "Build a disposable WSL core adapter smoke-test artifact":
  exec "mkdir -p /workspace/.tmp"
  exec "nim c -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-wsl-core-client-artifact-nimcache --out:/workspace/.tmp/nimino-wsl-core-client-smoke --path:packages/core --path:packages/wsl --path:packages/native tools/ci/wsl_core_client_smoke.nim"

task buildWslCoreRpcAsyncClientArtifact, "Build a disposable WSL core async RPC smoke-test artifact":
  exec "mkdir -p /workspace/.tmp"
  exec "nim c -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-wsl-core-rpc-async-client-artifact-nimcache --out:/workspace/.tmp/nimino-wsl-core-rpc-async-client-smoke --path:packages/core --path:packages/wsl --path:packages/native tools/ci/wsl_core_rpc_async_client_smoke.nim"

task buildWslCoreRpcUrlClientArtifact, "Build a disposable WSL core URL document-start RPC smoke-test artifact":
  exec "mkdir -p /workspace/.tmp"
  exec "nim c -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-wsl-core-rpc-url-client-artifact-nimcache --out:/workspace/.tmp/nimino-wsl-core-rpc-url-client-smoke --path:packages/core --path:packages/wsl --path:packages/native tools/ci/wsl_core_rpc_url_client_smoke.nim"
