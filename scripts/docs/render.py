#!/usr/bin/env python3
"""Render current SwiftUI views with isolated sample state, then compose README media."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

from compose import main as compose_media

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / 'build/docs'


def run(args, timeout=240):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True, timeout=timeout)


def replace_region(text, start, end, replacement):
    if text.count(start) != 1 or text.count(end) != 1:
        raise RuntimeError(f'Source changed; review documentation isolation: {start}')
    first = text.index(start)
    last = text.index(end, first)
    return text[:first] + replacement + text[last:]


def main():
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
                text = replace_region(text, '    init() {', '    func refresh() {', '    init() {}\n\n')
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
        run([executable], timeout=60)
    compose_media()


if __name__ == '__main__':
    main()
