# Test Display Scaling on a Dell ultrawide

This checklist is for the Switchboard **1.2.0 RC1 test release (build 58)** with a **3440 × 1440** external monitor. The Dell hardware checks below still need to be run on the target monitor. Automated tests and a signed build do not establish image quality, refresh rate, or compatibility with a particular cable or dock.

## Record the starting setup

Before trying scaling, note:

- Dell model, Mac model, macOS version, and Switchboard version.
- Connection path, including the cable, adapter, and dock if used.
- The monitor's current resolution, refresh rate, and HDR setting in **System Settings > Displays**.
- The input resolution and refresh rate shown by the Dell's own on-screen information menu. Record **3440 × 1440** as the baseline if that is the native signal it reports.
- Which screen is the main display, their arrangement, and whether the laptop lid is open.

Use an extended desktop with the Dell at its normal orientation. Existing mirror sets and rotated displays are unsupported. Turn off scaling or virtual-display sessions created by other utilities before this test. Keep the Mac's built-in display available for the first trial if possible.

Open a document you normally read, your browser, and any spreadsheet or editor you use at work. Save your work before testing sleep, disconnection, or quitting.

## Try 125% first

1. Open **settings gear > Display Scaling…** in Switchboard.
2. Select the Dell under **Display**. If it is absent, click **Refresh Displays** or **Refresh**.
3. Choose **125% · 2752 × 1152**, then **Try Scaling**.
4. Allow any brief display blink to finish. Check that the Dell shows the desktop, that the pointer reaches all four corners, and that text is readable.
5. For the first trial, let the **20-second** confirmation expire. Confirm that the prior display mode returns.
6. Try the same size again. Choose **Keep Scaling** within the countdown, then **Done**. Reopen Display Scaling and confirm that it reports scaling as active.

At 125%, the logical desktop is 2752 × 1152. HiDPI rendering draws that desktop at 5504 × 2304 before it is fitted to the physical display. The larger render is not proof that the cable is carrying a native 3440 × 1440 signal. Check the Dell's on-screen information menu again.

If the Dell reports a lower-than-native signal or the desktop is stretched, use **Restore Original** and record the result. Do not treat the trial as a successful native-output test.

## Compare readability and compatibility

Compare each result at your normal viewing distance. Restore the original mode between comparisons when you want a baseline.

| Check | What to record |
| --- | --- |
| Text in your usual apps | Whether small text, bold text, and spreadsheet gridlines are easier to read or noticeably softer. |
| Interface size | Whether 125% leaves enough room for the windows you use. Try 110% or 150% if needed. |
| Native output | The Dell information menu's input resolution before and during scaling. A macOS screenshot's dimensions do not establish this. |
| Refresh rate | The monitor's reported refresh rate and whether pointer movement, scrolling, and video remain smooth. Do not assume the original rate is retained. |
| Colour | Compare SDR colours, brightness, and gradients. The virtual desktop uses SDR sRGB primaries and a fixed refresh rate; HDR and variable refresh rate are unsupported in this version. Restore Original for HDR/VRR use. |
| Streaming and protected video | Whether the video services you use play normally. Mirroring can affect HDCP-protected content; a black video frame is a failed compatibility check. |
| Desktop behaviour | Main-display placement, menu bar, Spaces, full-screen apps, window movement, and pointer transitions between displays. |
| Performance | Whether the Mac becomes noticeably slower, warmer, or less responsive during the same work. Higher rendering resolutions increase graphics work. |

Available presets are **100%, 110%, 125%, 150%, 175%, and 200%**, subject to dimension and rendering limits. A higher percentage enlarges the interface. At 100%, the desktop size stays the same but rendering still uses HiDPI. It is not an off switch.

This feature cannot add physical pixels to a 3440 × 1440 panel. Fractional sizes may improve the appearance of enlarged text while softening some edges. Compare the result yourself; no preset is advertised as lossless or as Retina-quality on this monitor.

## Check restoration

Complete these independently, starting a fresh scaling session each time:

- [ ] Let an unconfirmed preview expire. The original mode returns.
- [ ] During a preview, click **Revert**. The original mode returns.
- [ ] During a preview, press **Escape** or close the scaling window. The preview ends and the original mode returns.
- [ ] Confirm with **Keep Scaling**, close the window, reopen it, and choose **Restore Original**. The original mode returns.
- [ ] Confirm scaling and quit Switchboard through its settings gear. The Dell returns to its original mode.
- [ ] Confirm scaling, put the Mac or displays to sleep, and wake them. Scaling has ended and does not reapply itself.
- [ ] Confirm scaling, unplug the Dell, then reconnect it. Scaling does not reapply itself. Check resolution, refresh rate, and display arrangement before starting a new preview.
- [ ] If another external monitor is available, confirm that only the selected monitor is scaled. Starting a session on the other monitor ends the first one.

If restoration reports an error, retry **Restore Original** and follow the recovery steps below. Record any moved windows or altered arrangement; restoring a display mode does not guarantee that every application will move its windows back.

## Recover the display

If the preview is unreadable, **do not choose Keep Scaling**. Let the 20-second confirmation expire, or press **Escape** while the scaling window has focus.

If the display does not recover:

1. From the built-in or another usable display, open **Display Scaling…** and choose **Restore Original**.
2. Quit Switchboard from the settings gear. If it is unresponsive, use **Activity Monitor** to select the Switchboard process and quit it.
3. Disconnect and reconnect the Dell. In **System Settings > Displays**, check that it extends the desktop and select the normal resolution and refresh rate.
4. Confirm that the Dell's own information menu reports the original signal again.

To return to the preceding release, quit Switchboard, download [Switchboard 1.1.7](https://github.com/Mehul72/switchboard/releases/tag/v1.1.7), and replace the Applications copy using its DMG. Version 1.1.7 has no Display Scaling feature. Do not disable macOS security protections to install it.

## Report the result

Use the [bug report form](https://github.com/Mehul72/switchboard/issues/new?template=bug_report.yml) for failures. Include the setup recorded above, chosen percentage, whether you pressed Keep Scaling, the exact error message, and whether **Restore Original** or quitting recovered the display. For a signal issue, include the Dell's reported resolution and refresh rate before and during the trial.

A useful result is specific: “125%, 3440 × 1440 at 60 Hz confirmed by the Dell menu; readable text; timeout and disconnect restore passed.” Avoid reporting “lossless” based only on a screenshot.

## Implementation limits

Switchboard creates a temporary virtual HiDPI display and mirrors it to the selected external monitor. The virtual source exists only while its scaling session is active. It does not install a display driver, require administrator access, or capture the screen with Screen Recording permission.

The virtual display bridge uses private macOS APIs because public display-mode APIs do not create the missing HiDPI modes on these monitors. Those APIs can change across macOS releases. An unavailable bridge or rejected configuration should produce an error and restore the previous configuration. Test again after a macOS update, and report failures with the OS version.

The first release supports one external monitor at a time. Built-in displays, displays already in a mirror set, and rotated displays are deliberately excluded. Sessions stop on restore, quit, display sleep, or disconnection and are not automatically restored after wake, reconnect, or relaunch.
