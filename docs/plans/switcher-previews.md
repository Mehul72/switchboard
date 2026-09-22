# Plan: switcher previews for every window, captured lazily
Status: done

## Goal
Cards for windows on other Spaces (including full-screen apps), minimized
windows and hidden apps show a real preview. Opening the switcher shows known
previews at once and captures only what the visible cards need, instead of
capturing every window each time Command-Tab is pressed.

## Decisions
- ScreenCaptureKit cannot capture those windows ("Failed to start stream"),
  verified on macOS 27. `CGSHWCaptureWindowList` (private, resolved at runtime
  like the other switcher symbols) captured an other-Space full-screen window, a
  minimized window and a hidden app's window with real content in 7-27ms. If
  the symbol disappears, cards fall back to app icons. ScreenCaptureKit is removed
  from the switcher, which also drops the per-open shareable-content query.
- Thumbnails are downscaled to 400px at most (about 2x the card) as soon as
  they are captured; the full-size capture is released immediately.
- Keep thumbnails in memory between openings, keyed by window ID, so the panel
  shows them at once. Pruned to the windows in each new snapshot, and discarded
  on sleep, user switch, turning the feature off, or losing Screen Recording.
  Never written to disk. This changes the README promise that previews are
  discarded when the switcher closes, so the README states the new rule.
- Capture only cards the grid actually creates, selected card first, one at a
  time, and skip a window whose thumbnail is under 2 seconds old. A quick switch
  commits before any card exists, and closing drops the queue, so no separate
  "panel visible" gate is needed (changed from the first draft of this plan).

## Out of scope
- Background capture while the switcher is closed.
- Live-updating previews while the panel stays open.

## Steps
- [x] 1. Capture service: private capture, downscale, cache, prioritized serial queue.
  files: SwitcherPreviews.swift, WindowSwitchingTests.swift
  done when: unit tests cover queue order, dedupe, freshness skip, pruning and
  discard with an injected capturer; ownership stress probe passes (done: 480 captures, no crash).
- [x] 2. Wire it to the switcher: cached images on load, the selected card first,
  requests from cards as the grid creates them, discard triggers.
  files: WindowSwitcher.swift, WindowSwitcherView.swift, StatusItemController.swift
  done when: controller tests cover cached images at load, selected first, no
  capture on a quick switch, discard on sleep/feature off/lost permission; native
  check shows a preview for an other-Space full-screen window and a minimized window.
- [x] 3. README/CONTRIBUTING, full suite, diff review, record verification.

## Log
- 2026-09-22 SCK failed for other-Space, minimized and hidden windows; CGS
  capture succeeded for all three (images inspected). Per window capture plus
  400px downscale: 7-19ms. 480 captures with takeRetainedValue: no crash, RSS
  29 to 46MB (a leak would be about 2.5GB), so the array is returned +1.
- Unrelated app hang fixed in the same session (see SwitchboardApp.swift):
  background Accessibility hit tests over Switchboard's own window ran SwiftUI
  off the main thread and deadlocked it. Reproduced 2/2 in a harness, fixed by
  refusing off-main hit tests in an NSApplication subclass (0 deadlocks in 12s,
  about 290k probes). The built app's NSApp is the subclass (checked with lldb).
- Steps 1-2: 6 preview and 2 controller tests written first (compile-red), now
  pass. Removing the freshness skip or the discard generation check fails 4 of
  them. Native check with the production controller and panel, 2 runs: a quick
  switch captured nothing; first open loaded 7 cards at about 145ms, first
  preview at about 165ms, every card (other-Space full-screen, minimized and
  hidden fixtures included) by about 230ms, 7 captures for 7 cards, selected
  first; reopening showed 7 of 7 cached with no new capture. Thumbnails inspected.
- The first native run captured the first card before the selected one: laying
  out the panel creates cards synchronously. The selected request now precedes fit.
- Step 3: Xcode ran 276 tests with zero failures; only warning is the existing
  AppIntents notice. `git diff --check` passed. Not verified: DRM-protected
  windows, two displays, and whether this capture API changes how often macOS
  re-asks for Screen Recording.
