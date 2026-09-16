# Plan: window snapping

Status: done (manual checks outstanding)

## Goal
Keyboard shortcuts move and resize the focused window of any app into halves,
quarters, thirds, two thirds, maximised, centred, onto another display, or back
to its size before snapping. Verifiable by the layout and memory unit tests, a
clean build, and pressing a shortcut on a trusted build.

## Decided already
- Shortcuts only. Dragging windows to screen edges is out of scope.
- An Everyday toggle, "Snap windows with shortcuts", off by default. Window
  shortcuts register only while it is on and Accessibility is granted, so an
  update never takes Control-Option-arrow away from apps without consent.
  Follows the existing red-button quit and mouse scrolling permission pattern.
- Window actions join `ShortcutAction`, reusing recording, persistence,
  conflict checks, and the Keyboard Shortcuts window, shown in their own section.
- Defaults are Control-Option with: arrows (halves), U I J K (quarters),
  D F G (thirds), E T (two thirds), Return (maximise), C (centre),
  Delete (restore). Control-Option-Command-Left/Right moves between displays.
  Return and Delete become recordable keys.
- Accessibility calls run on a serial background queue with a messaging
  timeout, so a hung app cannot freeze the panel and repeated presses apply in
  order. Screen geometry is read on the main thread first.
- Switchboard's own windows are skipped: AX calls into our own process from
  our own queue would wait on the main thread.
- Nothing to do (no focused window, full screen, not movable) is a system beep
  plus a log line. Missing permission prompts and shows a notice in the panel.

## Out of scope
- Drag to edge snapping, window gaps, custom layouts, Stage Manager handling.
- Moving windows between Spaces.

## Steps
- [x] 1. Pure layout: placements, target frame per placement, display move,
      clamping an app-resized window back inside the screen, coordinate
      conversion, restore memory.
      files: Switchboard/Model/WindowLayout.swift, SwitchboardTests/WindowLayoutTests.swift, project.pbxproj
      done when: new tests pass, including tiling without gaps on odd widths
- [x] 2. Window actions in the shortcut model, gated registration, Return and
      Delete key names.
      files: Switchboard/Model/GlobalShortcut.swift, Switchboard/Services/GlobalShortcuts.swift, SwitchboardTests/GlobalShortcutsTests.swift
      done when: tests prove window bindings stay unregistered while off,
      register when on, unregister when off, and duplicates are caught across groups
- [x] 3. AX snapper, toggle in the catalog and store, wiring in the status
      item controller, sectioned shortcut settings.
      files: Switchboard/Services/WindowSnapper.swift, Model/Tweak.swift, Model/TweakCatalog.swift, Model/TweakStore.swift, App/StatusItemController.swift, Views/ShortcutSettingsView.swift
      done when: app builds with no new warnings; full test suite passes
- [x] 4. README and CONTRIBUTING manual checklist; Release build.
      done when: docs describe the toggle, defaults, permission; Release build succeeds

## Open questions
- Live snapping needs an Accessibility-trusted build, which cannot be granted
  from this session. Blocks only manual verification in step 4.

## Log
- 2026-09-16 Step 1: 14 WindowLayoutTests passed via xcodebuild -only-testing.
  SnapMemory is generic, so its tolerance is a computed static property.
- 2026-09-16 Step 2: the new cases make StatusItemController's switch
  non-exhaustive, and the test scheme builds the app, so step 2's tests run
  together with step 3's wiring. Both steps are verified by the same run.
- 2026-09-16 Steps 2 and 3: full suite 201 tests passed, no Swift warnings.
  AXUIElement is Hashable through CoreFoundation, so SnapMemory keys on it.
- 2026-09-16 Live check: this shell is Accessibility-trusted, so a scratch
  harness compiled WindowLayout.swift and WindowSnapper.swift and drove a
  throwaway window in a child process. Halves, thirds, quarters, maximise,
  centre, restore, and the "no second display" and "nothing to restore" skips
  all matched. A fixed-size window sent to top-right stopped at the quarter's
  left edge, so WindowLayout.anchored now hugs the edges a placement touches.
  Rerun confirmed; full suite 202 tests passed.
- Not verified: moving between displays (one display attached), Chromium's
  enhanced interface path, and the shortcuts through the installed app.
- 2026-09-16 Step 4: README documents the toggle, defaults, behaviour, and
  permission; CONTRIBUTING has a manual snapping checklist. Release build
  succeeded with no Swift warnings.
