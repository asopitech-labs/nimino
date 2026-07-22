## Authenticated application update lifecycle.
##
## Core deliberately does not download or execute an updater.  The host or
## packager supplies a verified manifest and an application-owned signature
## verifier.  This keeps cryptographic key ownership outside the WebView and
## prevents an unsigned URL from becoming an update merely by being reachable.

import std/[strutils, uri]

import ./errors

const NiminoCoreVersion* = "0.1.1"

type
  UpdateState* = enum
    updateIdle
    updateChecking
    updateAvailable
    updateDownloading
    updateReady
    updateFailed

  UpdateManifest* = object
    version*: string
    url*: string
    sha256*: string
    signature*: string
    keyId*: string
    channel*: string

  UpdateSignatureVerifier* = proc(manifest: UpdateManifest): bool {.closure.}

  UpdateLifecycle* = ref object
    appId*: string
    currentVersion*: string
    state*: UpdateState
    manifest*: UpdateManifest
    failure*: CoreError

proc isHex(value: string): bool =
  if value.len == 0: return false
  for ch in value:
    if ch notin {'0'..'9', 'a'..'f', 'A'..'F'}: return false
  true

proc validateUpdateManifest*(manifest: UpdateManifest): CoreResult =
  if manifest.version.strip.len == 0:
    return coreFailure(coreError(invalidArgument, "update.manifest",
      detail = "version must not be empty"))
  if manifest.url.len == 0 or manifest.url.find({'\r', '\n', '\0'}) >= 0:
    return coreFailure(coreError(invalidArgument, "update.manifest",
      detail = "update URL is invalid"))
  try:
    let parsed = parseUri(manifest.url)
    if parsed.scheme.toLowerAscii() != "https" or parsed.hostname.len == 0 or
        parsed.username.len > 0 or parsed.password.len > 0:
      return coreFailure(coreError(permissionDenied, "update.manifest",
        detail = "updates require an HTTPS URL without user information"))
  except CatchableError:
    return coreFailure(coreError(invalidArgument, "update.manifest",
      detail = "update URL is malformed"))
  if manifest.sha256.len != 64 or not isHex(manifest.sha256):
    return coreFailure(coreError(invalidArgument, "update.manifest",
      detail = "sha256 must be 64 hexadecimal characters"))
  if manifest.signature.strip.len == 0 or manifest.keyId.strip.len == 0:
    return coreFailure(coreError(permissionDenied, "update.manifest",
      detail = "a detached signature and key id are required"))
  coreSuccess()

proc newUpdateLifecycle*(appId, currentVersion: string): UpdateLifecycle =
  UpdateLifecycle(appId: appId, currentVersion: currentVersion,
    state: updateIdle)

proc checkForUpdate*(lifecycle: UpdateLifecycle; manifest: UpdateManifest;
                     verifier: UpdateSignatureVerifier): CoreResultOf[bool] =
  if lifecycle.isNil:
    return coreFailureOf[bool](coreError(invalidState, "update.check"))
  lifecycle.state = updateChecking
  let valid = validateUpdateManifest(manifest)
  if not valid.isOk:
    lifecycle.failure = valid.failure
    lifecycle.state = updateFailed
    return coreFailureOf[bool](valid.failure)
  if verifier.isNil or not verifier(manifest):
    lifecycle.failure = coreError(permissionDenied, "update.check",
      detail = "update manifest signature was rejected")
    lifecycle.state = updateFailed
    return coreFailureOf[bool](lifecycle.failure)
  lifecycle.manifest = manifest
  lifecycle.state = if manifest.version == lifecycle.currentVersion:
      updateIdle else: updateAvailable
  coreSuccessOf(lifecycle.state == updateAvailable)

proc beginDownload*(lifecycle: UpdateLifecycle): CoreResult =
  if lifecycle.isNil or lifecycle.state != updateAvailable:
    return coreFailure(coreError(invalidState, "update.download",
      detail = "an available verified update is required"))
  lifecycle.state = updateDownloading
  coreSuccess()

proc markReady*(lifecycle: UpdateLifecycle): CoreResult =
  if lifecycle.isNil or lifecycle.state != updateDownloading:
    return coreFailure(coreError(invalidState, "update.ready",
      detail = "update download has not started"))
  lifecycle.state = updateReady
  coreSuccess()

proc failUpdate*(lifecycle: UpdateLifecycle; detail: string): CoreResult =
  if lifecycle.isNil:
    return coreFailure(coreError(invalidState, "update.fail"))
  lifecycle.failure = coreError(osError, "update.fail", detail = detail)
  lifecycle.state = updateFailed
  coreSuccess()

proc cancelUpdate*(lifecycle: UpdateLifecycle): CoreResult =
  if lifecycle.isNil:
    return coreFailure(coreError(invalidState, "update.cancel"))
  lifecycle.state = updateIdle
  lifecycle.failure = CoreError()
  coreSuccess()
