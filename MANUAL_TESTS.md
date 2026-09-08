# Switchboard manual feature checks

Run these against the newly built app. These are instructions and expected results,
not a claim that the live checks have already passed. Automated audit results are
in [AUDIT.md](AUDIT.md).

## Before starting

1. Quit any other copy of Switchboard using its settings menu.
2. Open `Switchboard.xcodeproj`, select **Switchboard > My Mac**, and press
   **Command-R**. For login-item and permission-persistence tests, use a signed
   build installed in Applications. The unsigned command-line test build is not
   a substitute for that installation.
3. Note your original settings before changing them. Use disposable files and
   documents for Finder and close-button tests.
4. Enable **System Settings > Keyboard > Keyboard navigation** for keyboard tests.
5. Record macOS version, output device, app version, and pass/fail for each check.
   For a failure, record the exact sequence and any message Switchboard shows.

## Panel, navigation, and search

1. Click the routed S menu-bar icon. Expected: the panel opens fully onscreen.
2. Visit Tweaks, Audio, Clipboard, and System. Inside Tweaks visit Everyday,
   Files, Capture, and Dock. Expected: all four main tabs fit without horizontal
   scrolling, and each category displays its controls and scrolls to its last row.
   Select Files, switch to Audio, then return to Tweaks. Expected: Files remains
   selected. Close and reopen the panel while on Audio and repeat the return.
3. Search for `hidden`, `volume`, and `clipboard` separately. Expected: matching
   settings or the relevant special list appear.
4. Search for `no-such-setting-928`. Expected: **No matching settings**.
5. Press Escape once with a search present. Expected: search clears. Press again.
   Expected: panel closes. Reopen it and click outside. Expected: it closes.
6. Repeat on a smaller display if available. Expected: bottom controls remain reachable.
   With a notice and pending restart visible, scroll through the controls. On
   short panels, secondary categories and notices scroll with the content.
7. Repeat in light and dark appearances. Check readable descriptions, output
   device names, native controls, and clipboard previews. Try a long app/device
   name and empty Audio and Clipboard lists.
8. With Keyboard navigation enabled, Tab through search, the settings gear,
   navigation, and controls. Use left/right arrows within each navigation row and
   Space to activate a focused button. Expected: visible focus and the selected
   category stay in sync; Escape still clears search before closing the panel.
9. Check VoiceOver labels for search, selected tabs, app volume, output devices,
   copy/remove clip actions, and the settings gear. Enable Reduce transparency,
   Increase contrast, and Reduce motion in Accessibility > Display and verify
   opaque backgrounds, clear borders, and no navigation animation respectively.

## Everyday

### Keep Mac awake

1. Select **30 minutes**. In Terminal, run `pmset -g assertions`.
   Expected: a Switchboard sleep-prevention assertion is listed, and the row reads
   **Ends in 30 minutes** in place of its description.
2. Watch the row for a minute. Expected: it reads **Ends in 30 minutes** from the
   moment you pick it, never 31, and turns over to **Ends in 29 minutes** about a
   minute later.
3. Select **1 hour**, **2 hours**, and **Until I stop it** in turn. Reopen the panel
   after each selection. Expected: the selected duration remains correct, timed
   choices read **Ends in ...**, and **Until I stop it** reads **On for ...**
   counting from when the assertion first started, not from the last change.
4. Select **Off** and rerun the command. Expected: Switchboard's assertion disappears
   and the row shows its description again.
5. Select **30 minutes**, leave it running for the full duration, and reopen the
   panel. Expected: Off is selected, the expiry notice appears, and no countdown
   remains.
6. Enable it again and quit Switchboard. Expected: its assertion disappears.
   Closing the laptop lid or choosing Sleep explicitly is outside this feature.

### Copy text from the screen

1. Display two lines of clearly readable text in TextEdit or a browser.
2. Click **Select Area**. If prompted, allow Switchboard in **Privacy & Security >
   Screen & System Audio Recording** (called Screen Recording on older macOS),
   relaunch if macOS requires it, and try again.
3. Drag around the text. Expected: the panel disappears during selection, returns
   on Clipboard, and shows recognised text in reading order. Paste into TextEdit.
