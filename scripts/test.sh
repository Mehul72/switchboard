#!/bin/bash
#
# Builds the app and runs the test suite. People, CI and release.sh all come
# through here, so a pass means the same thing wherever it happened.
#
#   ./scripts/test.sh
#   ./scripts/test.sh -only-testing:SwitchboardTests/WindowLayoutTests
#
# The suite needs a logged-in desktop. It takes keyboard focus for a few
# seconds and opens a file picker briefly.
set -euo pipefail

cd "$(dirname "$0")/.."

exec xcodebuild -project Switchboard.xcodeproj -scheme Switchboard \
  -destination 'platform=macOS' \
  -derivedDataPath "${SWITCHBOARD_TEST_DERIVED_DATA:-build/tests}" \
  CODE_SIGNING_ALLOWED=NO test "$@"
