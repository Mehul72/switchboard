# Switchboard

Switchboard is a free menu bar app for macOS that fixes small, recurring
annoyances in the system. It puts twenty two settings in one panel, most of
which macOS either buries or does not expose at all, and it can read text off
your screen, set the volume of one app without touching the rest, and remember
what you copied.

It lives in the menu bar, has no Dock icon, and sends nothing anywhere.

Requires macOS 14.2 or later, on Apple silicon or Intel.

## Install

1. Download **Switchboard.dmg** from the
   [latest release](https://github.com/Mehul72/switchboard/releases/latest).
2. Open the downloaded `.dmg`.
3. Drag **Switchboard** onto the **Applications** shortcut in the window.
4. Open your Applications folder and double click Switchboard.
5. The Switchboard icon appears at the right of the menu bar. Click it to open
   the panel.

There is no installer and no background helper. To uninstall, quit Switchboard
from the panel's menu and drag it from Applications to the Trash.

**Do not run it from Downloads or from inside the disk image.** macOS copies an
app launched from either place into a temporary read only location, and any
permission you grant follows that throwaway copy. Features then look enabled and
do nothing. Drag it to Applications first.

Switchboard is signed with an Apple Developer ID and notarised by Apple, so it
opens without a security warning.

## Everything it does

The panel has six tabs. Search at the top to find any setting by name.

### Everyday

| Setting | What it does |
| --- | --- |
| **Keep Mac awake** | Stops the display sleeping and the Mac idling, for 30 minutes, 1 hour, 2 hours, or until you switch it off. Useful for long downloads, builds and presentations. It tells you when the time is up, and always releases if you quit the app. |
| **Copy text from the screen** | Click **Select Area** and drag over anything at all: a screenshot, a video frame, an error dialog, a scanned PDF. The text is recognised and put on your clipboard, and also lands in the Clipboard tab so you can read it. Works on text you could never normally select. |
| **Red button quits the app** | Makes the red traffic light button behave like Command-Q rather than only closing the window, so apps stop piling up in the Dock. Apps also quit when their last window closes, which covers browsers closing their final tab. It sends a normal quit request, so anything unsaved still prompts you. |
| **Show scroll bars** | Automatic, always visible, or only while scrolling. |
| **Traditional mouse scrolling** | Reverses the scroll direction for a mouse wheel while leaving the trackpad natural. macOS has one shared setting for both, so this is the fix if you switch between a mouse and a trackpad and keep flipping it. |
| **Strip clipboard formatting** | Replaces whatever you copied with its plain text, dropping fonts, colours and links, so it pastes cleanly. |

### Files

Every setting here takes effect once Finder relaunches. Switchboard shows a bar
with a single button for that, and keeps the panel open while it happens.

| Setting | What it does |
| --- | --- |
| **Show hidden files** | Reveals dotfiles and other hidden items in Finder. |
| **Show all file extensions** | Shows `.png`, `.txt` and the rest on every file, including the ones macOS hides. |
| **Show full path in Finder title** | Puts the full folder path in the window title instead of just the folder name. |
| **Keep folders on top** | Groups folders above loose files when a window is sorted by name. |
| **Search the current folder** | Command-F searches the folder you are looking at rather than the whole Mac. |
| **Skip extension warnings** | Stops Finder asking for confirmation every time you rename a file extension. |
| **Hide desktop icons** | Clears the desktop to bare wallpaper. Nothing is deleted; the files stay in your Desktop folder. |
| **No .DS_Store on network drives** | Stops macOS scattering `.DS_Store` files across shared drives. Applies the next time a drive is mounted. |

### Capture

These apply to your very next screenshot. No restart, no logout.

| Setting | What it does |
| --- | --- |
| **Save screenshots to** | Choose the folder new screenshots are written to, instead of the Desktop. |
| **Copy screenshots to clipboard** | Sends captures straight to the clipboard with no file written, ready to paste. |
| **Screenshot format** | PNG, JPEG or HEIC. JPEG and HEIC produce far smaller files. macOS ignores this for clipboard captures and always makes a PNG, so Switchboard converts those itself, keeping the Retina scale so pasted images are not doubled in size. |
| **Skip the floating thumbnail** | Removes the preview that hovers in the corner, writing the file immediately. |
| **Remove window shadows** | Drops the large shadow and its transparent margin from window captures, the ones taken with Command-Shift-4 then Space. |

Use the keyboard shortcuts to test these. The `screencapture` terminal command
ignores these preferences entirely and always writes a PNG.

### Dock

These take effect once the Dock relaunches, again with one button in the panel.

| Setting | What it does |
| --- | --- |
| **Reveal hidden Dock instantly** | Removes the delay before an auto hidden Dock slides back. Only does anything if you have the Dock set to hide. |
| **Hide recent apps** | Removes the recently used apps macOS appends to the Dock. |
| **Minimise into app icons** | Minimised windows collapse into their app's icon rather than piling up as separate Dock tiles. |

### Audio

A live list of every app currently able to play sound, each with its own volume
slider. Turn one app down without touching anything else, or your main volume.
Apps that are actually playing sort to the top, and helper processes are grouped
under the app you recognise.

macOS has no per application volume control and exposes no setting for one, so
Switchboard captures that app's audio and replays it at your chosen level. Set a
slider back to 100% and the app is handed straight back to the system. If
Switchboard quits, macOS restores normal audio on its own.

### Clipboard

The last 20 things you copied, text or image, newest first. Hover an entry to
copy it back or remove it; click to select and read the text; long entries
expand. Text you captured from the screen appears here too, labelled, which is
where you go to read it.

**It is never written to disk.** The history lives in memory and is gone the
moment Switchboard quits. Anything a password manager marks as private is
skipped entirely, so copied passwords are never recorded.

## Permissions

Most of Switchboard needs nothing. Three features do, and macOS asks the first
time you use each one.

| Feature | Permission |
| --- | --- |
| Traditional mouse scrolling, Red button quits the app | Accessibility |
| Copy text from the screen | Screen Recording |
| Per app volume | Audio Recording |

Grant them in **System Settings > Privacy & Security**. Switching a feature on
before its permission exists opens the prompt and leaves the switch off; grant
the permission, then switch it on again.

Because Switchboard is signed with a stable Developer ID, a permission granted
once keeps working across updates.

## Undoing everything

Switchboard records what every setting looked like before it first changed it,
including settings that were never set at all. **Restore Original Settings** at
the bottom of the panel puts them all back and releases anything still running.

## What it never does

- No data leaves your Mac. There is no networking code in the app.
- No clipboard history is written to disk.
- No background helper, and no login item unless you turn one on.
- It changes documented macOS preferences, the same ones the `defaults` command
  reads and writes.