4. Repeat, pressing Escape instead of dragging. Expected: cancellation is reported
   and the previous clipboard contents remain available.
5. Select a blank area. Expected: **No text found**, without replacing the clipboard.
6. Repeat after changing screenshot destination and format in Capture. Expected:
   OCR still returns text. Also test a second display if available.
7. Revoke permission and try again. Expected: a permission message, no hang.
   Translation is intentionally disabled and has no exposed feature to test.

### Red button quits the app

1. Enable the toggle. Grant Accessibility permission if requested, then enable again.
2. Open two disposable TextEdit documents. Close one with its red button.
   Expected: TextEdit stays running with the other document.
3. Close the last document. Resolve any save prompt. Expected: TextEdit quits
   after the close is confirmed, normally within a few seconds.
4. Repeat with an unsaved document, choosing **Cancel** in the save prompt.
   Expected: the document and app remain open.
5. Repeat the two-window check with the remaining window minimised, on another
   Desktop, and full-screen. Expected: the app stays running in each case.
6. With Chrome open for at least eight seconds, close its final tab.
   Expected: it quits after roughly three seconds with no windows. Entering or
   leaving full screen must not quit Chrome.
7. Put two Chrome windows in full screen and a Safari window in full screen,
   leave a second Safari window on the Desktop, then return to the Desktop and
   wait ten seconds. Expected: both browsers keep running. Now close the
   Desktop Safari window with its red button. Expected: Safari keeps running
   for the full-screen window, and Chrome is untouched. This is the regression
   that quit both browsers from one click: a window on a Space that is not
   showing is invisible to Accessibility, so the window server has to be asked
   whether the window is parked elsewhere or really gone.
8. While the feature is enabled, revoke Accessibility permission. Wait a second.
   Reopen Switchboard. Expected: the toggle reflects that the monitor is stopped.
   Regrant access and reopen the panel. Expected: the saved enabled preference
   resumes. Explicitly turning the toggle off must keep it off across relaunch.
9. Close a Finder window. Expected: Finder is never quit by this feature.

### Traditional mouse scrolling

1. With natural scrolling enabled in macOS, connect a mouse with a physical wheel
   and compare its direction with the trackpad in a long document.
2. Enable **Traditional mouse scrolling**, granting Accessibility if requested.
   Expected: wheel direction reverses; trackpad gestures and momentum stay the same.
3. Test horizontal wheel scrolling if your mouse supports it.
4. Turn the toggle off. Expected: original wheel direction returns.
5. Enable, quit, and reopen Switchboard. Expected: it resumes with permission.
6. Revoke permission while enabled, then regrant and reopen the panel. Expected:
   input follows permission and the saved enabled preference resumes.
7. Known limitation: this feature inverts discrete wheel events. Magic Mouse
   gestures and drivers that emit continuous events are not inverted. If macOS
   natural scrolling is already off, inversion reverses that existing direction.

### Show scroll bars

1. Choose **Always** and reopen a long TextEdit document. Expected: bars stay visible.
2. Choose **When scrolling**. Expected: bars appear during scrolling and then fade.
3. Choose **Automatic**. Expected: macOS selects behavior for the input device.
   Reopen affected apps if they do not pick up the setting immediately.

### Strip clipboard formatting

1. Copy bold, coloured text containing a link. Click **Make Plain**.
2. Paste into a rich-text TextEdit document. Expected: text uses the destination's
   formatting, with no source fonts, colours, or link metadata.
3. Copy an image and try again. Expected: a copy-text-first message; image remains.
4. Optional privacy regression check: use a disposable dummy entry in a password
   manager that marks private copies. Copy it, click Make Plain, and inspect
   Clipboard. Expected: it never appears in history. Do not use a real password.

## Files

For each setting with a restart bar, click **Restart Finder** after changing it.
The Switchboard panel should stay open through the restart. Test both on and off.

