## Authentication and session checks shared by the Windows host lifecycle.

import ../protocol/[authentication, messages]

proc authenticateHello*(expectedToken: string; message: ProtocolMessage): ProtocolResult =
  if not expectedToken.isValidAuthenticationToken:
    return failure(protocolError(authenticationFailed, "host authentication is unavailable"))
  let hello = message.validateHello()
  if not hello.isOk:
    return hello
  if not expectedToken.secureEquals(message.authenticationToken):
    return failure(protocolError(authenticationFailed, "host authentication failed"))
  success()

proc validateSessionMessage*(sessionId: string; message: ProtocolMessage): ProtocolResult =
  if not message.version.validateVersion.isOk:
    return failure(protocolError(unsupportedVersion, "host version mismatch"))
  if sessionId.len == 0 or message.sessionId != sessionId:
    return failure(protocolError(authenticationFailed, "session is invalid"))
  if message.authenticationToken.len != 0:
    return failure(protocolError(authenticationFailed, "authentication token is only allowed in hello"))
  success()

proc validatePolicyResponse*(sessionId: string; requestId: uint64;
                             message: ProtocolMessage): ProtocolResult =
  ## A synchronous permission/navigation callback must only consume the
  ## response for its own authenticated request.  Treat every mismatch as a
  ## protocol failure so the caller can deny (and close) rather than applying
  ## a stale or injected decision.
  let session = sessionId.validateSessionMessage(message)
  if not session.isOk:
    return session
  if message.kind != ProtocolMessageKind.response:
    return failure(protocolError(invalidMessage, "expected policy response"))
  if requestId == 0 or message.requestId != requestId:
    return failure(protocolError(invalidMessage, "policy response request is invalid"))
  success()
