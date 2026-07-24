## URL-only manifest generation.
##
## A caller supplies the web application's entry URL.  Identity, packaging
## metadata, profile and window defaults are derived here; callers do not need
## to author a second manifest just to wrap a site.

import std/[os, strutils, uri]

import ./manifest

proc titleWord(value: string): string =
  if value.len == 0:
    return value
  result = value
  result[0] = result[0].toUpperAscii()

proc hostToken(host: string): string =
  var normalized = host.toLowerAscii().strip(chars = {'.'})
  if normalized.startsWith("www."):
    normalized = normalized[4 .. ^1]
  result = ""
  for character in normalized:
    if character.isAlphaNumeric:
      result.add(character)
    elif result.len == 0 or result[^1] != '-':
      result.add('-')
  result = result.strip(chars = {'-'})
  if result.len == 0:
    result = "site"

proc identifierSegment(value: string): string =
  result = hostToken(value)
  ## D-Bus and desktop application identifiers require every segment to begin
  ## with a letter or underscore. URL hosts and user-supplied app names can
  ## legitimately begin with a digit, so give those generated segments a
  ## stable alphabetic prefix.
  if result[0] notin {'a'..'z', 'A'..'Z', '_'}:
    result = "app-" & result

proc generatedName(host: string): string =
  var normalized = host.toLowerAscii().strip(chars = {'.'})
  if normalized.startsWith("www."):
    normalized = normalized[4 .. ^1]
  let labels = normalized.split('.')
  ## Pake derives a display name from the registrable domain rather than an
  ## arbitrary product subdomain (`weekly.tw93.fun` -> `Tw93`). Keep the
  ## public-suffix exceptions needed by common multi-label TLDs explicit; the
  ## fallback remains safe for private/local host names.
  const twoLabelSuffixes = [
    "ac.uk", "co.uk", "gov.uk", "ltd.uk", "me.uk", "net.uk", "nhs.uk",
    "org.uk", "plc.uk", "sch.uk", "com.au", "net.au", "org.au", "edu.au",
    "gov.au", "co.jp", "ne.jp", "or.jp", "com.br", "com.cn", "com.mx",
    "co.nz", "org.nz", "co.kr", "co.in", "com.sg", "com.hk", "com.tw"
  ]
  let suffixLength = if labels.len >= 2 and
      (labels[^2] & "." & labels[^1]) in twoLabelSuffixes: 2 else: 1
  let labelAt = labels.len - suffixLength - 1
  let label = if labelAt >= 0 and labels[labelAt].len > 0: labels[labelAt]
    elif labels.len > 0 and labels[0].len > 0: labels[0]
    else: "site"
  titleWord(label.replace('-', ' ').replace('_', ' '))

proc localApplicationName*(source: string): string =
  ## A local `.hidden.html` entry is a normal desktop app, not a dotfile.
  ## Preserve meaningful dots such as `Vectorizer.AI.html`, as Pake does for
  ## macOS and Windows display names.
  var base = if dirExists(source): extractFilename(source) else: splitFile(source).name
  base = base.strip(chars = {'.', '-', ' '})
  if base.len == 0:
    return "Local App"
  titleWord(base.replace('-', ' ').replace('_', ' '))

proc generatedId(host: string; name = ""): string =
  result = "com.nimino." & identifierSegment(host)
  if name.strip().len > 0:
    ## Apps wrapping the same site need distinct default identity/profile
    ## roots. Preserve an explicit --id unchanged; this applies only to the
    ## generated identifier path.
    result.add("." & identifierSegment(name))

