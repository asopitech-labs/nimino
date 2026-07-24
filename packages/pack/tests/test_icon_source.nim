## Reference parity for Pake's icon-source unit suite.

import nimino_pack

for host in ["localhost", "LOCALHOST", "127.0.0.1", "10.0.0.5", "::1",
             "fe80::1", "myhost", "router.local", "nas.lan", "svc.internal",
             "box.home", "pi.localdomain"]:
  doAssert isLikelyLocalHostname(host)
for host in ["example.com", "a.b.example.com", "", "   "]:
  doAssert not isLikelyLocalHostname(host)

doAssert dashboardIconSlugs("GitHub") == @["github"]
doAssert dashboardIconSlugs("Notion AI") == @["notion ai", "notion-ai"]
doAssert dashboardIconSlugs("") == @[]
doAssert dashboardIconSlugs("   ") == @[]

doAssert not shouldPreferDashboardIcons("https://github.com/", "")
doAssert not shouldPreferDashboardIcons("not a url", "GitHub")
doAssert not shouldPreferDashboardIcons("https://github.com/", "GitHub")
doAssert not shouldPreferDashboardIcons("https://mail.google.com/", "Gmail")
doAssert shouldPreferDashboardIcons("https://notebooklm.google.com/", "NotebookLM")
doAssert shouldPreferDashboardIcons("https://grafana.mylab.local/", "Grafana")
doAssert iconSourcePriority("https://github.com/", "GitHub") ==
  @[domainIconSource, dashboardIconSource]
doAssert iconSourcePriority("https://notebooklm.google.com/", "NotebookLM") ==
  @[dashboardIconSource, domainIconSource]

echo "nimino-pack icon source tests passed"
