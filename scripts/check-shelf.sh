#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/switchboard-shelf.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM

cd "$project_root"
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$check_dir/module-cache" \
    Switchboard/Services/FileShelf.swift \
    Switchboard/Services/ShelfVolumes.swift \
    Switchboard/Support/ShelfDragging.swift \
    Switchboard/Views/Theme.swift \
    Switchboard/Views/FileShelfView.swift \
    Switchboard/App/FileShelfController.swift \
    scripts/check-shelf.swift -o "$check_dir/check-shelf"
"$check_dir/check-shelf" "$@"
