# Plan: global shortcuts

Status: done (manual checks outstanding)

## Goal
Use configurable shortcuts from any app to toggle Switchboard, open clipboard
history, capture screen text, and toggle keep-awake. Bindings survive relaunch,
can be disabled individually, and report conflicts without losing a working binding.

## Decisions
- Use native Carbon hotkey registration, with no package dependency or additional
  Accessibility permission. Record keys only in the focused shortcuts window.
- Defaults: Control-Option-Command with S (Switchboard), V (clipboard), T (text
  capture), and A (keep-awake). Custom bindings need Control or Option, or Command with another modifier.
- Keep-awake toggles between off and one hour; an existing session is stopped.
- Reuse existing capture permission checks and prevent overlapping captures.
- Settings live in a separate keyboard-accessible window opened from the gear.
- Validate saved preferences and detect duplicate and system-reserved shortcuts.
- No audio shortcuts, paste automation, launcher, or third-party integrations.

## Steps
- [x] 1. Implement bindings, persistence, validation, and native registration.
      Verify model and registration failure paths with focused XCTest cases.
- [x] 2. Connect all four actions and add the shortcut editor.
      Verify the app builds and exercise native event dispatch and editor lifecycle.
- [x] 3. Update user documentation and complete regression checks.
      Run the full test suite, inspect the diff, and record manual-check limitations.

## Log
- The codegraph index is empty, so structure was confirmed by reading the source.
- The test target compiles selected service files directly rather than importing
  the app. New shortcut service and test files will follow that convention.
- Step 1: 17 focused tests passed, including actual Carbon registration,
  synthetic native events, duplicate-registration rejection, and cleanup.
  Xcode test execution needed sandbox escalation to reach testmanagerd.
- Step 2: app and editor compiled; two native editor tests passed. Tests now
  run NSApplication's event loop and wait for activation before checking focus,
  matching the real application's lifecycle. No production focus workaround
  was needed.
- Visual verification found NSHostingView expanded the window to its intrinsic
  scroll-view height. Step 2 reopened to give AppKit control of the initial size.
- 2026-09-16 Step 2 closed: the settings window sets `sizingOptions = []` so
  AppKit owns its size.
- 2026-09-16 Step 3: the full suite (179 tests) passed, and so did the Release
  build, with no Swift warnings. The README now says the keep-awake shortcut
  opens the panel.
- Not verified: live hotkey presses from another app, VoiceOver, and other
  keyboard layouts. The installed Switchboard was running and holds the same
  default bindings, so the test build was not launched. The checklist is in
  CONTRIBUTING.md.
