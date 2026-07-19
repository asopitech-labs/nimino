import nimino_wsl
import std/strutils

block emptyHostPathIsRejectedBeforeProcessCreation:
  let launched = launchHost("")
  doAssert not launched.isOk
  doAssert launched.failure.kind == invalidMessage

block startupDiagnosticsNeverRelayArbitraryChildStderr:
  let token = repeat("ab", 32)
  doAssert sanitizeStartupDiagnostic("nimino-wsl-host: authentication failed") ==
    "nimino-wsl-host: authentication failed"
  doAssert sanitizeStartupDiagnostic("nimino-wsl-host: authentication failed " & token) == ""
