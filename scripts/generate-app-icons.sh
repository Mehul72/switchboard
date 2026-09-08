#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
master="$project_root/docs/brand/app-icon-master.png"
icon_set="$project_root/Switchboard/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$master" ]; then
    printf 'App icon master is missing: %s\n' "$master" >&2
    exit 1
fi

for size in 16 32 64 128 256 512 1024; do
    sips --resampleHeightWidth "$size" "$size" "$master" \
        --out "$icon_set/icon_$size.png" >/dev/null
done

printf 'Generated all seven macOS app icon sizes from %s\n' "$master"
