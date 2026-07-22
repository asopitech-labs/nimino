## URL-only manifest generation.
##
## A caller supplies the web application's entry URL.  Identity, packaging
## metadata, profile and window defaults are derived here; callers do not need
## to author a second manifest just to wrap a site.

import std/[strutils, uri]

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

proc generatedName(host: string): string =
  var normalized = host.toLowerAscii().strip(chars = {'.'})
  if normalized.startsWith("www."):
    normalized = normalized[4 .. ^1]
  let labels = normalized.split('.')
  let label = if labels.len > 0 and labels[0].len > 0: labels[0] else: "site"
  titleWord(label.replace('-', ' ').replace('_', ' '))

proc generatedId(host: string): string =
  "com.nimino." & hostToken(host)

proc generateManifest*(url: string; name = ""; id = ""; profile = "default";
                      icon = ""; deepLinkSchemes: seq[string] = @[];
                      width = 1200; height = 800; resizable = true;
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
    let appName = if name.strip().len > 0: name.strip() else: generatedName(parsed.hostname)
    let appId = if id.strip().len > 0: id.strip() else: generatedId(parsed.hostname)
    let metadata = PackPackageMetadata(
      version: "0.1.0",
      description: appName & " web application",
      publisher: "Nimino",
      homepage: url,
      categories: @[
        "Network"])
    validate(PackManifest(
      name: appName,
      id: appId,
      url: url,
      icon: icon,
      profile: if profile.strip().len > 0: profile.strip() else: "default",
      window: PackWindowOptions(width: width, height: height, resizable: resizable),
      package: metadata,
      deepLink: PackDeepLinkOptions(schemes: deepLinkSchemes),
      navigationAllow: navigationAllow,
      navigationExternal: navigationExternal,
      permissionsAllow: permissionsAllow,
      css: css,
      javascript: javascript))
  except CatchableError:
    failure[PackManifest](invalidManifest, "URL-only generation received an invalid URL")
