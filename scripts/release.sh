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
TEAM_ID="MACDPWQG37"
KEYCHAIN_PROFILE="switchboard-notary"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_NAME="Switchboard"

cd "$(dirname "$0")/.."

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[31mFAILED: %s\033[0m\n" "$1" >&2; exit 1; }

# --- preflight -------------------------------------------------------------
step "Checking prerequisites"
# Capture first: under `set -o pipefail`, `grep -q` exits on the first match and
# the producer dies of SIGPIPE, which fails the pipeline however the match went.
IDENTITIES=$(security find-identity -v -p codesigning 2>&1 || true)
case "$IDENTITIES" in
  *"Developer ID Application"*) ;;
  *) fail "No Developer ID Application certificate. Create one in Xcode > Settings > Accounts." ;;
esac
xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1 \
  || fail "Notary credentials '$KEYCHAIN_PROFILE' not stored. See the header of this script."
echo "  certificate and notary credentials present"

# Apple rejects a build number it has already seen, so bump it every run.
CURRENT_BUILD=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk '/CURRENT_PROJECT_VERSION/{print $3; exit}')
NEXT_BUILD=$((CURRENT_BUILD + 1))
MARKETING=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk '/MARKETING_VERSION/{print $3; exit}')
echo "  version $MARKETING, build $CURRENT_BUILD -> $NEXT_BUILD"
sed -i '' "s/CURRENT_PROJECT_VERSION = $CURRENT_BUILD;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/g" \
  "$PROJECT/project.pbxproj"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- archive and export ----------------------------------------------------
# Keep release products away from Xcode's shared Derived Data. Cleaning the
# shared target can delete a running Debug app's bundle and leave its process
# unable to register itself as a login item.
step "Cleaning previous Release products"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED_DATA" clean >/dev/null 2>&1 || true

step "Archiving"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED_DATA" -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" archive \
  | grep -E "error:|warning: .*\.swift|BUILD" || true
[ -d "$BUILD_DIR/$APP_NAME.xcarchive" ] || fail "Archive not produced."

step "Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/$APP_NAME.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist ExportOptions.plist \
  | grep -E "error:|EXPORT" || true
APP="$BUILD_DIR/export/$APP_NAME.app"
[ -d "$APP" ] || fail "Export not produced."

step "Verifying the signature before submitting"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
SIGN_INFO=$(codesign -dvvv "$APP" 2>&1 || true)
printf '%s\n' "$SIGN_INFO" | grep -E "Authority=Developer ID|flags=" | head -2
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
DMG_ROOT="$BUILD_DIR/dmg"
mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
DMG="$BUILD_DIR/$APP_NAME-$MARKETING.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG" >/dev/null
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

step "Done"
echo "  $DMG"
echo "  version $MARKETING (build $NEXT_BUILD)"
echo
echo "  Gatekeeper check on this machine:"
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | sed 's/^/    /' || true
echo
echo "  Upload the .dmg to a GitHub release."
