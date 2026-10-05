# Plan: fix the October 2026 review findings
Status: done
Branch: main (uncommitted)

## Goal
Every bug, risk and improvement from the 2026-10-04 review is fixed in source,
covered by a test where a test can reach it, and the docs match. Verifiable by
the suite passing, a test run leaving no new files in `~/Library/Preferences`,
and the checks listed under each step.

## Decided already
- **Audio routes** survive the routed app quitting; volumes do not (as today).
  Polling runs only while something needs it: a live tap, a pending volume, or
  a routed app that is running. A launch notification restarts it.
- **Stalled renderer** forgets the route as well as the volume, so it cannot
  rebuild and stall in a loop.
- **Private symbol** `responsibility_get_pid_responsible_for_pid` is resolved
  with `privateSymbol`, like the others. Missing symbol falls back to bundle ID
  trimming.
- **Clipboard text**: preview (first 300 characters) and line count are worked
  out once when the clip is recorded. "Show all" lays out at most 20,000
  characters and says so. What gets recorded is unchanged (no size cap).
- **Duplicate screenshot**: the converter reports the PNG it replaced and the
  history drops that entry.
- **Converted screenshots on disk** are deleted at quit and at launch. The
  Capture row no longer says "No file is saved".
- **Shelf picker**: closing the shelf cancels an open picker.
- **Boolean preferences** stored as strings are read the way macOS reads them
  (`NSString.boolValue`).
- **Finder Command-Delete** is ignored while a text field has focus.
- **Popover**: a click on a menu bar item that toggles the panel is never held
  for activation.
- **Event taps**: the scroll tap and the Command-Tab tap run on one dedicated
  thread. State their callbacks read sits behind a lock. The switcher's
  navigation tap stays on the main thread: it exists only while the switcher is
  open and its commands must stay in step with the panel.
- **Tests** use an in-memory `UserDefaults` where they inject one. Tests that
  need a real CFPreferences domain sweep what earlier runs left. Shelf tests
  anchor to a plain window, never a status item.
- **TweakStore** runs on the main actor and takes its catalog, defaults and
  pasteboard as parameters, so tests can drive it against throwaway domains.
- **Off switches** live in the settings gear: clipboard history, opening the
  shelf during drags, Command-Delete eject in Finder. A submenu lists apps the
  red button never quits. Nothing visible in the documentation images changes.
- **Release gate**: `release.sh` runs the suite before bumping the build
  number. CI builds and runs the classes that need no desktop session or audio
  hardware.

## Out of scope
- LICENSE and the copyright string. Both are the owner's legal choice.
- A full Swift 6 migration. Only `TweakStore` moves to the main actor.
- Tests activating the test process. Key-window assertions need it.
- Moving the switcher's navigation tap off the main thread.
- A size cap on recorded text clips.
- Regenerating documentation images (no rendered view changes).
- The one "uncommitted CATransaction" log line. Source unknown.
- Committing. The user commits.

## Steps
- [x] 1. Tests stop leaving files behind
      files: SwitchboardTests/TestSupport.swift (new), the suites that call
      `UserDefaults(suiteName:)`, CaptureDestinationTests, ShelfDraggingTests,
      FileShelfController (anchor type), project.pbxproj
      done when: suite passes; plist count in ~/Library/Preferences is the
      same before and after a run (checked again 10 s later)
- [x] 2. TweakStore on the main actor with injected dependencies, plus the
      preference fixes that ride on it
      files: TweakStore, Tweak (bool strings, unused case), TweakCatalog
      (translation row from the flag), UndoLedger tests, TweakStore tests,
      PrefValueTests, LaunchAtLogin, scripts/docs/render.py marker
      done when: new UndoLedgerTests and TweakStoreTests pass; the docs
      renderer's patched sources still compile
- [x] 3. Audio: routes survive quit, stall forgets the route, soft-linked
      symbol, polling only when needed
      files: AppAudio, TweakStore, AudioRoutingTests
      done when: a test proves a saved route outlives `reconcile` for an app
      that is not running; `nm -u` on a build lists no
      `_responsibility_get_pid_responsible_for_pid`
- [x] 4. Clipboard: cheap previews, capped expansion, no duplicate
      screenshot, spool cleanup and wording
      files: ClipboardHistory, ClipboardHistoryList, ClipboardImageConverter,
      TweakStore, TweakCatalog, StatusItemController, SwitchboardApp, tests
      done when: tests pass; the scratch benchmark shows a 5 MB clip costing
      under 5 ms per row render; one screenshot yields one entry either way
      round
