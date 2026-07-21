version = "0.1.0"
author = "asopitech-labs"
description = "Nim-native cross-platform Web UI desktop application foundation"
license = "MIT"

requires "nim >= 2.2.0"

task test, "Run Nimino unit tests in ARC mode":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-nimcache --out:/tmp/nimino-test-foundation --path:packages/native packages/native/tests/test_foundation.nim"
  exec "nim c -r -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-wsl-desktop-capabilities-nimcache --out:/tmp/nimino-test-wsl-desktop-capabilities --path:packages/native packages/native/tests/test_wsl_desktop_capabilities.nim"
  exec "nim c -r -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-wsl-load-html-base-url-nimcache --out:/tmp/nimino-test-wsl-load-html-base-url --path:packages/native packages/native/tests/test_wsl_load_html_base_url.nim"
  exec "nimble testWebView2ProfileFfi"
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
  exec "nim c --mm:arc --nimcache:/tmp/nimino-wsl-fake-launcher-host-nimcache --out:/tmp/nimino-wsl-fake-launcher-host --path:packages/wsl packages/wsl/tests/fake_launcher_host.nim"
  exec "nim c --mm:arc --nimcache:/tmp/nimino-wsl-launcher-nimcache --out:/tmp/nimino-test-launcher --path:packages/wsl --path:packages/native packages/wsl/tests/test_launcher.nim"
  exec "/tmp/nimino-test-launcher /tmp/nimino-wsl-fake-launcher-host"
  ## Host adapter tests model the Windows host contract; compile without the
  ## Linux WebKit backend so unsupported runtime behavior is deterministic.
  exec "nim c -r -d:niminoWsl --mm:arc --nimcache:/tmp/nimino-wsl-host-nimcache --out:/tmp/nimino-test-host-adapter --path:packages/wsl --path:packages/native packages/wsl/tests/test_host_adapter.nim"

task testLinuxSmoke, "Run the Linux GTK/WebKitGTK M1 smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-linux-smoke-nimcache --out:/tmp/nimino-linux-smoke --path:packages/native packages/native/tests/test_linux_smoke.nim"
  ## Give GNotification a private session bus; Xvfb alone does not provide one.
  ## Keep a stalled GLib/WebKit callback from indefinitely occupying a CI
  ## worker. The smoke itself reports all required completion assertions.
  exec "timeout 45s dbus-run-session -- xvfb-run -a /tmp/nimino-linux-smoke"

task testLinuxCustomProtocolSmoke, "Run the Linux WebView custom protocol harness under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-linux-custom-protocol-smoke-nimcache --out:/tmp/nimino-linux-custom-protocol-smoke --path:packages/native packages/native/tests/test_linux_custom_protocol_smoke.nim"
  exec "timeout 45s dbus-run-session -- xvfb-run -a /tmp/nimino-linux-custom-protocol-smoke"

task testCoreLinuxRpcSmoke, "Run the Linux core RPC smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-core-linux-rpc-smoke-nimcache --out:/tmp/nimino-core-linux-rpc-smoke --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_linux_rpc_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-core-linux-rpc-smoke"

task testPackManifest, "Run nimino-pack manifest tests":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-pack-manifest-nimcache --path:packages/pack packages/pack/tests/test_manifest.nim"

task buildPackCli, "Build the nimino-pack validation CLI":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-pack-cli-nimcache --out:/tmp/nimino --path:packages/pack tools/cli/nimino.nim"

task buildNiminoHost, "Build the generic native Nimino host":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-host-nimcache --out:/tmp/nimino-host --path:packages/core --path:packages/native --path:packages/wsl tools/hosts/nimino_host.nim"

task buildNiminoHostWindows, "Cross-compile the generic Windows Nimino host":
  exec "nim c --os:windows --cpu:amd64 --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-host-windows-nimcache --out:/tmp/nimino-host.exe --path:packages/core --path:packages/native --path:packages/wsl tools/hosts/nimino_host.nim"
  exec "x86_64-w64-mingw32-objdump -f /tmp/nimino-host.exe | grep -q 'file format pei-x86-64'"

task testPackCli, "Verify nimino-pack emits a runnable manifest bundle":
  exec "bash tools/ci/test_pack_cli.sh /tmp/nimino"

