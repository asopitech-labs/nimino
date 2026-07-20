## One-shot host for exercising the authenticated launcher lifecycle without
## starting a native GUI.  It deliberately offers only a fixed v2 capability
## snapshot and acknowledges the dedicated shutdown frame.

import std/[os, streams]

import ../src/nimino_wsl/client/transport
import ../src/nimino_wsl/protocol/[authentication, messages, versioning]

const SessionId = "1234567890abcdef1234567890abcdef"

let token = getEnv("NIMINO_WSL_HOST_TOKEN")
if not token.isValidAuthenticationToken:
  quit(QuitFailure)

let input = newFileStream(stdin)
let output = newFileStream(stdout)
if input.isNil or output.isNil:
  quit(QuitFailure)

let hello = input.readMessageFrom()
if not hello.isOk or not hello.value.validateHello().isOk or
    not token.secureEquals(hello.value.authenticationToken):
  quit(QuitFailure)

let mode = if paramCount() == 1: paramStr(1) else: ""
let invalidCapability = mode == "invalid-capability"
let version = case mode
  of "legacy-version": ProtocolVersion - 1'u16
  of "future-version": ProtocolVersion + 1'u16
  else: ProtocolVersion
let payload = if invalidCapability:
  "{\"capabilities\":[\"arbitraryHostFeature\"]}"
else:
  nativeCapabilitiesPayload(["webPermissionEvents"])
doAssert output.writeMessageTo(ProtocolMessage(
  version: version,
  kind: ready,
  sessionId: SessionId,
  payload: payload
)).isOk

if mode.len > 0:
  quit(QuitSuccess)

let shutdown = input.readMessageFrom()
if not shutdown.isOk or shutdown.value.kind != ProtocolMessageKind.shutdown or
    shutdown.value.sessionId != SessionId:
  quit(QuitFailure)
doAssert output.writeMessageTo(ProtocolMessage(
  version: ProtocolVersion,
  kind: ProtocolMessageKind.response,
  sessionId: SessionId,
  requestId: shutdown.value.requestId,
  payload: "{}"
)).isOk
