import std/strutils

import nimino_pack

let prepacks = reviewedPrepacks()
doAssert prepacks.len == 3
for prepack in prepacks:
  let loaded = loadPrepack(prepack.slug)
  doAssert loaded.isOk
  doAssert loaded.value.url == prepack.url
  doAssert loaded.value.name.len > 0
  doAssert loaded.value.id.startsWith("com.nimino.")
  doAssert loaded.value.navigationAllow.len == 0
  doAssert loaded.value.navigationExternal.len == 0

let unknown = loadPrepack("not-a-real-prepack")
doAssert not unknown.isOk
doAssert unknown.error.kind == invalidManifest

echo "nimino-pack prepack tests passed"
