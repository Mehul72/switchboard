# Contributing

## Build

Use Xcode 16 or later on macOS 14.2 or later. Open `Switchboard.xcodeproj`, select
**Switchboard > My Mac**, and press **Command-R**.

Debug builds use your Apple Development certificate. A build signed with a
different identity needs its own Accessibility permission. App Sandbox is
disabled because Switchboard updates macOS preference domains outside its
container.

## Test

Run the test suite with **Command-U** in Xcode, or from the repository root:

```sh
xcodebuild -project Switchboard.xcodeproj -scheme Switchboard \
  -destination 'platform=macOS' -derivedDataPath build/tests \
  CODE_SIGNING_ALLOWED=NO test
```

After changing theme colors, check text contrast:

```sh
./scripts/check-appearance.sh
```

The appearance check covers light and dark surfaces over white and black
backgrounds. It reports increased-contrast modes as skipped when macOS does not
expose them in the current accessibility settings.

Before a release, check the app on a Mac with disposable files and quiet audio:

- Install a fresh copy in Applications and launch it: the welcome window
  opens. Quit with it open, relaunch, and log out and back in with Launch at
  Login on: it stays closed. Move the app to Trash, install it again, and
  install a newer DMG over it: each shows the welcome. Check Return, Escape,
  and VoiceOver in the window.
- Visit each tab in light and dark appearances. Test search, keyboard navigation,
  VoiceOver, long labels, and scrolling on a short display.
- Change a Finder or Dock setting, apply its restart, and restore the original
  value. Check Launch at Login from a signed copy in Applications.
- Check Keep Awake's timer and expiry. Test red-button quit with multiple,
  minimized, and full-screen windows, and with unsaved work.
- Grant and revoke Accessibility and Screen Recording access. Confirm mouse
  scrolling, screen text capture, and red-button quit report missing access.
- Play two apps at low volume. Adjust each app, switch outputs, disconnect a
  device, and reset app audio. Check device volume separately, including an
  output with no software volume control.
- Copy text and images, expand and remove history entries, and clear history.
  Check that private clipboard content stays excluded and that JPEG/HEIC
  screenshots can be pasted into apps that accept files.
- From another app, test the four Switchboard shortcuts, including holding a key.
  Record a new binding, cancel with Escape or Tab, disable and restore it,
  and relaunch to check persistence. Try duplicates and occupied combinations.
  Check recording with VoiceOver and a different keyboard layout. Confirm
  capture shortcuts respect Screen Recording permission and do not overlap.
- Turn on window snapping without Accessibility, then with it. Snap a
  resizable window, a fixed-size window, a Chrome or Electron window, and a
  full-screen window through every layout and Restore. Walk the arrow map in
  all four directions from full screen, a third, and a free window, including
  Terminal. Drag with Control across cells on each display, release Control
  before the mouse, and drag without Control to confirm macOS tiling still
  works. Move a window between two displays of different sizes, including one
  above or left of the main display. Turn snapping off and confirm
  Control-Option-Left and Control-drags reach apps again.
- Compare System readings with Activity Monitor. Close the panel and reopen it
  to check that monitoring resumes.

Record failures in an issue with the macOS version, hardware, and reproduction
steps. Automated tests do not replace permission, hardware, or accessibility
checks.

## Artwork

The app icon master is [artwork/app-icon-master.png](artwork/app-icon-master.png).
The menu bar and header use the vector
[BrandMark.svg](Switchboard/Assets.xcassets/BrandMark.imageset/BrandMark.svg).

After editing the master, regenerate the icon sizes:

```sh
./scripts/generate-app-icons.sh
```

Keep the master's transparent padding. Check the smallest icons and the menu bar
mark in light and dark appearances before committing the exported assets.

## Release

Release builds use Developer ID and Hardened Runtime. Store notarization
credentials once using an app-specific Apple ID password:

```sh
xcrun notarytool store-credentials switchboard-notary \
  --apple-id you@example.com --team-id MACDPWQG37
```

Omit `--password` so the tool prompts for it without putting it in shell history.
Then run:

```sh
./scripts/release.sh
```

The script increments the build number, archives the app, signs it, notarizes
both the app and DMG, and staples their tickets. It replaces `build/` and writes
`build/Switchboard-<version>.dmg`. Upload that DMG to the corresponding GitHub
release.

## Add a setting

Add a `Tweak` to `Switchboard/Model/TweakCatalog.swift`. The model determines which
control the interface displays:

```swift
Tweak(id: "dock.hide-recents",
      title: "Hide recent apps",
      category: .dock,
      symbol: "clock.arrow.circlepath",
      domain: "com.apple.dock", key: "show-recents",
      onValue: .bool(false), offValue: .bool(true), restart: .dock)
```

Omit `offValue` when disabling the setting should delete the preference and let
macOS choose its default. Features that run continuously or perform actions,
such as Keep Awake and screen text capture, belong in `Switchboard/Services`.