task testPackLinux, "Build Debian/RPM archives from nimino-pack Linux metadata":
  exec "bash tools/ci/test_pack_linux.sh /tmp/nimino"

task testPackOnline, "Exercise the URL-to-bundle online pack flow":
  exec "nimble buildPackCli"
  exec "nimble buildNiminoHost"
  exec "bash tools/ci/test_pack_online.sh /tmp/nimino /tmp/nimino-host"

task testPackPopularCatalog, "Verify signed Popular Packages catalog entries":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-pack-popular-catalog-nimcache --out:/tmp/nimino-test-popular-catalog --path:packages/pack --path:packages/pack/src packages/pack/tests/test_popular_catalog.nim"
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-pack-popular-signature-nimcache --out:/tmp/nimino-test-popular-signature --path:packages/pack --path:packages/pack/src packages/pack/tests/test_popular_catalog_signature.nim"

task testPackAppImageGuardrails, "Verify incomplete AppImage closure fails closed":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-pack-appimage-guardrails-nimcache --out:/tmp/nimino-test-appimage-guardrails --path:packages/pack --path:packages/pack/src packages/pack/tests/test_appimage_guardrails.nim"
  exec "bash tools/ci/test_pack_appimage_guardrails.sh /tmp/nimino"

task testPackWindows, "Build an NSIS installer from nimino-pack Windows metadata":
  exec "bash tools/ci/test_pack_windows.sh /tmp/nimino"

task testPackArchive, "Verify Linux and Windows pack archives":
  exec "tar -czf /tmp/nimino-pack-cli-test/nimino-demo-linux.tar.gz -C /tmp/nimino-pack-cli-test/out ."
  exec "tar -a -cf /tmp/nimino-pack-cli-test/nimino-demo-windows.zip -C /tmp/nimino-pack-cli-test/out ."
  exec "test -s /tmp/nimino-pack-cli-test/nimino-demo-linux.tar.gz && test -s /tmp/nimino-pack-cli-test/nimino-demo-windows.zip"

task testCoreLinuxRpcUrlSmoke, "Run the Linux URL document-start RPC smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-core-linux-rpc-url-smoke-nimcache --out:/tmp/nimino-core-linux-rpc-url-smoke --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_linux_rpc_url_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-core-linux-rpc-url-smoke"

task testCoreLinuxRpcAsyncSmoke, "Run the Linux async and timeout core RPC smoke test under Xvfb":
  exec "nim c --mm:arc --nimcache:/tmp/nimino-core-linux-rpc-async-smoke-nimcache --out:/tmp/nimino-core-linux-rpc-async-smoke --path:packages/core --path:packages/native --path:packages/wsl packages/core/tests/test_linux_rpc_async_smoke.nim"
  exec "xvfb-run -a /tmp/nimino-core-linux-rpc-async-smoke"

task testWindowsCross, "Cross-compile the Windows native M1 smoke target":
  exec "nim c --os:windows --cpu:amd64 --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-windows-cross-nimcache --out:/tmp/nimino-windows-cross.exe --path:packages/native packages/native/tests/test_windows_cross.nim"
  exec "x86_64-w64-mingw32-objdump -f /tmp/nimino-windows-cross.exe | grep -q 'file format pei-x86-64'"

task testWebView2ProfileFfi, "Run the WebView2 Profile/CookieManager fake-vtable ABI test":
  exec "nim c -r --mm:arc --nimcache:/tmp/nimino-webview2-profile-ffi-nimcache --out:/tmp/nimino-test-webview2-profile-ffi --path:packages/native packages/native/tests/test_webview2_profile_ffi.nim"

task testWindowsProfileFfiCross, "Cross-compile the Windows WebView2 Profile/CookieManager ABI contract":
  exec "nim c --os:windows --cpu:amd64 --mm:arc --gcc.exe:x86_64-w64-mingw32-gcc --gcc.linkerexe:x86_64-w64-mingw32-gcc --passL:-static --nimcache:/tmp/nimino-windows-profile-ffi-cross-nimcache --out:/tmp/nimino-windows-profile-ffi-cross.exe --path:packages/native packages/native/tests/test_windows_profile_ffi_cross.nim"
  exec "x86_64-w64-mingw32-objdump -f /tmp/nimino-windows-profile-ffi-cross.exe | grep -q 'file format pei-x86-64'"

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
