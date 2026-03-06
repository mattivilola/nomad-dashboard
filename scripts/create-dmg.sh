#!/bin/zsh
set -euo pipefail

APP_PATH="artifacts/NomadDashboard.xcarchive/Products/Applications/Nomad Dashboard.app"
STAGING_DIR="artifacts/dmg-staging"
DMG_PATH="artifacts/NomadDashboard.dmg"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Archive not found at $APP_PATH. Run ./scripts/archive-release.sh first." >&2
  exit 1
fi

mkdir -p "$STAGING_DIR"
rm -rf "$STAGING_DIR/Nomad Dashboard.app"
cp -R "$APP_PATH" "$STAGING_DIR/"

hdiutil create \
  -volname "Nomad Dashboard" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

