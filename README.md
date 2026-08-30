# Switchboard

Switchboard is a macOS 14.2+ menu bar utility for small, recurring Mac annoyances.
It uses native SwiftUI/AppKit controls, reads the current macOS preference before
showing a value, verifies every write, and explains when a service restart is
needed.

## What it fixes

- Everyday: keep the Mac awake for a chosen time, copy text from any screen
  region, quit an app when its last window closes, give a mouse traditional
  scrolling without changing the trackpad, choose scroll-bar behaviour, and
  strip rich formatting from the clipboard.
- Files: reveal hidden files and extensions, show Finder paths, keep folders on
  top, search the current folder, hide desktop clutter, and stop `.DS_Store`
  files on network drives.
- Capture: save screenshots to a folder or the clipboard, choose PNG, JPEG, or
  HEIC encoding, skip the floating thumbnail, and remove window shadows.
- Dock: remove its reveal delay, hide recent apps, and minimise windows into
  their application icons.
- Audio: change the volume of individual apps that currently own an audio
  stream, without changing the Mac's main output volume.
- Clipboard: the last 20 things you copied, text or image, ready to put back.

## Installing

1. Download the `.dmg` from the
   [latest release](https://github.com/Mehul72/switchboard/releases/latest).
2. Open it and **drag Switchboard into Applications**.
3. Launch it from Applications. An icon of three linked points appears in the menu bar.

Do not run Switchboard from the Downloads folder. macOS relocates an app opened
from there into a temporary read only location, and every permission you grant
is attached to that copy, so the settings below silently stop working.

## Permissions

Most of Switchboard needs no permission at all. Three features do, and macOS
asks the first time each one is used.

| Feature | Permission | Where to grant it |
| --- | --- | --- |
| Traditional mouse scrolling, Red button quits the app | Accessibility | System Settings > Privacy & Security > Accessibility |
| Copy text from the screen | Screen Recording | System Settings > Privacy & Security > Screen Recording |
| Per app volume | Audio Recording | Prompted on the first slider change |

Switching a toggle on before its permission exists opens the relevant prompt and
leaves the toggle off. Grant the permission, then switch it on again.

Switchboard is signed with a stable Developer ID, so a permission granted once
survives future updates.

## What it never does

- No clipboard history is written to disk. It lives in memory and is forgotten
  when Switchboard quits, and anything a password manager marks as private is
  skipped entirely.
- Nothing is sent anywhere. There is no network code in the app.
- Every preference it changes is recorded first, and **Restore Original
  Settings** puts them all back.

## Build and run

1. Open `Switchboard.xcodeproj` in Xcode.
2. Select the **Switchboard** scheme and **My Mac** destination.
3. Press **Command-R**.
4. Click the three linked points icon in the menu bar.

The app has no package dependencies. It is deliberately not App Sandbox enabled,
because it must update macOS preference domains outside its own container.

## Releasing

Debug builds sign with your Apple Development certificate. Release builds sign
with Developer ID and enable the Hardened Runtime, which notarisation requires.

Store your notary credentials once, using an app specific password from
appleid.apple.com rather than your Apple ID password:

```
xcrun notarytool store-credentials switchboard-notary \
    --apple-id you@example.com --team-id MACDPWQG37
```

Omit `--password` so notarytool prompts securely and the app-specific password
does not enter your shell history.

Then:

```
./scripts/release.sh
```

It bumps the build number, archives, exports with Developer ID, verifies the
signature, notarises, staples the ticket, and writes a stapled disk image to
`build/`. Upload that `.dmg` to a GitHub release.

Stapling is not optional. Without it the app refuses to launch for anyone whose
Mac cannot reach Apple to check the notarisation.

## Using it

Changes that macOS can read immediately show a confirmation. Finder and Dock
changes show a restart bar; use its button once after making all the changes you
want. Switchboard keeps its panel open during that restart. Global app settings
may require reopening affected apps, and the network-drive setting applies on
the next mount.

**Keep Mac awake** offers 30-minute, one-hour, two-hour, and open-ended choices.
The assertion ends when its timer finishes, when you turn it off, when you
restore settings, or when Switchboard quits.

**Copy text from the screen** asks for Screen Recording access the first time.
After approving Switchboard in **System Settings > Privacy & Security**, choose
**Select Area**, drag over the text, and paste the recognised result anywhere.

**Quit apps from the red close button** and mouse-only scroll inversion require
Accessibility access because they observe system-wide input. Turn the feature
on, approve Switchboard in **System Settings > Privacy & Security >
Accessibility**, then turn it on once more. These features work while
Switchboard is running.

The red button quits an app only when it closes that app's **last** window.
Closing one of several windows just closes that window, and windows you cannot
see at that moment still count: minimised ones, ones in full screen, and ones
left on another Desktop. It sends a normal quit request, so anything unsaved
still prompts you.

For clipboard screenshots, turn on **Copy screenshots to clipboard** and choose
JPEG or HEIC. Switchboard re-encodes new single-image clipboard captures while
it runs; macOS may ask for Clipboard access. The pasteboard carries the selected
encoding, although an app receiving the paste can still normalise it to PNG.

The **Audio** tab lists apps once they create an audio stream. Moving a slider
below 100% asks for System Audio Recording access the first time. Switchboard
then taps only that app's stream for the current output device and plays it back
at the chosen level. Returning the slider to 100% releases the app to the normal
system mixer. These controls work only while Switchboard is running and reset
to 100% if the app, its audio helpers, or the output device cannot be safely
reconnected.

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
behaviour back to macOS. Runtime features such as Keep Awake, Region OCR,
per-app audio, clipboard cleanup, clipboard image conversion, and quit-on-close
live in `Services` rather than as preference-only rows.
