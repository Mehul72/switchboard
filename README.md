# Switchboard

Switchboard is a macOS 14+ menu bar utility for small, recurring Mac annoyances.
It uses native SwiftUI/AppKit controls, reads the current macOS preference before
showing a value, verifies every write, and explains when a service restart is
needed.

## What it fixes

- Everyday: keep the Mac awake, stop apps reopening old windows, choose scroll
  bar behaviour, and strip rich formatting from the clipboard.
- Files: reveal hidden files and extensions, show Finder paths, keep folders on
  top, search the current folder, hide desktop clutter, and stop `.DS_Store`
  files on network drives.
- Capture: choose the screenshot folder and format, skip the floating thumbnail,
  and remove window shadows.
- Dock: remove its reveal delay, hide recent apps, and minimise windows into
  their application icons.

## Build and run

1. Open `Switchboard.xcodeproj` in Xcode.
2. Select the **Switchboard** scheme and **My Mac** destination.
3. Press **Command-R**.
4. Click the blue Switchboard icon in the menu bar.

The app has no package dependencies. It is deliberately not App Sandbox enabled,
because it must update macOS preference domains outside its own container.

## Using it

Changes that macOS can read immediately show a confirmation. Finder, Dock, and
screenshot changes show a restart bar; use its button once after making all the
changes you want. Global app settings may require reopening affected apps, and
the network-drive setting applies on the next mount.

Before Switchboard first changes a key, `UndoLedger` records its exact previous
value—including an unset key. **Restore Original Settings…** replays that ledger.

Launch at Login is in the ellipsis menu. macOS may require approval in **System
Settings > General > Login Items**.

## Adding a preference

Add one `Tweak` to `TweakCatalog`; the interface chooses its control from the
model:

```swift
Tweak(id: "dock.hide-recents",
      title: "Hide recent apps",
      category: .dock,
      symbol: "clock.arrow.circlepath",
      domain: "com.apple.dock", key: "show-recents",
      onValue: .bool(false), offValue: .bool(true), restart: .dock)
```

Omit `offValue` when disabling the setting should delete the preference and hand
behaviour back to macOS. Keep-Awake and clipboard cleanup are local actions in
`UtilityServices` rather than preference writes.
