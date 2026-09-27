# Updating documentation images

[README](../README.md) · [Contributing](../CONTRIBUTING.md)

The README and user guide use native app views with sample content. Keep the images close to what someone will see in the app. Put instructions in the Markdown beside them, where they stay readable on a phone and accessible to screen readers.

The README is a visual introduction, with a warm background, native panels, and seven short GIF demos. The user guide keeps the plain captures. Each demo has a still-image link, and its main instructions also appear in the Markdown. Window previews and snapping scenes use example windows, not a recording of someone's desktop. App names, clips, files, disks, and system readings are sample data.

## Regenerate

On a logged-in Mac with Xcode 16 or later and Python 3.9 or later, run this from the repository root:

```sh
python3 -m venv build/docs/venv
build/docs/venv/bin/python -m pip install -r scripts/docs/requirements.txt
build/docs/venv/bin/python scripts/docs/render.py
```

The command builds the app without signing, compiles a separate documentation renderer, then creates the overview, GIF demos, and stills in `docs/images/`. Pillow is used only by the documentation composer; the app has no Python dependency. A failed build or render exits with an error. Nothing is uploaded.

The build log is `build/docs/build.log`. All captures, including intermediate example states, are in `build/docs/captures/`.

## Files to edit

| File | What it controls |
| --- | --- |
| [Render.swift](../scripts/docs/Render.swift) | Main panels, sample clips and readings, appearance, capture size |
| [Features.swift](../scripts/docs/Features.swift) | Audio and shelf examples, sample disk eject, screen-text recognition |
| [Windows.swift](../scripts/docs/Windows.swift) | Example windows, native switcher and snapping grid |
| [compose.py](../scripts/docs/compose.py) | Overview layout, demo steps, captions, GIF timing, and native image exports |
| [render.py](../scripts/docs/render.py) | Build and capture setup |

To rebuild the presentation from existing captures, run `build/docs/venv/bin/python scripts/docs/compose.py`. Run the full renderer after changing the app or sample content. GIF frames share a palette to keep colours steady between steps. Native captures for the guide are copied unchanged.

Use ordinary example text instead of taglines. Keep captions short and label sample content. Don't describe rendered views as desktop screenshots or recordings.

## How the examples stay separate from your data

The renderer compiles temporary copies of app sources. It removes startup and audio-refresh work from `TweakStore`, disables live sampling in `SystemMonitor`, and makes sample state assignable. It exposes the private switcher and grid views in those temporary copies. Production files are unchanged. Source markers are checked so a renamed method fails the render instead of silently leaving live behaviour enabled.

Window examples use providers that fail if asked to enumerate, capture, focus, or quit real windows. Snapping positions come from `WindowLayout` and `SnapGrid`; no real window is moved.

The text example runs `TextCapture.recognise` against a generated meeting note and checks the result. Recognised text is saved to `build/docs/captures/recognised-text.txt` and shown in the clipboard view. It never reaches your clipboard.

Shelf files live under `build/docs/captures/Sample files`. Disk eject uses a stand-in service that only removes the example drive from its own list. No real disk is ejected, no audio tap is started, and no clipboard history is read.

The renderer has a separate app identity and appearance preference suite. It doesn't launch your installed Switchboard copy or change its appearance.

## Check before committing

1. Regenerate from the source you intend to release.
2. Open each published image and inspect every GIF frame. Check for clipped text, missing icons, incorrect sample state, and readable captions. Keep the still-image links beside the demos.
3. Preview the README and guide at desktop and phone widths, in light and dark themes. Images should fit the page, and the instructions should make sense without them.
4. Check local links and image alt text. Compare control names, defaults, and permissions with the app.
5. Before a release, follow the install and clipboard instructions using the release DMG. Rendering source views doesn't verify signing, notarization, or a clean install.

Images were refreshed in September 2026. The release download may lag behind the source shown here.
