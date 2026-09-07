# Plan: per-app audio without a recording indicator

Status: unfinished

## Goal

Keep per-app attenuation active during continuous playback without opening a
recording stream or showing a privacy indicator. Preserve the existing feature
fixes and provide manual checks for every exposed feature.

## Decisions

- The user accepts a driver-based installation if it removes the indicator
  (7 September 2026).
- Resetting volume after five seconds does not satisfy persistent per-app volume.
- Do not substitute an orange microphone indicator for the purple indicator.
- Use supported driver APIs, and do not publish readable audio to unrelated users.
- No driver has been added, installed, or verified in this change.

## Steps

- [x] Audit the existing app and reproduce specific failures with regression tests.
      Verified: baseline 59 tests passed; new clipboard and permission cases failed
      before their fixes and pass afterward.
- [x] Fix confirmed clipboard, permission-state, and clipboard-control visibility
      problems, and build the app.
      Verified: 66 tests pass, Debug and Release compile. Live UI checks are listed
      separately and have not been claimed as passed.
- [x] Investigate driver references and document their actual limitations.
      Verified: Background Music release notes, Faded source at
      `951661296467b9d8d10a3c960aaf5f49ca3239ed`, and Apple's installed SDK header.
- [ ] Implement a supported output-only driver and private audio transport.
      Done when: per-client gain and concurrent audio transport pass bounded-memory
      and sanitizer tests; unrelated processes cannot retrieve the audio buffer.
- [ ] Integrate output-only playback and routing recovery into Switchboard.
      Done when: two-app attenuation, output switching, helper restart, app crash,
      and return to native routing are tested without silent output or stale gains.
- [ ] Package a signed installation and removal path, then verify live behavior.
      Done when: continuous playback at reduced volume shows neither audio privacy
      indicator, and install/uninstall and device-recovery checks pass on macOS.
- [x] Write manual steps for every currently exposed feature.
      Artifact: ../../MANUAL_TESTS.md. Instructions written; live checks not run.

## Findings affecting the driver work

Background Music's v0.5.0 notes explicitly say the microphone indicator remains
while audio plays. It therefore fails the user's condition.

Faded's legacy output-only driver is a useful design reference, but its
`SharedRing` constructor uses `shm_open(..., 0644)` and `fchmod(..., 0644)`, exposing
mixed audio to every local user. Its ring cannot be adopted unchanged. A private
transport with authenticated peers is still needed.

VolumeRouter says it forwards audio by calling Core Audio from within its driver.
Apple's `AudioServerPlugIn.h` states that a plug-in must not call the client HAL
API, because the result is undefined. That approach is not a supported replacement.

## Verification record

- `xcodebuild test ... CODE_SIGNING_ALLOWED=NO`: 66 tests, zero failures.
- `xcodebuild build ... -configuration Release CODE_SIGNING_ALLOWED=NO`: succeeded.
- `git diff --check`: passed.
- SwiftLint could not run: installed binary crashes loading SourceKit, both inside
  and outside the sandbox. No lint-pass claim is made.
- No live test of a driver, audio attenuation, or privacy-indicator disappearance
  has occurred. The original continuous-playback indicator request remains open.
