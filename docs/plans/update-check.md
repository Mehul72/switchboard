# Plan: check for updates
Status: done
Branch: main (uncommitted)

## Goal
Switchboard tells people when a newer release exists. The settings gear gets
**Check for Updates…**, which reports "up to date", "X.Y.Z is available", or a
failure. An automatic check runs at most once a day and announces each new
version once. Verifiable by running the app with a lower `MARKETING_VERSION`
and seeing the notice and the **Update to X.Y.Z…** menu item.

## Decided already
- Source: `GET https://api.github.com/repos/Mehul72/switchboard/releases/latest`.
  GitHub excludes drafts and prereleases from that endpoint. Only `tag_name`
  is read; it must look like `vX.Y.Z` (the release routine already tags this way).
- Compare numerically against `CFBundleShortVersionString`; missing components
  count as zero, so `1.2` equals `1.2.0`. A dev build newer than the release is
  "up to date".
- Notify only. Nothing is downloaded or installed. The update action opens the
  constant `https://github.com/Mehul72/switchboard/releases/latest`; no URL
  from the response is ever opened.
- Automatic checks are on by default with a toggle in the settings gear. First
  check 60 s after launch, then an hourly tick that only calls GitHub when the
  last successful check is 24 h old. A failed check is retried at the next
  tick, so a failure costs at most one request an hour (GitHub allows 60 an
  hour unauthenticated).
- One request per check: 10 s request timeout, 20 s total, no retry inside a
  check, ephemeral session (no cookies, no cache). A check already in flight
  absorbs a second request instead of starting another.
- No package dependencies (Sparkle is out, per the README).

## Out of scope
- Downloading, verifying, or installing the DMG.
- Showing release notes inside the app.
- Beta channel, skipping a version.

## Steps
- [x] 1. `UpdateChecker` service with version parsing, the GitHub feed, schedule, and state
      files: Switchboard/Services/UpdateChecker.swift, SwitchboardTests/UpdateCheckerTests.swift, project.pbxproj
      done when: new tests pass in `xcodebuild test`, covering parse, compare,
      decode, due logic, announce-once, failure, coalescing, and automatic off
- [x] 2. Wire it into the app: gear menu items, notice with a link button, startup
      files: StatusItemController.swift, PopoverView.swift, TweakStore.swift (StoreNotice), scripts/docs/Render.swift
      done when: app builds, full suite passes, and a live request through the
      production feed returns the current GitHub release
- [x] 3. Docs: update section, privacy disclosure, release contract
      files: docs/user-guide.md, README.md, CONTRIBUTING.md
      done when: every statement matches the code (interval, toggle name, what is sent)

## Open questions
- None blocking. Default-on automatic checking is a product call the user may
  flip; it is one constant.

## Log
- 2026-09-27 step 1: 25 tests pass (`-only-testing` the three new classes). The
  sinkhole test times out at the configured 0.5 s, so the session's
  `timeoutIntervalForRequest` is honoured without setting one on the request.
  Mutations (no coalescing, always announce) fail 3 tests, so they bite.
- 2026-09-27: README, user guide, CONTRIBUTING, docs images and scripts/docs are
  being edited by someone else in this working tree. Keep edits there minimal and
  targeted; do not reformat or revert their changes.
- 2026-09-27 step 2: full suite 364 tests pass. Live request through
  `GitHubReleaseFeed` returned 1.1.4 in 0.32 s. The docs renderer type-checks
  with its patched sources. A scratch render of the popover showed the notice
  link in primary text colour (the popover's foregroundStyle overrides
  `.link`), so it now copies the clipboard list's accent borderless button.
- 2026-09-27 step 3: user guide (update section, troubleshooting row), README
  privacy line, CONTRIBUTING tag contract and manual release check. Every menu
  title, the daily interval and the 20 s bound were checked against the code.
  Final: 364 tests pass, the Release build succeeds, and the new files compile
  with no warnings. The timer has no stop because the checker lives as long as
  the app.
