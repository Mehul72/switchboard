# Plan: window switcher
Status: done

The follow-up in [command-tab-switcher.md](command-tab-switcher.md) changes the
all-window defaults to Command-Tab and replaces the native macOS switcher.

## Goal
Offer an opt-in Windows-style switcher with one preview per window, including
multiple windows of the same app. Holding Option and pressing Tab cycles all
windows; Option-grave cycles the frontmost app's windows. Shift reverses,
releasing the held modifier activates the selection, and Escape cancels.

## Decisions
- Integrate with Everyday toggles and the existing configurable global shortcuts.
- Accessibility enumerates and focuses exact windows; ScreenCaptureKit supplies
  previews when Screen Recording is allowed. Icons and titles remain usable without it.
- Keep enumeration and Accessibility calls off the main thread with messaging
  timeouts. Ignore stale asynchronous results after cancellation or a new session.
- Use Switchboard's existing theme. No copied reference source or new dependencies.
- Scope is windows exposed through Accessibility, including minimized/hidden
  windows. Private Space navigation, closing windows, search and Dock previews are out of scope.

## Steps
- [x] 1. Add window identity, ordering, session selection and Accessibility inventory/focus.
  Verify empty/single/duplicate windows, same-app filtering, cycling and release while loading with XCTest.
- [x] 2. Add the preview panel, ScreenCaptureKit thumbnails and keyboard session controller.
  Verify compilation, cancellation, stale results, bounded preview memory and input teardown.
- [x] 3. Integrate opt-in settings, configurable press-triggered shortcuts and permission guidance.
  Verify shortcut lifecycle and recording regressions with tests; update README and manual checks.
- [x] 4. Run the full test suite and build, inspect the final diff and record manual limitations.

## Log
- Inspected the reference switcher, AX window resolver, activation and preview services.
- Codegraph is available but its index is empty; direct source reads are the fallback.
- Step 1: built the app and ran all 7 WindowSwitchingTests, zero failures.
  Xcode needs execution outside the sandbox for Swift macros and test services.
- Step 2: build-for-testing passed. All 13 model/controller tests passed, including
  stale responses, quick release, cancellation, permission failure and hook failure.
  Captures are serial, limited to 32 thumbnails at 512px, and cancelled on dismissal.
- Step 3: full suite passed, 249 tests, zero failures. README and manual release
  checks cover controls, custom bindings, permission fallback and Space limitations.
- The sandboxed permission preflight returned false, but the native helper
  outside the sandbox has both permissions. Native checks use three disposable
  windows and restore the previous app afterwards.
- Native verification confirmed three separate windows, exact same-app focus
  and real ScreenCaptureKit thumbnails. It exposed a restore timeout: the AX
  restore returned cannotComplete after 156ms, then the window finished restoring.
  Focus now uses a 1s messaging timeout; discovery retains its 150ms timeout.
- Rendered and inspected light/dark panels with 17 fixture windows and long titles.
- Native checks now pass: enumeration, exact same-app focus, three real captures,
  minimized restore, hidden-app reveal, actual Option-grave key events with
  modifier-release activation, and Escape cancellation preserving focus.
- Custom registered chords now pass through the session input tap to Carbon,
  preserving remapped Tab/arrow actions. Escape also works with a custom Control
  or Command modifier while unrelated VoiceOver chords pass through.
- Final verification: Xcode built the app and ran all 250 tests with zero
  failures after the restore fix. `git diff --check` passed. No Swift compiler
  warnings were introduced; Xcode reports its existing AppIntents metadata notice.
- Multi-display positioning, other-Space/full-screen app differences and a full
  VoiceOver interaction pass remain manual checks in CONTRIBUTING.md.
- The project version changed externally during the session to 1.1.0 (31);
  those existing workspace edits were preserved.
