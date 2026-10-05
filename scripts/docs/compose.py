"""Build captioned image and video demos from isolated native sample captures."""
from pathlib import Path
import shutil
import subprocess
import tempfile

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[2]
CAPTURES = ROOT / 'build/docs/captures'
OUTPUT = ROOT / 'docs/images'
VIDEO_OUTPUT = ROOT / 'docs/videos'
STEP_DURATION_MS = 3000
VIDEO_FPS = 10

CAPTURE_NAMES = {
    'everyday-light': 'everyday-light',
    'everyday-dark': 'everyday-dark',
    'audio-dark': 'audio-dark',
    'clipboard-light': 'clipboard-light',
    'system-dark': 'system-dark',
    'system-cpu': 'system-cpu',
    'system-memory': 'system-memory',
    'system-readouts': 'system-readouts',
    'shelf-step-2': 'file-shelf',
    'switcher-2': 'window-switcher',
    'grid-half': 'window-grid',
    'text-source': 'text-source',
    'text-result': 'text-result',
}


PAPER = '#f5f2eb'
INK = '#23322f'
MUTED = '#56625e'
BLUE = '#245fd6'
FONTS = Path('/System/Library/Fonts/Supplemental')


def text(image, xy, value, size=26, bold=False, color=INK):
    face = 'Arial Bold.ttf' if bold else 'Arial.ttf'
    font = ImageFont.truetype(str(FONTS / face), size)
    draw = ImageDraw.Draw(image)
    bounds = draw.multiline_textbbox(xy, value, font=font, spacing=8)
    if bounds[2] > image.width - 24 or bounds[3] > image.height - 12:
        raise ValueError(f'Caption does not fit: {value!r}')
    draw.multiline_text(xy, value, font=font, fill=color, spacing=8)


def panel(image, name, box):
    with Image.open(CAPTURES / f'{name}.png') as source:
        capture = ImageOps.contain(source.convert('RGBA'), (box[2], box[3]), Image.Resampling.LANCZOS)
    x = box[0] + (box[2] - capture.width) // 2
    y = box[1] + (box[3] - capture.height) // 2
    image.paste(capture, (x, y), capture)


def frame(title, instruction, capture, step, total, wide=False, short=False):
    width, height = (1200, 620 if short else 840) if wide else (800, 980)
    image = Image.new('RGB', (width, height), PAPER)
    draw = ImageDraw.Draw(image)
    draw.ellipse((36, 30, 76, 70), fill=BLUE)
    text(image, (49, 36), str(step), 24, bold=True, color='white')
    text(image, (94, 31), title, 34, bold=True)
    text(image, (36, 92), instruction, 24, color=MUTED)
    panel(image, capture, (36, 148, width - 72, height - 214))
    text(image, (36, height - 42), 'Switchboard / Rendered sample demo', 19, color=MUTED)
    for index in range(total):
        x = width - 36 - (total - index) * 20
        draw.ellipse((x, height - 34, x + 8, height - 26), fill=BLUE if index == step - 1 else '#c7cdc8')
    return image


def save_video(name, frames):
    size = frames[0].size
    if any(dimension % 2 for dimension in size):
        raise ValueError(f'Video dimensions must be even: {size}')
    VIDEO_OUTPUT.mkdir(parents=True, exist_ok=True)
    destination = VIDEO_OUTPUT / f'{name}.mp4'
    with tempfile.TemporaryDirectory(prefix='.encode-', dir=VIDEO_OUTPUT) as directory:
        temporary = Path(directory) / destination.name
        command = [
            imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel', 'error',
            '-f', 'rawvideo', '-pixel_format', 'rgb24',
            '-video_size', f'{size[0]}x{size[1]}', '-framerate', f'1000/{STEP_DURATION_MS}',
            '-i', 'pipe:0', '-an', '-c:v', 'libx264', '-preset', 'slow', '-crf', '20',
            '-pix_fmt', 'yuv420p', '-r', str(VIDEO_FPS), '-threads', '1',
            '-movflags', '+faststart', str(temporary),
        ]
        pixels = b''.join(image.convert('RGB').tobytes() for image in frames)
        try:
            subprocess.run(command, input=pixels, capture_output=True, check=True, timeout=60)
        except subprocess.CalledProcessError as error:
            raise RuntimeError(f'Could not encode {destination}: {error.stderr.decode(errors="replace")}') from error
        temporary.replace(destination)


def save_demo(name, frames, still=0, still_name=None):
    if not frames or not 0 <= still < len(frames):
        raise ValueError(f'Demo {name!r} needs frames and a valid still index')
    if any(image.size != frames[0].size for image in frames):
        raise ValueError(f'Demo {name!r} has frames with different dimensions')
    # A shared palette prevents app icons changing colour between frames.
    strip = Image.new('RGB', (frames[0].width, sum(f.height for f in frames)))
    for index, image in enumerate(frames):
        strip.paste(image, (0, index * image.height))
    colours = strip.quantize(colors=255, method=Image.Quantize.FASTOCTREE).getpalette()
    palette = Image.new('P', (1, 1))
    palette.putpalette(list(Image.new('RGB', (1, 1), PAPER).getpixel((0, 0))) + colours[:765])
    images = [image.quantize(palette=palette, dither=Image.Dither.NONE) for image in frames]
    images[0].save(OUTPUT / f'{name}.gif', save_all=True, append_images=images[1:],
                   duration=STEP_DURATION_MS, loop=0, optimize=True, disposal=2)
    frames[still].save(OUTPUT / f'{still_name or name}.png', optimize=True)
    save_video(name, frames)


def walkthrough(name, steps, *, wide=False, short=False, still=0, still_name=None):
    frames = [frame(title, detail, capture, index + 1, len(steps), wide, short)
              for index, (title, detail, capture) in enumerate(steps)]
    save_demo(name, frames, still, still_name)


