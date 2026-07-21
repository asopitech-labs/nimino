import std/[os, strutils]

import nimino_pack/private/appimage_guardrails

block fixedDependencyContract:
  doAssert AppImageRequiredTools == [
    "appimagetool", "linuxdeploy", "patchelf", "lddtree", "pkg-config",
    "glib-compile-schemas", "gdk-pixbuf-query-loaders", "gio-querymodules",
    "bwrap", "xdg-dbus-proxy"
  ]
  doAssert AppImageRequiredPkgConfigModules == [
    "gtk4", "webkitgtk-6.0", "gio-2.0", "gdk-pixbuf-2.0"
  ]
  doAssert AppImageRequiredRuntimeLibraries == [
    "libgtk-4.so.1", "libwebkitgtk-6.0.so.4"
  ]
  doAssert AppImageRequiredWebKitAssets == [
    "WebKitGPUProcess", "WebKitNetworkProcess", "WebKitWebProcess",
    "injected-bundle/libwebkitgtkinjectedbundle.so"
  ]
  doAssert AppImageIncompleteClosureError ==
    "AppImage package generation is unavailable: dependency copying and " &
    "WebKitGTK 6.0 helper relocation are not implemented"

block resolvedStaticReport:
  let checked = validateAppImageDependencyReport("""
/app/usr/lib/libgtk-4.so.1
/app/usr/lib/libwebkitgtk-6.0.so.4
""", 0, AppImageRequiredRuntimeLibraries)
  doAssert checked.isOk

block missingRequiredSeed:
  let checked = validateAppImageDependencyReport(
    "/app/usr/lib/libgtk-4.so.1", 0, AppImageRequiredRuntimeLibraries)
  doAssert not checked.isOk
  doAssert checked.error.detail ==
    "AppImage dependency closure is unresolved: libwebkitgtk-6.0.so.4 (not reported)"

block explicitlyUnresolvedDependency:
  let checked = validateAppImageDependencyReport("""
/app/usr/lib/libgtk-4.so.1
libwebkitgtk-6.0.so.4 => not found
""", 0, AppImageRequiredRuntimeLibraries)
  doAssert not checked.isOk
  doAssert checked.error.detail.contains("libwebkitgtk-6.0.so.4 => not found")

block emptyAndFailedInspection:
  let empty = validateAppImageDependencyReport(
    "", 0, AppImageRequiredRuntimeLibraries)
  doAssert not empty.isOk
  doAssert empty.error.detail ==
    "AppImage dependency closure inspection returned no dependencies"
  let failed = validateAppImageDependencyReport(
    "tool failure", 2, AppImageRequiredRuntimeLibraries)
  doAssert not failed.isOk
  doAssert failed.error.detail ==
    "AppImage dependency closure inspection failed"

block completeSyntheticBuildEnvironment:
  ## The production checker must be testable without downloading or executing
  ## the real packaging tools.  These fixtures only model probe output; they
  ## never produce an AppImage.
  let root = getTempDir() / ("nimino-appimage-guardrails-" & $getCurrentProcessId())
  let binDir = root / "bin"
  let libDir = root / "lib"
  let webKitDir = libDir / "webkitgtk-6.0"
  let schemasDir = root / "share" / "glib-2.0" / "schemas"
  let gioModulesDir = libDir / "gio" / "modules"
  let pixbufModulesDir = libDir / "gdk-pixbuf" / "loaders"
  let pixbufCache = libDir / "gdk-pixbuf" / "loaders.cache"
  if dirExists(root):
    removeDir(root)
  createDir(binDir)
  createDir(webKitDir / "injected-bundle")
  createDir(schemasDir)
  createDir(gioModulesDir)
  createDir(pixbufModulesDir)
  writeFile(libDir / "libgtk-4.so.1", "fixture")
  writeFile(libDir / "libwebkitgtk-6.0.so.4", "fixture")
  writeFile(pixbufCache, "fixture")
  writeFile(webKitDir / "injected-bundle" / "libwebkitgtkinjectedbundle.so",
    "fixture")

  let executablePermissions = {fpUserExec, fpUserRead, fpUserWrite}
  for tool in AppImageRequiredTools:
    let path = binDir / tool
    writeFile(path, "#!/bin/sh\nexit 0\n")
    setFilePermissions(path, executablePermissions)
  for helper in ["WebKitGPUProcess", "WebKitNetworkProcess", "WebKitWebProcess"]:
    let path = webKitDir / helper
    writeFile(path, "#!/bin/sh\nexit 0\n")
    setFilePermissions(path, executablePermissions)

  writeFile(binDir / "pkg-config", """#!/bin/sh
case "$1" in
  --exists) exit 0 ;;
  --variable=libdir) echo """ & libDir & """ ;;
  --variable=schemasdir) echo """ & schemasDir & """ ;;
  --variable=giomoduledir) echo """ & gioModulesDir & """ ;;
  --variable=gdk_pixbuf_moduledir) echo """ & pixbufModulesDir & """ ;;
  --variable=gdk_pixbuf_cache_file) echo """ & pixbufCache & """ ;;
  *) exit 1 ;;
esac
""")
  setFilePermissions(binDir / "pkg-config", executablePermissions)
  writeFile(binDir / "lddtree", """#!/bin/sh
last=""
for value in "$@"; do last="$value"; done
printf '%s\n' "$last"
""")
  setFilePermissions(binDir / "lddtree", executablePermissions)

  let oldPath = getEnv("PATH")
  try:
    putEnv("PATH", binDir)
    let checked = validateAppImageBuildEnvironment()
    doAssert checked.isOk
  finally:
    putEnv("PATH", oldPath)
    removeDir(root)

echo "AppImage guardrail tests passed"
