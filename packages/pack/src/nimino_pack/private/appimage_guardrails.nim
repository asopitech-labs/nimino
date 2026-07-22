## Fail-closed checks for the future AppImage dependency-closure pipeline.
##
## This module does not build an AppImage.  It records and verifies the fixed
## build tools and GTK/WebKitGTK runtime assets that must be available before a
## complete AppDir may be produced.  Keeping this separate from a smoke-test
## fixture prevents a test host from being mistaken for a distributable host.

import std/[os, osproc, strutils]

import ../manifest

const
  AppImageRequiredTools* = [
    "appimagetool",
    "linuxdeploy",
    "patchelf",
    "lddtree",
    "pkg-config",
    "glib-compile-schemas",
    "gdk-pixbuf-query-loaders",
    "gio-querymodules",
    "bwrap",
    "unsquashfs",
    "xdg-dbus-proxy"
  ]
  AppImageRequiredPkgConfigModules* = [
    "gtk4",
    "webkitgtk-6.0",
    "gio-2.0",
    "gdk-pixbuf-2.0"
  ]
  AppImageRequiredRuntimeLibraries* = [
    "libgtk-4.so.1",
    "libwebkitgtk-6.0.so.4"
  ]
  AppImageRequiredWebKitAssets* = [
    "WebKitGPUProcess",
    "WebKitNetworkProcess",
    "WebKitWebProcess",
    "injected-bundle/libwebkitgtkinjectedbundle.so"
  ]
type
  AppImageProbeResult = object
    exitCode: int
    output: string

  AppImageAssetKind = enum
    assetFile
    assetDirectory
    assetExecutable

  AppImageRuntimeAsset = object
    label: string
    path: string
    kind: AppImageAssetKind
    inspectElf: bool

proc shellQuote(value: string): string =
  "'" & value.replace("'", "'\"'\"'") & "'"

proc runProbe(command: string; arguments: openArray[string]): AppImageProbeResult =
  var commandLine = command.shellQuote()
  for argument in arguments:
    commandLine.add(" " & argument.shellQuote())
  let executed = execCmdEx(commandLine)
  AppImageProbeResult(exitCode: executed.exitCode, output: executed.output.strip())

proc unresolvedDependencyLine(line: string): bool =
  let normalized = line.strip().toLowerAscii()
  normalized.contains("=> not found") or
    normalized.endsWith("=> none") or
    normalized.contains("did not match any paths") or
    normalized.contains("no such file or directory")

proc validateAppImageDependencyReport*(report: string; exitCode: int;
                                       requiredDependencies: openArray[string]): PackResult[bool] =
  ## Validates the output of a static ELF dependency inspector such as
  ## lddtree.  This deliberately does not invoke `ldd`, which can execute the
  ## interpreter named by an untrusted application binary.
  if exitCode != 0:
    return failure[bool](ioFailure,
      "AppImage dependency closure inspection failed")
  let content = report.strip()
  if content.len == 0:
    return failure[bool](ioFailure,
      "AppImage dependency closure inspection returned no dependencies")
  var unresolved: seq[string]
  for line in content.splitLines():
    if line.unresolvedDependencyLine():
      unresolved.add(line.strip())
  for dependency in requiredDependencies:
    if dependency.len == 0 or content.find(dependency) < 0:
      unresolved.add(dependency & " (not reported)")
  if unresolved.len > 0:
    return failure[bool](ioFailure,
      "AppImage dependency closure is unresolved: " & unresolved.join(", "))
  success(true)

proc requirePkgConfigVariable(pkgConfig, module, variable: string): PackResult[string] =
  let inspected = pkgConfig.runProbe(["--variable=" & variable, module])
  if inspected.exitCode != 0 or inspected.output.len == 0 or
      not inspected.output.isAbsolute():
    return failure[string](unsupportedFeature,
      "AppImage package generation is unavailable: pkg-config did not provide " &
      module & "." & variable)
  success(inspected.output)

proc appImagePkgConfigVariable*(module, variable: string): PackResult[string] =
  ## Expose only the validated absolute pkg-config paths needed by the closure
  ## stage.  Distribution-specific fallback paths remain deliberately absent.
  let pkgConfig = findExe("pkg-config")
  if pkgConfig.len == 0:
    return failure[string](unsupportedFeature,
      "AppImage package generation is unavailable: pkg-config is missing")
  pkgConfig.requirePkgConfigVariable(module, variable)

proc missingRuntimeAssets(assets: openArray[AppImageRuntimeAsset]): seq[string] =
  for asset in assets:
    let present =
      case asset.kind
      of assetFile, assetExecutable: fileExists(asset.path)
      of assetDirectory: dirExists(asset.path)
    if not present:
      result.add(asset.label)
    elif asset.kind == assetExecutable:
      try:
        let permissions = getFilePermissions(asset.path)
        if fpUserExec notin permissions and fpGroupExec notin permissions and
            fpOthersExec notin permissions:
          result.add(asset.label & " (not executable)")
      except OSError:
        result.add(asset.label & " (permissions unavailable)")

