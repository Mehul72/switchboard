# Plan: top processes, menu bar readout, more keep-awake options
Status: done
Branch: main (uncommitted)

## Goal
1. The System tab lists what is using the most CPU and memory, grouped by app,
   with a Quit button on apps that can be quit. Verifiable by running a busy
   loop in a disposable app and seeing it at the top, then quitting it there.
2. An optional live readout beside the menu bar icon (CPU, GPU, memory,
   network, battery). Off by default. Verifiable by switching metrics on in
   System and watching the status item update every two seconds.
3. Keep awake gains "Until an app quits", "While plugged in" (Macs with a
   battery) and a "Let display sleep" option. Verifiable with
   `pmset -g assertions` while each mode is active, ends, pauses and resumes.

## Decided already (product calls made without asking; flag in the report)
- Processes are grouped by their outermost `.app` bundle, so browser helpers
  count toward the browser. Processes outside an app bundle show by name.
- CPU per process is a share of the whole Mac (matches the CPU tile, which is
  "All cores"), not Activity Monitor's per-core percentage. Labelled in the UI.
- Own processes: `proc_pid_rusage` deltas (exact) and `ri_phys_footprint`
  (Activity Monitor's Memory column). CPU times are Mach ticks; verified on
  this Mac: 1 s busy = 24M ticks, timebase 125/3.
- Processes owned by other users (334 of 935 here, e.g. WindowServer,
  Spotlight) are unreadable without root. They come from one `/bin/ps` call
  per sample (setuid root, 20 ms): decayed CPU and resident memory. Bounded by
  a timeout; if ps fails the list still shows the user's own processes.
- Processes are sampled only while the System tab is visible.
- Quit is the polite quit the Dock sends (`NSRunningApplication.terminate`),
  so apps can ask about unsaved work. Only for regular or accessory apps owned
  by the user, not under `/System/`, not Finder, not Switchboard. No Force Quit.
- The list stops reordering while the pointer is over it, so a Quit click
  cannot land on a row that just moved under the cursor.
- Readout lives in the existing status item (one item, one click target),
  after the shelf count. Text labels (`CPU 12%`), monospaced digits padded to
  a fixed width so the menu bar does not jiggle. Choice persists in
  UserDefaults. The monitor keeps sampling (without processes) while any
  readout metric is on.
- Keep awake modes do not persist across relaunch, same as today. "Let
  display sleep" is a persisted preference. "While plugged in" holds the
  assertion only on external power and waits otherwise; hidden on Macs
  without a battery. "Until an app quits" follows one process ID.

## Out of scope
- Force Quit, signalling non-app processes, quitting other users' processes.
- Per-process GPU, energy, disk or network columns.
- A second status item or graphs in the menu bar.
- Keep-awake triggers beyond the three above (until a time, while
  downloading, external display).
- Regenerating the README/guide images (needs the Pillow docs pipeline).
  Renderer sources must still compile.

## Steps
- [x] 1. Process sampler: listing, rusage deltas with tick conversion, ps
      fallback with timeout, grouping, top N
      files: Switchboard/Services/ProcessUsage.swift, SwitchboardTests/ProcessUsageTests.swift, project.pbxproj
      done when: tests cover bundle grouping, ps parsing, CPU share maths, pid
      reuse, and a live sample that finds the test process; all pass
- [x] 2. Monitor demand model and top-process UI with Quit
      files: SystemMonitor.swift, SystemMonitorView.swift, StatusItemController.swift, SystemMonitorTests.swift
      done when: tests for panel/menu-bar demand pass; app builds; running app
      shows a busy `yes`-style app at the top and Quit ends a disposable app
- [x] 3. Menu bar readout: model, formatting, settings panel, status item title
      files: Switchboard/Services/MenuBarReadout.swift, SwitchboardTests/MenuBarReadoutTests.swift,
      StatusItemController.swift, SystemMonitorView.swift, PopoverView.swift, project.pbxproj
      done when: formatting and persistence tests pass; running app shows the
      readout; Switchboard's own CPU with readout on measured and recorded
- [x] 4. Keep-awake modes: AwakeController modes with injected environment,
      store, menu control, status wording, display-sleep option
      files: UtilityServices.swift, TweakStore.swift, Tweak.swift, TweakCatalog.swift, TweakRow.swift,
      AwakeControllerTests.swift, AwakeStatusTests.swift, GlobalShortcut.swift
      done when: tests prove app quit ends it, unplug pauses, replug resumes,
      display option changes assertion flags; `pmset -g assertions` agrees live
- [x] 5. Docs and renderer
      files: docs/user-guide.md, README.md, CONTRIBUTING.md, scripts/docs/Render.swift, scripts/docs/render.py
      done when: renderer sources type-check with the patches applied; every
      control name in docs matches the code
- [x] 6. Whole-change bar: full suite, Release build, code-quality review
      done when: suite green, Release build clean, review findings fixed or listed

## Open questions
- None blocking. The decisions above are one-line flips if the user disagrees.

## Log
- 2026-09-27: probe showed 600 readable / 334 EPERM processes; `ps -axo` takes
  ~20 ms system time.
- 2026-09-27 step 1: 16 ProcessUsageTests pass (`-only-testing`). Live sampler
  measured the test process on its second sample with no unavailable sources.
  `PROC_PIDPATHINFO_MAXSIZE` is a macro Swift does not import; used 4 * MAXPATHLEN.
- 2026-09-27 step 2: 9 monitor tests pass (3 new demand tests). Scratch harness
  (live monitor, offscreen render, not the full app) showed `yes` at 6.66%
  (one of 15 cores) on top of the CPU list. Quit ended a hidden Chess; Finder,
  Dock, Control Center, own pid and launchd were refused. Fixed: an empty
  `Group` drops its frame, so non-quittable rows lost the button slot. "Siri"
  in the memory list is `Siri AI.app` (accessory, /System/Applications), so
  quittable by design; CoreServices Siri is excluded.
- 2026-09-27 step 3: 10 MenuBarReadoutTests pass, including a width
  invariant over 72 reading combinations. Cost over 30 s (harness, -O):
  menu bar only 0.06% of one core; panel with processes 0.51% plus ps's own
  ~20 ms per call. Not checked in the real menu bar: running a second
  Switchboard would share preferences with the installed copy (Command-Tab
  takeover, shortcuts), so the status item title is covered by unit tests and
  left for the manual check.
- 2026-09-27 step 4: 14 AwakeControllerTests + 11 AwakeStatusTests pass. Live
  harness with the real environment: pmset showed display+system assertions
  for each mode, system-only with "Let display sleep", and none after Chess
  quit (onFinish reported appQuit). Unplugging not exercised live (Mac on
  adapter); covered by the fake environment only. Offscreen render of the
  Everyday and System tabs (renderer patches applied) looks right in light
  and dark. `set` now returns a Result so the panel can say why a mode failed.
- 2026-09-27 step 5: user guide (keep awake options, Using the most, menu bar
  readings, troubleshooting row), README bullets, CONTRIBUTING manual checks.
  Render.swift gets sample process rows so regenerated images are not stuck
  on "Measuring…". Patched renderer sources type-check. Images themselves not
  regenerated (out of scope).
- 2026-09-27 step 6: review found three should-fix items, all fixed: the
  plugged-in row went stale on unplug (added onHoldChange, tested), ps
  failure reasons were not logged (logged once per change), and battery
  presence was read from IOKit on every view init (now once per launch).
  Full suite 410 tests pass; Release build succeeds; no warnings in changed
  files; xctest log noise identical to a clean baseline run.
- 2026-09-28 regression found on the installed 1.1.6 build 52: with every
  readout on and the panel closed, 3.6 to 7.7% CPU and memory swinging 76 to
  181 MB. Stack sample: SwiftUI re-rendering PopoverView/SystemMonitorView
  while closed. Cause: StatusItemController kept the NSHostingController after
  close; before this change the monitor stopped on close, so nothing
  published. Harness proof: retained hidden view 5 renders in 10 s, released
  0. Fix: release the popover content in popoverDidClose; also skip
  status item setters whose value did not change. 410 tests pass. Not yet
  re-measured on an installed build. Note for re-enabling translation: the
  bridge reacts only to changes, so a request queued while the panel is
  closed will not start in a freshly built panel.
- 2026-09-28 verified on installed build 53 (fix at StatusItemController.swift:402
  confirmed in the binary via its dSYM). All readouts on, panel closed
  throughout (window list checked before, during, after): 1.3 to 1.6% CPU,
  55 MB flat, 0 new idle wakeups in 30 s, no panel views in an 8 s sample,
  monitor queue 3 samples. The remaining main-thread work is quit-on-close's
  poll (109 of about 128 busy samples). A first sample of build 53 looked bad
  because the panel was open during it. NSPopover harness: clearing content
  in popoverDidClose stops rendering (0 vs 5 per 10 s) even before the
  controller is freed.
- 2026-09-29 quit-on-close: Chrome lookup now asks Launch Services for the
  five bundle IDs (0.04% vs 0.54% of a core, measured in isolation) and the
  0.5 s poll runs only while a Chrome-family browser does, restarted by
  launch notifications and by the panel opening. Decision rules, thresholds
  and window evidence untouched. 7 lifecycle tests added (fake browser pid 1);
  never run live against the user's Chrome.
- 2026-09-29 panel jump: proven in a harness that an open popover follows its
  anchor (anchor 24 -> 120 -> 200 pt wide moved the panel 725 -> 629 -> 549).
  The readout widened the Switchboard item, so ticking a reading dragged the
  panel. Readings now live in their own status item (autosave
  SwitchboardReadings); clicking it opens System from the Switchboard icon.
  Driving the real panel with Accessibility or the shortcut did not open it,
  so the fix is unverified on an installed build. 417 tests pass.
