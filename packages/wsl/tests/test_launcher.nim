import nimino_wsl
import std/[monotimes, options, os, strutils]
from std/times import inMilliseconds

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

  block partialReadyFramesHonorTheHandshakeDeadline:
    let host = paramStr(1)
    let started = getMonoTime()
    let launched = launchHost(host, ["partial-ready"])
    let elapsedMs = (getMonoTime() - started).inMilliseconds
    doAssert not launched.isOk
    doAssert launched.failure.kind == timedOut
    doAssert elapsedMs < 7_000

  block shortPollIntervalsDoNotBecomePartialFrameDeadlines:
    let host = paramStr(1)
    let launched = launchHost(host, ["split-event"])
    doAssert launched.isOk
    let received = launched.value.receiveNextWithin(10)
    doAssert received.isOk
    doAssert received.value.isSome
    doAssert received.value.get().kind == event
    doAssert received.value.get().methodName == "test.split"
    doAssert launched.value.close().isOk

  block synchronousRequestsTimeOutAndCancelTheHostOperation:
    let host = paramStr(1)
    let launched = launchHost(host, ["timeout-request"])
    doAssert launched.isOk
    let response = launched.value.call("test.never", "{}", 50)
    doAssert not response.isOk
    doAssert response.failure.kind == timedOut
    doAssert launched.value.close().isOk

  block structuredNativeErrorsSurviveLauncherMapping:
    let host = paramStr(1)
    let launched = launchHost(host, ["structured-error"])
    doAssert launched.isOk
    let response = launched.value.call("native.window.setTitle", "{}")
    doAssert not response.isOk
    doAssert response.failure.nativeKind == "osError"
    doAssert response.failure.nativeOperation == "window.setTitle"
    doAssert response.failure.nativePlatformCode == 5
    doAssert response.failure.nativeDetail == "SetWindowTextW failed"
    doAssert launched.value.close().isOk

  block shutdownAcknowledgementDoesNotHideALingeringHost:
    let host = paramStr(1)
    let launched = launchHost(host, ["linger-after-shutdown"])
    doAssert launched.isOk
    let closed = launched.value.close()
    doAssert not closed.isOk
    doAssert closed.failure.kind == timedOut
