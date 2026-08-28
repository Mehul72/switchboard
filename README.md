# Switchboard

A macOS menu bar app that exposes hidden system preferences as toggles, so I
don't have to remember `defaults write` incantations. It writes the same
preference keys the Terminal one-liners do, then restarts Dock, Finder or
SystemUIServer as needed.

Requires macOS 14 or later.

## Building

Open `Switchboard.xcodeproj` and run. No dependencies, no entitlements — the app
is deliberately unsandboxed, because writing to other apps' preference domains
is the whole point. The build is unsigned, so the first launch needs a
right-click and Open.

## How it works

Every setting is one `Tweak` value in `TweakCatalog`. The views iterate the
catalog and pick a control based on `control`, so adding a setting is adding a
struct, not writing UI:

    Tweak(id: "dock.no-bouncing",
          title: "No launch bounce",
          category: .dock,
          domain: "com.apple.dock",
          key: "no-bouncing",
          onValue: .bool(true),
          offValue: .bool(false),
          restart: .dock)

Leave `offValue` off and switching the toggle back deletes the key instead,
which hands the setting back to whatever macOS defaults to.

Toggle state is read from CFPreferences every time the popover opens — nothing
is cached, so changing something in System Settings keeps the app honest.

Before the first write to any key, the previous value is copied into
Switchboard's own preferences, including the fact that a key was unset.
"Restore defaults" replays that record and clears it.

Flipping toggles marks Dock/Finder/SystemUIServer as needing a restart and shows
an Apply bar — one `killall` per process on Apply, not one per toggle.

## Known issues

Instant window resize only affects apps that animate their own window resizes.
Plenty ignore `NSWindowResizeTime` entirely.

The typing settings are read when a text view is created, so apps that are
already running keep the old behaviour until you relaunch them.

Disabling `.DS_Store` on network volumes takes effect the next time you mount
one, not immediately.

Launch at login silently fails to register when the app runs out of DerivedData.

TODO: no way to export or import a set of tweaks yet, which is the thing I
actually want when setting up a new machine.
