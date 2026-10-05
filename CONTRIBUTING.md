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
./scripts/test.sh
```

Pass `xcodebuild` options through to run part of it, for example
`./scripts/test.sh -only-testing:SwitchboardTests/WindowLayoutTests`.

The suite needs a logged-in desktop. It takes keyboard focus for a few seconds
and briefly opens a file picker, so don't type while it runs. Tests keep their
preferences in memory. The few that need a real preferences domain use names
starting `com.switchboard.tests.` and remove those files a few seconds after
the run, so nothing is left in `~/Library/Preferences`.

Never switch on mouse scrolling, red-button quit, snapping, or switching from
a test, and never call `applyPendingRestarts` or start screen text capture. In
a terminal that has Accessibility access those would hook the real session,
restart the real Finder, or put a crosshair on the screen.

Every push to `main` and every pull request runs the same script on GitHub
through [ci.yml](.github/workflows/ci.yml).

After changing theme colors, check text contrast:

```sh
./scripts/check-appearance.sh
```

Render the file shelf with example content in light, dark, empty, disk-drag and
short-window states:

```sh
./scripts/check-shelf.sh
```

Inspect the PNGs in `build/shelf-preview`. They use disposable example files and
mock disk actions; the rendering check never ejects a real disk.

To verify native image discovery and eject, run `./scripts/check-shelf.sh --disk`.
It creates temporary 20 MB HFS+ and APFS disk images, mounts each without opening
a Finder window, ejects it through the production service, verifies the image is
fully detached and its source file remains, and removes its fixtures. Existing disks are not ejected.

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
- Check Keep Awake's timer and expiry. Choose Until an app quits with a
  disposable app and quit it: the notice names the app and the assertion is
  gone from `pmset -g assertions`. On a laptop, choose While plugged in and
  unplug and replug the adapter. Check Let display sleep with `pmset -g
  assertions` (system sleep only). Test red-button quit with multiple,
  minimized, and full-screen windows, and with unsaved work. Check an app
  under **Red Button Never Quits** in the settings gear and close its last
  window: it keeps running. With Chrome
  closed, start Switchboard, then open Chrome and close its last tab: Chrome
  quits after about three seconds. Repeat with a second Chrome window
  full screen on another Space, and with one minimized: Chrome stays open.
- Grant and revoke Accessibility and Screen Recording access. Confirm mouse
  scrolling, screen text capture, and red-button quit report missing access.
- Check a slow first text read. Quit Switchboard, then run
  `rm -rf ~/Library/Caches/com.Mehul72.switchboard/com.apple.e5rt.e5bundlecache`
  so macOS has to compile its recognition models again. Relaunch and select an
  area within twenty seconds: the panel returns at once saying it is reading,
  the menu bar icon and the shortcuts keep working, and the text arrives about
  half a minute later. To check the background preparation instead, also run
  `defaults delete com.Mehul72.switchboard TextRecognitionPreparedForSystem`,
  relaunch, wait a minute, and select an area: the text arrives at once.
- Play two apps at low volume. Adjust each app, switch outputs, disconnect a
  device, and reset app audio. Check device volume separately, including an
  output with no software volume control. Send an app to another output, quit
  and reopen it, and play: it uses that output again, at full volume. Then deny
  System Audio Recording in Privacy & Security and lower an app's volume: the
  app must stay audible or the panel must report the failure. It has not been
  established which of the two happens.
- Copy text and images, expand and remove history entries, and clear history.
  Check that private clipboard content stays excluded and that JPEG/HEIC
  screenshots can be pasted into apps that accept files, each appearing once in
  the history. Copy the contents of a file of several megabytes and open
  Clipboard: the panel stays quick, and with Traditional mouse scrolling and
  Window switcher on, scrolling and Command-Tab in other apps do too. Turn off
  **Record Clipboard History** in the settings gear: the list empties and new
  copies stay out of it.
- Drag disposable files from Finder and shake, then repeat with a Shift press.
  The shelf must open beside the pointer, not under it. Check that a straight
  drag, a window drag, text selection, Shift held from the start, and Shift with
  Command do not open it. Drop into the shelf. Drag
  them into Finder and an attachment field; originals must remain in place. Check
  duplicates, the 40-item limit, renaming and deleting originals, Clear, the item
  menus, Command-O, Escape, outside-click dismissal, and the menu bar count.
  Open the file picker with **+**, then click the menu bar icon: both close,
  and **+** opens a picker again. Turn off **Open Shelf During File Drags** in
  the settings gear: shaking and Shift no longer open the shelf.
  Mount a disposable DMG and verify its source file offers Open before mounting
  and Eject afterward. Hover and cancel without ejecting, then drop explicitly
  onto Eject and confirm the mounted volume disappears while the DMG remains.
  In Finder, select the mounted volume on the desktop and press Command-Delete;
  it must eject. Select a file, and a file plus a disk, and press Command-Delete;
  both must go to the Trash as normal, with no eject. Rename the mounted volume
  on the desktop and press Command-Delete in the name field: it stays mounted.
  Turn off **Command-Delete Ejects Disks in Finder** in the settings gear: the
  shortcut no longer ejects.
  Test an external drive, a busy disk, an unplug during eject, keyboard navigation,
  VoiceOver, full-screen Spaces, and a short display. Never force-eject a busy disk.
- From another app, test the five Switchboard shortcuts, including holding a key.
  Repeat with that app in a full-screen Space and its menu bar hidden. The panel
  must stay open on that Space, accept typing in search, and close with Escape,
  an outside click, or the panel shortcut. Open the panel and click its icon
  again at once: it closes without a pause. Open clipboard history while the
  panel is already showing and confirm it stays open with keyboard focus.
  Still over the full-screen app, click a row in the panel so Switchboard is
  the front app, then start **Copy text from the screen** from the panel: after
  the selection the panel must come back and stay open. Close it with the panel
  shortcut and open it with the shortcut again: it must stay open then too.
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
- Compare System readings with Activity Monitor. Its process CPU counts each
  core as 100%, so divide by the core count. Run `yes > /dev/null` and check it
  tops Using the most, then quit a disposable app from the list, including one
  with unsaved changes. Hover the list and confirm rows stop reordering. Turn
  on each menu bar reading: the open panel stays where it is, the readings
  item keeps one width as figures change and keeps updating with the panel
  closed, and clicking it opens System. Command-drag it elsewhere and
  relaunch: it keeps that place. Close the panel and reopen it to check that
  monitoring resumes.
- Choose Check for Updates: it reports the current release. Build with a lower
  `MARKETING_VERSION` and check again: the notice offers the newer release, its
  link and the gear's Update item open the release page, and the notice
  doesn't return after the next panel open. Check with Wi-Fi off: it reports a
  failure within 20 seconds. Turn off automatic checks and relaunch: the
  setting sticks.
- Enable Window switcher and open two windows of the same app plus one of
  another app. Hold Command-Tab, reverse with Shift, use Left/Right and Return,
  cancel with Escape or an outside click, and choose a card with the mouse.
  Verify the exact selected window gains keyboard focus. Repeat with Option-`
  for just the current app, a quick press/release, minimized and hidden windows,
  a closed window, and an unresponsive app. From a desktop, switch to a
  full-screen app and a window on another Space, then Command-Tab back from
  full screen: the previous app comes next. Hover cards, press Q on a disposable
  app (one with unsaved changes too), hold Q, and try Finder. With previews on,
  full-screen, other-Space, minimized and hidden windows show real previews,
  and reopening at once shows them without flicker. Close every window of an
  app without quitting it: it appears under Apps without windows, Tab reaches
  it after the windows, choosing it brings it forward, and Q quits it. Grant/revoke Screen
  Recording and Accessibility, check icon fallbacks, two displays, light/dark
  appearance, VoiceOver, many windows and a short display. Remap both directions,
  record a currently registered binding, disable the feature during a session,
  restore settings, and relaunch to confirm persistence and shortcut cleanup.
  The Dock switcher must stay hidden while Switchboard owns Command-Tab and
  return after disabling the feature, quitting, or force quitting Switchboard.

