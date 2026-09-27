"""Compose captured native views into small, self-contained GitHub media."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
CAPTURES = ROOT / 'build/docs/captures'
OUTPUT = ROOT / 'docs/images'
FONTS = Path('/System/Library/Fonts/Supplemental')
INK = '#f5f7fb'
MUTED = '#aabbd2'
ACCENT = '#91c5ff'


def font(size, bold=False):
    return ImageFont.truetype(str(FONTS / ('Arial Bold.ttf' if bold else 'Arial.ttf')), size)


def canvas(width, height):
    image = Image.new('RGB', (width, height))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / height
        draw.line((0, y, width, y), fill=(int(12 + 9*t), int(22 + 15*t), int(39 + 20*t)))
    return image


def text(image, position, words, size, color=INK, bold=False):
    ImageDraw.Draw(image).text(position, words, font=font(size, bold), fill=color, spacing=10)


def panel(image, name, x, y, width):
    capture = Image.open(CAPTURES / f'{name}.png').convert('RGB')
    height = round(capture.height * width / capture.width)
    capture = capture.resize((width, height), Image.Resampling.LANCZOS)
    mask = Image.new('L', capture.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width-1, height-1), radius=18, fill=255)
    shadow = Image.new('RGBA', image.size)
    ImageDraw.Draw(shadow).rounded_rectangle((x, y+14, x+width, y+height+14), radius=20, fill=(0, 0, 0, 120))
    image.paste(Image.alpha_composite(image.convert('RGBA'), shadow.filter(ImageFilter.GaussianBlur(22))).convert('RGB'))
    image.paste(capture, (x, y), mask)


def save(image, name):
    image.save(OUTPUT / name, optimize=True)


def walkthrough_frame(label, title, instruction, capture, wide=False):
    frame = canvas(1200, 680 if wide else 900)
    text(frame, (50, 35), label, 19, ACCENT, True)
    text(frame, (48, 73), title, 42, bold=True)
    text(frame, (50, 132), instruction, 23, MUTED)
    panel(frame, capture, 50, 191, 1100)
    text(frame, (50, frame.height - 42),
         'Rendered walkthrough • Example windows • Default shortcuts', 18, MUTED)
    return frame


def save_walkthrough(frames, name, duration=2800):
    # One palette for the whole GIF: per-frame palettes turned small colours such as app icons grey.
    # The background's exact colours are reserved so its gradient does not band.
    background = sorted(set(canvas(1, frames[0].height).getdata()))
    strip = Image.new('RGB', (frames[0].width, frames[0].height * len(frames)))
    for index, frame in enumerate(frames):
        strip.paste(frame, (0, index * frame.height))
    views = strip.quantize(colors=256 - len(background), method=Image.Quantize.FASTOCTREE)
    entries = views.getpalette()
    colours = background + [tuple(entries[3 * index:3 * index + 3]) for _, index in views.getcolors(256)]
    colours += [colours[-1]] * (256 - len(colours))
    palette = Image.new('P', (1, 1))
    palette.putpalette([value for colour in colours for value in colour])
    paletted = [frame.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG) for frame in frames]
    paletted[0].save(OUTPUT / name, save_all=True, append_images=paletted[1:],
                     duration=duration, loop=0, optimize=True, disposal=2)


def window_walkthroughs():
    switcher_steps = [
        ('Hold Command + Tab', 'Every window gets its own card.', 'switcher-0'),
        ('Keep Command held. Press Tab.', 'Move from your workspace to your notes.', 'switcher-1'),
        ('Press Tab again.', 'Two windows of the same app. Two separate choices.', 'switcher-2'),
        ('Hold Option + ` for the current app.', 'Browse just that app’s windows. Release Option to switch.', 'switcher-same-app')
    ]
    frames = [walkthrough_frame('WINDOW SWITCHER', title, detail, capture, wide=True)
              for title, detail, capture in switcher_steps]
    save_walkthrough(frames, 'window-switcher.gif', 3200)
    still = frames[2].copy()
    save(still, 'window-switcher.png')

    snap_steps = [
        ('Start with a window.', 'Enable Snap windows in Tweaks > Everyday first.', 'snap-free'),
        ('Give it half the display.', 'Control + Option + Left  /  From this unsnapped window', 'snap-half'),
        ('Make it a third.', 'Control + Option + F  /  Centre third', 'snap-third'),
        ('Tuck it into a quarter.', 'Control + Option + I  /  Top-right quarter', 'snap-quarter'),
        ('Take the whole workspace.', 'Control + Option + Return  /  Maximise without entering full screen', 'snap-maximise'),
        ('Back where you started.', 'Control + Option + Delete  /  Restore the original size and position', 'snap-free')
    ]
    frames = [walkthrough_frame('WINDOW SNAPPING', title, detail, capture)
              for title, detail, capture in snap_steps]
    save_walkthrough(frames, 'window-snapping.gif')
    save(frames[1], 'window-snapping.png')

    grid_steps = [
        ('Drag. Hold Control.', 'Start dragging the title bar, then hold Control to reveal the grid.', 'grid-start'),
        ('Choose how much room you need.', 'Keep Control held. Sweep across three columns and both rows.', 'grid-half'),
        ('Release the mouse. It fits.', 'The window fills your selection. Release Control early to cancel snapping.', 'snap-half')
    ]
    frames = [walkthrough_frame('DRAG TO SNAP', title, detail, capture)
              for title, detail, capture in grid_steps]
    save_walkthrough(frames, 'window-grid.gif', 3400)
    save(frames[1], 'window-grid.png')


def feature_frame(label, title, body, hint, capture, width=450):
    frame = canvas(1200, 830)
    text(frame, (50, 46), label, 19, ACCENT, True)
    text(frame, (48, 107), title, 40, bold=True)
    text(frame, (50, 242), body, 25, MUTED)
    text(frame, (50, 475), hint, 22, ACCENT)
    panel(frame, capture, 665 - (width - 450) // 2, 145, width)
    text(frame, (50, 780), 'Native app views • Rendered example states • Sample content', 18, MUTED)
    return frame


def feature_walkthroughs():
    audio = [
        ('01 / PER-APP AUDIO', 'Start with your\nown mix.', 'Play something in your apps.\nOpen Audio to see each\nstream separately.', 'Music, browser, and calls.\nEach has its own controls.', 'audio-step-0'),
        ('02 / PER-APP AUDIO', 'Less music.\nSame clear call.', 'Lower Music to 35%.\nSafari and FaceTime\nstay at 100%.', 'First adjustment asks for\nSystem Audio Recording access.', 'audio-step-1'),
        ('03 / PER-APP AUDIO', 'Choose where\nit plays.', 'Send Music to headphones.\nLeave the other apps on\nthe system default output.', 'One output choice per app.', 'audio-step-2'),
        ('04 / PER-APP AUDIO', 'Back to normal.\nIn one click.', 'Reset app audio returns\nevery app to full volume\nand the default output.', 'Releases the per-app audio taps.', 'audio-step-3')
    ]
    frames = [feature_frame(*step) for step in audio]
    save_walkthrough(frames, 'app-audio.gif', 3300)
    save(frames[2], 'app-audio.png')

    shelf = [
        ('01 / FILE SHELF', 'Pick up a file.\nMake a little room.', 'Start dragging from Finder.\nPress Shift once, or shake\nthe pointer, to open the shelf.', 'Move onto Drop to keep.', 'shelf-step-0'),
        ('02 / FILE SHELF', 'Drop it here.\nKeep the original.', 'The shelf keeps a reference,\nnot a copy. Your files wait\nthere while you switch apps.', 'Your original stays in its folder.', 'shelf-step-1'),
        ('03 / FILE SHELF', 'Gather first.\nSend when ready.', 'Add files from other folders.\nThen drag a thumbnail into\nFinder, an email, or another app.', 'Up to 40 references.\nCleared when Switchboard quits.', 'shelf-step-2')
    ]
    frames = [feature_frame(*step, width=490) for step in shelf]
    save_walkthrough(frames, 'file-shelf.gif', 3400)
    save(frames[2], 'file-shelf-workflow.png')

    disks = [
        ('01 / DISKS', 'Finished with\nthat drive?', 'External drives and mounted\ndisk images appear under\nDisks on the shelf.', 'Click Eject, or use a drag.', 'shelf-step-2'),
        ('02 / DISKS', 'Drop to eject.', 'Drag the disk, then press\nShift or shake the pointer.\nRelease on Drop to eject.', 'Hovering alone does not eject it.', 'disk-target'),
        ('03 / DISKS', 'Gone from the list.\nFiles still in place.', 'After macOS completes eject,\nthe disk disappears. Your\nshelved files stay on the shelf.', 'Busy disks show an error.\nSwitchboard never force-ejects.', 'disk-ejected')
    ]
    frames = [feature_frame(*step, width=490) for step in disks]
    save_walkthrough(frames, 'disk-eject.gif', 3400)
    save(frames[1], 'disk-eject.png')

    frames = []
    for step in range(3):
        frame = canvas(1400, 760)
        text(frame, (60, 38), 'SCREEN TEXT CAPTURE', 21, ACCENT, True)
        text(frame, (58, 86), 'If you can see it, try copying it.', 52, bold=True)
        text(frame, (60, 162), 'Text inside an image becomes text you can paste.', 27, MUTED)
        panel(frame, 'text-source', 60, 270, 600)
        if step >= 1:
            ImageDraw.Draw(frame).rounded_rectangle((93, 307, 630, 602), radius=8, outline=ACCENT, width=4)
        text(frame, (60, 224), 'SOURCE IMAGE', 20, ACCENT, True)
        if step == 0:
            text(frame, (755, 282), '1. Start a text capture.', 33, bold=True)
            text(frame, (755, 358), 'Control + Option + Command + T\n\nAllow Screen Recording\nwhen macOS asks.', 24, MUTED)
        elif step == 1:
            text(frame, (755, 282), '2. Select the words.', 33, bold=True)
            text(frame, (755, 358), 'Drag around the text.\nRelease to recognise it.\n\nEscape cancels the selection.', 24, MUTED)
        else:
            text(frame, (755, 224), '3. TEXT, READY TO REUSE', 20, ACCENT, True)
            panel(frame, 'text-result', 745, 300, 580)
            text(frame, (755, 543), 'Paste into your app with Command-V.\nFind it again in Clipboard history.', 23, MUTED)
        text(frame, (60, 702), 'Illustrated region selection • Native result view • Sample text recognised by the app’s OCR', 20, MUTED)
        frames.append(frame)
    save_walkthrough(frames, 'screen-text.gif', 3400)
    save(frames[2], 'screen-text.png')


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    hero = canvas(1600, 1360)
    text(hero, (86, 62), 'S W I T C H B O A R D   /   F O R  M A C', 24, ACCENT, True)
    text(hero, (82, 117), 'Your Mac. A little more yours.', 72, bold=True)
    text(hero, (86, 214), 'Everyday controls. Individual app audio. One place to reach for.', 31, MUTED)
    panel(hero, 'everyday-light', 160, 332, 600)
    panel(hero, 'audio-dark', 840, 332, 600)
    text(hero, (162, 288), '01   MAKE IT FEEL RIGHT', 22, ACCENT, True)
    text(hero, (842, 288), '02   SET YOUR OWN MIX', 22, ACCENT, True)
    text(hero, (86, 1310), 'Native SwiftUI views • Sample content • Light and dark appearance', 21, MUTED)
    save(hero, 'overview.png')

    board = canvas(1600, 1190)
    text(board, (82, 60), 'Less retracing. More doing.', 60, bold=True)
    text(board, (84, 142), 'Bring a clip back. Check in on your Mac. Get back to work.', 29, MUTED)
    panel(board, 'clipboard-light', 180, 246, 550)
    panel(board, 'system-dark', 870, 246, 550)
    text(board, (182, 205), 'CLIPBOARD / YOUR LAST 20 CLIPS', 21, ACCENT, True)
    text(board, (872, 205), 'SYSTEM / AT A GLANCE', 21, ACCENT, True)
    text(board, (84, 1135), 'Sample clipboard content and system readings. History clears when you quit.', 23, MUTED)
    save(board, 'clipboard-system.png')

    window_walkthroughs()
    feature_walkthroughs()

    slides = [
        ('everyday-light', '01 / TWEAKS', 'Make it yours.', 'Open Tweaks > Everyday.\nKeep your Mac awake or\ncopy text from your screen.', 'Search all settings with Command-F.'),
        ('audio-dark', '02 / AUDIO', 'Find your mix.', 'Play audio in an app, then\nopen Audio to change its\nvolume and output device.', 'First adjustment asks for audio access.'),
        ('clipboard-light', '03 / CLIPBOARD', 'Copy. Keep. Reuse.', 'Copy text while Switchboard\nis running. Open Clipboard\nand copy an older clip back.', 'Return to your app and paste as usual.'),
        ('system-dark', '04 / SYSTEM', 'A quick check-in.', 'Open System for CPU, GPU,\nmemory, network, disk,\nand battery readings.', 'Available readings depend on your Mac.')
    ]
    frames = []
    for name, label, title, body, hint in slides:
        slide = canvas(1000, 700)
        text(slide, (44, 57), label, 19, ACCENT, True)
        text(slide, (42, 115), title, 35, bold=True)
        text(slide, (44, 196), body, 23, MUTED)
        text(slide, (44, 367), hint, 18, ACCENT)
        text(slide, (44, 580), 'SWITCHBOARD', 19, bold=True)
        text(slide, (44, 615), 'Guided tour • Sample content', 16, MUTED)
        panel(slide, name, 556, 40, 410)
        frames.append(slide)
    save_walkthrough(frames, 'tour.gif', 5000)
    # The guide links full-resolution captures for readers who prefer a static view.
    for name in ['everyday-light', 'everyday-dark', 'audio-dark', 'clipboard-light', 'system-dark']:
        Image.open(CAPTURES / f'{name}.png').save(OUTPUT / f'{name}.png', optimize=True)
    for path in sorted(OUTPUT.iterdir()):
        print(f'{path.name}: {path.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
