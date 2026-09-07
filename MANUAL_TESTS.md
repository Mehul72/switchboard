# Switchboard manual feature checks

Run these against the newly built app. These are instructions and expected results,
not a claim that the live checks have already passed. Automated audit results are
in [AUDIT.md](AUDIT.md).

## Before starting

1. Quit any other copy of Switchboard using its ellipsis menu.
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

1. Click the linked-points menu-bar icon. Expected: the panel opens fully onscreen.
2. Visit Everyday, Files, Capture, Dock, Audio, and Clipboard. Expected: each tab
   displays its own controls and scrolls to its last row.
3. Search for `hidden`, `volume`, and `clipboard` separately. Expected: matching
   settings or the relevant special list appear.
4. Search for `no-such-setting-928`. Expected: **No matching settings**.
5. Press Escape once with a search present. Expected: search clears. Press again.
   Expected: panel closes. Reopen it and click outside. Expected: it closes.
6. Repeat on a smaller display if available. Expected: bottom controls remain reachable.

## Everyday

### Keep Mac awake

1. Select **30 minutes**. In Terminal, run `pmset -g assertions`.
   Expected: a Switchboard sleep-prevention assertion is listed.
2. Select **1 hour**, **2 hours**, and **Until I stop it** in turn. Reopen the panel
   after each selection. Expected: the selected duration remains correct.
3. Select **Off** and rerun the command. Expected: Switchboard's assertion disappears.
4. Select **30 minutes**, leave it running for the full duration, and reopen the
   panel. Expected: Off is selected and the expiry notice appears.
5. Enable it again and quit Switchboard. Expected: its assertion disappears.
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
   A receiving app may convert it to PNG. For exact encoding, the automated
   conversion tests inspect the pasteboard and image bytes directly.
5. Capture a large image, then immediately copy some text. Expected: a finishing
   image conversion must not replace the newer text.
6. **Skip the floating thumbnail:** enable and capture. Expected: immediate save,
   no thumbnail. Disable and capture. Expected: the thumbnail returns.
7. **Remove window shadows:** press Command-Shift-4, then Space and click a window.
   Compare captures with the setting on and off. Expected: only the off capture
   includes the surrounding shadow. Region captures do not test this setting.
8. Quit Switchboard with clipboard JPEG/HEIC enabled and capture again. The macOS
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
6. Reduce both apps, then press **Reset All Volumes**. Expected: all sliders show
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

**Current limitation:** reduced volume requires continuous audio processing.
The dot cannot disappear after five seconds of continuous reduced-volume playback
with this implementation. Reset stops the processing by returning volume to 100%.

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
   audio. Click **Restore Original Settings**.
2. Expected: stored preferences return to their first recorded values, runtime
   controls stop, and audio returns to 100%. Click the restart bar and check
   Finder/Dock behavior. Press Restore again if enabled; it must be safe to repeat.
3. Remember that Restore replays the first recorded settings, which can predate
   this test session. It does not clear clipboard history or disable Launch at Login.
4. From the ellipsis menu choose **Launch at Login**. Approve it in **System
   Settings > General > Login Items & Extensions** if requested.
5. Log out and in. Expected: exactly one installed Switchboard copy launches.
6. Choose **Disable Launch at Login**, log out and in again. Expected: it does not
   launch automatically. macOS's separate “reopen windows” option may also reopen apps.
