# Plan: file shelf and quick eject

Status: in progress

## Goal

Provide a polished contextual panel that opens when files or mounted volumes are
dragged onto Switchboard. Files can be parked temporarily and dragged back out;
external drives and mounted disk images have explicit eject targets and buttons.
The same panel is available from the main panel and a configurable global shortcut.

## Decisions

- Match the existing adaptive palette with spacious cards, file previews, and
  separate shelf and connected-drive sections. Support keyboard and VoiceOver.
- Keep at most 40 local file references in memory. Never move, delete, or upload
  originals. Clear the shelf when the app quits; duplicates do not consume slots.
- Hover opens the panel. Only an explicit eject drop or button can request eject.
- Use native volume metadata and normal macOS eject, protecting internal volumes.
  Read `hdiutil info -plist` with fixed arguments and a timeout to associate a
  downloaded image with its mounted volumes; never run a shell with file paths.
- Keep files on the shelf after dragging them out. Mark missing files unavailable.
- Add Control-Option-Command-F for the shelf through the existing shortcut system.

## Out of scope

Persistent storage, cloud uploads, file promises from non-file drags, automatic
ejection, force eject, and deleting downloaded installers.

## Steps

- [x] 1. Implement file-reference storage, payload classification, mounted-volume
  discovery and ejection. Add focused XCTest coverage for deduplication, limits,
  unavailable files, mounted-image mapping, protected volumes, and eject outcomes.
  Done when the new service tests pass.
- [x] 2. Build the adaptive shelf UI, native drag targets and drag sources, panel
  lifecycle, status-item count, entry point, and global shortcut. Verify the app
  builds and targeted interaction/shortcut tests pass.
- [x] 3. Verify light/dark renderings, native file drag and a disposable mounted
  image. Fix defects, run the full suite and appearance checks, and update the
  README, user guide, and contributor checks. Record any checks the environment
  cannot exercise.
- [ ] 4. Replace the menu-bar drop target with a drag gesture: while a file drag
  from another app is in progress, a shake or a lone Shift press opens the shelf
  beside the pointer (never under it, so an eject still needs a deliberate drop).
  Done when gesture and placement tests pass, the full suite passes, docs are
  updated, and a real Finder drag opens the shelf in a debug build.

## Log

- 2026-09-24: Read existing menu-bar controller, theme, shortcut registration,
  build setup and test conventions. Working tree was clean. No package dependencies
  are needed. Native eject is synchronous, so it will run off the UI thread.
- Step 1: 18 service tests passed, including a real bookmark rename, file URL
  pasteboard round-trip, duplicate/limit checks, protected volumes, image plist
  parsing, coalesced refreshes, stale identity and busy-disk retry. Build passed.
- Step 2: App builds and 55 targeted tests pass. Added native AppKit drag
  destinations, copy-only drag sources, the adaptive panel, menu-bar count,
  toolbar entry point and configurable shortcut. Native destination tests verify
  hover has no side effects and changed payloads are revalidated on drop.
- Step 3 finding: the disposable image mounted with `-nobrowse` was omitted by
  `.skipHiddenVolumes`. Probed the same mount with both enumeration options:
  it is local, removable, ejectable, and has a UUID, but is not browsable. Removed
  the Finder visibility filter; internal/system-volume protection still applies.
- Step 3: Full suite 311/311, all appearance checks, light/dark shelf renders and
  `check-shelf.sh --disk` pass. Review fix: `hdiutil` failure or timeout blanked
  the whole Connected list; image association is now best effort and logged,
  with tests for both paths.
- Not exercised (needs the installed copy quit): a real Finder drag onto the menu
  bar icon, a normal click through the overlaid drop view to the main panel, a
  physical external drive, VoiceOver. Native AppKit destination tests cover the
  drop logic; the CONTRIBUTING release checklist covers the rest.
- Reversed the `-nobrowse` change: including hidden mounts listed Xcode's iOS
  Simulator runtimes (CoreSimulator and cryptexd mounts, non-browsable) as
  ejectable. Only browsable volumes are listed now; the disk check mounts with
  `-noautoopen` instead of `-nobrowse`.
- 2026-09-24: User rejected the menu-bar icon as the entry point and asked for a
  key press or shake during a drag, which brings the global drag monitor into
  scope. Polls the pointer at 60 Hz only while the button is held in another app,
  because drag events are not reliably forwarded to global monitors during a
  drag session. A file drag is detected from the drag pasteboard change count.
  Shift was chosen because Finder drags do not use it (Option copies, Command
  moves). Removed `ShelfStatusDropView`, which also removes the click-through risk.
- 2026-09-25 bug: after Eject on a mounted APFS DMG, double-clicking the DMG did
  nothing. `NSWorkspace.unmountAndEjectDevice` ejected the synthesized APFS
  container, which unmounts the volume but leaves the image attached;
  DiskImageMounter then "re-attaches" the existing device and mounts nothing.
  HFS+ images detach fully, which is why the HFS+-only disk check passed. Fix:
  image volumes eject their own whole disk with `diskutil eject` (`hdiutil detach`
  is deprecated), after re-confirming the device still backs the same image. The
  disk check now covers HFS+ and APFS and asserts the image is detached.
  Unverified: a physical APFS external drive still uses the NSWorkspace eject.
- 2026-09-25 design pass (user: smaller, easier gesture, more aesthetic): panel
  296 pt wide and fitted to its content (capped at 560 pt, scrolls beyond),
  keeping its top edge still as content changes. Files became a four-column
  thumbnail grid with a hover or right-click menu; the drop card shows only when
  the shelf is empty or a drag is in progress, since the whole panel accepts
  drops. Removed the subtitle, footer and all-caps section labels. Shake now
  needs 2 reversals of 30 pt within 0.5 s (was 3 of 40 pt within 0.8 s); the
  short window keeps slow aiming from counting. Panel opens 12 pt from the
  pointer (was 24).
- 2026-09-25: Command-Delete on a selected item: a disk, or a shelved DMG whose
  image is mounted, is ejected; any other shelf item is removed from the shelf.
  Clicking a tile or disk row selects it. Scoped to the shelf panel, not Finder.
- 2026-09-25: Command-Delete in Finder. The shelf-only version did nothing for a
  volume selected on the desktop, which is what the user meant. A global keyDown
  monitor (Accessibility) reacts only to plain Command-Delete with Finder
  frontmost; Finder's selection is read through Accessibility (desktop icons and
  list rows both carry AXURL file references), so no Apple Events permission is
  needed. Ejects only when every selected item is an ejectable volume. Verified
  the reader on a disposable desktop volume; the key path in a signed build is
  not yet verified.
