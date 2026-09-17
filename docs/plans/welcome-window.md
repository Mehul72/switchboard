# Plan: welcome window for a new copy of the app

Status: done (manual checks in CONTRIBUTING outstanding)

## Goal
The first launch of a newly installed copy of Switchboard opens a welcome
window. Relaunching that same copy never shows it again, including after a
quit, a crash, a login launch, or quitting with the welcome still open.
Deleting the app and installing it again shows it again.

Verifiable by unit tests on the gate and on copy identity, and by launching a
build with its own bundle identifier: first launch shows the window, relaunch
does not, a fresh `cp -R` of the bundle shows it, and an `mv` of the bundle
does not.

## Decided already (user, 2026-09-17)
- "Every new copy": macOS has no uninstall event and dragging the app to the
  Trash leaves its preferences behind, so a first-launch flag alone cannot see
  a reinstall. A copy is identified by the app bundle's inode. Updates from a
  new DMG replace the bundle, so they show the welcome too; the user accepted
  that.

## Decided while planning
- Copy ID is the bundle directory's inode plus CFBundleVersion. APFS never
  reuses an inode, so a reinstall always gets a new one. Moving the app
  within a volume (Downloads to Applications) keeps it. The build number
  guards against inode reuse across volumes, such as two disk images.
- App Translocation (running from Downloads without moving) keeps the inode:
  xnu nullfs `nullfs_getattr` passes the lower vnode's attributes through and
  only rewrites the fsid. Volume UUID is therefore not part of the ID.
- Shown copy IDs are kept as a list in UserDefaults, not a single value, so
  switching between two copies (a debug build and the installed app) does not
  re-show it. The list keeps the 20 most recent IDs.
- The copy is recorded before the window opens, so quitting with it open does
  not bring it back.
- If the bundle cannot be stat'ed, do not show it and log the error. Showing
  on every launch is the worse failure.
- Content: brand mark, where the menu bar icon is and the current Show
  Switchboard shortcut, one line per area (Tweaks, Audio, Clipboard, System,
  Window snapping), a permissions note, and a default button that closes the
  welcome and opens the panel under the menu bar icon.

## Out of scope
- Launch at Login or permission prompts inside the welcome.
- Warning about running outside Applications.
- A way to reopen the welcome from the settings menu.

## Steps
- [x] 1. `AppCopy` identity and `WelcomeGate` with tests
      files: Switchboard/Services/WelcomeGate.swift,
             SwitchboardTests/WelcomeGateTests.swift, project.pbxproj
      done when: tests pass for first claim, second claim, relaunch with a new
      gate, list cap, corrupt stored value, ID stable across calls and a
      rename, ID changes after delete and recreate
- [x] 2. Welcome window and wiring at launch
      files: Switchboard/Views/WelcomeView.swift,
             Switchboard/App/StatusItemController.swift,
             Switchboard/App/SwitchboardApp.swift, project.pbxproj
      done when: full test suite passes; a build with a separate bundle ID
      shows the window on first launch, not on relaunch, again after
      `cp -R`, not after `mv`
- [x] 3. README and CONTRIBUTING
      done when: README mentions the welcome window; CONTRIBUTING's manual
      checklist covers reinstall and update

## Open questions
None.

## Log
- 2026-09-17 step 1: 12 WelcomeGateTests pass. Tried to confirm translocation
  keeps the inode by calling SecTranslocateCreateSecureDirectoryForURL; it
  returned EPERM from a command-line probe, so the evidence is the xnu nullfs source.
  Added least-recently-launched eviction so the running copy is never dropped.
- 2026-09-17 step 2: 226 tests pass. Live check with bundle ID
  com.Mehul72.switchboard.welcomecheck, every instance killed with SIGTERM:
  first launch shows it; two relaunches do not; mv to another folder (same
  inode) does not; cp -R shows it; relaunching the original after that does
  not; rm and cp -R again shows it; relaunch does not. Return closes it and
  opens the panel under the menu bar icon. Escape did nothing with
  onExitCommand (probably because the hosting view is not in the responder
  chain; not confirmed); the Close
  button now carries .cancelAction and Escape works. Checked light and dark.
  System row icon changed to match the panel's System tab.