def demos():
    walkthrough('app-audio', [
        ('Open Audio', 'Play something to see its app here.', 'audio-step-0'),
        ('Turn down Music', 'The other apps stay at 100%.', 'audio-step-1'),
        ('Choose headphones', 'Each app has its own output menu.', 'audio-step-2'),
        ('Reset app audio', 'Full volume, back on the default output.', 'audio-step-3'),
    ], still=2)
    walkthrough('file-shelf', [
        ('Drag a file, then press Shift', 'Or shake the pointer to open the shelf.', 'shelf-step-0'),
        ('Drop it on the shelf', 'The original stays in its folder.', 'shelf-step-1'),
        ('Add files from other folders', 'Drag a thumbnail into your destination app.', 'shelf-step-2'),
    ], still=2, still_name='file-shelf-workflow')
    walkthrough('disk-eject', [
        ('Find your drive', 'External disks appear below your files.', 'shelf-step-2'),
        ('Drop onto the eject target', 'You can also click the Eject button.', 'disk-target'),
        ('Wait for the confirmation', 'A busy disk stays mounted and shows an error.', 'disk-ejected'),
    ], still=1)
    walkthrough('window-switcher', [
        ('Hold Command and press Tab', 'Each window gets a card, including windows from the same app.', 'switcher-0'),
        ('Press Tab again', 'Keep Command held while you choose.', 'switcher-1'),
        ('Choose the other Notes window', 'Release Command to switch to the selected window.', 'switcher-2'),
        ('Browse just the current app', 'Hold Option and press `, then release Option to switch.', 'switcher-same-app'),
    ], wide=True, short=True, still=2, still_name='window-switcher-demo')
    walkthrough('window-snapping', [
        ('Start with a window', 'Turn on Snap windows in Tweaks > Everyday first.', 'snap-free'),
        ('Left half', 'Control + Option + Left, starting from this unsnapped window', 'snap-half'),
        ('Centre third', 'Control + Option + F', 'snap-third'),
        ('Top-right quarter', 'Control + Option + I', 'snap-quarter'),
        ('Fill the workspace', 'Control + Option + Return', 'snap-maximise'),
        ('Put it back', 'Control + Option + Delete restores its previous size and position.', 'snap-free'),
    ], wide=True, still=1)
    walkthrough('window-grid', [
        ('Drag the title bar, then hold Control', 'The cell under your pointer is the start of the selection.', 'grid-start'),
        ('Select the left half', 'Move across three columns and both rows.', 'grid-half'),
        ('Release the mouse to snap', 'Release Control first if you want to cancel instead.', 'snap-half'),
    ], wide=True, still=1, still_name='window-grid-demo')
    walkthrough('system-monitor', [
        ('Find busy apps', 'Open System, then choose CPU in Using the most.', 'system-cpu'),
        ('Check memory use', 'Choose Memory to sort the same process list.', 'system-memory'),
        ('Keep readings in view', 'Enable CPU and Memory under Show in menu bar.', 'system-readouts'),
    ], still=2)

    frames = []
    steps = [
        ('Start a text capture', 'Control + Option + Command + T'),
        ('Draw a box around the words', 'Release the mouse to recognise the text. Escape cancels.'),
        ('Paste the result', 'Command-V pastes it. History saves it when recording is on.'),
    ]
    for index, (title, detail) in enumerate(steps):
        image = Image.new('RGB', (1200, 680), PAPER)
        text(image, (36, 32), f'{index + 1}. {title}', 34, bold=True)
        text(image, (36, 90), detail, 24, color=MUTED)
        text(image, (36, 177), 'Image', 22, color=MUTED)
        panel(image, 'text-source', (36, 215, 550, 340))
        if index >= 1:
            ImageDraw.Draw(image).rounded_rectangle((66, 290, 555, 478), radius=4, outline=BLUE, width=3)
        if index == 2:
            text(image, (635, 177), 'Copied text', 22, color=MUTED)
            panel(image, 'text-result', (635, 215, 529, 340))
        else:
            text(image, (650, 300), 'Screen Recording\naccess is needed.' if index == 0 else 'The selection here\nis an illustration.', 28, color=MUTED)
        text(image, (36, 633), 'Switchboard / Rendered demo, example image recognised by the app', 19, color=MUTED)
        frames.append(image)
    save_demo('screen-text', frames, still=2)


def main():
    for source in CAPTURE_NAMES:
        capture = CAPTURES / f'{source}.png'
        if not capture.is_file():
            raise FileNotFoundError(f'Missing native capture: {capture}. Run scripts/docs/render.py.')
    OUTPUT.mkdir(parents=True, exist_ok=True)
    hero = Image.new('RGB', (1400, 1170), PAPER)
    text(hero, (68, 43), 'A home in your menu bar.', 40, bold=True)
    text(hero, (68, 104), 'Everyday settings', 26, color=MUTED)
    text(hero, (744, 104), 'Volume for each app', 26, color=MUTED)
    panel(hero, 'everyday-light', (68, 163, 588, 909))
    panel(hero, 'audio-dark', (744, 163, 588, 909))
    text(hero, (68, 1118), 'Light or dark. Your choice.', 24, color=MUTED)
    hero.save(OUTPUT / 'overview.png', optimize=True)
    demos()
    for source, name in CAPTURE_NAMES.items():
        shutil.copyfile(CAPTURES / f'{source}.png', OUTPUT / f'{name}.png')
    for directory in (OUTPUT, VIDEO_OUTPUT):
        for path in sorted(directory.iterdir()):
            if path.is_file():
                print(f'{path.relative_to(ROOT)}: {path.stat().st_size // 1024} KB')


if __name__ == '__main__':
    main()