- [x] 5. Shelf, panel and Finder fixes
      files: FileShelfController, StatusItemController (plural),
      MenuBarPopover, FinderEjectShortcut, tests
      done when: tests pass for picker cancel, anchor click with the app
      inactive, and the text-field guard
- [x] 6. Event taps on their own thread
      files: EventTapThread (new), ScrollDirection, CommandTabHotKeys,
      GlobalShortcut, tests, project.pbxproj
      done when: unit tests pass; a scratch run with real taps shows callbacks
      on the tap thread, a wheel event inverted, and Command-Tab delivered and
      swallowed
- [x] 7. Off switches, red-button exclusions, permission links
      files: TweakStore, QuitOnClose, ScrollDirection, StatusItemController,
      PopoverView, tests
      done when: tests pass for each preference and for the exclusion rule
- [x] 8. Smaller fixes: drag grid probes only with Control, 64-bit network
      counters, Quit picks the matching app, welcome rows, app category
      files: WindowDragGrid, SystemMonitor, ProcessUsage, WelcomeView,
      Info.plist, tests
      done when: tests pass; counters read back as 64-bit values
- [x] 9. Release gate, CI, docs
      files: scripts/release.sh, .github/workflows/ci.yml, CONTRIBUTING.md,
      docs/user-guide.md, README.md
      done when: `bash -n` passes; the test command the script uses has run;
      every doc claim touched matches the code
- [x] 10. Whole-change verification and cleanup
      done when: full suite passes; strict-concurrency count recorded; helper
      scripts compile; old leftover test plists removed after checking each is
      empty

## Open questions
- What a denied System Audio Recording permission does to a tapped app. Cannot
  be tested without changing the owner's privacy settings. Now a line in the
  release checklist in CONTRIBUTING.md, which outlives this plan.

## Log
- 2026-10-04 plan written. The shell running the tests has Accessibility
  trust, so tests must never switch on the scroll hook or red-button quit:
  they would act on the real session.
- 2026-10-04 step 1 done. Ran the full suite: 419 tests pass, and 14 s after
  the run no scratch domain file is left. Surprise: the test process rewrites
  every domain it touched as it exits, so deleting the files from inside the
  process (even at bundle finish) does not stick. A detached shell removes them
  a few seconds after the process has gone; the next run's first scratch
  domain clears them if that shell never ran. No API deletes the file of an
  emptied domain, `defaults delete` included.
- 2026-10-04 step 2 done. UndoLedgerTests (9), TweakStoreTests (12) and
  PrefValueTests (9) pass; the docs renderer type-checks with render.py's
  patches applied (marker moved from `init() {` to `private func start() {`).
  AppAudioEngine took its defaults in this step, earlier than planned, so the
  store under test never touches the real domain.
- 2026-10-04 step 3 done. Three new AudioRoutePersistenceTests pass. `nm -u`
  on the Debug build shows no import of the responsibility symbol; its name
  is still in the binary as the string dlsym looks up. The stalled-renderer
  change has no test: reaching it needs a live tap, which prompts for System
  Audio Recording.
- 2026-10-04 step 4 done. Clipboard suites pass (59 tests). Re-measured with
  the scratch benchmark: a 5 MB clip costs 5.7 ms once when recorded and about
  0 ms per collapsed row render (was roughly 500 ms); an expanded row lays out
  20,000 characters. The spool is cleared from the app only, never from the
  converter's init: tests and the docs renderer share the real temp folder and
  would delete the running app's files.
- 2026-10-04 step 5 done. 27 tests pass across the shelf, popover, Finder
  eject and file shelf suites. Removing the picker and anchor fixes makes
  their two new tests fail, so both bugs are now reproduced by a test, not
  only inferred. The Finder guard is tested as a rule (`isTextEntry`); the
  rename itself still needs a manual check in Finder.
- 2026-10-04 step 6 done. 17 unit tests pass. A scratch run with real taps
  (events posted by the harness, marked, and swallowed by a safety-net tap so
  none reached another app) passed 12 of 12 checks: a wheel tick was inverted
  and Command-Tab swallowed while the main thread was blocked, the action was
  delivered on the main thread afterwards, and unregistering or releasing the
  owner stopped the tap with no dangling callback. The Command-Tab decision is
  now a pure function (`verdict`) so it has tests without a tap.
