## Core-level errors intentionally hide native FFI and backend object types.

type
  CoreErrorKind* = enum
    invalidArgument
    invalidState
    platformUnavailable
    nativeFailure

  CoreError* = object
    kind*: CoreErrorKind
    operation*: string
    platformCode*: int32
    detail*: string

  CoreResult* = object
    case isOk*: bool
    of true:
      discard
    of false:
      failure*: CoreError

  CoreResultOf*[T] = object
    case isOk*: bool
    of true:
      value*: T
    of false:
      failure*: CoreError

proc coreError*(kind: CoreErrorKind; operation: string;
                platformCode: int32 = 0; detail: string = ""): CoreError =
  CoreError(kind: kind, operation: operation, platformCode: platformCode,
            detail: detail)

proc coreSuccess*(): CoreResult {.inline.} =
  CoreResult(isOk: true)

proc coreFailure*(error: CoreError): CoreResult {.inline.} =
  CoreResult(isOk: false, failure: error)

proc coreSuccessOf*[T](value: T): CoreResultOf[T] {.inline.} =
  CoreResultOf[T](isOk: true, value: value)

proc coreFailureOf*[T](error: CoreError): CoreResultOf[T] {.inline.} =
  CoreResultOf[T](isOk: false, failure: error)
