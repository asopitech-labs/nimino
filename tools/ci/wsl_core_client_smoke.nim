import std/os

import nimino_core

if paramCount() != 1:
  quit("usage: wsl-core-client-smoke <windows-host-executable>", QuitFailure)

putEnv("NIMINO_WSL_HOST_EXE", paramStr(1))

let created = newApp(id = "tech.asopi.wsl-core-smoke", name = "WSL core smoke")
doAssert created.isOk
let app = created.value

let window = app.newWindow(title = "WSL core smoke", width = 800, height = 600)
doAssert window.isOk

## This is intentionally a pre-UI-loop smoke: the available host machine may
## not have WebView2 Runtime installed, but core must still select the Windows
## host rather than creating a Linux/WSLg Window on WSL.
doAssert app.quit().isOk
echo "WSL core client/host setup smoke passed"
