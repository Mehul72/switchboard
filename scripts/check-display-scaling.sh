#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/switchboard-display-scaling.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT HUP INT TERM

cd "$project_root"
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Werror \
    -c Switchboard/Support/VirtualDisplayBridge.m -o "$check_dir/VirtualDisplayBridge.o"
xcrun swiftc -parse-as-library -swift-version 5 -module-cache-path "$check_dir/module-cache" \
    -import-objc-header Switchboard/Support/VirtualDisplayBridge.h \
    Switchboard/Services/DisplayScalingModels.swift \
    Switchboard/Services/DisplayScalingBackend.swift \
    scripts/check-display-scaling.swift "$check_dir/VirtualDisplayBridge.o" \
    -framework AppKit -framework CoreGraphics -o "$check_dir/check-display-scaling"
"$check_dir/check-display-scaling"
