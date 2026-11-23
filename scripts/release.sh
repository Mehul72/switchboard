#!/bin/bash
#
# Builds, signs, notarises and packages Switchboard for direct distribution.
#
# One time setup, storing an app specific password from appleid.apple.com
# (not your Apple ID password):
#
#   xcrun notarytool store-credentials switchboard-notary \
#       --apple-id you@example.com --team-id MACDPWQG37
#
# Leaving --password off makes notarytool prompt for it securely, so the
# password never lands in your shell history. It validates against Apple
# before saving to the Keychain.
#
# Then:  ./scripts/release.sh
#
set -euo pipefail

PROJECT="Switchboard.xcodeproj"
SCHEME="Switchboard"
KEYCHAIN_PROFILE="switchboard-notary"
RELEASE_ROOT="build/releases"
APP_NAME="Switchboard"

cd "$(dirname "$0")/.."

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[31mFAILED: %s\033[0m\n" "$1" >&2; exit 1; }

# --- preflight -------------------------------------------------------------
step "Checking prerequisites"
# Capture first: under `set -o pipefail`, `grep -q` exits on the first match and
# the producer dies of SIGPIPE, which fails the pipeline however the match went.
if ! IDENTITIES=$(security find-identity -v -p codesigning 2>&1); then
  fail "Could not read signing identities from the Keychain."
fi
case "$IDENTITIES" in
  *"Developer ID Application"*) ;;
  *) fail "No Developer ID Application certificate. Create one in Xcode > Settings > Accounts." ;;
esac
xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1 \
  || fail "Could not authenticate with notary profile '$KEYCHAIN_PROFILE'. Refresh its credentials using the secure prompt described above, then retry."
echo "  certificate and notary credentials present"

# Before the build number is bumped, so a failing suite leaves the project
# file untouched. The suite takes keyboard focus for a few seconds.
step "Running the tests"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/switchboard-release-tests.XXXXXX")
if ! SWITCHBOARD_TEST_DERIVED_DATA="$TEST_DIR/DerivedData" ./scripts/test.sh > "$TEST_DIR/test.log" 2>&1; then
  grep -E "error:|Test Case .* failed" "$TEST_DIR/test.log" | tail -20 || true
  fail "Tests failed. Full log: $TEST_DIR/test.log"
fi
grep -E "Executed [0-9]+ tests" "$TEST_DIR/test.log" | tail -1 \
  || fail "The test run returned no test summary. Full log: $TEST_DIR/test.log"

# Apple rejects a build number it has already seen, so bump it every run.
if ! BUILD_SETTINGS=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2> "$TEST_DIR/build-settings.log"); then
  fail "Could not read release build settings. Full log: $TEST_DIR/build-settings.log"
