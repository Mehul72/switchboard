# Contributing to Switchboard

Notes for changing and releasing the app. If you only want to use Switchboard,
the [README](README.md) is all you need.

## Building from source

Only needed if you want to change Switchboard. To use it, download the disk
image above.

Requires Xcode 16 or later on macOS 14.2 or later.

1. Clone the repository and open `Switchboard.xcodeproj`.
2. Select the **Switchboard** scheme and the **My Mac** destination.
3. Press **Command-R**.

The app has no package dependencies. It is deliberately not App Sandbox enabled,
because it must write macOS preference domains outside its own container.

Debug builds sign with your own Apple Development certificate, so a build of
your own needs its Accessibility permission granted separately from a release
copy.

## Releasing

Debug builds sign with your Apple Development certificate. Release builds sign
with Developer ID and enable the Hardened Runtime, which notarisation requires.

Store your notary credentials once, using an app specific password from
appleid.apple.com rather than your Apple ID password:

```
xcrun notarytool store-credentials switchboard-notary \
    --apple-id you@example.com --team-id MACDPWQG37
```

Omitting `--password` makes notarytool prompt for it securely, so it never
enters your shell history. Create the app specific password at
account.apple.com under Sign-In and Security. It is shown once, so store it in
your password manager; if you lose it, revoke it and generate another.

Then:

```
./scripts/release.sh
```

It bumps the build number, archives, exports with Developer ID, verifies the
signature, notarises, staples the ticket, and writes a stapled disk image to
`build/`. Upload that `.dmg` to a GitHub release.

Stapling is not optional. Without it the app refuses to launch for anyone whose
Mac cannot reach Apple to check the notarisation.

## Adding a preference

Add one `Tweak` to `TweakCatalog`; the interface chooses its control from the
model:

```swift
Tweak(id: "dock.hide-recents",
      title: "Hide recent apps",
      category: .dock,
      symbol: "clock.arrow.circlepath",
      domain: "com.apple.dock", key: "show-recents",
      onValue: .bool(false), offValue: .bool(true), restart: .dock)
```

Omit `offValue` when disabling the setting should delete the preference and hand
behaviour back to macOS. Runtime features such as Keep Awake, Region OCR,
per-app audio, clipboard cleanup, clipboard image conversion, and quit-on-close
live in `Services` rather than as preference-only rows.
