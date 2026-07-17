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
