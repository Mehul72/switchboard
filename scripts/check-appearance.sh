#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/switchboard-appearance.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM

xcrun swiftc -parse-as-library -module-cache-path "$check_dir/module-cache" \
    "$project_root/Switchboard/Views/Theme.swift" \
    "$project_root/scripts/check-appearance.swift" -o "$check_dir/check-appearance"
"$check_dir/check-appearance"
