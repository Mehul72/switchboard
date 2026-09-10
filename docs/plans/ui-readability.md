# UI readability

Status: done

## Goal
Keep Switchboard readable over bright and dark windows, and improve navigation,
scrolling, settings, and audio controls without changing the underlying utilities.

## Decisions
Use opaque adaptive light/dark surfaces, measured text contrast, clear selected
tabs, and native controls. Keep the menu bar popover and its four sections.
Use compact macOS text styles, regular-weight setting labels, a quiet segmented
main navigation, and underlined subcategories. Keep decoration subordinate to
the controls and reduce the panel's footprint.

## Scope
Presentation and navigation only. No changes to system preferences, audio routing,
permissions, installation, or release behavior.

## Steps
- [x] Replace translucent surfaces and weak text colors; verify appearance contrast.
- [x] Improve navigation, reset scroll position, and expose a readable scrollbar;
      verify native rendering and compile.
- [x] Improve audio layout and shared row hierarchy; verify rendering and build.
- [x] Update usage/manual checks, run existing tests, and review the final diff.

## Verification
Measure text against each surface in light, dark, and increased contrast appearances.
Render native UI with synthetic settings to avoid changing user preferences.
Build with Xcode and run the existing test suite. Record any checks requiring a
live manual session instead of claiming those checks passed.

## Log
- 2026-09-09: Screenshots show backdrop bleed through the behind-window material.
  Theme adds half-opacity cards and low-opacity labels. The shared ScrollView
  also retains its offset when the category changes.
- 2026-09-09: Initial build and all 160 tests passed. Native fixtures checked
  dark/light shared navigation, audio rows, and settings. Baseline text contrast
  fell to 1.24:1 over white. macOS normalizes requested high-contrast appearances
  unless the accessibility setting is enabled, so those modes require live checks.
- 2026-09-10: User requested smaller native macOS type and more visual refinement.
  Replace heavy blue navigation blocks and large headings, tighten row spacing,
  and recheck the revised native layouts. Preserve the user's build-number bump.
- 2026-09-10: 78 appearance checks passed, lowest text contrast 4.56:1. macOS
  reports 12-point callouts and 11-point small system fonts, now used in the UI.
  The revised app builds and all 160 tests pass. Native rendering uses actual
  views with a synthetic store; no production preference or audio controls run.
- 2026-09-10: Native compact-panel checks exposed a 16-point scroll offset after
  category changes. Moving the scroll target from a zero-height lazy child to
  the padded content container fixes it. Category and search reset checks now
  pass in light, dark, and 350-point panels. Snapshots cover all four sections.
- 2026-09-10: Final Xcode build/test run passes all 160 tests. Final appearance
  check passes all 78 available checks; native rendering and scroll resets pass
  after the final audio spacing adjustment. `git diff --check` passes. Usage
  labels and manual checks match the interface. No service behavior changed.

## Remaining manual verification
Full VoiceOver and keyboard traversal, Increase Contrast, and Reduce Motion
require a live accessibility session. Native previews use an inactive window
and synthetic settings, so they verify layout and scrolling, not permission
flows or live system-setting changes. The installed app was not replaced.
