version = "0.2.1"
author = "asopitech-labs"
description = "Nimino packaging toolkit: URL/manifest wrapping, bundle metadata, and platform package generation"
license = "MIT"

## nimino-pack is a build-time toolkit and is released independently of the
## nimino-core runtime. It imports no other Nimino package: `nimino_pack` and
## its CLI depend on the Nim standard library alone, so installing it never
## pulls in GTK/WebKitGTK, WebView2, or any native GUI SDK.
##
##   nimble install "https://github.com/asopitech-labs/nimino?subdir=packages/pack"
##
## Package generation shells out to the platform tooling for the requested
## format (dpkg-deb, rpmbuild, appimagetool, makensis, wixl, minisign, ...).
## Those are runtime requirements of the generated formats, not build
## dependencies of this package; each generator fails closed when its tool is
## absent rather than emitting an incomplete artifact.

srcDir = "."
bin = @["nimino"]
installDirs = @["src", "schema"]
installFiles = @["nimino_pack.nim"]
skipDirs = @["tests"]

requires "nim >= 2.2.0"
