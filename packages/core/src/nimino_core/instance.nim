## Process-lifetime single-instance lock used by nimino-core.
##
## The lock is deliberately independent of the WSL transport: a WSL client
## owns its lock in the Linux process, while a native Windows/Linux process
## owns the corresponding OS primitive directly.  No lock state is sent over
## the WSL protocol.

when defined(windows):
  import std/widestrs
else:
  import std/os

type
  InstanceLockStatus* = enum
    instanceAcquired
    instanceAlreadyHeld
    instanceUnavailable

  InstanceLock* = ref object
    held: bool
    path: string
    when defined(windows):
      handle: pointer
    else:
      fd: cint

  InstanceLockResult* = object
    status*: InstanceLockStatus
    lock*: InstanceLock
    detail*: string

when defined(windows):
  proc createMutexW(attributes: pointer; initiallyOwned: int32;
                    name: WideCString): pointer
    {.stdcall, importc: "CreateMutexW", dynlib: "kernel32.dll".}
  proc releaseMutex(handle: pointer): int32
    {.stdcall, importc: "ReleaseMutex", dynlib: "kernel32.dll".}
  proc closeHandle(handle: pointer): int32
    {.stdcall, importc: "CloseHandle", dynlib: "kernel32.dll".}
  proc getLastError(): uint32
    {.stdcall, importc: "GetLastError", dynlib: "kernel32.dll".}

  const ErrorAlreadyExists = 183'u32
else:
  proc niminoOpen(path: cstring; flags, mode: cint): cint
    {.importc: "open".}
  proc niminoClose(fd: cint): cint
    {.importc: "close".}
  proc niminoFlock(fd, operation: cint): cint
    {.importc: "flock".}
  proc niminoErrnoLocation(): ptr cint
    {.importc: "__errno_location".}

  const
    OpenReadWrite = 0x2.cint
    OpenCreate = 0x40.cint
    LockExclusive = 0x2.cint
    LockNonBlocking = 0x4.cint
    ErrorWouldBlock = 11.cint

proc lockFileName(appId: string): string =
  const Hex = "0123456789abcdef"
  var safe = newStringOfCap(appId.len)
  for character in appId:
    if character in {'a'..'z', 'A'..'Z', '0'..'9', '.', '-', '_'}:
      safe.add(character)
    else:
      safe.add('_')
      safe.add(Hex[(ord(character) shr 4) and 0x0f])
      safe.add(Hex[ord(character) and 0x0f])
  if safe.len == 0:
    safe = "app"
  if safe.len > 120:
    safe.setLen(120)
  "Nimino." & safe

when not defined(windows):
  proc ensureDirectory(path: string) =
    if dirExists(path):
      return
    try:
      createDir(path)
    except OSError:
      ## Another process may have created the directory between the existence
      ## check and createDir.  Only propagate a real inability to use it.
      if not dirExists(path):
        raise

proc acquireInstanceLock*(appId: string): InstanceLockResult =
  if appId.len == 0:
    return InstanceLockResult(status: instanceUnavailable,
      detail: "application id must not be empty")
  when defined(windows):
    let name = newWideCString("Local\\" & lockFileName(appId))
    let handle = createMutexW(nil, 1, name)
    if handle == nil:
      return InstanceLockResult(status: instanceUnavailable,
        detail: "CreateMutexW failed with error " & $getLastError())
    if getLastError() == ErrorAlreadyExists:
      discard closeHandle(handle)
      return InstanceLockResult(status: instanceAlreadyHeld,
        detail: "another instance already owns the application mutex")
    return InstanceLockResult(status: instanceAcquired,
      lock: InstanceLock(held: true, path: "Local\\" & lockFileName(appId),
        handle: handle))
  else:
    var root = getEnv("XDG_RUNTIME_DIR")
    let directory = if root.len > 0:
        root / "nimino"
      else:
        getHomeDir() / ".cache" / "nimino"
    try:
      ensureDirectory(parentDir(directory))
      ensureDirectory(directory)
    except OSError as error:
      return InstanceLockResult(status: instanceUnavailable,
        detail: "cannot create instance lock directory: " & error.msg)
    let path = directory / (lockFileName(appId) & ".lock")
    let fd = niminoOpen(cstring(path), OpenReadWrite or OpenCreate, 0o600)
    if fd < 0:
      return InstanceLockResult(status: instanceUnavailable,
        detail: "cannot open instance lock file: " & path)
    if niminoFlock(fd, LockExclusive or LockNonBlocking) != 0:
      let errorNumber = if niminoErrnoLocation() == nil: 0 else: niminoErrnoLocation()[]
      discard niminoClose(fd)
      if errorNumber == ErrorWouldBlock:
        return InstanceLockResult(status: instanceAlreadyHeld,
          detail: "another instance already owns the lock: " & path)
      return InstanceLockResult(status: instanceUnavailable,
        detail: "cannot acquire instance lock " & path & " (errno " & $errorNumber & ")")
    return InstanceLockResult(status: instanceAcquired,
      lock: InstanceLock(held: true, path: path, fd: fd))

proc releaseInstanceLock*(instance: InstanceLock) =
  if instance.isNil or not instance.held:
    return
  when defined(windows):
    if instance.handle != nil:
      discard releaseMutex(instance.handle)
      discard closeHandle(instance.handle)
      instance.handle = nil
  else:
    discard niminoFlock(instance.fd, 8.cint)
    discard niminoClose(instance.fd)
    instance.fd = -1
  instance.held = false
