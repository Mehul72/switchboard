#!/usr/bin/env python3
"""Render current SwiftUI views with isolated sample state, then export documentation images."""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess
import tempfile

from compose import main as export_media

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/docs'


def run(args, timeout=240, env=None):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, timeout=timeout, env=env)


def replace_region(text, start, end, replacement):
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError(f'Source changed; review documentation isolation: {start}')
    first = text.index(start)
    last = text.index(end, first)
    return text[:first] + replacement + text[last:]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-scale', type=int, choices=range(1, 5),
                        help='Native pixels per logical point; defaults to the screen backing scale.')
    parser.add_argument('--captures-dir', type=Path, default=BUILD / 'captures',
                        help='Native capture directory (a custom directory requires --captures-only).')
    parser.add_argument('--captures-only', action='store_true',
                        help='Skip publishing images, GIFs, and videos to docs/.')
    options = parser.parse_args()
    captures = options.captures_dir.resolve()
    if captures != (BUILD / 'captures').resolve() and not options.captures_only:
        parser.error('--captures-dir requires --captures-only when using a custom directory')
    environment = os.environ.copy()
    environment['SWITCHBOARD_DOCS_CAPTURES'] = str(captures)
    environment.pop('SWITCHBOARD_DOCS_CAPTURE_SCALE', None)
    if options.capture_scale is not None:
        environment['SWITCHBOARD_DOCS_CAPTURE_SCALE'] = str(options.capture_scale)
    BUILD.mkdir(parents=True, exist_ok=True)
    with (BUILD / 'build.log').open('w') as log:
        subprocess.run(['xcodebuild', '-project', 'Switchboard.xcodeproj', '-scheme', 'Switchboard',
                        '-configuration', 'Debug', '-derivedDataPath', str(BUILD),
                        'CODE_SIGNING_ALLOWED=NO', 'build'], cwd=ROOT, stdout=log,
                       stderr=subprocess.STDOUT, check=True, timeout=240)
    with tempfile.TemporaryDirectory(prefix='switchboard-docs-') as directory:
        work = Path(directory)
        sources = []
        for source in sorted((ROOT / 'Switchboard').rglob('*.swift')):
            if source.name == 'SwitchboardApp.swift':
                continue
            text = source.read_text()
            if source.name == 'TweakStore.swift':
                # Only the temporary model copy is changed. Production views stay intact.
                text = replace_region(text, '    private func start() {', '    func refresh() {',
                                      '    private func start() {}\n\n')
                text = replace_region(text, '    func refreshAudioApps() {',
                                      '    func volume(for app:', '    func refreshAudioApps() {}\n\n')
                old = 'var hasAdjustedAudio: Bool { appAudio.isControllingAnything }'
                if text.count(old) != 1:
                    raise RuntimeError('Review documentation audio state isolation')
                text = text.replace(old, 'var hasAdjustedAudio: Bool { !audioRoutes.isEmpty || audioVolumes.values.contains { $0 < 1 } }')
                text = text.replace('private(set)', '')
            if source.name == 'SystemMonitor.swift':
                text = replace_region(text, '    func start() {', '    func stop() {',
                                      '    func start() { isRunning = true }\n\n')
                text = text.replace('private(set)', '')
            if source.name == 'SystemMonitorView.swift':
                replacements = {
                    '@State private var processSort = ProcessSort.cpu': '@State var processSort = ProcessSort.cpu',
                    'private var processPanel: some View': 'var processPanel: some View',
                    'private var readoutPanel: some View': 'var readoutPanel: some View',
                    'AppQuitter.quittableApp(for: usage) != nil': 'usage.isOwnedByUser && usage.bundlePath != nil',
                    'AppQuitter.quit(usage)': 'documentationQuit(usage)',
                }
                for original, replacement in replacements.items():
                    if text.count(original) != 1:
                        raise RuntimeError(f'Review documentation System view access: {original}')
                    text = text.replace(original, replacement)
                text += '\nprivate func documentationQuit(_ usage: ProcessUsage) -> Bool {\n'
                text += '    fatalError("Documentation must not quit real apps")\n}\n'
            if source.name == 'WindowSwitcher.swift':
                text = text.replace('private(set)', '')
            if source.name in ('WindowSwitcherView.swift', 'WindowDragGrid.swift'):
                declaration = ('private struct WindowSwitcherView' if source.name == 'WindowSwitcherView.swift'
                               else 'private final class GridCanvas')
                if text.count(declaration) != 1:
                    raise RuntimeError(f'Review documentation view access: {declaration}')
                text = text.replace(declaration, declaration.removeprefix('private '))
            target = work / source.name
            target.write_text(text)
            sources.append(target)
        generated = BUILD / 'Build/Intermediates.noindex/Switchboard.build/Debug/Switchboard.build/DerivedSources/GeneratedAssetSymbols.swift'
        app = work / 'Documentation.app/Contents'
        (app / 'MacOS').mkdir(parents=True)
        (app / 'Resources').mkdir()
        with (app / 'Info.plist').open('wb') as plist:
            plistlib.dump({'CFBundleIdentifier': 'com.switchboard.documentation',
                          'CFBundleExecutable': 'Documentation', 'CFBundlePackageType': 'APPL',
                          'LSUIElement': True}, plist)
        shutil.copy(BUILD / 'Build/Products/Debug/Switchboard.app/Contents/Resources/Assets.car', app / 'Resources')
        executable = app / 'MacOS/Documentation'
        run(['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
             '-module-cache-path', BUILD / 'module-cache', *sources, generated,
             ROOT / 'scripts/docs/Render.swift', ROOT / 'scripts/docs/Windows.swift', ROOT / 'scripts/docs/Features.swift', '-o', executable])
        run([executable], timeout=60, env=environment)
    if not options.captures_only:
        export_media()


if __name__ == '__main__':
    main()
