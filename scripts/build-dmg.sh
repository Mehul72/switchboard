#!/bin/bash
set -euo pipefail

fail() { printf 'DMG build failed: %s\n' "$1" >&2; exit 1; }
[[ $# -eq 2 ]] || fail "Usage: $0 <Switchboard.app> <output.dmg>"
[[ -d "$1/Contents" && -f "$1/Contents/Info.plist" ]] || fail "App bundle not found: $1"
[[ "$2" == *.dmg ]] || fail "Output must end in .dmg"
[[ ! -e "$2" && ! -L "$2" ]] || fail "Output already exists: $2"

project_root=$(cd "$(dirname "$0")/.." && pwd)
app=$(cd "$1" && pwd)
mkdir -p "$(dirname "$2")"
output_dir=$(cd "$(dirname "$2")" && pwd)
output="$output_dir/$(basename "$2")"

# Keep the Applications symlink outside the repo so workspace scanners cannot follow it.
work_dir=$(mktemp -d "${TMPDIR:-/tmp}/switchboard-dmg.XXXXXX")
mount_path="$work_dir/mount"
mounted=false
publish_dir=""
cleanup() {
    if $mounted; then
        if ! hdiutil detach "$mount_path" -quiet; then
            printf 'Could not detach installer volume. Temporary files retained at %s\n' "$work_dir" >&2
            return 1
        fi
    fi
    rm -rf "$work_dir"
    [[ -z "$publish_dir" ]] || rm -rf "$publish_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

mkdir -p "$work_dir/root/.background" "$mount_path"
printf 'Rendering installer artwork...\n'
xcrun swiftc -warnings-as-errors "$project_root/scripts/render-dmg-artwork.swift" -o "$work_dir/render-artwork"
"$work_dir/render-artwork" "$work_dir/artwork"
tiffutil -cathidpicheck "$work_dir/artwork/background.png" "$work_dir/artwork/background@2x.png" \
    -out "$work_dir/root/.background/installer.tiff" >/dev/null
ditto "$app" "$work_dir/root/Switchboard.app"
ln -s /Applications "$work_dir/root/Applications"
printf 'Creating and styling installer volume...\n'
hdiutil create -volname Switchboard -fs HFS+ -srcfolder "$work_dir/root" \
    -format UDRW "$work_dir/writable.dmg" -quiet
hdiutil attach "$work_dir/writable.dmg" -mountpoint "$mount_path" -nobrowse -noautoopen -quiet
mounted=true
osascript "$project_root/scripts/style-dmg.applescript" "$mount_path" \
    || fail "Finder styling failed. Run in a logged-in macOS desktop and allow Finder automation."

# Finder writes the layout asynchronously; never emit a silently unstyled image.
for ((attempt = 0; attempt < 20; attempt++)); do
    [[ -s "$mount_path/.DS_Store" ]] && break
    sleep 1
done
[[ -s "$mount_path/.DS_Store" ]] || fail "Finder did not save the installer layout"
sync
hdiutil detach "$mount_path" -quiet
mounted=false
publish_dir=$(mktemp -d "$output_dir/.switchboard-dmg.XXXXXX")
hdiutil convert "$work_dir/writable.dmg" -format UDZO -imagekey zlib-level=9 \
    -o "$publish_dir/finished.dmg" -quiet
hdiutil verify "$publish_dir/finished.dmg" -quiet
# An atomic, exclusive link preserves any output created by another build in the meantime.
ln "$publish_dir/finished.dmg" "$output"
printf 'Created %s\n' "$output"
