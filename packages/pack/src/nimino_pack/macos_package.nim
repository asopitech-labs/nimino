## macOS application bundles and optional DMG images built from a nimino-pack bundle.

import std/[json, os, osproc, strutils]

import ./manifest

type
  MacosPackageFormat* = enum
    macosAppPackage
    macosDmgPackage

  MacosPackageOptions* = object
    bundleDirectory*: string
    outputDirectory*: string
    format*: MacosPackageFormat
    architecture*: string
    signingIdentity*: string
    notaryProfile*: string

proc safeName(value: string): bool =
  if value.len == 0 or value in [".", ".."]: return false
  for ch in value:
    if ch notin {'a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_'}: return false
  true

proc jsonString(node: JsonNode; key: string): string =
  if node.kind != JObject or not node.hasKey(key) or node[key].kind != JString:
    return ""
  node[key].getStr()

proc shellQuote(value: string): string =
  "'" & value.replace("'", "'\"'\"'") & "'"

proc runTool(command: string; args: openArray[string]): PackResult[bool] =
  var line = shellQuote(command)
  for arg in args: line.add(" " & shellQuote(arg))
  let executed = execCmdEx(line)
  if executed.exitCode != 0:
    let output = executed.output.strip()
    return failure[bool](ioFailure, "macOS packaging tool failed: " & extractFilename(command) &
      (if output.len > 0: ": " & output else: ""))
  success(true)

proc copyTree(source, destination: string): PackResult[bool] =
  try:
    createDir(destination)
    for path in walkDirRec(source):
      let relative = relativePath(path, source)
      let target = destination / relative
      if dirExists(path):
        createDir(target)
      elif fileExists(path):
        createDir(parentDir(target))
        copyFile(path, target)
    success(true)
  except OSError:
    failure[bool](ioFailure, "macOS package bundle could not be copied")

proc hostNameFromLauncher(bundle: string): PackResult[string] =
  let launcherPath = bundle / "run-nimino.sh"
  if not fileExists(launcherPath):
    return failure[string](ioFailure, "macOS package bundle is missing run-nimino.sh")
  let text = try: readFile(launcherPath)
    except OSError: return failure[string](ioFailure, "macOS package launcher cannot be read")
  let marker = "exec \"$(dirname \"$0\")/"
  let start = text.find(marker)
  if start < 0: return failure[string](invalidManifest, "macOS package launcher is malformed")
  let first = start + marker.len
  let finish = text.find('"', first)
  if finish <= first: return failure[string](invalidManifest, "macOS package launcher host path is malformed")
  let name = text[first ..< finish]
  if not safeName(name) or not fileExists(bundle / name):
    return failure[string](ioFailure, "macOS package bundle is missing its host executable")
  success(name)

proc validateHostArchitecture(path, architecture: string): PackResult[bool] =
  let inspected = execCmdEx(shellQuote("file") & " " & shellQuote(path))
  if inspected.exitCode != 0:
    return failure[bool](ioFailure, "macOS host architecture could not be inspected")
  let output = inspected.output.toLowerAscii()
  let requested = if architecture.toLowerAscii() == "amd64": "x86_64" else: architecture.toLowerAscii()
  if output.find("mach-o") < 0 or output.find(requested) < 0:
    return failure[bool](unsupportedFeature,
      "macOS host executable does not contain the requested " & requested & " architecture")
  success(true)

proc manifestPermissionAllowed(manifest: JsonNode; permission: string): bool =
  if not manifest.hasKey("permissions") or manifest["permissions"].kind != JObject:
    return false
  let permissions = manifest["permissions"]
  if not permissions.hasKey("allow") or permissions["allow"].kind != JArray:
    return false
  for item in permissions["allow"].items:
    if item.kind == JString and item.getStr().toLowerAscii() == permission.toLowerAscii():
      return true
  false

proc manifestWebviewProxy(manifest: JsonNode): string =
  if not manifest.hasKey("webview") or manifest["webview"].kind != JObject:
    return ""
  let webview = manifest["webview"]
  for key in ["proxyUrl", "proxy_url"]:
    if webview.hasKey(key) and webview[key].kind == JString:
      return webview[key].getStr()
  ""

