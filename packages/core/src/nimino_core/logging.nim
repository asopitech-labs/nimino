## Small, dependency-free application logger.
##
## Logging is deliberately opt-in and structured.  The default sink is nil, so
## applications do not accidentally write credentials or browser state to
## stdout.  All emitted text passes through a conservative redactor before it
## reaches the application-owned sink.

import std/[strutils, times]

type
  LogLevel* = enum
    logTrace
    logDebug
    logInfo
    logWarn
    logError

  LogRecord* = object
    timestampUnixMs*: int64
    level*: LogLevel
    operation*: string
    message*: string

  LogSink* = proc(record: LogRecord) {.closure.}

  Logger* = ref object
    minimum*: LogLevel
    sink*: LogSink

proc newLogger*(sink: LogSink = nil; minimum = logInfo): Logger =
  Logger(minimum: minimum, sink: sink)

proc redactPair(value, key: string): string =
  ## Redact key=value fragments without logging the value.  This catches the
  ## common forms used by HTTP headers, IPC diagnostics, and query strings.
  result = value
  var cursor = 0
  let needle = key.toLowerAscii() & "="
  while true:
    let lower = result.toLowerAscii()
    let found = lower.find(needle, cursor)
    if found < 0:
      break
    let valueStart = found + needle.len
    var valueEnd = valueStart
    while valueEnd < result.len and result[valueEnd] notin {'\r', '\n', '&', ';', ','}:
      inc valueEnd
    let suffix = if valueEnd < result.len: result[valueEnd .. ^1] else: ""
    result = result[0 ..< valueStart] & "<redacted>" & suffix
    cursor = valueStart + "<redacted>".len

proc redact*(value: string): string =
  ## Public for tests and custom sinks; it never attempts to parse JSON.
  result = value
  for key in ["authorization", "token", "session", "cookie", "password",
              "passwd", "secret", "access_token", "refresh_token"]:
    result = redactPair(result, key)

proc shouldLog*(logger: Logger; level: LogLevel): bool {.inline.} =
  not logger.isNil and not logger.sink.isNil and level >= logger.minimum

proc emit*(logger: Logger; level: LogLevel; operation, message: string) =
  if not logger.shouldLog(level):
    return
  let record = LogRecord(timestampUnixMs: int64(epochTime() * 1000.0),
    level: level, operation: redact(operation), message: redact(message))
  try:
    logger.sink(record)
  except CatchableError:
    ## A logging sink must never break UI lifecycle or RPC processing.
    discard

proc trace*(logger: Logger; operation, message: string) =
  logger.emit(logTrace, operation, message)

proc debug*(logger: Logger; operation, message: string) =
  logger.emit(logDebug, operation, message)

proc info*(logger: Logger; operation, message: string) =
  logger.emit(logInfo, operation, message)

proc warn*(logger: Logger; operation, message: string) =
  logger.emit(logWarn, operation, message)

proc error*(logger: Logger; operation, message: string) =
  logger.emit(logError, operation, message)
