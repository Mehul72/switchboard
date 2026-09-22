# Plan: replace Command-Tab
Status: done

## Goal
While Window switcher is enabled, Command-Tab and Command-Shift-Tab open
Switchboard's window previews in place of the native app switcher. Releasing
Command selects the window. Disabling or quitting Switchboard restores native behavior.

User feedback added after step 2:
- Windows on other Spaces, including full-screen apps, appear as cards and can be focused.
- As in the native switcher, moving the pointer over a card selects it and Q
  quits the selected card's app. Its cards disappear once it terminates.

## Decisions
- Capture just the registered Command-Tab chords with a session event tap.
  Carbon accepts these registrations but receives no events while Dock owns them.
- Do not change WindowServer symbolic-hotkey settings. A native probe confirmed
  those changes survive process death, while returning nil from the event tap
  suppresses Dock and automatically releases the shortcut when the tap disappears.
- Change the two all-window defaults and migrate saved bindings matching the old
  Option-Tab defaults once. Keep disabled/custom bindings and same-app shortcuts.
- Allow Command-Tab only for switcher actions; retain the normal Command-key guard.
- Accessibility's window list omits other Spaces. For an app with a WindowServer
  window on a Space that is not showing, look up its elements by remote token
  (private, resolved at runtime like `_AXUIElementGetWindow`) within a per-app
  time budget. Missing symbols fall back to the current-Space list.
- Other-Space, minimized and hidden windows have no on-screen z-order. Merge them
  by app activation recency so Command-Tab from a full-screen app reaches the previous app.
- Q uses `NSRunningApplication.terminate`, the Dock's quit request. Key repeat
  never quits a second app, Finder is excluded as in quit-on-close, and releasing
  the modifier does not focus an app that was asked to quit.
- Hover selects only after the pointer actually moves, so a panel opening or
  scrolling under a still pointer cannot steal the keyboard selection.

## Steps
- [x] 1. Implement scoped Command-Tab registration, defaults and preference migration.
  Verify routing, duplicate registration, teardown, validation and migration with tests.
- [x] 2. Update shortcut guidance and verify actual keyboard events against Dock,
  including reverse cycling, modifier release and restoration after unregister/exit.
- [x] 3. List and focus windows on other Spaces and full-screen apps.
  files: SwitcherWindows.swift, WindowSwitching.swift, WindowSwitchingTests.swift
  done when: ordering tests pass, and a native check with a full-screen fixture
  lists its window from the desktop Space and focusing it switches to that Space.
- [x] 4. Q quits the selected card's app; pointer hover selects a card.
  files: SwitcherInput.swift, WindowSwitcher.swift, WindowSwitching.swift, WindowSwitcherView.swift
  done when: unit tests cover key mapping, repeat, removal and commit after quit,
  and a native check quits a fixture app from the switcher and hover moves the selection.
- [x] 5. Run the full suite, inspect the diff, update README/CONTRIBUTING and record verification.

## Log
- 2026-09-22 resumed in a new session. Reproduced feedback 1: Chrome full screen
  on Space 19 returned an empty `AXWindows` list while WindowServer reported its
  window on that Space. A remote-token lookup found it (AXStandardWindow,
  AXFullScreen true) in 37ms after 1000 element IDs on macOS 27.
- Remote lookup missed a fixture window that went full screen before any client
  queried it: apps assign element IDs lazily. Querying it once on its Space made
  it findable (prediction held). From the desktop, `AXMainWindow` still returns
  the unqueried full-screen window, so enumeration reads it before the lookup.
  Residual gap: a non-main window on another Space that no Accessibility client
  has ever queried stays hidden until it is queried on its own Space.
- `.optionAll` window order is not stacking order (Finder listed before the
  frontmost Code window), so off-screen windows are ordered by app activation recency.
- Step 3: 16 switcher unit tests pass. Native check with production
  SwitcherWindows: from the desktop, cards were Code, fixture desktop window,
  fixture full-screen window, Finder, Chrome full-screen window (98-101ms
  snapshot). Focusing the full-screen card made the fixture frontmost and moved
  to its Space. The fixture was terminated and Code restored.
