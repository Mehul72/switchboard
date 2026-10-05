# Documentation and media refresh

Status: done

## Goal

Update the README and user guide to match the current Switchboard source, refresh
the native sample images and GIFs, and provide matching downloadable MP4 demos.

## Decisions

- Keep the existing native SwiftUI renderer and isolated sample data.
- Label all media as rendered examples, with readable instructions in Markdown.
- Cover System monitoring and menu bar readings alongside existing workflows.
- App behavior, release publishing, and real personal desktop recordings are out of scope.

## Steps

- [x] Audit recent changes and update the README and user guide against source.
      Verify control names, shortcuts, defaults, permissions, and troubleshooting.
- [x] Extend the sample captures and export pipeline for current features and MP4.
      Verify the renderer builds and completes without accessing personal data.
- [x] Regenerate and inspect published images, every GIF step, and video frames.
      Verify files decode, dimensions and durations match, and text is readable.
- [x] Validate documentation links, run appropriate build/tests, and review the diff.
      Record checks and any limits before completion.

## Log

- 2026-10-05: Started from clean commit 281c8c5. Existing media had seven GIFs,
  source-rendered screenshots, and no video exports. Guide and media updates are
  delegated independently; the README and native capture additions stay with root.
- 2026-10-05: Source audit corrected clipboard permissions and temporary files,
  mouse-wheel behavior, audio persistence, restore scope, and optional controls.
  Added Finder, Dock, and screenshot how-tos and a System walkthrough.
- 2026-10-05: Native renderer and unsigned app build passed. The renderer now
  injects private defaults and a private pasteboard, and sample process controls
  cannot look up or quit real apps. Exported 22 PNGs, eight GIFs, and eight MP4s.
  All MP4s fully decode with matching dimensions and three seconds per GIF step.
- 2026-10-05: All 511 tests passed through scripts/test.sh. Independent review
  verified 112 local links/anchors and found no blocking source/doc mismatches.
- 2026-10-05: Inspected native captures, all GIF steps, and decoded video frames.
  All eight MP4s played and sought to the middle and final step in Chromium.
  Local README and guide HTML previews passed image/alt-text and overflow checks
  at 390px and 1280px in light and dark themes. Python compilation and
  git diff --check passed. No separate lint configuration exists in the repo.
- 2026-10-05: Retained original PNG bytes for seven captures whose pixels matched
  the fresh renders exactly. No application source changed. Release signing,
  notarization, and fresh-DMG installation were outside this documentation update.
