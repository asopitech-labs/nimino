import std/strutils
import nimino_core

var records: seq[LogRecord]
let logger = newLogger(proc(record: LogRecord) = records.add(record), logTrace)
logger.info("rpc.invoke", "token=abc123 cookie=session=private")
doAssert records.len == 1
doAssert records[0].message.find("abc123") < 0
doAssert records[0].message.find("private") < 0
doAssert records[0].message.find("<redacted>") >= 0
doAssert redact("Authorization=Bearer secret-value") ==
  "Authorization=<redacted>"

let quiet = newLogger(proc(record: LogRecord) = discard, logError)
doAssert not quiet.shouldLog(logWarn)
doAssert quiet.shouldLog(logError)

echo "core logging tests passed"
