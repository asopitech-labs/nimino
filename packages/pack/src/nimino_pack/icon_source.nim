## Deterministic icon-source selection for URL wrappers.

import std/[sequtils, strutils, uri]

type IconSource* = enum
  dashboardIconSource
  domainIconSource

const LocalHostSuffixes = [".local", ".lan", ".internal", ".home", ".localdomain"]
const TwoLabelSuffixes = [
  "ac.uk", "co.uk", "gov.uk", "ltd.uk", "me.uk", "net.uk", "nhs.uk",
  "org.uk", "plc.uk", "sch.uk", "com.au", "net.au", "org.au", "edu.au",
  "gov.au", "co.jp", "ne.jp", "or.jp", "com.br", "com.cn", "com.mx",
  "co.nz", "org.nz", "co.kr", "co.in", "com.sg", "com.hk", "com.tw"
]

proc normalized(value: string): string = value.strip().toLowerAscii()

proc simplified(value: string): string =
  for character in normalized(value):
    if character notin {' ', '.', '_', '-'}:
      result.add(character)

proc isIpv4(value: string): bool =
  let parts = value.split('.')
  if parts.len != 4: return false
  for part in parts:
    if part.len == 0 or part.len > 3 or part.anyIt(it notin {'0'..'9'}):
      return false
  true

proc isLikelyLocalHostname*(hostname: string): bool =
  let host = normalized(hostname)
  if host.len == 0: return false
  host == "localhost" or isIpv4(host) or host.contains(':') or
    not host.contains('.') or LocalHostSuffixes.anyIt(host.endsWith(it))

proc dashboardIconSlugs*(appName: string): seq[string] =
  let name = normalized(appName)
  if name.len == 0: return @[]
  result.add(name)
  let hyphenated = name.splitWhitespace().join("-")
  if hyphenated.len > 0 and hyphenated notin result:
    result.add(hyphenated)

proc registrableDomain(hostname: string): string =
  let labels = normalized(hostname).split('.')
  if labels.len < 2: return ""
  let suffixLength = if labels.len >= 3 and
      (labels[^2] & "." & labels[^1]) in TwoLabelSuffixes: 2 else: 1
  if labels.len <= suffixLength: return ""
  labels[labels.len - suffixLength - 1 .. ^1].join(".")

proc shouldPreferDashboardIcons*(url, appName: string): bool =
  if appName.strip().len == 0: return false
  try:
    let host = parseUri(url).hostname.toLowerAscii()
    if host.len == 0: return false
    if isLikelyLocalHostname(host): return true
    let domain = registrableDomain(host)
    if domain.len == 0 or host == domain: return false
    let labels = host.split('.')
    let domainLabels = domain.split('.')
    if labels.len <= domainLabels.len: return false
    let productLabel = labels[labels.len - domainLabels.len - 1]
    let rootLabel = domainLabels[0]
    let name = simplified(appName)
    name.len > 0 and simplified(productLabel) == name and
      simplified(rootLabel) != name
  except CatchableError:
    false

proc iconSourcePriority*(url, appName: string): seq[IconSource] =
  if shouldPreferDashboardIcons(url, appName):
    @[dashboardIconSource, domainIconSource]
  else:
    @[domainIconSource, dashboardIconSource]
