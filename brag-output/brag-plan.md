# Brag Plan: Switchboard

30-second landscape product film, **3840 × 2160 (4K)** at **30 fps**, with seven features sharing the story. Revised 5 October 2026. The previous 25-second cut and source are backed up locally under `build/docs/brag-v2/`; delivery paths stay in `brag-output/`.

## The angle

Small fixes for everyday Mac tasks. Open with native audio, clipboard, and shelf panels, then show one useful action or result for each feature. Include window switching and snapping as part of the app's broader set of tools. Their scenes total **7.10 seconds**, about **23.7%** of the film.

This is an animated demonstration using native app views and sample content. Keep **Rendered demo · Sample content** legible throughout. It is not a desktop recording or a performance measurement. Native sources were captured at four pixels per logical point for the 4K delivery.

## Planning rubric

1. **What is the app?** A native macOS menu bar utility for per-app audio, clipboard history, screen text, a file shelf, individual-window switching, snapping, and system readings.
2. **Strongest claim?** Useful controls for several everyday Mac tasks are available in one utility. Prove this with actual native UI and a visible result in each scene, without a speed or superiority claim.
3. **Visual hook?** Audio, clipboard, and shelf views form a broad product composition beside **Your Mac. A little easier.** The real app name and icon are visible immediately.
4. **Actual UI to show?** Music's volume control, stored sample clips, a selected meeting note and recognised text, collected files, separate window cards, keyboard snapping states, and sample CPU/Memory readings.
5. **Shortest satisfying duration?** 30 seconds allows seven feature demonstrations plus an opening and closing hold. The extra time keeps clipboard and screen text visible without relegating the other tools to unreadable flashes.
6. **Tone?** `app-store`: bold system typography, restrained motion, clear native UI, and short everyday language. This is an editorial tone, not an App Store distribution claim.
7. **Audio?** Bundled “Happy Beats / Business Moves” vol-12, estimated 109.96 BPM, with sparse clicks and placement sounds. No narration.
8. **Share caption?** “Small fixes for everyday Mac tasks. Switchboard brings app audio, clipboard history, screen text, a file shelf, window tools, and system readings to your menu bar. Watch the 30-second tour in 4K. For macOS 14.2 or later: https://github.com/Mehul72/switchboard”
9. **User flow?** Each feature has a separate action/result example: adjust one app, retrieve a clip, recognise visible text, collect files, choose a window, place a window, and inspect readings. Do not imply these examples are one continuous desktop session.

## Visual identity

- Main canvas **#F3F5F8**, ink **#20242C**, and accent **#005BC4** come from `Switchboard/Views/Theme.swift`. Secondary **#4A586A** is a derived ink shade for the film.
- Preserve native light and dark appearances. Keep screenshot aspect ratios and control labels intact.
- Use bold system type and large product states. Vary the framing between native panels, the text example, the wide switcher, and the snapping desktop.
- A slow outline circle and subtle music-reactive accent sit behind the product. No strobe or motion on readable UI text.
- Original icon: `Switchboard/Assets.xcassets/AppIcon.appiconset/icon_1024.png`.

## Storyboard

| Scene | Time | Duration | Visible purpose |
| --- | --- | --- | --- |
| Broad product hook | 0.00-2.73 | 2.73 s | Your Mac. A little easier. |
| Per-app audio | 2.73-6.55 | 3.82 s | Adjust Music without changing the other apps |
| Clipboard | 6.55-10.37 | 3.82 s | Find and copy an earlier sample clip |
| Screen text | 10.37-13.65 | 3.28 s | Select visible text and show the recognised result |
| File shelf | 13.65-17.47 | 3.82 s | Collect sample files |
| Window switcher | 17.47-21.29 | 3.82 s | Select an individual window, including one of two from the same app |
| Window snapping | 21.29-24.57 | 3.28 s | Place a separate example window with keyboard layouts |
| System | 24.57-27.30 | 2.73 s | Show CPU/Memory controls and sample readings |
| Outro | 27.30-30.00 | 2.70 s | Small fixes. Everyday. |

