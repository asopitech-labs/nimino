## Built-in, reviewed URL wrappers for common Google web applications.
##
## These are packaging presets, not a signed Popular Packages release catalog.
## They keep the URL, identity, profile, and navigation allow-list together so
## `nimino pack prepack <name>` is deterministic and does not fetch remote
## configuration at build time.

import std/strutils

import ./manifest

type
  PackPrepack* = object
    slug*: string
    manifest*: PackManifest

proc reviewedPrepacks*(): seq[PackPrepack] =
  @[
    PackPrepack(
      slug: "youtube",
      manifest: PackManifest(
        name: "YouTube",
        id: "com.nimino.youtube",
        url: "https://www.youtube.com/",
        profile: "default",
        window: PackWindowOptions(width: 1280, height: 800, resizable: true),
        package: PackPackageMetadata(
          version: "0.1.0",
          description: "YouTube web application",
          publisher: "Nimino",
          homepage: "https://www.youtube.com/",
          categories: @["AudioVideo"]),
        navigationAllow: @[
          "https://www.youtube.com/**",
          "https://youtube.com/**",
          "https://*.youtube.com/**",
          "https://accounts.google.com/**",
          "https://*.googleusercontent.com/**"],
        navigationExternal: @["https://support.google.com/**"])),
    PackPrepack(
      slug: "gmail",
      manifest: PackManifest(
        name: "Gmail",
        id: "com.nimino.gmail",
        url: "https://mail.google.com/mail/u/0/",
        profile: "default",
        window: PackWindowOptions(width: 1280, height: 900, resizable: true),
        package: PackPackageMetadata(
          version: "0.1.0",
          description: "Gmail web application",
          publisher: "Nimino",
          homepage: "https://mail.google.com/",
          categories: @["Network"]),
        navigationAllow: @[
          "https://mail.google.com/**",
          "https://accounts.google.com/**",
          "https://*.googleusercontent.com/**",
          "https://*.google.com/**"],
        navigationExternal: @["https://support.google.com/**"])),
    PackPrepack(
      slug: "google-analytics",
      manifest: PackManifest(
        name: "Google Analytics",
        id: "com.nimino.google-analytics",
        url: "https://analytics.google.com/analytics/web/",
        profile: "default",
        window: PackWindowOptions(width: 1440, height: 900, resizable: true),
        package: PackPackageMetadata(
          version: "0.1.0",
          description: "Google Analytics web application",
          publisher: "Nimino",
          homepage: "https://analytics.google.com/",
          categories: @["Network"]),
        navigationAllow: @[
          "https://analytics.google.com/**",
          "https://accounts.google.com/**",
          "https://*.google.com/**",
          "https://*.googleusercontent.com/**",
          "https://tagmanager.google.com/**"],
        navigationExternal: @["https://support.google.com/**"]))
  ]

proc loadPrepack*(slug: string): PackResult[PackManifest] =
  let normalized = slug.strip().toLowerAscii()
  for prepack in reviewedPrepacks():
    if prepack.slug == normalized:
      return validate(prepack.manifest)
  failure[PackManifest](invalidManifest, "unknown prepack: " & slug)
