# Switchboard

A macOS menu bar app for everyday settings, per-app audio, clipboard history,
and system monitoring. Requires macOS 14.2 or later.

## Install

1. Download the DMG from the [latest release](https://github.com/Mehul72/switchboard/releases/latest).
2. Open it and drag Switchboard into **Applications**.
3. Launch Switchboard from Applications and click its menu bar icon.

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

## Using Switchboard

Search across all settings with **Command-F**. **Escape** clears the search;
press it again to close the panel. Tweaks are grouped into Everyday, Files,
Capture, and Dock. Your last category is remembered when you return to Tweaks.

Most changes apply immediately. Settings that need Finder or the Dock to restart
show a restart button, so you can apply several changes together. Some global
settings take effect when affected apps reopen.

The settings gear contains **Launch at Login**, **Restore Original Settings**,
and **Quit Switchboard**. Restore Original Settings puts preferences back to the
values they had before Switchboard changed them.

### Permissions

macOS asks for access when you first use a feature that needs it.

| Feature | Permission |
| --- | --- |
| Traditional mouse scrolling and red-button quit | Accessibility |
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
