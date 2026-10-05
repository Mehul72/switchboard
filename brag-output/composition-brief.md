# Hyperframes Composition Brief: Switchboard

## Objective and delivery

A balanced introduction to seven Switchboard features, following `brag-plan.md`: per-app audio, clipboard history, screen text, the file shelf, window switching, keyboard snapping, and System readings. Deliver **3840 × 2160 (4K)**, **30.00 seconds**, **30 fps**, **900 frames**, music and sparse SFX, no narration.

Keep `brag-output/composition/`, `brag-output/brag.mp4`, `brag-output/brag.jpg`, and `brag-output/share-copy.txt` as the delivery paths. The preceding 25-second cut and source are backed up locally under `build/docs/brag-v2/`. Production stays local.

## Creative contract

Open on a broad composition of audio, clipboard, and shelf UI. Give all seven features a readable action/result scene. Window switching and snapping occupy **7.10 seconds**, about **23.7%** of the runtime. Neither the opening nor the closing positions them as the main product.

- Tone: `app-store`, with clear native UI, bold system type, and restrained motion. This does not claim App Store availability.
- Canvas **#F3F5F8**, ink **#20242C**, and accent **#005BC4** come from `Theme.swift`. Secondary **#4A586A** is a derived ink shade.
- Preserve the native light and dark appearances, labels, and screenshot aspect ratios. Use varied framing, deliberate camera focus, and a quiet background accent.
- Keep **Rendered demo · Sample content** visible throughout. The interactions are illustrated with native rendered fixtures, not recorded from a desktop or timed as a performance demonstration.
- Native source views are captured at **four pixels per logical point**. The 1920 × 1080 logical canvas renders at DPR 2 for the 3840 × 2160 output; the source images supply enough pixels for their displayed sizes.

## Timeline and copy

| Time | Scene | Headline | Action/result |
| --- | --- | --- | --- |
| 0.00-2.73 | Hook | **Your Mac. A little easier.** | Audio, clipboard, and shelf views beside the app name/icon |
| 2.73-6.55 | Per-app audio | **Your mix. Your volume.** | Music moves from 100% to 35% over 3.55-4.15, then routes to Studio Headphones at 5.12 |
| 6.55-10.37 | Clipboard | **Copy it again.** | A ring highlights the **Weekend jobs** clip's Copy button and presses at 8.20 |
| 10.37-13.65 | Screen text | **Copy text. Skip the retyping.** | Control-Option-Command-T cue at 10.90; selection expands at 10.91; recognised result appears from 11.75 |
| 13.65-17.47 | File shelf | **Files, within reach.** | Three-file drag badge moves from 14.13; collected files appear at 14.73 |
| 17.47-21.29 | Window switcher | **Pick the window you need.** | Launch checklist is selected first; Tab selects Release notes at 18.56; matching window expands from 19.64 to 20.28 |
| 21.29-24.57 | Keyboard snapping | **Put it in place.** | Separate Launch checklist example: left half at 22.05, top-right quarter at 23.14 |
| 24.57-27.30 | System | **Your Mac. At a glance.** | CPU list appears first; CPU/Memory controls and labeled readings enter at 25.91 |
| 27.30-30.00 | Outro | **Small fixes. Everyday.** | Switchboard icon/name, feature list, **macOS 14.2 or later**, and **github.com/Mehul72/switchboard** |

Transitions fit inside the scene intervals. Each short headline stays through its interaction; each result gets a hold. The final lockup stays visible through the last frame, with no fade to black.

## Interaction constraints

Clipboard **Copy** puts content on the clipboard without pasting into another app. The screen-text result shown in Clipboard assumes history recording is enabled. Use the recognised sample text rather than inventing output.

The shelf's drag badge shows **3** to match the three collected files. It holds references and leaves originals in place. The audio scene's output choice is separate from its volume adjustment; only Music changes.

For the switcher, preserve **Release notes** from the selected preview through the enlarged native sample window, then hold until 21.29. The separate snapping scene uses **Launch checklist**; do not transform the selected title into it. Use actual snapping endpoint captures and an animated placement outline without stretching native UI. **Control-Option-Left** moves the unsnapped window to the left half; **Control-Option-I** places it in the top-right quarter. The film does not demonstrate other layouts or Control-drag snapping.

System values are examples. Keep the existing sample label and **CPU 18% MEM 35%** reading.

## Source assets

Claims and appearance come from `README.md`, `docs/user-guide.md`, `Switchboard/Views/Theme.swift`, and the native sample renderers in `scripts/docs/`. These are repository-root source paths; production copies live under `composition/assets/`.

| Material | Source |
| --- | --- |
| App icon | `Switchboard/Assets.xcassets/AppIcon.appiconset/icon_1024.png` |
| Audio states | `build/docs/captures-4k/audio-step-0.png`, `audio-step-1.png`, `audio-step-2.png` |
| Clipboard sample | `build/docs/captures-4k/clipboard-light.png` |
| Screen-text source/result | `build/docs/captures-4k/text-source.png`, `text-result.png` |
| Shelf states | `build/docs/captures-4k/shelf-step-0.png`, `shelf-step-2.png` |
| Selected window previews | `build/docs/captures-4k/switcher-1.png`, `switcher-2.png` |
| Matching focused sample window | `build/docs/captures-4k/sample-window-2.png` |
| Snapping endpoints | `build/docs/captures-4k/snap-free.png`, `snap-half.png`, `snap-quarter.png` |
| System process list, controls, and readings | `build/docs/captures-4k/system-cpu.png`, `system-readouts.png` |

Abbreviated filenames use the directory from the first filename in that row. The sample windows, clips, files, text, and readings contain no personal desktop content. Native snapping positions come from `WindowLayout`. Regenerate with `build/docs/venv/bin/python scripts/docs/render.py --capture-scale 4 --captures-dir build/docs/captures-4k --captures-only`, then copy the 16 used captures and original icon as listed in the [delivery README](README.md#regenerate-native-captures).

## Music and sound

Use the first **30 seconds** of `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`, bundled with Brag 0.4.0. The preset estimates **109.96 BPM** and covers timing hints through 25 seconds.

- Music gain **0.34**, fade in **0.00-0.22**, fade out **28.50-30.00**. No voice track or narration ducking.
- Strong cue matches include **17.47** for the switcher and the **24.56** cue near the System cut at **24.57**. Reading time takes precedence over exact beat alignment.
- Sparse clicks and placement sounds follow visible interactions. Preserve Brag's original music notice and the Kenney SFX provenance; no broader music-rights claim.
- Extracted RMS data covers all 30 seconds. Only the background accent responds, leaving controls and text steady.

## Implementation and verification

Use the installed Hyperframes core, animation, creative, keyframes, and CLI skills. Headline entrances adapt **line-by-line-slide**; focused native-content handoffs adapt **zoom-through-transition** scaling without a strobe. Keep both original catalog components, registry metadata, Apache 2.0 notice, and the local GSAP notice.

Run `hyperframes check`, then the local export script. Its rendering command uses **`--resolution landscape-4k`** with delivery quality and 30 fps. Validate **3840 × 2160**, **900 frames**, **30 seconds**, H.264 video and AAC audio; decode the result and inspect all seven actions, their result holds, the disclosure, and the final lockup. Review text at the actual delivery size as well as a normal embedded playback size.

Extract the settled hook at **1.5 seconds** for the poster and bake it into frame 0 without shifting the soundtrack or duration.