| Feature | Steps | Expected result |
| --- | --- | --- |
| Show hidden files | 1. Open your home folder. 2. Enable and restart Finder. 3. Disable and restart. | Hidden entries such as `.zshrc`, if present, appear and then disappear. |
| Show all file extensions | 1. Create a disposable `.txt` file and enable Hide extension in Get Info. 2. Enable this setting and restart. 3. Disable and restart. | `.txt` is visible while forced on; the file's own hidden-extension setting applies when off. |
| Show full path in Finder title | 1. Open a nested folder. 2. Enable and restart. 3. Disable and restart. | Title shows the full path when on and the normal folder title when off. |
| Keep folders on top | 1. Put a file named `A.txt` and folder named `Z-folder` together. 2. Sort by Name. 3. Enable and restart. 4. Disable and restart. | Folder precedes the file when on; normal name ordering returns when off. |
| Search the current folder | 1. Enable and restart. 2. Open a nested folder and search for a filename. 3. Disable and restart, then retry. | Current-folder scope is initially selected when on; macOS default scope applies when off. |
| Skip extension warnings | 1. Enable and restart. 2. Rename a disposable `.txt` file to `.md`. 3. Disable and restart, then rename back. | No extension confirmation when on; confirmation when off. |
| Hide desktop icons | 1. Place a disposable file on Desktop. 2. Enable and restart. 3. Open Desktop in Finder. 4. Disable and restart. | Icons disappear from the desktop, files remain in Finder, and icons return when off. |
| No .DS_Store on network drives | 1. Enable. 2. Disconnect and reconnect a writable SMB share. 3. Open a new test folder and change its view. 4. Inspect hidden files on the share. | No new `.DS_Store` is created there. Existing files are not removed. Requires a real network share; local folders do not test this. |

## Capture

Use **Command-Shift-4** for region screenshots. Test a new screenshot after each change.

1. **Save screenshots to:** turn clipboard destination off, choose a writable test
   folder, and capture. Expected: the file appears there. Cancel another folder
   selection. Expected: the previous destination remains selected.
2. **Screenshot format:** choose PNG, JPEG, then HEIC, capturing a new file each
   time. Run `file` on each file or open it in Preview's Inspector. Expected:
   actual encoding matches the selected format, not just its filename.
3. **Copy screenshots to clipboard:** turn it on and capture. Expected: no new
   file in the destination; paste or Preview > File > New from Clipboard works.
4. With clipboard destination on, repeat PNG, JPEG, and HEIC. Allow at least a
   second for conversion. Expected: the image is pasteable and reaches history.
   For exact encoding, the automated conversion tests inspect the pasteboard and
   image bytes directly.
5. With clipboard destination on and JPEG selected, capture, then paste into an
   app that accepts a pasted file (Finder, Mail, or a chat with an upload area).
   Expected: a `.jpg` named `Screenshot <date> at <time>`. Run `file` on it and
   confirm real JPEG bytes, not a renamed PNG. Repeat with HEIC. An app that
   pastes the image data alone still produces PNG; that is macOS transcoding it.
6. Capture at least six times in a row with JPEG selected. Expected: pasting the
   most recent capture still yields its file. Switchboard keeps only the last
   few converted files in the temporary spool.
7. Capture a large image, then immediately copy some text. Expected: a finishing
   image conversion must not replace the newer text.
8. **Skip the floating thumbnail:** enable and capture. Expected: immediate save,
   no thumbnail. Disable and capture. Expected: the thumbnail returns.
9. **Remove window shadows:** press Command-Shift-4, then Space and click a window.
   Compare captures with the setting on and off. Expected: only the off capture
   includes the surrounding shadow. Region captures do not test this setting.
10. Quit Switchboard with clipboard JPEG/HEIC enabled and capture again. The macOS
   preference persists, but Switchboard's clipboard converter only runs while
   the app is open. Reopen it before testing conversion again.

## Dock

Click **Restart Dock** after each change. The Switchboard panel should stay open.

1. **Reveal hidden Dock instantly:** enable Dock auto-hide in System Settings.
   Enable this tweak, restart Dock, and move the pointer to its edge. Expected:
   no initial reveal delay. Disable and restart to compare the macOS default.
