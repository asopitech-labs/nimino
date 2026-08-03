version = "0.2.2"
author = "asopitech-labs"
description = "Nimino application framework: app lifecycle, typed RPC, profiles, downloads, navigation and permission policy over native WebViews"
license = "MIT"

## nimino-core is the public application framework packaged Nimino apps and
## embedders program against.  It builds on nimino_native for the platform
## Window/WebView layer and selects the nimino_wsl transport automatically
## when a Linux binary runs under WSL.
##
##   nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/core"

srcDir = "."
installDirs = @["src"]
installFiles = @["nimino_core.nim"]
skipDirs = @["tests"]

requires "nim >= 2.2.0"
requires "nimino_native >= 0.2.1"
requires "nimino_wsl >= 0.2.1"
