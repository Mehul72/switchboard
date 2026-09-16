# Plan: drag-to-grid and arrow layout map

Status: done (manual checks outstanding)
Follows: docs/plans/window-snapping.md

## Goal
1. Control-Option-arrows move a window around a map of layouts, so halves,
   thirds, quarters, and full screen are all reachable with arrows alone.
2. Holding a key while dragging a window shows a grid over its screen; sweeping
   the pointer highlights cells, and releasing the mouse snaps the window to
   them. The grid can express halves and thirds.

Verifiable by unit tests for every step transition and grid span, and by a
trusted scratch harness that drives a real window with synthetic keys-free
calls (steps) and synthetic mouse events (drag).

## Decided already (user, 2026-09-16)
- Drag: grid overlay only while a key is held. Plain drags are untouched, so
  macOS's own edge tiling keeps working. The grid must allow thirds.
- Arrows: move around a layout map, not repeat-to-cycle.
- The letter shortcuts keep their defaults; arrows are added on top.

## Decided while planning
- Layouts are a lattice of columns (left third, left half, centre third, full,
  right half, right third) and rows (top, full, bottom).
  Left: full > left half > left third; right half > full; right third >
  centre third > left third. Right mirrors it. Up: any layout > full screen,
  full screen > top half (amended 2026-09-17, see log). Down: top > full >
  bottom. A window on no layout starts at left half, right half,
  full screen, or bottom half. At the edge of the map the Mac beeps.
  The preview offered "full screen, Down restores"; that collides with
  "full, Down gives bottom half", so Down stays spatial and Control-Option-
  Delete remains restore. Report this to the user.
- The four half actions become four step actions on the same arrow keys.
  Top and bottom half stay reachable from full screen with Up and Down.
- The layout a window is on comes from memory of the last snap when the
  window has not moved since, else from matching its frame. Apps that round
  sizes (Terminal) still step correctly after a snap.
- Grid is 6 columns by 2 rows: 3 cells is a half, 2 a third, 4 two thirds.
- Grid key is Control, pressed after the drag starts. Option is avoided:
  macOS uses Option during a drag for its own tiling (confirmed: macOS
  26.6.2's WindowManager binary has an enableTilingOptionAccelerator key). Control held at mouse down
  would be a right click, so the grid only reacts once a drag is under way.
- The cell under the pointer when Control goes down is the anchor; sweeping
  extends the span; releasing Control before the mouse cancels.
- A drag counts as a window drag only once the window under the original
  click has moved without resizing, checked through Accessibility off the
  main thread.
- One toggle covers both: "Snap windows", Accessibility required.

## Out of scope
- Configurable grid size or key, plain drag-to-edge zones, overlay labels,
  crossing to another display with arrows at the map's edge.

## Steps
- [x] 1. Layout lattice and step transitions in WindowLayout; SnapMemory
      remembers the layout cell; frame matching.
      files: Model/WindowLayout.swift, SwitchboardTests/WindowLayoutTests.swift
      done when: tests cover every transition, edges, unknown start, matching
- [x] 2. Step actions replace the half actions; snapper handles `.step`.
      files: Model/GlobalShortcut.swift, Services/WindowSnapper.swift, GlobalShortcutsTests.swift
      done when: full suite passes; harness walks a real window through
      left, left, right, right, right, up, down, down and every frame matches
- [x] 3. Grid geometry: cell under a point, frame for a span, AppKit flip.
      files: Model/WindowLayout.swift, WindowLayoutTests.swift
      done when: tests prove spans of 3 and 2 cells equal half and third frames
- [x] 4. Drag tracker, overlay window, snap on release; wired to the toggle.
      files: Services/WindowDragGrid.swift, Services/WindowSnapper.swift, App/StatusItemController.swift, Model/TweakCatalog.swift, Model/TweakStore.swift, project.pbxproj
      done when: builds with no warnings; harness posts a real title-bar drag
      with Control and the window lands on the swept cells; a drag without
      Control does not snap
- [x] 5. README, CONTRIBUTING checklist, Release build.

## Open questions
- None open. Global monitors do see another app's title-bar drag (step 4 log).

## Log
- 2026-09-16 Steps 1 and 2 were verified together: SnapMemory's new cell
  parameter breaks the snapper until it passes one. Full suite 209 passed.
  Harness walked a real window: left, left, right, right, right (edge), up,
  down, down, down (edge), up, up, left, left, left (edge), restore. Every
  frame matched the lattice on a 1512x949 visible frame.
- Placement frames now come from the lattice, so halves and thirds share one
  rounding rule (whole sixths); the earlier tiling tests still pass.
- 2026-09-16 Step 3: 26 WindowLayoutTests passed. The AppKit flip already
  exists (accessibilityRect is its own inverse), so no new function.
- 2026-09-16 Step 4: full suite 212 passed, no Swift warnings. Drag harness
  posted HID-level mouse and Control events at a child window's title bar:
  sweep to left half PASS, sweep top-right third PASS, drag without Control
  moved but did not snap PASS, Control released before mouse up did not snap
  PASS. A mid-drag screenshot showed the 6x2 grid over the visible frame with
  the left half highlighted. This settles the open question.
- Snapper's tail became `move`, shared by keyboard snaps and drops, so both
  use the same queue and restore memory; a drop remembers the pre-drag frame.
- 2026-09-16 Step 5: README describes the arrow map, the Control drag grid,
  and the renamed toggle; CONTRIBUTING checklist covers both. Release build
  succeeded with no Swift warnings.
- Not verified: two displays (grid re-anchoring, arrow map per display),
  Chromium windows, VoiceOver (the overlay is hidden from accessibility and
  purely visual), and the installed app end to end.
- 2026-09-17 User reported full screen was hard to reach with arrows. Cause:
  thirds never pass through full screen sideways, and Up/Down kept the width,
  so a third could not reach full screen at all; quarters took two presses.
  Up now goes to full screen from every layout, and from full screen to the
  top half. Top-row layouts are reached by full screen, Up, then sideways.
  Up is no longer undone by Down, so the reversibility test covers only
  sideways steps. Full suite 214 passed. Harness on a real window: left,
  left, up (full), up (top half), left, left (top-left third), up (full),
  down (bottom half), right (bottom-right quarter), up (full), restore; all
  frames matched.
