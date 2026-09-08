# Plan: native Switchboard style

Status: done

## Goal

Implement the approved image concept as a native macOS interface: a frosted
460 by 560 point panel, readable typography, neutral icons, four visible main
tabs, grouped controls, and light and dark appearances. Preserve every existing
setting, audio control, clipboard action, permission explanation, and restart flow.

## Decided already

- Main tabs are Tweaks, Audio, Clipboard, and System. Tweaks contains Everyday,
  Files, Capture, and Dock, and remembers its selected category.
- Use native controls and semantic colors. Respect reduced transparency, reduced
  motion, and increased contrast. Keep the panel constrained to available height.
- Move Restore Original Settings into the settings gear menu.
- The generated image is a visual reference; keep real app data and behavior.

## Out of scope

New features, changes to system services, release/signing configuration, publishing,
and replacing the running installed app. Preserve the user's existing build-number edit.

## Steps

- [x] 1. Implement the shared theme, shell, navigation, and setting rows.
      Files: Theme, VisualEffectBackground, CategoryNav, PopoverView, TweakRow.
      Done when: Debug build succeeds; every category and global search remains
      reachable; restore and restart controls remain available.
- [x] 2. Apply the same treatment to audio, clipboard, system readings, and notices.
      Files: AppVolumeList, ClipboardHistoryList, SystemMonitorView, ApplyBar.
      Done when: Debug build succeeds and native view renders show readable controls
      in light and dark appearances, including empty content and short panels.
- [x] 3. Verify the final app and update navigation documentation.
      Files: README, MANUAL_TESTS, this plan.
      Done when: existing automated tests and Release build pass, diff checks pass,
      render and navigation checks are recorded, and any manual limits are explicit.

## Open questions

None. Remaining manual accessibility checks are listed in MANUAL_TESTS.md.

## Log

- 2026-09-08: Read current views and test setup. The only existing working-tree
  modification is the user's project build number (8 to 9); preserve it.
- 2026-09-08: Step 1 Debug build passed. Source checks confirm all seven categories,
  global search, restore, and restart actions remain connected. The only build
  warning is Xcode's skipped App Intents metadata extraction (no framework used).
- 2026-09-08: Step 2 compiled. Rendered every category plus empty lists, long app
  names, a missing output, search with no matches, and notices with pending restarts.
  Native mouse-event checks passed for tab selection, remembering Files when
  returning to Tweaks, navigation initiated by the store, and clearing search.
- 2026-09-08: A 320-point panel had too little scrolling space with both a notice
  and restart bar. At heights below 420 points, secondary categories and notices
  now scroll with content. Verified a 112-point viewport and successful scrolling.
- 2026-09-08: Previews use actual view sources with a temporary copy of the store
  seeded with sample data; initialization and audio polling are disabled in that
  copy. The harness and images are in ignored build/native-style-preview. These
  renders do not test hardware actions. Full VoiceOver and system accessibility
  preference testing remain manual.
- 2026-09-08: The sandbox allowed compilation but blocked testmanagerd. Rerunning
  the existing suite with the approved sandbox exception.
- 2026-09-08: Final validation passed: 148 existing tests with zero failures,
  Debug and unsigned Release builds, native render checks, and git diff --check.
  No Swift compiler warnings; Xcode reports skipped App Intents extraction because
  the app does not use that framework. No separate linter is configured.
- 2026-09-08: Recreating the hosting view while Audio is selected and returning to
  Tweaks preserved Files, passing the reopen navigation check. Updated README and
  manual checks for the new tabs and settings gear. Final sample-data previews:
  build/native-style-preview/everyday-light.png and audio-dark.png.
- 2026-09-08: The user's project build-number changes remain untouched. No service
  implementation, signing configuration, or installed application was changed.