2. **Hide recent apps:** enable macOS's suggested/recent apps Dock section first,
   then enable this tweak and restart. Expected: recent unpinned apps disappear
   from that section. Pinned and currently running apps remain. Disable and restart.
3. **Minimise into app icons:** open an app with a window. Enable and restart, then
   minimise the window. Expected: no separate thumbnail at the Dock's right end.
   Disable and restart; minimise again. Expected: a separate thumbnail returns.

## Audio and the purple indicator

Keep the Mac's main volume comfortably low before testing reset or mute recovery.

1. Play audio in two apps, for example Safari and Music. Open Audio. Expected:
   both apps appear; browser helper streams are grouped under their parent app.
2. Lower one app to roughly 30%. Expected: only that app becomes quieter; the
   Mac's main volume and other app remain unchanged. Grant System Audio Recording
   access on the first request, then retry if necessary.
3. Set that app to 0%. Expected: it is silent. Raise it again; sound returns.
4. Close Switchboard's panel and keep playing for ten seconds. Expected: chosen
   volume persists. The purple dot can remain throughout this test.
5. Return the app to 100%. Expected: its tap is released. If another app is still
   reduced, the dot can remain because that app still needs audio access.
6. Reduce both apps, then press **Reset App Volumes and Outputs**. Expected: all app sliders show
   100%, normal playback continues, and Switchboard releases its taps. macOS owns
   indicator disappearance timing and may show recent access afterward. Another
   recording app can independently keep the indicator visible.
7. Pause and resume a reduced app. Expected: volume is reapplied. A paused app
   may keep its audio stream open, so pausing is not guaranteed to remove the dot.
8. Switch output between built-in speakers and headphones. Expected: control
   reconnects or reports a failure and resets to 100%; no permanently silent app.
   Repeat for Bluetooth/HDMI devices you use. Unsupported layouts must report an error.
9. Quit an adjusted app, then relaunch it. Expected: it returns at normal volume.
10. Reduce volume again, then quit Switchboard. Expected: the app returns to normal
    playback and Switchboard no longer owns active audio taps.
11. Revoke System Audio Recording permission and try reducing volume. Expected:
    a useful error and no false claim that the volume was successfully changed.

**Current limitation:** reduced volume and per-app output both require
continuous audio processing. The dot cannot disappear while either is in effect.
Reset stops the processing by returning every app to 100% on the default output.

## Per-app output device

Needs at least two output devices. These steps assume AirPods are the system
default and the built-in speakers are the second device.

1. Play audio in one app and open Audio. Expected: each row shows an output menu
   reading **System Default**, and the menu lists every device that can play,
   with no microphones and nothing named after Switchboard.
2. Send that app to **MacBook Pro Speakers**. Expected: only that app moves to the
   speakers. Everything else, including system sounds, stays on the default.
3. Leave its volume at 100%. Expected: routing alone still works, and the purple
   dot appears because a tap is required to move the audio.
4. Lower the routed app to 30%. Expected: it is quieter and still on the speakers.
5. Set the app back to **System Default**. Expected: it returns to the default
   device, and if its volume is also 100% the tap is released.
6. Route an app to a device, quit Switchboard, relaunch it and play that app
   again. Expected: the chosen device is remembered and reapplied.
7. Route an app to a removable device, then unplug it. Expected: within about two
   seconds the app returns to the default device and keeps playing. The menu
   reads **Chosen device unavailable** in orange rather than showing the default.
8. Plug that device back in. Expected: the app returns to it and the warning
   clears.
9. Change the Mac's default output while an app is routed elsewhere. Expected:
   the routed app stays where it was sent; unrouted apps follow the new default.
10. Route an app to a one-channel device, for example a virtual conferencing
    device. Expected: audio is folded to mono and plays at normal pitch and
    speed, never at half speed or an octave low.
11. Route an app to a device that also has a microphone. Expected: the app's own
    audio plays, never the microphone.
12. Press **Reset App Volumes and Outputs**. Expected: every app is back at 100% on
    the default device and the saved routes are cleared.

## Output device volume

1. Open Audio without any apps playing. Expected: the app section comes first,
   followed by a collapsed **Output devices** section. Expand it: connected
   outputs appear, with **System Default** beside the current default. Collapse
   it again: device controls are hidden and the app section remains visible.
