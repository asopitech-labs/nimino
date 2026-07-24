## Small, platform-neutral helpers for release artifact discovery.
##
## The release test consumes artifacts produced by a pack builder, so its
## matcher must treat regular package files and macOS `.app` directories
## consistently without depending on a shell glob implementation.

import std/[algorithm, os, strutils]

proc matchesArtifactPattern*(value, pattern: string): bool =
  ## Match the `*` and `?` glob tokens used by the release artifact contract.
  ## Package file names are plain path components, therefore deliberately do
  ## not give either token special path-separator behavior.
  var valueAt = 0
  var patternAt = 0
  var starAt = -1
  var retryAt = 0
  while valueAt < value.len:
    if patternAt < pattern.len and
        (pattern[patternAt] == '?' or pattern[patternAt] == value[valueAt]):
      inc valueAt
      inc patternAt
    elif patternAt < pattern.len and pattern[patternAt] == '*':
      starAt = patternAt
      inc patternAt
      retryAt = valueAt
    elif starAt >= 0:
      patternAt = starAt + 1
      inc retryAt
      valueAt = retryAt
    else:
      return false
  while patternAt < pattern.len and pattern[patternAt] == '*':
    inc patternAt
  patternAt == pattern.len

proc findArtifacts*(directory, pattern: string): seq[string] =
  ## Return matching direct children only. Other directories are never
  ## artifacts; a macOS `.app` bundle is the intentional directory exception.
  if not dirExists(directory):
    return @[]
  try:
    for kind, path in walkDir(directory, relative = false):
      let name = extractFilename(path)
      if not matchesArtifactPattern(name, pattern):
        continue
      if kind == pcFile or (kind == pcDir and name.endsWith(".app")):
        result.add(path)
    result.sort()
  except OSError:
    result = @[]

proc findFirstExistingArtifact*(locations: openArray[string]): string =
  ## Preserve the release workflow's primary-output then fallback-output
  ## search order. A file or a macOS application bundle counts as an artifact.
  for location in locations:
    if fileExists(location) or (dirExists(location) and location.endsWith(".app")):
      return location
  ""
