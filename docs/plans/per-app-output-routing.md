# Plan: per-app output device routing

Status: code complete, audible check outstanding
Branch: main

## Goal

Send one app's audio to an output device other than the system default, while
per-app volume keeps working, and make the render path correct on devices whose
channel count is not stereo or which carry their own input stream. Verifiable by
playing audio in one app, routing it to MacBook Pro Speakers while AirPods stay
the system default, and hearing only that app move.

## Decided already

- The tap becomes `CATapDescription(stereoMixdownOfProcesses:)`. The current
  `CATapDescription(processes:deviceUID:stream:)` binds the tap to one device
  and captures only streams already headed there, so the destination can never
  differ from the source. A mixdown tap is device-independent, which is what
  makes routing possible at all.
- Tap lifetime is unchanged. It stays alive while the app holds an audio
  connection, so the purple audio-recording dot behaves exactly as it does today
  (user, 8 September 2026).
- Chosen routes persist per bundle ID in `UserDefaults` and are reapplied when
  the app is seen again (user, 8 September 2026).
- Volume stays capped at 100%. No boost, no peak limiter (user, 8 September 2026).
- Written from Apple's public Core Audio API. `vorssaint/vorssaint-utils` is
  GPL-3.0-or-later and Switchboard carries no licence, so no source is copied
  from it.

## Out of scope

- Removing the purple dot. That is `audio-driver.md`, still unfinished, and the
  finding recorded there is that no tap-based approach avoids it.
- Volume above 100% and the limiter that would need.
- Per-app input device or microphone routing.
- Replacing the 2-second maintenance poll with per-process `IsRunningOutput`
  listeners. Worth doing later; routing does not need it, and a device that
  disappears is picked up within one poll.
- Changing the system default output device from Switchboard.

## Steps

- [x] 1. Channel-mapping render helpers, pure and tested, called by nothing yet
      files: Switchboard/Services/AudioRender.swift,
      SwitchboardTests/AudioRenderTests.swift
      done when: tests cover stereo to stereo, stereo folded to mono, stereo into
      8 channels with the rest silenced, mono duplicated into both front
      channels, tap found at a buffer other than zero when the device brings its
      own input, no writable output, and a short output buffer whose tail is
      silenced. All pass.

- [x] 2. Route resolution, pure and tested
      files: Switchboard/Services/AudioRouting.swift,
      SwitchboardTests/AudioRoutingTests.swift
      done when: tests cover no selection resolving to the default, a selection
      that is unavailable falling back to the default and reporting unavailable,
      a selection equal to the default, and the tap-needed decision across gain
      1 on default (no tap), gain 1 on another device (tap), and gain below 1
      (tap). All pass.

- [x] 3. Output device enumeration
      files: Switchboard/Services/AppAudio.swift, SwitchboardTests/AudioRoutingTests.swift
      done when: `outputDevices()` returns only devices with output streams and
      excludes Switchboard's own private aggregates by UID prefix; the filter
      predicate has unit tests; the app builds.

- [x] 4. Switch the tap to a stereo mixdown and render through step 1
      files: Switchboard/Services/AppAudio.swift
      done when: builds clean with no warnings, all tests still pass, and a live
      check confirms reducing an app's volume on the default device still works.

- [x] 5. Per-app route selection and persistence
      files: Switchboard/Services/AppAudio.swift, Switchboard/Model/TweakStore.swift
      done when: a saved route round-trips through `UserDefaults` under test;
      `reconcile` rebuilds when the effective device changes and falls back to
      the default when a chosen device disappears; live check routes one app to
      MacBook Pro Speakers while AirPods stay default.

- [x] 6. Device picker in the audio row
      files: Switchboard/Views/AppVolumeList.swift
      done when: each row offers the output devices, shows which is in use, marks
      a saved-but-missing device as unavailable, and Reset All returns every app
      to both 100% and the default device. Builds clean.

- [x] 7. Documentation
      files: README.md, MANUAL_TESTS.md
      done when: the audio bullet describes routing, and MANUAL_TESTS.md has
      steps for routing, device disappearance, and the mono virtual device, with
      no stale claim that per-app volume is default-device-only.

## Open questions

- Whether a 1-channel virtual device (Microsoft Teams Audio is present on this
  Mac) can be an aggregate main sub-device at all, or whether Core Audio refuses
  it. Blocks the "unavailable" wording in step 6. Resolve by trying it in step 5.

## Log

- 2026-09-08 Plan written. Root cause of the missing feature confirmed by
  reading AppAudio.swift:415: the tap is device-bound, so tap source and render
  destination are structurally the same device.
- 2026-09-08 Existing render block at AppAudio.swift:545 assumes equal buffer
  counts and equal channel counts and silently `continue`s otherwise, so it
  would produce silence on a mono destination and play the device's own
  microphone when the destination has an input stream. Step 1 exists to fix
  that before the tap type changes.
- 2026-09-08 Step 1 landed. 32 tests added across five suites; full suite now
  107 tests, zero failures. `AudioRender` is registered in both the app and
  test targets but nothing calls it yet, so the tree still builds and behaves
  exactly as before.
- 2026-09-08 Step 2 landed. `AudioRouting` added with 20 tests. Found a live bug
  while writing it: the volume slider is continuous, so dragging back to the top
  can land on 0.9998, which the row displays as 100% but which keeps the tap and
  its privacy indicator alive for the rest of the session. `isFullVolume` covers
  it but nothing calls it yet, so the bug is still live in the app.
- 2026-09-08 Step 3 landed. `outputDevices()` and `systemDefaultOutputUID()` added,
  `AppAudio.swift` joined the test target. Verified against this Mac: both
  microphones filtered out, MacBook Pro Speakers, Microsoft Teams Audio (one
  channel) and both Audiojingle devices offered. 134 tests, zero failures.
- 2026-09-08 Step 4 attempted and stopped by the user partway through. Two of the
  three edits had already landed, which left `install` referencing a deleted
  `OutputRoute` and the tree not compiling. Reverted both to the device-bound tap
  and confirmed 134 tests pass again. Lesson for the retry: step 4 changes the
  tap type, the `Controlled` record and the render block together, so it is one
  edit or the tree is broken in between.
- 2026-09-08 Steps 4 to 7 landed in one pass. The tap is now
  `CATapDescription(stereoMixdownOfProcesses:)` rendered through `AudioRender`,
  `AppAudioEngine` gained `setOutputDevice`/`selectedOutputUID` with routes saved
  under `audio.outputRoutes`, `TweakStore` publishes the device list and per-app
  route, and the audio row gained an output menu. 138 tests pass, Release builds
  with no warnings from this code.
- 2026-09-08 `setGain` now normalises through `AudioRouting.isFullVolume`, so the
  0.9998 slider bug recorded above is fixed rather than merely covered by a test.
- 2026-09-08 Open question about a one-channel device as an aggregate main
  sub-device is NOT resolved. It is now manual test 10 in MANUAL_TESTS.md.
- 2026-09-08 Not verified: nothing audible has been checked. No audio has been
  played through the new render path. The manual steps exist; they have not run.