fi
CURRENT_BUILD=$(printf '%s\n' "$BUILD_SETTINGS" | awk '/CURRENT_PROJECT_VERSION =/ && !found { value=$3; found=1 } END { print value }')
MARKETING=$(printf '%s\n' "$BUILD_SETTINGS" | awk '/MARKETING_VERSION =/ && !found { value=$3; found=1 } END { print value }')
[[ "$CURRENT_BUILD" =~ ^[0-9]{1,9}$ ]] || fail "Invalid build number: $CURRENT_BUILD"
[[ "$MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Invalid release version: $MARKETING"
NEXT_BUILD=$((10#$CURRENT_BUILD + 1))
BUILD_DIR="$RELEASE_ROOT/$MARKETING-build-$NEXT_BUILD"
DERIVED_DATA="$BUILD_DIR/DerivedData"
mkdir -p "$RELEASE_ROOT"
# Reserving a new directory prevents an old archive from satisfying a failed build.
mkdir "$BUILD_DIR" || fail "Release output already exists or cannot be created: $BUILD_DIR"
cp "$TEST_DIR/test.log" "$TEST_DIR/build-settings.log" "$BUILD_DIR/"
rm -rf "$TEST_DIR"
echo "  version $MARKETING, build $CURRENT_BUILD -> $NEXT_BUILD"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/g" \
  "$PROJECT/project.pbxproj"

# --- archive and export ----------------------------------------------------
# A fresh, isolated Derived Data directory preserves running apps and older builds.
step "Archiving"
if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED_DATA" -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" archive \
  > "$BUILD_DIR/archive.log" 2>&1; then
  tail -40 "$BUILD_DIR/archive.log"
  fail "Archive failed. Full log: $BUILD_DIR/archive.log"
fi
[ -d "$BUILD_DIR/$APP_NAME.xcarchive" ] || fail "Archive not produced."

step "Exporting with Developer ID"
if ! xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist ExportOptions.plist \
  > "$BUILD_DIR/export.log" 2>&1; then
  tail -40 "$BUILD_DIR/export.log"
  fail "Developer ID export failed. Full log: $BUILD_DIR/export.log"
fi
APP="$BUILD_DIR/export/$APP_NAME.app"
[ -d "$APP" ] || fail "Export not produced."

step "Verifying the signature before submitting"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
SIGN_INFO=$(codesign -dvvv "$APP" 2>&1) || fail "Could not inspect the exported app's signature."
printf '%s\n' "$SIGN_INFO" > "$BUILD_DIR/signature.log"
printf '%s\n' "$SIGN_INFO" | awk '/Authority=Developer ID|flags=/ { if (++count <= 2) print }'
case "$SIGN_INFO" in
  *"(runtime)"*) ;;
  *) fail "Hardened Runtime is off. Notarisation will be rejected." ;;
esac
case "$SIGN_INFO" in
  *"Developer ID Application"*) ;;
  *) fail "Not signed with Developer ID. Check the Release signing identity." ;;
esac

# --- notarise --------------------------------------------------------------
step "Notarising (a few minutes)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"
xcrun notarytool submit "$BUILD_DIR/$APP_NAME.zip" \
  --keychain-profile "$KEYCHAIN_PROFILE" --wait 2>&1 | tee "$BUILD_DIR/notary.log"
grep -q "status: Accepted" "$BUILD_DIR/notary.log" || {
  ID=$(awk '/id:/{print $2; exit}' "$BUILD_DIR/notary.log")
  echo "Fetching the rejection reason..."
  xcrun notarytool log "$ID" --keychain-profile "$KEYCHAIN_PROFILE" || true
  fail "Notarisation rejected."
}

step "Stapling"
# Without the staple the app refuses to launch for anyone who is offline.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- package ---------------------------------------------------------------
step "Building the disk image"
# A drag to Applications matters: run from Downloads, macOS translocates the app
# to a read only path and every permission grant silently breaks.
DMG="$BUILD_DIR/$APP_NAME-$MARKETING.dmg"
./scripts/build-dmg.sh "$APP" "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"

step "Notarising the disk image"
# The image needs a submission of its own. Stapling the app's ticket to it fails
# with "Record not found", because a ticket belongs to the exact thing uploaded.
xcrun notarytool submit "$DMG" \
  --keychain-profile "$KEYCHAIN_PROFILE" --wait 2>&1 | tee "$BUILD_DIR/notary-dmg.log"
grep -q "status: Accepted" "$BUILD_DIR/notary-dmg.log" || {
  ID=$(awk '/id:/{print $2; exit}' "$BUILD_DIR/notary-dmg.log")
  xcrun notarytool log "$ID" --keychain-profile "$KEYCHAIN_PROFILE" || true
  fail "Disk image notarisation rejected."
}
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

step "Checking Gatekeeper"
if ! spctl -a -vvv -t open --context context:primary-signature "$DMG" \
  > "$BUILD_DIR/gatekeeper.log" 2>&1; then
  cat "$BUILD_DIR/gatekeeper.log"
  fail "Gatekeeper rejected the disk image. Full log: $BUILD_DIR/gatekeeper.log"
fi
cat "$BUILD_DIR/gatekeeper.log"

step "Done"
echo "  $DMG"
echo "  version $MARKETING (build $NEXT_BUILD)"
echo
echo "  Full release logs: $BUILD_DIR"
echo "  Upload the .dmg to a GitHub release."
