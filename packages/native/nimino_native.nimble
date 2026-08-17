version = "0.2.7"
author = "asopitech-labs"
description = "Thin native Window/WebView layer for Nimino: Win32 + WebView2, GTK 4 + WebKitGTK 6.0, and AppKit + WKWebView"
license = "MIT"

## nimino-native holds the platform backends and deliberately excludes RPC,
## profiles, packaging, and policy; those live in nimino_core.  Building on
## Linux requires the GTK 4 and WebKitGTK 6.0 development headers, on
## Windows the WebView2 SDK loader, and on macOS Xcode's AppKit toolchain.
##
##   nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/native"

srcDir = "."
installDirs = @["src"]
installFiles = @["nimino_native.nim"]
skipDirs = @["tests"]

requires "nim >= 2.2.0"
