#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/MsgVaultMacDesktop/MsgVaultMacDesktop.xcodeproj"
SCHEME="${SCHEME:-MsgVaultMacDesktop}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-MailTrawl}"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${TEAM_ID:-H5V83A3XV8}"
EXPORT_METHOD="${EXPORT_METHOD:-developer-id}"
ALLOW_DEVELOPMENT_FALLBACK="${ALLOW_DEVELOPMENT_FALLBACK:-1}"

BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
ARCHIVE_PATH="$BUILD_DIR/${SCHEME}.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
EXPORT_OPTIONS_PATH="$BUILD_DIR/exportOptions.plist"
DMG_STAGE_PATH="$BUILD_DIR/dmg-root"
DMG_PATH="$BUILD_DIR/${APP_DISPLAY_NAME}.dmg"

NOTARIZE="${NOTARIZE:-1}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"

log() {
  printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$1"
}

fail() {
  printf "\nERROR: %s\n" "$1" >&2
  exit 1
}

[[ -d "$ROOT_DIR" ]] || fail "Repository root not found: $ROOT_DIR"
[[ -d "$PROJECT_PATH" ]] || fail "Xcode project not found: $PROJECT_PATH"

mkdir -p "$BUILD_DIR"

identities="$(security find-identity -v -p codesigning || true)"
if [[ "$EXPORT_METHOD" == "developer-id" && "$identities" != *"Developer ID Application"* ]]; then
  if [[ "$ALLOW_DEVELOPMENT_FALLBACK" == "1" ]]; then
    log "No Developer ID Application certificate found. Falling back to development export."
    EXPORT_METHOD="development"
    NOTARIZE="0"
  else
    fail "Developer ID Application certificate not found, and fallback is disabled."
  fi
fi

if [[ "$EXPORT_METHOD" != "developer-id" && "$NOTARIZE" == "1" ]]; then
  log "Export method '$EXPORT_METHOD' cannot be notarized for external distribution. Disabling notarization."
  NOTARIZE="0"
fi

log "Writing export options plist"
cat >"$EXPORT_OPTIONS_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
</dict>
</plist>
EOF

log "Cleaning previous build artifacts"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DMG_STAGE_PATH" "$DMG_PATH"

log "Archiving app (Release)"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -archivePath "$ARCHIVE_PATH"

log "Exporting signed app"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PATH"

shopt -s nullglob
apps=("$EXPORT_PATH"/*.app)
shopt -u nullglob
(( ${#apps[@]} > 0 )) || fail "No exported .app found in $EXPORT_PATH"
APP_PATH="${apps[0]}"
APP_NAME="$(basename "$APP_PATH")"

# ── Inject a complete AppIcon.icns built via iconutil ─────────────────────
# actool sometimes rejects large PNG sizes; iconutil is always reliable.
log "Building full AppIcon.icns via iconutil and injecting into app bundle"
ICON_SRC="$ROOT_DIR/MsgVaultMacDesktop/MsgVaultMacDesktop/Assets.xcassets/AppIcon.appiconset"
ICONSET_TMP="$BUILD_DIR/AppIcon.iconset"
ICNS_TMP="$BUILD_DIR/AppIcon.icns"
rm -rf "$ICONSET_TMP" && mkdir -p "$ICONSET_TMP"

sips -z 16   16   "$ICON_SRC/icon-16.png"   --out "$ICONSET_TMP/icon_16x16.png"    >/dev/null
sips -z 32   32   "$ICON_SRC/icon-32.png"   --out "$ICONSET_TMP/icon_16x16@2x.png" >/dev/null
sips -z 32   32   "$ICON_SRC/icon-32.png"   --out "$ICONSET_TMP/icon_32x32.png"    >/dev/null
sips -z 64   64   "$ICON_SRC/icon-64.png"   --out "$ICONSET_TMP/icon_32x32@2x.png" >/dev/null
sips -z 128  128  "$ICON_SRC/icon-128.png"  --out "$ICONSET_TMP/icon_128x128.png"  >/dev/null
sips -z 256  256  "$ICON_SRC/icon-256.png"  --out "$ICONSET_TMP/icon_128x128@2x.png" >/dev/null
sips -z 256  256  "$ICON_SRC/icon-256.png"  --out "$ICONSET_TMP/icon_256x256.png"  >/dev/null
sips -z 512  512  "$ICON_SRC/icon-512.png"  --out "$ICONSET_TMP/icon_256x256@2x.png" >/dev/null
sips -z 512  512  "$ICON_SRC/icon-512.png"  --out "$ICONSET_TMP/icon_512x512.png"  >/dev/null
sips -z 1024 1024 "$ICON_SRC/icon-1024.png" --out "$ICONSET_TMP/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_TMP" -o "$ICNS_TMP"

ICNS_DEST="$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$ICNS_TMP" "$ICNS_DEST"
log "AppIcon.icns replaced ($(wc -c <"$ICNS_TMP" | tr -d ' ') bytes)"

# Re-sign the app with the new icon injected
SIGN_ID="$(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed -E 's/.*\) //' | sed 's/ .*//')"
if [[ -n "$SIGN_ID" ]]; then
  log "Re-signing app after icon injection: $SIGN_ID"
  codesign --force --deep --sign "$SIGN_ID" -o runtime "$APP_PATH"
else
  log "No Developer ID cert found — skipping re-sign (development build)"
fi

log "Staging app for DMG: $APP_NAME"
mkdir -p "$DMG_STAGE_PATH"
cp -R "$APP_PATH" "$DMG_STAGE_PATH/"

log "Generating DMG background image"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKGROUND_IMG="$SCRIPTS_DIR/dmg-background.png"
python3 "$SCRIPTS_DIR/generate-dmg-background.py"

log "Creating DMG with installer window"
# Icon centres (px) within the 660×400 window:
#   App icon      x=165, y=185
#   Applications  x=495, y=185
create-dmg \
  --volname "$APP_DISPLAY_NAME" \
  --background "$BACKGROUND_IMG" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 120 \
  --icon "$APP_NAME" 165 185 \
  --hide-extension "$APP_NAME" \
  --app-drop-link 495 185 \
  "$DMG_PATH" \
  "$DMG_STAGE_PATH/"

if [[ "$NOTARIZE" == "1" ]]; then
  log "Submitting DMG for notarization using profile '$NOTARY_PROFILE'"
  set +e
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  submit_status=$?
  set -e

  if [[ $submit_status -ne 0 ]]; then
    if [[ -n "${APPLE_ID:-}" && -n "${APP_SPECIFIC_PASSWORD:-}" ]]; then
      log "Existing profile failed. Attempting to store credentials and retry."
      xcrun notarytool store-credentials "$NOTARY_PROFILE" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD"
      xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    else
      fail "Notarization failed. Configure profile '$NOTARY_PROFILE' or set APPLE_ID and APP_SPECIFIC_PASSWORD."
    fi
  fi

  log "Stapling notarization ticket"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  log "Gatekeeper verification"
  set +e
  spctl_output="$(spctl -a -vv -t open "$DMG_PATH" 2>&1)"
  spctl_status=$?
  set -e
  if [[ $spctl_status -ne 0 ]]; then
    if [[ "$spctl_output" == *"Insufficient Context"* ]]; then
      log "Gatekeeper open check returned 'Insufficient Context' (common for local DMG checks)."
      printf "%s\n" "$spctl_output"
    else
      fail "Gatekeeper verification failed:\n$spctl_output"
    fi
  else
    printf "%s\n" "$spctl_output"
  fi
else
  log "NOTARIZE=0, skipping notarization and stapling"
fi

log "Done. DMG available at: $DMG_PATH"
