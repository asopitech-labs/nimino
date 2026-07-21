import nimino_wsl
import std/[os, strutils]

block emptyHostPathIsRejectedBeforeProcessCreation:
  let launched = launchHost("")
  doAssert not launched.isOk
  doAssert launched.failure.kind == invalidMessage

block startupDiagnosticsNeverRelayArbitraryChildStderr:
  let token = repeat("ab", 32)
  doAssert sanitizeStartupDiagnostic("nimino-wsl-host: authentication failed") ==
    "nimino-wsl-host: authentication failed"
  doAssert sanitizeStartupDiagnostic("nimino-wsl-host: authentication failed " & token) == ""

if paramCount() == 1:
  block authenticatedReadySnapshotsCapabilitiesAndShutdownsCleanly:
    let host = paramStr(1)
    let launched = launchHost(host)
    doAssert launched.isOk
    doAssert launched.value.capabilities == @["webPermissionEvents"]
    doAssert launched.value.close().isOk

  block malformedReadyCapabilitiesAreRejected:
    let host = paramStr(1)
    let launched = launchHost(host, ["invalid-capability"])
    doAssert not launched.isOk
    doAssert launched.failure.kind == invalidMessage

  block incompatibleHostVersionsAreRejectedBeforeSessionUse:
    let host = paramStr(1)
    for mode in ["legacy-version", "future-version"]:
      let launched = launchHost(host, [mode])
      doAssert not launched.isOk
      doAssert launched.failure.kind == unsupportedVersion

  block synchronousRequestsTimeOutAndCancelTheHostOperation:
    let host = paramStr(1)
    let launched = launchHost(host, ["timeout-request"])
    doAssert launched.isOk
    let response = launched.value.call("test.never", "{}", 50)
    doAssert not response.isOk
    doAssert response.failure.kind == timedOut
    doAssert launched.value.close().isOk