- Step 4: 22 switcher unit tests pass. Removing the key-repeat guard, the
  quitting-app commit guard or the pointer-moved hover guard each failed its test.
  Native check with the production controller, input tap and SwiftUI panel:
  a disposable fixture was frontmost so a leaked Command-Q could only reach it.
  Posted pointer moves selected the hovered cards, Command-Q quit only the
  selected fixture, its card vanished while the switcher stayed open with the
  next card selected, and releasing Command focused the hovered original app.
  `requestQuit` refused Finder. Fixtures terminated, pointer and focus restored.
- ScreenCaptureKit lists Chrome's full-screen window as shareable but capture
  fails ("Failed to start stream"); an on-screen window captured. Cards for
  other Spaces therefore show the app icon.
- Step 5: diff review found hover republishing and re-announcing the same card
  on every pointer move inside it. A failing test (one objectWillChange on a
  no-op move) now passes. Added logs for a missing Space lookup and unresolved
  other-Space windows. Xcode ran 268 tests with zero failures; the only warning
  is the existing AppIntents metadata notice. `git diff --check` passed. Both
  native checks passed again on the final sources.
- Not verified natively: a window on a second regular desktop (this Mac has one
  desktop plus full-screen Spaces), two displays, a quit that stops for unsaved
  changes, and VoiceOver. These stay in the CONTRIBUTING release checks.
- Step 2 passed with production sources: Command-Tab opens window cards with no
  Dock overlay, Shift reverses, Command release focuses the exact window, Escape
  cancels, and 12 consecutive quick switches focus correctly. Native Command-Tab
  returns after unregister, registrar deinitialization and SIGKILL of a separate
  process owning the hook. All checks used disposable windows and restored focus.
- Step 2 found a rapid-release race in native checks: a modifier release queued
  before the session tap is installed can miss its callback and arrive after
  enumeration checked modifier state. A session-only 50ms state check covers this
  gap and is removed with the tap. Regression verification repeats quick switching.
- Step 1: 39 shortcut and native registration tests passed. Coverage includes
  default migration, preserving custom/disabled bindings, one-time migration,
  action validation, duplicate IDs, dispatch after removal and failed registration/removal.
- Native probe: Carbon registration returned success but received zero presses;
  exclusive registration failed with -9878. Session and HID event taps both
  intercepted the key and suppressed the Dock overlay. Without a tap, the native
  Dock overlay appeared, establishing the positive control.
- 2026-09-22 follow-up: one of two Chrome full-screen windows went missing.
  Cause: the remote lookup stopped at element 1000, and Chrome's second window
  was element 1561 (its live elements ran 1 to 1587, gaps up to 231). The scan
  now runs until 1000 quiet numbers past the newest live element (about 30ms for
  Chrome), remembers found elements and already-searched windows between
  openings, and only rules a window out after a finished scan. Second opening:
  7ms. While enabled, every app's showing windows are noted on each Space change
  and again 0.8s later, because mid-animation a window entering full screen is
  listed as a temporary stand-in (traced: 9510 instead of 9505). Native pair
  fixture (two full-screen windows, the unqueried one not main): hook off lists
  1 of 2 in 4 runs, hook on lists 2 of 2 in 4 runs; both real Chrome windows
  listed. 280 tests pass.
- 2026-09-22 follow-up: Command-Tab from full-screen Chrome window 1 went to
  Chrome window 2 instead of back to VS Code. Cause: windows off the showing
  Space were ranked by app recency, with the frontmost app first, so the
  frontmost app's other windows beat the previous app. Now a window-level
  recency list (focused window at each opening, the picked window, and the
  focused window 0.3s after an activation or 0.8s after a Space change, except
  within 2s of a pick) ranks used windows first. Native check with a minimized
  window standing in for another Space, 2 runs: hooks off ordered W1, W2, Q
  (bug reproduced); hooks on W1, Q, W2; after picking Q, Q, W1, W2. 282 tests pass.
- 2026-09-22 follow-up: running apps with no windows are listed after the
  window cards under "Apps without windows" (all-apps mode only), ordered by app
  recency, with no preview. Choosing one activates the app, as the macOS
  switcher does; Q, hover and termination removal work as for windows. App
  entries use IDs with the top bit set, which window IDs never reach. Native
  checks: Activity Monitor and Finder (no open windows) listed on this Mac; a
  fixture that closed its windows was listed last, picking it made it frontmost,
  and the current-app switcher listed nothing for it. Panel rendered in light and
  dark. 284 tests pass.