proc validateAppImageBuildEnvironment*(): PackResult[bool] =
  ## Checks only the build environment.  Passing this function does not mean
  ## dependency copying or WebKitGTK relocation has been implemented.
  var tools: seq[(string, string)]
  var missingTools: seq[string]
  for name in AppImageRequiredTools:
    let path = findExe(name)
    tools.add((name, path))
    if path.len == 0:
      missingTools.add(name)
  if missingTools.len > 0:
    return failure[bool](unsupportedFeature,
      "AppImage package generation is unavailable: missing fixed build dependencies: " &
      missingTools.join(", "))

  proc toolPath(name: string): string =
    for tool in tools:
      if tool[0] == name:
        return tool[1]

  let pkgConfig = toolPath("pkg-config")
  var missingModules: seq[string]
  for module in AppImageRequiredPkgConfigModules:
    if pkgConfig.runProbe(["--exists", module]).exitCode != 0:
      missingModules.add(module)
  if missingModules.len > 0:
    return failure[bool](unsupportedFeature,
      "AppImage package generation is unavailable: missing fixed pkg-config modules: " &
      missingModules.join(", "))

  let gtkLibDir = pkgConfig.requirePkgConfigVariable("gtk4", "libdir")
  if not gtkLibDir.isOk:
    return failure[bool](gtkLibDir.error.kind, gtkLibDir.error.detail)
  let webKitLibDir = pkgConfig.requirePkgConfigVariable("webkitgtk-6.0", "libdir")
  if not webKitLibDir.isOk:
    return failure[bool](webKitLibDir.error.kind, webKitLibDir.error.detail)
  let schemasDir = pkgConfig.requirePkgConfigVariable("gio-2.0", "schemasdir")
  if not schemasDir.isOk:
    return failure[bool](schemasDir.error.kind, schemasDir.error.detail)
  let gioModulesDir = pkgConfig.requirePkgConfigVariable("gio-2.0", "giomoduledir")
  if not gioModulesDir.isOk:
    return failure[bool](gioModulesDir.error.kind, gioModulesDir.error.detail)
  let pixbufModulesDir = pkgConfig.requirePkgConfigVariable(
    "gdk-pixbuf-2.0", "gdk_pixbuf_moduledir")
  if not pixbufModulesDir.isOk:
    return failure[bool](pixbufModulesDir.error.kind, pixbufModulesDir.error.detail)
  let pixbufCache = pkgConfig.requirePkgConfigVariable(
    "gdk-pixbuf-2.0", "gdk_pixbuf_cache_file")
  if not pixbufCache.isOk:
    return failure[bool](pixbufCache.error.kind, pixbufCache.error.detail)

  let webKitDirectory = webKitLibDir.value / "webkitgtk-6.0"
  var assets: seq[AppImageRuntimeAsset] = @[
    AppImageRuntimeAsset(label: AppImageRequiredRuntimeLibraries[0],
      path: gtkLibDir.value / AppImageRequiredRuntimeLibraries[0],
      kind: assetFile, inspectElf: true),
    AppImageRuntimeAsset(label: AppImageRequiredRuntimeLibraries[1],
      path: webKitLibDir.value / AppImageRequiredRuntimeLibraries[1],
      kind: assetFile, inspectElf: true),
    AppImageRuntimeAsset(label: "GLib schemas", path: schemasDir.value,
      kind: assetDirectory),
    AppImageRuntimeAsset(label: "GIO modules", path: gioModulesDir.value,
      kind: assetDirectory),
    AppImageRuntimeAsset(label: "GdkPixbuf modules", path: pixbufModulesDir.value,
      kind: assetDirectory),
    AppImageRuntimeAsset(label: "GdkPixbuf loader cache", path: pixbufCache.value,
      kind: assetFile),
    AppImageRuntimeAsset(label: "bubblewrap", path: toolPath("bwrap"),
      kind: assetExecutable, inspectElf: true),
    AppImageRuntimeAsset(label: "xdg-dbus-proxy", path: toolPath("xdg-dbus-proxy"),
      kind: assetExecutable, inspectElf: true)
  ]
  for relative in AppImageRequiredWebKitAssets:
    let executable = not relative.endsWith(".so")
    assets.add(AppImageRuntimeAsset(
      label: relative,
      path: webKitDirectory / relative,
      kind: if executable: assetExecutable else: assetFile,
      inspectElf: true))
  let missingAssets = assets.missingRuntimeAssets()
  if missingAssets.len > 0:
    return failure[bool](unsupportedFeature,
      "AppImage package generation is unavailable: unresolved fixed runtime dependencies: " &
      missingAssets.join(", "))

  ## Verify the fixed system-provided ELF seeds without executing them.  The
  ## future closure stage must repeat this validation after copying into the
  ## AppDir; this preflight only proves that the build root is internally
  ## complete.
  let lddtree = toolPath("lddtree")
  for asset in assets:
    if not asset.inspectElf:
      continue
    let inspected = lddtree.runProbe(["-l", asset.path])
    let dependencyName = extractFilename(asset.path)
    let validated = validateAppImageDependencyReport(
      inspected.output, inspected.exitCode, [dependencyName])
    if not validated.isOk:
      return failure[bool](validated.error.kind,
        validated.error.detail & " (seed: " & asset.label & ")")
  success(true)