proc generateManifest*(url: string; name = ""; id = ""; profile = "default";
                      icon = ""; deepLinkSchemes: seq[string] = @[];
                      title = ""; width = 1200; height = 800; resizable = true;
                      fullscreen = false; maximized = false;
                      alwaysOnTop = false; hideWindowDecorations = false;
                      hideTitleBar = false;
                      enableDragDrop = false;
                      userAgent = ""; proxyUrl = ""; incognito = false; zoom = 100;
                      ignoreCertificateErrors = false;
                      showSystemTray = false; startToTray = false;
                      hideOnClose = platformDefaultHideOnClose(); multiWindow = true;
                      multiInstance = false;
                      permissionsAllow: seq[string] = @[];
                      css: seq[string] = @[]; javascript: seq[string] = @[];
                      navigationAllow: seq[string] = @[];
                      navigationExternal: seq[string] = @[]):
                      PackResult[PackManifest] =
  ## Build a complete, validated manifest from an entry URL.  Navigation
  ## allow-lists are intentionally empty: the host applies Nimino's generic
  ## same-site/authentication policy at runtime.  A site-specific allow-list
  ## is an optional override for manifests that genuinely need one.
  try:
    let parsed = parseUri(url)
    let scheme = parsed.scheme.toLowerAscii()
    if scheme notin ["http", "https"] or parsed.hostname.len == 0:
      return failure[PackManifest](invalidManifest,
        "URL-only generation requires an http or https URL")
    if name.len > 0 and not validApplicationName(name):
      return failure[PackManifest](invalidManifest, "application name must not start with a dot, dash, or space")
    let requestedName = name
    let appName = if requestedName.len > 0: requestedName else: generatedName(parsed.hostname)
    let appId = if id.strip().len > 0: id.strip() else: generatedId(parsed.hostname, requestedName)
    let metadata = PackPackageMetadata(
      version: "0.1.0",
      description: appName & " web application",
      publisher: "Nimino",
      homepage: url,
      categories: @["Network"],
      installerLanguage: "en-US", bundle: true)
    validate(PackManifest(
      name: appName,
      id: appId,
      url: url,
      icon: icon,
      profile: if profile.strip().len > 0: profile.strip() else: "default",
      window: PackWindowOptions(title: title, width: width, height: height, resizable: resizable,
        fullscreen: fullscreen, maximized: maximized, alwaysOnTop: alwaysOnTop,
        hideWindowDecorations: hideWindowDecorations, hideTitleBar: hideTitleBar,
        enableDragDrop: enableDragDrop),
      webview: PackWebViewOptions(userAgent: userAgent, proxyUrl: proxyUrl,
        incognito: incognito, zoomFactor: zoom.float / 100.0,
        ignoreCertificateErrors: ignoreCertificateErrors),
      runtime: PackRuntimeOptions(showSystemTray: showSystemTray,
        startToTray: startToTray, hideOnClose: hideOnClose,
        multiWindow: multiWindow, multiInstance: multiInstance),
      package: metadata,
      deepLink: PackDeepLinkOptions(schemes: deepLinkSchemes),
      navigationAllow: navigationAllow,
      navigationExternal: navigationExternal,
      permissionsAllow: permissionsAllow,
      css: css,
      javascript: javascript))
  except CatchableError:
    failure[PackManifest](invalidManifest, "URL-only generation received an invalid URL")

proc generateLocalManifest*(source: string; name = ""; id = "";
                            profile = "default"; title = "";
                            icon = ""; width = 1200; height = 800;
                            resizable = true; fullscreen = false;
                            maximized = false; alwaysOnTop = false;
                            hideWindowDecorations = false; hideTitleBar = false; userAgent = "";
                            enableDragDrop = false;
                            proxyUrl = ""; incognito = false; zoom = 100;
                            ignoreCertificateErrors = false;
                            showSystemTray = false; startToTray = false;
                            hideOnClose = platformDefaultHideOnClose(); multiWindow = true;
                            multiInstance = false;
                            permissionsAllow: seq[string] = @[];
                            css: seq[string] = @[]; javascript: seq[string] = @[];
                            deepLinkSchemes: seq[string] = @[];
                            navigationAllow: seq[string] = @[];
                            navigationExternal: seq[string] = @[]):
                            PackResult[PackManifest] =
  ## Build a manifest for a local HTML file or static directory.  The source
  ## itself is staged by the CLI; only the relative entry is persisted here.
  let absolute = absolutePath(source).normalizedPath()
  let isDirectory = dirExists(absolute)
  if not isDirectory and not fileExists(absolute):
    return failure[PackManifest](ioFailure, "local source does not exist")
  let entry = if isDirectory: "index.html" else: extractFilename(absolute)
  if isDirectory and not fileExists(absolute / entry):
    return failure[PackManifest](invalidManifest,
      "local directory must contain an index.html entry")
  let localBase = if isDirectory: extractFilename(absolute) else: splitFile(absolute).name
  if name.len > 0 and not validApplicationName(name):
    return failure[PackManifest](invalidManifest, "application name must not start with a dot, dash, or space")
  let requestedName = name
  let appName = if requestedName.len > 0: requestedName else:
    localApplicationName(absolute)
  let appId = if id.strip().len > 0: id.strip() else:
    generatedId(localBase, requestedName)
  let metadata = PackPackageMetadata(
    version: "0.1.0",
    description: appName & " local web application",
    publisher: "Nimino",
    homepage: "",
    categories: @["Network"], installerLanguage: "en-US", bundle: true)
  validate(PackManifest(
    name: appName,
    id: appId,
    localEntry: entry,
    icon: icon,
    profile: if profile.strip().len > 0: profile.strip() else: "default",
    window: PackWindowOptions(title: title, width: width, height: height, resizable: resizable,
      fullscreen: fullscreen, maximized: maximized, alwaysOnTop: alwaysOnTop,
      hideWindowDecorations: hideWindowDecorations, hideTitleBar: hideTitleBar,
      enableDragDrop: enableDragDrop),
    webview: PackWebViewOptions(userAgent: userAgent, proxyUrl: proxyUrl,
      incognito: incognito, zoomFactor: zoom.float / 100.0,
      ignoreCertificateErrors: ignoreCertificateErrors),
    runtime: PackRuntimeOptions(showSystemTray: showSystemTray,
      startToTray: startToTray, hideOnClose: hideOnClose,
      multiWindow: multiWindow, multiInstance: multiInstance),
    package: metadata,
    deepLink: PackDeepLinkOptions(schemes: deepLinkSchemes),
    navigationAllow: navigationAllow,
    navigationExternal: navigationExternal,
    permissionsAllow: permissionsAllow,
    css: css,
    javascript: javascript))
