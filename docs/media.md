# Updating documentation images and videos

[README](../README.md) · [Contributing](../CONTRIBUTING.md)

The README and user guide use native app views with sample content. Keep the images close to what someone will see in the app. Put instructions in the Markdown beside them, where they stay readable on a phone and accessible to screen readers.

The README is a visual introduction, with a warm background, native panels, and eight short GIF demos. Each demo also has a silent MP4 and a still image. The user guide keeps the plain captures. Keep still-image and video links beside the GIFs, with the main instructions in the Markdown. App names, clips, files, disks, and system readings are sample data. Window previews and snapping scenes use example windows.

The videos show the same captioned sample frames as the GIFs. They are rendered demonstrations, not recordings of a desktop or live performance. Each step lasts three seconds. MP4 gives readers playback controls without an endlessly looping animation; the still image and written instructions provide a nonanimated alternative.

## Regenerate

On a logged-in Mac with Xcode 16 or later and Python 3.9 or later, run this from the repository root:

```sh
python3 -m venv build/docs/venv
build/docs/venv/bin/python -m pip install -r scripts/docs/requirements.txt
build/docs/venv/bin/python scripts/docs/render.py
```

The command builds the app without signing, compiles a separate documentation renderer, then creates the overview, GIF demos, and stills in `docs/images/`, plus MP4 demos in `docs/videos/`. The pinned Pillow and imageio-ffmpeg dependencies belong only to the documentation composer; the app has no Python dependency. imageio-ffmpeg includes FFmpeg in its macOS wheels, so a separate FFmpeg installation is not required. A failed build, render, or video encode exits with an error. Nothing is uploaded.

The build log is `build/docs/build.log`. All captures, including intermediate example states, are in `build/docs/captures/`.

## Files to edit

| File | What it controls |
| --- | --- |
| [Render.swift](../scripts/docs/Render.swift) | Main panels, sample clips and readings, appearance, capture size |
| [Features.swift](../scripts/docs/Features.swift) | Audio and shelf examples, sample disk eject, screen-text recognition |
| [Windows.swift](../scripts/docs/Windows.swift) | Example windows, native switcher and snapping grid |
| [compose.py](../scripts/docs/compose.py) | Overview layout, demo steps, captions, GIF/MP4 timing, and native image exports |
| [render.py](../scripts/docs/render.py) | Build and capture setup |
| [requirements.txt](../scripts/docs/requirements.txt) | Pinned image and video tooling |

To rebuild the presentation from existing captures, run `build/docs/venv/bin/python scripts/docs/compose.py`. Run the full renderer after changing the app or sample content. GIF frames share a palette to keep colours steady between steps. MP4 files use H.264 with `yuv420p`, 10 frames per second, and the same dimensions and step duration as their GIF. Fast-start metadata allows playback before the full download finishes. Each video is encoded to a temporary file and replaces its previous version only after encoding succeeds. Native captures for the guide are copied unchanged.

Use ordinary example text instead of taglines. Keep captions short and label sample content. Don't describe rendered views as desktop screenshots or recordings.

## Published demos

| Demo | GIF | MP4 | Still |
| --- | --- | --- | --- |
| Per-app audio | [GIF](images/app-audio.gif) | [Video](videos/app-audio.mp4) | [Image](images/app-audio.png) |
| File shelf | [GIF](images/file-shelf.gif) | [Video](videos/file-shelf.mp4) | [Image](images/file-shelf-workflow.png) |
| Disk eject | [GIF](images/disk-eject.gif) | [Video](videos/disk-eject.mp4) | [Image](images/disk-eject.png) |
| Window switcher | [GIF](images/window-switcher.gif) | [Video](videos/window-switcher.mp4) | [Image](images/window-switcher-demo.png) |
| Window snapping | [GIF](images/window-snapping.gif) | [Video](videos/window-snapping.mp4) | [Image](images/window-snapping.png) |
| Snapping grid | [GIF](images/window-grid.gif) | [Video](videos/window-grid.mp4) | [Image](images/window-grid-demo.png) |
| Screen text | [GIF](images/screen-text.gif) | [Video](videos/screen-text.mp4) | [Image](images/screen-text.png) |
| System monitor | [GIF](images/system-monitor.gif) | [Video](videos/system-monitor.mp4) | [Image](images/system-monitor.png) |

The System demo uses `system-cpu.png`, `system-memory.png`, and `system-readouts.png` from `build/docs/captures/`. These show CPU and memory sorting, then the menu bar readout choices. They are also copied to `docs/images/` for the guide. Any illustrated menu bar values are labeled as examples. `system-dark.png` remains the general System panel image.

## How the examples stay separate from your data

The renderer compiles temporary copies of app sources. It removes startup and audio-refresh work from `TweakStore`, disables live sampling in `SystemMonitor`, and makes sample state assignable. It exposes the private switcher, grid, process list, and menu bar readout views in those temporary copies. Production files are unchanged. Source markers are checked so a renamed method fails the render instead of silently leaving live behaviour enabled.

The System examples use sample processes without looking up real process IDs. Quit buttons reflect sample eligibility; their action fails immediately if called, so the renderer cannot quit an app through those buttons. Readout examples use the app's formatter with sample readings.

Window examples use providers that fail if asked to enumerate, capture, focus, or quit real windows. Snapping positions come from `WindowLayout` and `SnapGrid`; no real window is moved.

The text example runs `TextCapture.recognise` against a generated meeting note and checks the result. Recognised text is saved to `build/docs/captures/recognised-text.txt` and shown in the clipboard view. It never reaches your clipboard.

Shelf files live under `build/docs/captures/Sample files`. Disk eject uses a stand-in service that only removes the example drive from its own list. No real disk is ejected, no audio tap is started, and no clipboard history is read.

The renderer has a separate app identity, a disposable preferences suite, and a private pasteboard. Those preferences and the pasteboard are removed when rendering finishes. It doesn't launch your installed Switchboard copy or change its settings. Its update checker is never started, so rendering does not check GitHub for a release.

## Check before committing

1. Regenerate from the source you intend to release.
2. Open each published image and inspect every GIF frame. Check for clipped text, missing icons, incorrect sample state, and readable captions. Keep the still-image and MP4 links beside the demos.
3. Decode each MP4 and check that its dimensions, captions, step order, and duration match the GIF. Play each video in a browser or QuickTime; check seeking, the first and last steps, and that there is no audio track. Preview the README and guide at desktop and phone widths, in light and dark themes. Images should fit the page, and the instructions should make sense without them.
4. Check local links and image alt text. Compare control names, defaults, and permissions with the app.
5. Before a release, follow the install and clipboard instructions using the release DMG. Rendering source views doesn't verify signing, notarization, or a clean install.

Media was refreshed in October 2026. The release download may lag behind the source shown here.
