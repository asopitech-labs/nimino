import nimino_wsl

block emptyHostPathIsRejectedBeforeProcessCreation:
  let launched = launchHost("")
  doAssert not launched.isOk
  doAssert launched.failure.kind == invalidMessage