- 2026-10-04 step 7 done. 65 tests pass across the store, close-watch and
  switcher suites. With clipboard history off, screen text capture still
  copies the text but no longer lists it, since nothing is kept. The gear
  menu items compile but no test opens the menu; that needs a manual look.
- 2026-10-04 step 8 done. 38 tests pass in the monitor and process suites. A
  scratch run shows the 64-bit counters agreeing with the old 32-bit ones on
  en0 (3.24 GB, below the wrap point). The welcome window was laid out off
  screen and inspected: seven rows, 460 by 656 points. The drag grid change
  has no test: it needs real window drags.
- 2026-10-04 step 9 done. `scripts/test.sh` is the one entry point for people,
  CI and `release.sh`. `bash -n` passes for both scripts and the workflow
  parses as YAML. The checkout action is pinned to the commit of v7.0.1,
  looked up through the GitHub API. Not run: the workflow itself (nothing is
  pushed) and `release.sh` end to end (it notarises and bumps the build).
- 2026-10-04 step 1 reopened and corrected. The earlier log entry had the
  mechanism wrong. cfprefsd writes a changed domain about seven seconds after
  the change, or when the changing process exits, and a file deleted before
  that write comes back. The cleanup shell now waits for the test process to
  exit, removes the files three seconds later, and again seven seconds after
  that. Measured with a probe: the delayed write landed 6.9 s after the change.
- 2026-10-04 step 10 done. Full suite through `scripts/test.sh`: 485 tests, 0
  failures, 0 skipped, no compiler warnings. `~/Library/Preferences` held 924
  entries before the run and 924 twenty seconds after. Strict concurrency
  reports 210 warnings (was 224). The app type-checks for arm64 and x86_64;
  the shelf and appearance check scripts and the docs renderer type-check.
  2,285 leftover test preference files from earlier runs were deleted after
  each was confirmed to be an empty dictionary with a test suite's name.

## Follow-up: two bugs reported against 1.1.7 (2026-10-04, evening)
- The Keep Mac awake dropdown floated in the middle of its column. A menu is
  only as wide as its label, and an inner `.frame(maxWidth:)` centred it
  there. The same inner frame sat on the format picker and the folder button.
  All three are gone; the row's own column frame places every control.
  `TweakRowLayoutTests` renders each catalog row and checks its control ends
  on the trailing edge; it fails with the old frame back.
- Copy text from the screen looked hung. The first Vision read on a system
  build compiles its models, measured at 27 s from an empty cache, and the
  store counted the read as part of the capture, so the panel and every
  shortcut were refused until it finished. The capture is now two phases:
  selecting, which still holds the panel back, and reading, which holds
  nothing. A background warm-up 20 s after launch, once per system build,
  takes the slow read off the first capture (measured: 27.15 s to prepare,
  then 0.09 s for the first real read).

## Follow-up: panel flashed shut over a full-screen app (2026-10-04, night)
- After Copy text from the screen was started from the panel over a
  full-screen app, the panel came back for about 40 ms and closed. The click
  that started the capture had made Switchboard the front app, and it stayed
  the front app with the panel closed. Opening a panel from the menu bar over
  a full-screen Space makes macOS bring the menu bar in and hand the front to
  the Space's app; the panel closes when another app takes the front. The
  system log shows it four times in ten hours, each one a panel opened with
  Switchboard in front on the full-screen Space; the other twenty openings,
  with either condition missing, stayed open.
- `FrontHandover` now gives the front back to the full-screen app before the
  panel opens there and waits for both reports of the change, so the panel
  opens the way it does from a menu bar click. Every way of opening the panel
  goes through it. On a desktop, and whenever Switchboard is not in front,
  nothing changes.
- Measured with a scratch probe on macOS 27.0.1: the hand-back is allowed and
  reported within a few milliseconds, the Space does not change, the menu bar
  still belongs to the full-screen app while an accessory app is in front,
  and a popover holding the keyboard closes when its app resigns.

## Not verified by running
- The fixed panel over a real full-screen app, end to end: that needs the
  rebuilt app and a status item, which the tests never use.
- The CI workflow on GitHub, and `release.sh` end to end.
- Per-app audio with a stalled renderer (needs a live tap).
- The drag grid with real window drags.
- Command-Delete while renaming a disk in Finder.
- The new settings gear items, by opening the menu.