2. Play two apps through the same output. Lower that device's slider. Expected:
   both apps become quieter; their individual app sliders remain unchanged.
3. Route one app to another output and lower that device's volume. Expected:
   only sound on that device becomes quieter; the default output is unaffected.
4. Change the default device's volume using macOS. Expected: its slider reflects
   the change within two seconds while the Audio tab is open.
5. With no per-app adjustments active, move a device slider. Expected: no audio
   recording permission prompt and no new purple audio privacy indicator.
6. Connect an output with no software volume control, such as a fixed-volume
   HDMI output. Expected: a message to use its own controls, not a working slider.
7. Disconnect a device while adjusting it. Expected: no change to another
   output's volume; the disconnected row disappears on the next refresh.
8. Set a stereo balance in macOS, then change device volume. Expected: balance
   is preserved. Restore the original balance after checking.
9. Press **Reset App Volumes and Outputs**, then quit and reopen Switchboard.
   Expected: the device volumes remain at their chosen levels.

## Clipboard history

1. Copy three distinct text snippets, waiting at least one second between copies.
   Expected: newest first, no loss of line breaks when expanded.
2. Copy the same snippet twice. Expected: one entry. Recopy an older entry.
   Expected: it moves to the top without duplication.
3. Copy 21 distinct snippets with a one-second gap. Expected: only the latest 20.
4. Copy an image. Expected: thumbnail and pixel dimensions. Click **Copy** and
   paste into Preview. Expected: the image returns correctly.
5. Copy a long paragraph. Click **Show more** or **Show all … lines**, then
   **Show less**. Expected: expansion and collapse work without clipping controls.
6. Click **Copy** on an older entry. Expected: it pastes correctly without adding
   another history entry. Click **Remove clip**. Expected: only that entry disappears.
7. Keep the mouse outside the list. Tab to Copy and Remove and activate them with
   Space. Expected: both controls remain visible and usable without hovering.
   Repeat with VoiceOver navigation if you use it.
8. Click **Clear** in the Clipboard section. Expected: history stays empty until
   a new copy; the system clipboard itself is not erased. A copy just before
   clearing must not reappear on the next poll.
9. Quit and relaunch Switchboard. Expected: history is empty. It is memory-only.
10. Copy ordinary text after a private password-manager copy. Expected: ordinary
    text records normally while a copy marked private does not.

## Restore and launch at login

1. Change a Finder preference and a Dock preference; enable Keep Awake and adjust
   audio. Open the settings gear and choose **Restore Original Settings**.
2. Expected: stored preferences return to their first recorded values, runtime
   controls stop, and audio returns to 100%. Click the restart bar and check
   Finder/Dock behavior. Press Restore again if enabled; it must be safe to repeat.
3. Remember that Restore replays the first recorded settings, which can predate
   this test session. It does not clear clipboard history or disable Launch at Login.
4. From the settings gear menu choose **Launch at Login**. Approve it in **System
   Settings > General > Login Items & Extensions** if requested.
5. Log out and in. Expected: exactly one installed Switchboard copy launches.
6. Choose **Disable Launch at Login**, log out and in again. Expected: it does not
   launch automatically. macOS's separate “reopen windows” option may also reopen apps.


## System monitor

- Select System and wait two seconds. CPU and network should move from their
  initial state to live readings. Compare memory, swap and CPU with Activity
  Monitor, allowing for different sampling intervals.
- Generate CPU/network load. Confirm graphs and traffic rates change, history
  stays within two minutes, and scrolling through battery details stays responsive.
- Close the popover or switch categories. Confirm sampling stops. Reopen System
  and verify history restarts without a CPU/network spike.
- Search for battery, CPU or network. Confirm the monitor appears with no empty
  settings card or “No matching settings” message. Clear the search.
- Check battery and adapter states on a laptop, and no-battery state on a desktop.
  Missing GPU/battery sensors must display Unavailable rather than zero.
- Open Activity Monitor using the panel button. Check keyboard navigation and
  VoiceOver labels across categories and charts.
