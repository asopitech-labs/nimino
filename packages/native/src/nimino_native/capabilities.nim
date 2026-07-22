## Capability values are explicit: a missing backend feature is never a no-op.

type
  Capability* = enum
    multipleWebViews
    transparentWindow
    nativeMenu
    systemTray
    nativeNotification
    customProtocol
    webPermissionEvents

  ## Window controls are kept separate from the application capability set.
  ## The WSL handshake exposes `Capability` values, while these controls are
  ## native-window operations that are intentionally not part of that
  ## protocol surface yet.
  WindowCapability* = enum
    fullscreen
    maximize
    alwaysOnTop

  CapabilitySet* = set[Capability]

proc supports*(available: CapabilitySet; capability: Capability): bool {.inline.} =
  capability in available
