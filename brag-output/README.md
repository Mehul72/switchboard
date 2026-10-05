# Switchboard product video

[Video](brag.mp4) · [Poster](brag.jpg) · [Share copy](share-copy.txt) · [Storyboard](brag-plan.md) · [Composition brief](composition-brief.md)

A 30-second, **3840 × 2160 (4K)**, 30 fps product tour covering per-app audio, clipboard history, screen text, the file shelf, window switching, keyboard snapping, and System readings. The window scenes take 7.10 seconds of the film.

Native app views with sample content, simulated interactions, and restrained animation illustrate each feature. This is not a desktop recording. Music and a few sound effects accompany the video; there is no narration. Native sources were captured at four pixels per logical point for this 4K export. A local backup of the preceding 25-second cut and source is under the ignored `build/docs/brag-v2/` directory.

## Edit and rebuild locally

Use Node.js 22 or later, npm, FFmpeg and FFprobe on `PATH`, and the Chrome build managed by Hyperframes. On macOS, `brew install ffmpeg` supplies both FFmpeg and FFprobe. The npm scripts pin Hyperframes **0.8.127**; `package-lock.json` pins GSAP **3.14.2** for `npm ci`.

From the repository root:

```sh
cd brag-output/composition
npm ci
npx --yes hyperframes@0.8.127 doctor
npx --yes hyperframes@0.8.127 browser ensure
npm run check
npm run dev -- --background
```

Open the Studio URL printed by the preview command. Edit [composition/index.html](composition/index.html) for copy, layout, scene timing, audio cues, and animation. The preview reloads on changes. Source image references and the nine scene timings are recorded in the [plan](brag-plan.md). Keep the rendered-demo disclosure, native UI labels, and screenshot aspect ratios intact. The switcher focuses **Release notes**; the snapping example is a clearly separate **Launch checklist** scene.

The local [GSAP bundle](composition/assets/gsap.min.js) is copied from the pinned package. If you deliberately replace that bundle after installing dependencies, use `cp node_modules/gsap/dist/gsap.min.js assets/gsap.min.js`. Keep its license header. `assets/audio-data.js` and `assets/audio-data.json` contain the music analysis used for the subtle accent reaction; regenerate them through the Hyperframes audio-reactive workflow if you replace the music.

After reviewing the preview, run:

```sh
npm run check
bash export.sh
```

The [export script](composition/export.sh) runs Hyperframes 0.8.127 with delivery quality, **`--resolution landscape-4k`**, and 30 fps. It extracts the hook at **1.5 seconds** as `brag.jpg`, bakes that poster into frame 0, and probes the result. This revision requires **3840 × 2160, 900 frames, and 30 seconds**; the first-frame replacement preserves soundtrack timing. Check all seven feature results, readable controls, music, and the final hold. No publishing command is part of this workflow.

If you change the hook timing, inspect the new poster and update the script's extraction time if needed. Stop the preview when finished with `npx --yes hyperframes@0.8.127 preview --stop`.

## Regenerate native captures

This step needs a logged-in Mac, Xcode 16 or later, and the Python environment from the [media guide](../docs/media.md#regenerate). From the repository root:

```sh
build/docs/venv/bin/python scripts/docs/render.py \
  --capture-scale 4 --captures-dir build/docs/captures-4k --captures-only
```

The scale is pixels per logical point, from 1 through 4. Without it, the renderer uses the screen's backing scale. A custom capture directory requires `--captures-only`; this keeps the guide images and silent feature demos separate from the tour's source assets.

Copy the 16 captures used by the composition and the original app icon. Run this from the repository root after capture completes:

```sh
python3 - <<'PY'
from pathlib import Path
import shutil

names = """audio-step-0.png audio-step-1.png audio-step-2.png
clipboard-light.png text-source.png text-result.png
shelf-step-0.png shelf-step-2.png switcher-1.png switcher-2.png
sample-window-2.png snap-free.png snap-half.png snap-quarter.png
system-cpu.png system-readouts.png""".split()
source_dir = Path("build/docs/captures-4k")
destination = Path("brag-output/composition/assets")
sources = [source_dir / name for name in names]
icon = Path("Switchboard/Assets.xcassets/AppIcon.appiconset/icon_1024.png")
for source in [*sources, icon]:
    if not source.is_file():
        raise FileNotFoundError(source)
if not destination.is_dir():
    raise NotADirectoryError(destination)
for source in sources:
    shutil.copy2(source, destination / source.name)
shutil.copy2(icon, destination / "icon.png")
PY
```

Then return to `brag-output/composition` and run the check/export commands above. The composition uses a 1920 × 1080 logical canvas; `landscape-4k` renders at DPR 2 for the 3840 × 2160 output. The native assets are large enough for their displayed sizes in that export.

## Asset provenance

The app icon and native sample images come from this Switchboard repository. Their source paths are in the [composition brief](composition-brief.md).

Audio was copied from the installed [Brag 0.4.0 plugin](https://github.com/latent-spaces/brag). Original files were matched against the local copies by SHA-256:

| Local asset | Original bundled path |
| --- | --- |
| `composition/assets/music.mp3` | `skills/brag/assets/music/happy-beats-business-moves-vol-12-by-ende-dot-app.mp3` |
| `composition/assets/click.ogg` | `skills/brag/assets/sfx/ui/click2.ogg` |
| `composition/assets/place.ogg` | `skills/brag/assets/sfx/casino/card-slide-1.ogg` |

The music is the “Happy Beats / Business Moves” vol-12 track attributed to ende.app. Brag's [original music notice](composition/assets/licenses/brag-music-README.md) is preserved unchanged. That notice does not state the exact music license terms. Only local rendering is verified here; this package makes no broader claim about music publication rights.

Brag identifies its bundled Kenney sound effects as CC0/public domain. The two used files and source attribution are recorded in [SFX provenance](composition/assets/licenses/SFX-PROVENANCE.md). The plugin's own [MIT license](composition/assets/licenses/brag-MIT-LICENSE.txt) is retained separately.

The headline entrances adapt Hyperframes' **line-by-line-slide** catalog recipe to Switchboard typography and timing. The focused-window handoff adapts **zoom-through-transition** scaling without a strobe. Both original components, [line-by-line-slide](composition/compositions/components/line-by-line-slide.html) and [zoom-through-transition](composition/compositions/components/zoom-through-transition.html), are retained. [hyperframes.json](composition/hyperframes.json) records both imports from the [Hyperframes registry](https://github.com/heygen-com/hyperframes/tree/main/registry). The upstream [Apache 2.0 license](composition/assets/licenses/hyperframes-Apache-2.0-LICENSE.txt) is included.

`gsap.min.js` is the local GSAP 3.14.2 package bundle. Its original copyright header remains in the file; a copy is in [GSAP notice](composition/assets/licenses/GSAP-NOTICE.txt). GSAP uses its [Standard “No Charge” License](https://gsap.com/standard-license/), separately from the Brag and Hyperframes licenses.