proc plistEscaped(value: string): string =
  value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    .replace("\"", "&quot;")

proc buildMacosPackage*(options: MacosPackageOptions): PackResult[string] =
  let bundle = options.bundleDirectory
  if bundle.len == 0 or not dirExists(bundle):
    return failure[string](ioFailure, "macOS package bundle directory does not exist")
  if options.outputDirectory.len == 0:
    return failure[string](invalidManifest, "macOS package output directory is required")
  if options.architecture.toLowerAscii() notin ["arm64", "x86_64", "amd64"]:
    return failure[string](unsupportedFeature, "macOS package architecture must be arm64 or x86_64")
  if options.notaryProfile.len > 0 and options.format != macosDmgPackage:
    return failure[string](invalidManifest, "macOS notarization requires --format dmg")
  if options.notaryProfile.len > 0 and options.signingIdentity.len == 0:
    return failure[string](invalidManifest, "macOS notarization requires --sign-identity")
  let manifestPath = bundle / "nimino-manifest.json"
  if not fileExists(manifestPath):
    return failure[string](ioFailure, "macOS package bundle is missing nimino-manifest.json")
  let manifest = try: parseJson(readFile(manifestPath))
    except CatchableError: return failure[string](invalidManifest, "nimino-manifest.json is invalid JSON")
  let proxyUrl = manifest.manifestWebviewProxy()
  if proxyUrl.len > 0:
    let proxyScheme = proxyUrl.toLowerAscii()
    if not (proxyScheme.startsWith("http://") or proxyScheme.startsWith("socks5://")):
      return failure[string](unsupportedFeature,
        "macOS proxyUrl supports only http:// and socks5://")
  let id = manifest.jsonString("id")
  let name = manifest.jsonString("name")
  if not safeName(id) or name.len == 0:
    return failure[string](invalidManifest, "macOS manifest requires a safe id and non-empty name")
  let version = if manifest.hasKey("package") and manifest["package"].kind == JObject:
      manifest["package"].jsonString("version")
    else: "0.1.0"
  let host = hostNameFromLauncher(bundle)
  if not host.isOk: return failure[string](host.error.kind, host.error.detail)
  let architecture = validateHostArchitecture(bundle / host.value, options.architecture)
  if not architecture.isOk: return failure[string](architecture.error.kind, architecture.error.detail)
  try:
    createDir(options.outputDirectory)
    let appPath = options.outputDirectory / (id & ".app")
    let contents = appPath / "Contents"
    let macos = contents / "MacOS"
    let resources = contents / "Resources"
    createDir(macos); createDir(resources)
    copyFile(bundle / host.value, macos / id)
    setFilePermissions(macos / id, {fpUserExec, fpUserRead, fpUserWrite,
      fpGroupExec, fpGroupRead, fpOthersExec, fpOthersRead})
    copyFile(manifestPath, resources / "nimino-manifest.json")
    for path in walkDirRec(bundle):
      if fileExists(path) and parentDir(path) == bundle:
        let fileName = extractFilename(path)
        if fileName notin [host.value, "run-nimino.sh", "run-nimino.cmd",
            "nimino-manifest.json", "nimino-linux-package.json",
            "nimino-windows-installer.json", "install-windows.ps1",
            "uninstall-windows.ps1", "register-windows-shortcut.ps1"]:
          copyFile(path, resources / fileName)
    let assets = bundle / "assets"
    if dirExists(assets):
      let copied = copyTree(assets, resources / "assets")
      if not copied.isOk: return failure[string](copied.error.kind, copied.error.detail)
    let icon = manifest.jsonString("icon")
    var iconEntry = ""
    if icon.len > 0 and not fileExists(bundle / icon):
      return failure[string](ioFailure, "macOS manifest icon is missing from the package bundle")
    if icon.len > 0:
      if not icon.toLowerAscii().endsWith(".icns"):
        return failure[string](unsupportedFeature, "macOS application icons must use .icns")
      copyFile(bundle / icon, resources / extractFilename(icon))
      iconEntry = extractFilename(icon)
    var urlTypes = ""
    if manifest.hasKey("deepLink") and manifest["deepLink"].kind == JObject and
        manifest["deepLink"].hasKey("schemes") and manifest["deepLink"]["schemes"].kind == JArray:
      var schemeItems = ""
      for item in manifest["deepLink"]["schemes"].items:
        if item.kind != JString or not validDeepLinkScheme(item.getStr()):
          return failure[string](invalidManifest, "macOS manifest contains an invalid deep-link scheme")
        schemeItems.add("<string>" & item.getStr().toLowerAscii().plistEscaped() & "</string>")
      if schemeItems.len > 0:
        urlTypes = "<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>" &
          id.plistEscaped() & "</string><key>CFBundleURLSchemes</key><array>" & schemeItems &
          "</array></dict></array>"
    let iconXml = if iconEntry.len > 0: "<key>CFBundleIconFile</key><string>" & iconEntry.plistEscaped() & "</string>" else: ""
    let cameraAllowed = manifest.manifestPermissionAllowed("camera")
    let microphoneAllowed = manifest.manifestPermissionAllowed("microphone")
    let cameraUsage = if cameraAllowed:
        "<key>NSCameraUsageDescription</key><string>Camera access is required by this application.</string>" else: ""
    let microphoneUsage = if microphoneAllowed:
        "<key>NSMicrophoneUsageDescription</key><string>Microphone access is required by this application.</string>" else: ""
    let minimumSystemVersion = if proxyUrl.len > 0: "14.0" else: "12.0"
    let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict>" &
      "<key>CFBundleDisplayName</key><string>" & name.plistEscaped() & "</string>" &
      "<key>CFBundleExecutable</key><string>" & id & "</string>" &
      "<key>CFBundleIdentifier</key><string>" & id & "</string>" &
      "<key>CFBundleName</key><string>" & name.plistEscaped() & "</string>" &
      "<key>CFBundlePackageType</key><string>APPL</string>" &
      "<key>CFBundleShortVersionString</key><string>" & version.plistEscaped() & "</string>" &
      "<key>CFBundleVersion</key><string>" & version.plistEscaped() & "</string>" &
      "<key>LSMinimumSystemVersion</key><string>" & minimumSystemVersion & "</string>" & iconXml & urlTypes &
      cameraUsage & microphoneUsage &
      "<key>NSHighResolutionCapable</key><true/></dict></plist>\n"
    writeFile(contents / "Info.plist", plist)
    var entitlements = ""
    if cameraAllowed or microphoneAllowed:
      entitlements = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict>"
      if cameraAllowed:
        entitlements.add("<key>com.apple.security.device.camera</key><true/>")
      if microphoneAllowed:
        entitlements.add("<key>com.apple.security.device.audio-input</key><true/>")
      entitlements.add("</dict></plist>\n")
      writeFile(resources / "nimino-entitlements.plist", entitlements)
    if options.signingIdentity.len > 0:
      var signArgs = @["--deep", "--force", "--options", "runtime"]
      if entitlements.len > 0:
        signArgs.add("--entitlements")
        signArgs.add(resources / "nimino-entitlements.plist")
      signArgs.add("--sign")
      signArgs.add(options.signingIdentity)
      signArgs.add(appPath)
      let signed = runTool("codesign", signArgs)
      if not signed.isOk: return failure[string](signed.error.kind, signed.error.detail)
    if options.format == macosDmgPackage:
      let dmgPath = options.outputDirectory / (id & ".dmg")
      let made = runTool("hdiutil", ["create", "-volname", name, "-srcfolder", appPath,
        "-ov", "-format", "UDZO", dmgPath])
      if not made.isOk: return failure[string](made.error.kind, made.error.detail)
      if options.notaryProfile.len > 0:
        let submitted = runTool("xcrun", ["notarytool", "submit", dmgPath,
          "--wait", "--keychain-profile", options.notaryProfile])
        if not submitted.isOk: return failure[string](submitted.error.kind, submitted.error.detail)
        let stapled = runTool("xcrun", ["stapler", "staple", dmgPath])
        if not stapled.isOk: return failure[string](stapled.error.kind, stapled.error.detail)
      return success(dmgPath)
    success(appPath)
  except OSError:
    failure[string](ioFailure, "macOS application bundle could not be written")
