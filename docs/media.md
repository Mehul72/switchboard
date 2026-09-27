# Maintaining the repository visuals

[README](../README.md) · [Contributing](../CONTRIBUTING.md)

The README media combines native app views rendered from this checkout with labelled sample content and illustrated interaction steps. They are not desktop captures or interactive recordings. The general tour is a four-slide, 20-second GIF. Feature GIFs demonstrate window switching, keyboard snapping, Control-drag snapping, per-app audio, file collection, disk ejection, and screen text capture. App names, clipboard entries, files, disks, and system readings are examples.

## Regenerate

Use a logged-in macOS desktop with Xcode 16 or later and Python 3.9 or later. From the repository root:

```sh
python3 -m venv build/docs/venv
build/docs/venv/bin/python -m pip install -r scripts/docs/requirements.txt
build/docs/venv/bin/python scripts/docs/render.py
```

The command builds the app without signing, compiles a separate documentation renderer, captures its native views, and replaces the assets in `docs/images/`. The build log is `build/docs/build.log`; uncomposed captures are in `build/docs/captures/`. A failed build or render exits with an error. Nothing is uploaded.

The renderer compiles temporary copies of the app sources. In the temporary `TweakStore`, it removes startup and audio-refresh work, makes published state assignable, and derives the audio-active label from sample routes. In `SystemMonitor`, it disables live sampling and makes sample readings assignable. In `WindowSwitcher`, it makes sample window state assignable. It exposes the private `WindowSwitcherView` and `GridCanvas` types only in temporary copies, leaving their rendering code unchanged. Missing source markers fail the render so a renamed method cannot silently defeat isolation.

Window examples use a mock inventory and preview provider that fail if asked to enumerate, capture, focus, or quit real windows. Snapping renders an example document at positions calculated by `WindowLayout` and `SnapGrid`; it never moves a real app window.

The screen-text example runs `TextCapture.recognise` against the generated sample image and verifies its expected text. Its result is saved in `build/docs/captures/recognised-text.txt` and displayed in the native clipboard view. The selection rectangle is an illustration, not a capture of the macOS region picker. Nothing is copied to the real clipboard. Audio values are sample state. The eject sequence runs the shelf's own eject handling against a stand-in for macOS that reports success and only removes the sample drive from its list, so the final frame shows the app's real confirmation.

No live clipboard history is recorded, no audio tap is started, and no real disk is ejected. File examples, including a generated sample image, live under `build/docs/captures/Sample files`. Disk actions reach only that stand-in, never macOS. The renderer uses a separate app identity and an isolated appearance preference suite. It does not launch the installed Switchboard app or change its appearance.

## What to edit

| File | Purpose |
| --- | --- |
| [Render.swift](../scripts/docs/Render.swift) | Sample app state, native views, capture dimensions, and appearances. |
| [Features.swift](../scripts/docs/Features.swift) | Audio and shelf states, the stand-in disk eject, and verified sample image recognition. |
| [Windows.swift](../scripts/docs/Windows.swift) | Sample documents, native switcher states, layout calculations, and native drag-grid renders. |
| [compose.py](../scripts/docs/compose.py) | Layout, colours, typography, captions, and GIF slides. Each GIF shares one palette so colours stay stable between frames. |
| [render.py](../scripts/docs/render.py) | Build, temporary source isolation, and capture orchestration. |

The app itself has no Python dependency. Pillow is only used to compose documentation artwork.

## Before shipping a UI change

1. Regenerate the assets from the source you intend to release.
2. Open the PNGs at full size and at README width. Check text, native controls, clipping, light/dark appearance, and sample-data captions.
3. View every frame of each GIF. Keep instructions consistent with the static guide. Preserve the still-image links and the collapsed general tour. Feature GIFs are displayed directly in the README.
4. Check the README and guide links. Update menu names, defaults, permissions, and the first-run instructions against the app.
5. Preview the README in both GitHub themes and at a narrow width. Local Markdown previews may not match GitHub's sanitised HTML exactly.
6. Follow the install and clipboard exercise using the release DMG. A source build does not verify signing, notarization, or installation on a clean Mac.

The repository captures were refreshed in September 2026. They describe the current source; the download may lag until that source is released.
