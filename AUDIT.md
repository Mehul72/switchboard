# Feature audit, 7 September 2026

The feature catalog, services, store, panel, and controls were reviewed. This was
source review plus automated macOS tests, not a completed live hardware/UI audit.
Use [MANUAL_TESTS.md](MANUAL_TESTS.md) for every exposed feature's manual checks.

## Fixed and checked

- **Clear history race:** a clipboard change awaiting the 0.6-second polling
  timer reappeared after Clear. Clear now advances the observed change count,
  including when the history is already empty. Two regression tests failed before
  the fix and pass after it; the system clipboard remains intact.
- **Private text after Make Plain:** formatting cleanup discarded concealed and
  transient clipboard markers, making private text eligible for history capture.
  Cleanup now republishes exclusion markers with the plain text. A test with a
  marker on a second pasteboard item failed before the fix and passes afterward.
  Ordinary rich text still becomes recordable plain text.
- **Quit-on-close preference lost on permission revocation:** the timer called
  the explicit user-disable path when permission disappeared. It now stops the
  monitor without rewriting the saved preference. The regression test failed
  before the fix and passes afterward; explicit disable still clears the setting.
- **Keyboard access to clipboard actions:** Copy and Remove were conditionally
  absent unless the pointer hovered over the row. They now remain in the view
  and accessibility hierarchy. Compiled, but live keyboard/VoiceOver testing remains.

The 59-test baseline passed. The expanded 66-test suite passes with zero failures.
Added coverage includes actual JPEG/HEIC screenshot conversion and protecting a
newer clipboard copy from an older conversion. Tests use private pasteboards and
an isolated preference suite, not the user's clipboard or permission database.

## Audio finding and improvement

The screenshot shows the indicator beside Control Centre that Apple identifies as
[system audio recording](https://support.apple.com/en-ie/guide/mac-help/mchl50f94f8f/mac).
Switchboard uses [Core Audio process taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)
to continuously render an app's audio at reduced gain. This is live processing;
it does not save an audio recording to disk. Stopping that processing after five
seconds would also stop enforcing the requested volume.

The Audio tab now explains the indicator and offers **Reset All Volumes**, which
releases all taps and returns apps to normal volume. It does not promise a fixed
macOS indicator timeout. Audio attenuation and the new reset require live testing.
No audio-driver change or privacy-indicator suppression was implemented.

The user approved investigating a driver-based replacement if it removes the
indicator. It is **unfinished**, tracked in [the driver plan](docs/plans/audio-driver.md).
Three references were checked:

- [Background Music release notes](https://github.com/kyleneideck/BackgroundMusic/releases/tag/v0.5.0)
  explicitly say its microphone indicator still appears during playback.
- [Faded's legacy driver](https://github.com/pillgat3s/faded/blob/951661296467b9d8d10a3c960aaf5f49ca3239ed/driver/Driver.cpp)
  publishes audio through shared memory. Its `0644` permissions make that buffer
  readable by every local user. Its output-only transport is useful as a reference,
  but that access model must be replaced before adoption.
- [VolumeRouter](https://github.com/MirkoMorello/VolumeRouter) describes forwarding
  playback inside its HAL plug-in. Apple's installed `AudioServerPlugIn.h`, lines
  34-36, explicitly forbids client HAL calls from a plug-in as undefined behavior.

No third-party source was added to Switchboard. A secure output-only driver and
playback helper remain to be implemented and tested; no indicator-free result is
claimed for the current build.

## Remaining verification limits

- Live output attenuation, audio permission denial, device switching, and indicator
  disappearance timing have not been exercised in this session.
- OCR selection and permission UI, sleep expiry, actual mouse/trackpad input,
  Finder/Dock effects, network shares, and login/relogin require the manual checks.
- macOS preference readback proves the stored value, not that every macOS release
  still honors an undocumented preference. Manual behavior checks remain necessary.
- Mouse scrolling currently inverts discrete wheel events; it does not force an
  absolute direction independently of macOS's natural-scrolling preference.
- Translation is intentionally disabled in the catalog, so it was not treated as
  a broken exposed feature.

Debug tests and an unsigned Release build succeeded. `git diff --check` passed.
SwiftLint verification is unavailable: the installed binary crashes loading
`sourcekitdInProc.framework`, including when run outside the sandbox.
