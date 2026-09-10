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
  stream, without changing the Mac's main output volume, and send an app to an
  output device of its own while everything else stays on the system default.
  A chosen device is remembered per app and reapplied the next time it plays;
  unplugging that device hands the app back to the default rather than muting it.
  Separate output-device sliders adjust the overall volume of each connected
  device for every app playing through it.
- Clipboard: the last 20 things you copied, text or image, ready to put back.
- System: live CPU, GPU (where available), memory and swap history, Wi-Fi and
  Ethernet traffic rates, disk space, thermal state, and battery details.
  Readings refresh every two seconds only while the panel is visible. History
  covers up to two minutes and resets when monitoring resumes. Memory excludes
  reclaimable file cache. Battery power is the battery charging/discharging rate,
  not total wall power. Hardware-dependent sensors display Unavailable when macOS
  does not expose them. Open Activity Monitor from the panel to inspect processes.

## Installing

1. Download the `.dmg` from the
   [latest release](https://github.com/Mehul72/switchboard/releases/latest).
2. Open it and **drag Switchboard into Applications**.
3. Launch it from Applications. A routed S icon appears in the menu bar.

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
4. Click the routed S icon in the menu bar.

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

The panel follows your Mac's light or dark appearance, with solid surfaces that
stay readable over bright windows. Compact macOS text styles keep labels at
12 points and descriptions at 11 points. Its four main tabs are
**Tweaks**, **Audio**, **Clipboard**, and **System**. Inside Tweaks, choose
**Everyday**, **Files**, **Capture**, or **Dock**. Switchboard remembers that
category when you return from another tab. Each category opens at the top of its
list. Search looks across all categories; press **Command-F** to focus it and
**Escape** to clear a search before closing the panel.

The settings gear contains **Launch at Login**, **Restore Original Settings**,
and **Quit Switchboard**. On shorter screens the content scrolls so the controls
and restart bar remain reachable. A scrollbar stays visible whenever the list
has more content below or above the visible area.

Changes that macOS can read immediately show a confirmation. Finder and Dock
changes show a restart bar; use its button once after making all the changes you
want. Switchboard keeps its panel open during that restart. Global app settings
may require reopening affected apps, and the network-drive setting applies on
the next mount.

**Keep Mac awake** offers 30-minute, one-hour, two-hour, and open-ended choices.
While it runs, the row replaces its description with the time left ("Ends in 24
minutes") or, for the open-ended choice, how long it has been on ("On for 1 hour
5 minutes"). Changing the duration mid-span does not restart that count. The
assertion ends when its timer finishes, when you turn it off, when you restore
settings, or when Switchboard quits.

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
JPEG or HEIC. macOS ignores the format setting for clipboard captures and always
copies PNG, so Switchboard re-encodes new single-image clipboard captures while
it runs; macOS may ask for Clipboard access. The clipboard then carries both the
selected encoding and a matching `.jpg` or `.heic` file, so apps that accept a
pasted file keep that encoding. An app that pastes through the image data alone
still re-encodes to PNG, which macOS gives it on request.

The **Audio** tab shows apps first. Expand **Output devices** below the app list
to see each connected device's volume and a **System Default** label beside the
current default. The output section starts collapsed. Device sliders
affect every app using that output, reflect changes made in macOS within two
seconds while the panel is open, and do not require audio recording access.
Devices without writable volume controls show an explanation. Device volume
changes are left in place when Switchboard quits or app controls are reset.

The **App volume** section lists apps once they create an audio stream. Moving an app slider
below 100% asks for System Audio Recording access the first time. Switchboard
then taps only that app's stream for the current output device and plays it back
at the chosen level. Returning the slider to 100% releases the app to the normal
system mixer. These controls work only while Switchboard is running and reset
to 100% if the app, its audio helpers, or the output device cannot be safely
reconnected.

macOS shows a purple system-audio privacy indicator while these audio taps are
active. **Reset app audio** releases app controls, clears saved
routes, and returns apps to 100% on the default output. Device volumes stay unchanged.
Switchboard cannot set the system indicator's disappearance timeout. Stopping a
tap also stops applying its reduced volume.

Expand **About app audio** for the permission and privacy explanation. The reset
button is enabled while app volumes or outputs have custom adjustments.

For step-by-step checks of every exposed feature, see [Manual tests](MANUAL_TESTS.md).
The [feature audit](AUDIT.md) separates automated results from live checks still needed.

Before Switchboard first changes a key, `UndoLedger` records its exact previous
value—including an unset key. **Restore Original Settings** in the settings gear
menu replays that ledger.

Launch at Login is in the settings gear menu. macOS may require approval in **System
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
