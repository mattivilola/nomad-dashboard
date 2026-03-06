#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="artifacts/NomadDashboard.xcarchive/Products/Applications/Nomad Dashboard.app"
STAGING_DIR="artifacts/dmg-staging"
DMG_PATH="artifacts/NomadDashboard.dmg"
VOLUME_NAME="Nomad Dashboard"
BACKGROUND_SOURCE="Branding/Exports/NomadDashboard-dmg-background.tiff"
WINDOW_BOUNDS="{120, 120, 780, 540}"
APP_POSITION="{150, 214}"
APPLICATIONS_POSITION="{490, 214}"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nomad-dashboard-dmg.XXXXXX")"
RW_DMG_PATH="$TEMP_DIR/NomadDashboard-readwrite.dmg"
MOUNT_DIR="$TEMP_DIR/mount"
DEVICE=""
VOLUME_ICON_SOURCE=""

cleanup() {
  local exit_code="$?"

  if [[ -n "$DEVICE" ]]; then
    hdiutil detach "$DEVICE" -quiet >/dev/null 2>&1 || hdiutil detach "$DEVICE" -force -quiet >/dev/null 2>&1 || true
  fi

  rm -rf "$TEMP_DIR"
  exit "$exit_code"
}

prepare_applications_alias() {
  osascript <<EOF
set stagingFolder to POSIX file "$STAGING_DIR" as alias
tell application "Finder"
  make new alias file at stagingFolder to POSIX file "/Applications" with properties {name:"Applications"}
end tell
EOF
}

configure_staging_window() {
  osascript <<EOF
set backgroundAlias to POSIX file "$STAGING_DIR/.background/background.tiff" as alias
set stagingFolder to POSIX file "$STAGING_DIR" as alias
tell application "Finder"
  open stagingFolder
  delay 1
  set stagingWindow to front Finder window
  set current view of stagingWindow to icon view
  set toolbar visible of stagingWindow to false
  set statusbar visible of stagingWindow to false
  set the bounds of stagingWindow to $WINDOW_BOUNDS
  set viewOptions to the icon view options of stagingWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 144
  set text size of viewOptions to 14
  set background picture of viewOptions to backgroundAlias
  set position of item "Nomad Dashboard.app" of stagingWindow to $APP_POSITION
  set position of item "Applications" of stagingWindow to $APPLICATIONS_POSITION
  close stagingWindow
  open stagingFolder
  delay 1
  set stagingWindow to front Finder window
  delay 2
  close stagingWindow
end tell
EOF
}

configure_mounted_window() {
  osascript <<EOF
set backgroundAlias to POSIX file "$MOUNT_DIR/.background/background.tiff" as alias
set mountedFolder to POSIX file "$MOUNT_DIR" as alias
tell application "Finder"
  open mountedFolder
  activate
  delay 1
  set dmgWindow to front Finder window
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set the bounds of dmgWindow to $WINDOW_BOUNDS
  set viewOptions to the icon view options of dmgWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 144
  set text size of viewOptions to 14
  set background picture of viewOptions to backgroundAlias
  set position of item "Nomad Dashboard.app" of dmgWindow to $APP_POSITION
  set position of item "Applications" of dmgWindow to $APPLICATIONS_POSITION
  delay 1
  close dmgWindow
end tell
EOF
}

trap cleanup EXIT INT TERM

cd "$REPO_ROOT"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive not found at $APP_PATH. Run ./scripts/archive-release.sh first." >&2
  exit 1
fi

if [[ ! -f "$BACKGROUND_SOURCE" ]]; then
  ./scripts/export-brand-assets.sh
fi

VOLUME_ICON_SOURCE="$(find "$APP_PATH/Contents/Resources" -maxdepth 1 -name '*.icns' | head -n 1)"
if [[ -z "$VOLUME_ICON_SOURCE" ]]; then
  echo "App icon not found in $APP_PATH/Contents/Resources. Rebuild the archive before packaging the DMG." >&2
  exit 1
fi

mkdir -p "$STAGING_DIR"
rm -rf "$STAGING_DIR/Nomad Dashboard.app" \
  "$STAGING_DIR/Applications" \
  "$STAGING_DIR/.background" \
  "$STAGING_DIR/.VolumeIcon.icns"
cp -R "$APP_PATH" "$STAGING_DIR/"
mkdir -p "$STAGING_DIR/.background"
cp "$BACKGROUND_SOURCE" "$STAGING_DIR/.background/background.tiff"
cp "$VOLUME_ICON_SOURCE" "$STAGING_DIR/.VolumeIcon.icns"
prepare_applications_alias
for hidden_path in "$STAGING_DIR/.background" "$STAGING_DIR/.background/background.tiff" "$STAGING_DIR/.VolumeIcon.icns"; do
  SetFile -a V "$hidden_path"
done
configure_staging_window

DMG_SIZE_KB="$(du -sk "$STAGING_DIR" | awk '{print $1}')"
DMG_SIZE_KB="$((DMG_SIZE_KB + 16384))"

hdiutil create \
  -srcfolder "$STAGING_DIR" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDRW \
  -size "${DMG_SIZE_KB}k" \
  -ov \
  "$RW_DMG_PATH" >/dev/null

DEVICE="$(
  hdiutil attach \
    "$RW_DMG_PATH" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$MOUNT_DIR" |
    awk '/^\/dev\// {print $1; exit}'
)"

if [[ -z "$DEVICE" ]]; then
  echo "Unable to mount DMG for Finder customization." >&2
  exit 1
fi

for hidden_path in "$MOUNT_DIR/.background" "$MOUNT_DIR/.background/background.tiff" "$MOUNT_DIR/.VolumeIcon.icns"; do
  SetFile -a V "$hidden_path"
done
SetFile -a C "$MOUNT_DIR"
configure_mounted_window
sync
sleep 1

hdiutil detach "$DEVICE" -quiet >/dev/null
DEVICE=""

hdiutil convert \
  "$RW_DMG_PATH" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  -o "$DMG_PATH" >/dev/null

echo "Created $DMG_PATH"
