## Cross-platform error and result values. Platform backends map native failures here.

type
  NativeErrorKind* = enum
    unsupported
    invalidState
    permissionDenied
    osError
    webViewError

  NativeError* = object
    kind*: NativeErrorKind
    operation*: string
    platformCode*: int32
    detail*: string

  NativeResult* = object
    case isOk*: bool
    of true:
      discard
    of false:
      failure*: NativeError

  NativeResultOf*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      failure*: NativeError

proc nativeError*(kind: NativeErrorKind; operation: string;
                  platformCode: int32 = 0; detail: string = ""): NativeError =
  NativeError(
    kind: kind,
    operation: operation,
    platformCode: platformCode,
    detail: detail
  )

proc success*(): NativeResult {.inline.} =
  NativeResult(isOk: true)

proc failure*(error: NativeError): NativeResult {.inline.} =
  NativeResult(isOk: false, failure: error)

proc successOf*[T](value: T): NativeResultOf[T] {.inline.} =
  NativeResultOf[T](isOk: true, value: value)

proc failureOf*[T](error: NativeError): NativeResultOf[T] {.inline.} =
  NativeResultOf[T](isOk: false, failure: error)
