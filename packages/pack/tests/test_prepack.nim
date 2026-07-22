import nimino_pack

let prepacks = reviewedPrepacks()
doAssert prepacks.len == 3
for prepack in prepacks:
  let expected = case prepack.slug
    of "youtube": ("YouTube", "com.nimino.youtube", "https://www.youtube.com/")
    of "gmail": ("Gmail", "com.nimino.gmail", "https://mail.google.com/mail/u/0/")
    of "google-analytics": ("Google Analytics", "com.nimino.google-analytics",
      "https://analytics.google.com/analytics/web/")
    else: ("", "", "")
  doAssert expected[0].len > 0
  let loaded = loadPrepack(prepack.slug)
  doAssert loaded.isOk
  doAssert loaded.value.name == expected[0]
  doAssert loaded.value.id == expected[1]
  doAssert loaded.value.url == expected[2]
  doAssert loaded.value.navigationAllow.len > 0
  doAssert loaded.value.navigationExternal == @["https://support.google.com/**"]

let unknown = loadPrepack("not-a-real-prepack")
doAssert not unknown.isOk
doAssert unknown.error.kind == invalidManifest

echo "nimino-pack prepack tests passed"
