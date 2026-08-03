version = "0.2.1"
author = "asopitech-labs"
description = "Authenticated WSL client / Windows host transport for Nimino: Nim application logic in WSL, GUI ownership in a WebView2 host process"
license = "MIT"

## nimino-wsl keeps the packaged application's logic inside WSL while a
## separate nimino-wsl-host.exe owns the Win32/WebView2 GUI.  The two sides
## speak an authenticated, versioned protocol over the host process's stdio.
##
##   nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/wsl"

srcDir = "."
installDirs = @["src"]
installFiles = @["nimino_wsl.nim"]
skipDirs = @["tests"]

requires "nim >= 2.2.0"
requires "nimino_native >= 0.2.1"