Record failures in an issue with the macOS version, hardware, and reproduction
steps. Automated tests do not replace permission, hardware, or accessibility
checks.

## Documentation images

After changing the UI, regenerate the app views and README demos using
[the media guide](docs/media.md). It covers the render command, sample data,
and checks to make before committing the images.

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

The script runs the test suite first and stops there if a test fails, before
anything is changed. It then increments the build number, archives the app,
signs it, notarizes both the app and DMG, and staples their tickets. It
replaces `build/` and writes `build/Switchboard-<version>.dmg`. Upload that DMG
to the corresponding GitHub release.

The in-app update check reads GitHub's latest release, which leaves out drafts
and prereleases. Tag each release `vX.Y.Z` to match `MARKETING_VERSION`. A tag
that isn't a plain version number, such as `v1.2.0-beta`, fails the check
instead of being offered, and people won't hear about that release.

The DMG has a dark installer background, fixed icon positions, and an Applications
drop target. Packaging needs a logged-in macOS desktop and permission for the
terminal to automate Finder. The release fails if Finder cannot save the layout.

To preview the installer around an existing app without rebuilding or notarizing:

```sh
./scripts/build-dmg.sh build/export/Switchboard.app build/Switchboard-preview.dmg
open build/Switchboard-preview.dmg
```

Choose a new output filename on subsequent runs. The packager refuses to replace
an existing file. Preview DMGs are unsigned; use `release.sh` for distribution.
The app bundle's existing signature is preserved.

Edit `scripts/render-dmg-artwork.swift` for the artwork and
`scripts/style-dmg.applescript` for Finder layout. Both use an 800 by 540 point
canvas, with 108 point icons at `(220, 336)` and `(580, 336)`. The packager renders
standard and Retina artwork into a TIFF, embeds it in the DMG, and verifies the
compressed image. Check a remounted image: the icons and readable filenames must
line up with the background, and Applications must still point to `/Applications`.

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
