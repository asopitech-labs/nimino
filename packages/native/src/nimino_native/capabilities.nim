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

  CapabilitySet* = set[Capability]

proc supports*(available: CapabilitySet; capability: Capability): bool {.inline.} =
  capability in available