Total: **30.00 seconds**, nine scenes. Transitions are included in those intervals. Keep each headline steady during its interaction and leave a visible result hold before the next scene.

## Action and hold guidance

**Hook:** show audio, clipboard, and shelf together with the app name/icon. Let the composition settle before the first feature cut. The poster comes from the settled hook at 1.5 seconds.

**Audio:** **Your mix. Your volume.** Music moves from **100%** to **35%** over 3.55-4.15, then routes to **Studio Headphones** at 5.12. Hold the native result. Other app values stay unchanged.

**Clipboard:** **Copy it again.** Show existing sample clips and highlight the **Weekend jobs** clip's **Copy** button, with the press at 8.20. Copy returns content to the clipboard; it does not paste into another app automatically. Keep the chosen clip readable.

**Screen text:** **Copy text. Skip the retyping.** Show the **Control-Option-Command-T** cue at 10.90, select the generated meeting note, and reveal its recognised text from 11.75. The Clipboard result assumes history recording is enabled. Do not imply translation, automatic editing, or perfect recognition.

**Shelf:** **Files, within reach.** A badge marked **3** represents the three sample files moving into the shelf from 14.13. The collected state appears at 14.73 and holds. The shelf holds references and leaves originals in place; it is not a backup service.

**Switcher:** **Pick the window you need.** The first native panel selects **Launch checklist**. Tab selects **Release notes** at 18.56; releasing Command brings its matching sample window forward from 19.64 to 20.28. Hold until 21.29. Both Notes windows are separate cards. Cut clearly to the snapping example.

**Snapping:** **Put it in place.** A separate **Launch checklist** example moves to the left half with **Control-Option-Left** at 22.05, then the top-right quarter with **Control-Option-I** at 23.14. Connect the native endpoint captures with a placement outline. Keep labels and aspect ratios intact. These are captured layout states, not a continuous recorded resize. The film does not demonstrate other layouts or Control-drag snapping.

**System:** **Your Mac. At a glance.** Show the native CPU process list first, then CPU/Memory controls from 25.91 with the existing **CPU 18% MEM 35%** example. Keep the sample label visible and do not imply live readings from the viewer's Mac.

**Outro:** original icon and **Switchboard**, **Small fixes. Everyday.**, **macOS 14.2 or later**, and **github.com/Mehul72/switchboard**. Settle promptly and hold through frame 899. Retain the rendered-demo disclosure and paper background.

## Music and transitions

Use `happy-beats-business-moves-vol-12-by-ende-dot-app.mp3`, source time **0.00-30.00**. Gain **0.34**; opening fade **0.00-0.22**, final fade **28.50-30.00**. Keep narration absent.

The bundled cue preset estimates **109.96 BPM** and supplies timing hints through 25 seconds. The switcher reveal at **17.47** matches a strong cue; the System cut at **24.57** is near the **24.56** strong cue. Other scene boundaries use the existing beat grid where practical. Do not sacrifice reading time to force a cue, or describe later beats as verified by the 25-second preset.

Use sparse clicks and placements for visible interactions. Extend extracted RMS data through the full 30 seconds; only the background accent reacts. Preserve the original music notice and Kenney sound-effect provenance in the delivery package.

## Grounding and delivery

Sources: `README.md`, `docs/user-guide.md`, `Switchboard/Views/Theme.swift`, and the native fixtures in `scripts/docs/Render.swift`, `Features.swift`, and `Windows.swift`. Source assets are listed in the composition brief.

Window tools must be enabled and need Accessibility. Optional preview images and screen text need Screen Recording; per-app audio needs System Audio Recording. The film depicts enabled examples without claiming that setup is unnecessary.

Keep production local. Regenerate native sources with `--capture-scale 4 --captures-dir build/docs/captures-4k --captures-only`. Export with Hyperframes **`--resolution landscape-4k`** at **30 fps**, validate **3840 × 2160**, **900 frames**, and **30 seconds**, and inspect each action/result. The composition's 1920 × 1080 logical canvas renders at DPR 2; its native assets supply enough pixels for their displayed sizes. Extract the poster at 1.5 seconds and bake it into frame 0 without shifting duration or audio timing.
