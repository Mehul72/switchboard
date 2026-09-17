# Switchboard

A macOS menu bar app for everyday settings, per-app audio, clipboard history,
and system monitoring. Requires macOS 14.2 or later.

## Install

1. Download the DMG from the [latest release](https://github.com/Mehul72/switchboard/releases/latest).
2. Open it and drag Switchboard into **Applications**.
3. Launch Switchboard from Applications. A welcome window shows where the
   menu bar icon is and what each section does.

The welcome window opens once for each installed copy of the app. Relaunching
never shows it again. Deleting Switchboard and installing it again shows it,
and so does installing an update from a new DMG, because that also replaces
the app.

Keep the app in Applications. Running it from Downloads or the disk image can
cause problems with permissions and Launch at Login.

## Features

- **Tweaks:** keep your Mac awake, copy text from the screen, quit apps when
  their last window closes, change mouse scrolling independently of the
  trackpad, and adjust Finder, screenshot, and Dock settings.
- **Audio:** adjust volume and output devices per app, or change a connected
  device's overall volume.
- **Clipboard:** keep the last 20 text and image clips ready to copy again.
- **System:** view CPU, GPU, memory, network, disk, and battery readings.
  Some sensors are unavailable on certain Macs.
- **Global shortcuts:** open the panel or clipboard history, capture screen
  text, and toggle keep-awake without leaving the keyboard.
- **Window snapping:** move windows into halves, quarters, thirds, or onto
  another display with keyboard shortcuts, or drag them onto a grid.

## Using Switchboard

Search across all settings with **Command-F**. **Escape** clears the search;
press it again to close the panel. Tweaks are grouped into Everyday, Files,
Capture, and Dock. Your last category is remembered when you return to Tweaks.

Most changes apply immediately. Settings that need Finder or the Dock to restart
show a restart button, so you can apply several changes together. Some global
settings take effect when affected apps reopen.

The settings gear contains **Keyboard Shortcuts**, **Launch at Login**,
**Restore Original Settings**, and **Quit Switchboard**. Restore Original
Settings puts system preferences back to the values they had before Switchboard
changed them. Shortcut bindings are managed separately.

### Global shortcuts

These shortcuts work from any app while Switchboard is running. Actions run
once when you release the shortcut key.

| Action | Default shortcut |
| --- | --- |
| Show or hide Switchboard | Control-Option-Command-S |
| Open clipboard history | Control-Option-Command-V |
| Copy text from the screen | Control-Option-Command-T |
| Toggle keep-awake | Control-Option-Command-A |

Keep-awake starts a one-hour session when off and stops any active session,
then opens the panel so you can see the new state.
Text capture opens the region selector directly, then shows the result in the
panel. Other shortcuts are paused while a capture is in progress.

### Window snapping

Switch on **Snap windows** in Everyday. It needs Accessibility access and is
off by default, because its shortcuts take common Control-Option combinations
away from other apps. While it is off, window shortcuts are not registered, but
you can still change their bindings.

**Arrow keys.** Control-Option-arrows move a window around a map of layouts:

- **Up** goes to full screen from any layout. From full screen, Up gives the
  top half.
- Left from full screen gives the left half, then the left third. Right from
  the left half goes back to full screen. From any third, Left and Right move
  between the left, centre, and right thirds.
- Left and Right keep a window's row, so full screen, Up, Left gives the
  top-left quarter, and Left again the top-left third.
- **Down** joins a top-row layout back to full height, then gives the bottom
  half of that width. Full screen plus Down is the bottom half of the screen.
- A window that is on no layout starts at the left half, right half, full
  screen (Up), or bottom half (Down). At the edge of the map the Mac beeps.

**Dragging.** Start dragging a window by its title bar, then hold **Control**.
A grid of six columns and two rows appears. The cell under the pointer when you
press Control is where the layout starts; move across cells to extend it, then
release the mouse. Three columns make a half and two make a third. Release
Control before the mouse to drop the window normally. Option is not used
because macOS uses it for its own tiling during a drag.

**Other shortcuts** jump straight to a layout:

| Action | Default shortcut |
| --- | --- |
| Top-left, top-right, bottom-left, bottom-right quarter | Control-Option-U, I, J, K |
| Left, centre, or right third | Control-Option-D, F, G |
| Left or right two thirds | Control-Option-E, T |
| Maximise | Control-Option-Return |
| Centre | Control-Option-C |
| Restore previous size | Control-Option-Delete |
| Move to next or previous display | Control-Option-Command-Right or Left |

Shortcuts act on the focused window of the frontmost app. Maximise fills the
screen without entering full screen. Moving to another display keeps the
window's relative position and size. Restore returns a window to where it was
before its first snap or drag; moving the window by hand starts a new run. Windows that
cannot be resized keep their size and move against the matching screen edge.
Full-screen windows and Switchboard's own windows are not moved; the Mac beeps
instead.

### Customising shortcuts

Open **settings gear > Keyboard Shortcuts** to customise a binding. Click its
shortcut button and press a combination containing Control or Option, or
Command with another modifier. Use letters, numbers, punctuation, arrows,
Return, Delete, Space, or F1 to F12. A global shortcut takes the combination
away from every app: Option plus a letter stops typing characters such as å, and Control plus a
letter can replace text editing keys such as Control-A. Bindings follow physical key positions; labels reflect the keyboard layout.
Press **Escape** to cancel, **Delete** to disable, or **Tab** to leave recording.
Each row's options menu also provides **Restore Default** and **Disable Shortcut**.
Changes take effect immediately and survive relaunch.

Conflicting shortcuts show an error and keep the previous binding. macOS or
another app may consume a combination before the recorder receives it; choose
another if that happens. If a saved shortcut is unavailable at launch, close
the app using it and choose **Retry Unavailable Shortcuts**, or record another.

Global shortcut registration needs no additional permission. Screen text
capture still needs Screen Recording access, and window snapping needs
Accessibility.

### Permissions

macOS asks for access when you first use a feature that needs it.

| Feature | Permission |
| --- | --- |
| Traditional mouse scrolling, red-button quit, and window snapping | Accessibility |
| Copy text from the screen | Screen Recording |
| Per-app audio controls | System Audio Recording |

If a toggle stays off while you grant access, enable it again afterward.
Permissions are managed in **System Settings > Privacy & Security**. Launch at
Login may also need approval under **General > Login Items**.

### Audio

Apps appear after opening an audio stream. Lowering an app's volume or choosing
another output uses a Core Audio tap, so macOS shows a purple recording indicator
while that control is active. These controls work while Switchboard is running.

**Reset app audio** returns apps to full volume on the system default output and
releases their taps. A chosen output is remembered per app; if it disconnects,
playback falls back to the default output.

Expand **Output devices** to control a device's overall volume. These sliders
affect every app using that device and do not need recording access. Device
volume changes remain in place when app audio is reset or Switchboard quits.

### Screenshots and clipboard

When clipboard screenshots are set to JPEG or HEIC, Switchboard converts new
captures while it runs. The clipboard includes the chosen format and a matching
file. Some receiving apps still convert image data to PNG when pasting.

Clipboard history stays in memory and is cleared when Switchboard quits.
Content marked private by a password manager is skipped. Switchboard does not
send clipboard content or usage data to a server.

## Development

Open `Switchboard.xcodeproj` in Xcode, select **Switchboard > My Mac**, and run
with **Command-R**. The app has no package dependencies.

See [CONTRIBUTING.md](CONTRIBUTING.md) for testing, artwork, and release instructions.
