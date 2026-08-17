version = "0.2.7"
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

before build:
  ## The CLI resolves release archives for its own version, so the version
  ## declared here has to reach the binary nimble builds from `bin`.
  switch("define", "niminoVersion:" & version)

after install:
  ## Place the host for this machine beside the CLI so `nimino pack <url>
  ## --out <dir>` works without staging anything.  Nothing is compiled: the
  ## archive carries a binary the release workflow built for this version, so
  ## installing the CLI never pulls in a GUI toolchain.  A machine without
  ## network access still gets a usable CLI -- pack reports the missing host
  ## when an operation actually needs one.
  let home = getEnv("HOME", getEnv("USERPROFILE"))
  if home.len == 0:
    echo "nimino: no home directory; pass --host to nimino pack"
  else:
    let hostName = when defined(windows): "nimino-host.exe" else: "nimino-host"
    let archive =
      when defined(windows): "nimino-core-" & version & "-windows-x64.zip"
      elif defined(macosx): "nimino-core-" & version & "-macos-arm64.tar.gz"
      else: "nimino-core-" & version & "-linux-x86_64.tar.gz"
    let url = "https://github.com/asopitech-labs/nimino/releases/download/v" &
      version & "/" & archive
    let workspace = home & "/.cache/nimino/install"
    let extract =
      if archive.endsWith(".zip"): "unzip -q -o \"$w/$a\" -d \"$w\""
      else: "tar xzf \"$w/$a\" -C \"$w\""
    let stager = workspace & "/stage-host.sh"
    mkDir workspace
    writeFile(stager, """#!/bin/sh
set -e
w="$1"; a="$2"; u="$3"; h="$4"; b="$5"
mkdir -p "$w" "$b"
curl --fail --silent --show-error --location --output "$w/$a" "$u"
""" & extract & """

found=$(find "$w" -name "$h" -type f -print -quit)
test -n "$found"
install -m 0755 "$found" "$b/$h"
""")
    let staged = gorgeEx("sh " & stager & " " & workspace & " " & archive & " " &
      url & " " & hostName & " " & home & "/.nimble/bin")
    rmDir workspace
    if staged.exitCode == 0:
      echo "nimino: installed " & hostName & " to " & home & "/.nimble/bin"
    else:
      echo "nimino: could not stage " & hostName & " (" & archive & "); pass --host to nimino pack"
