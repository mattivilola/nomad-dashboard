#!/bin/zsh
set -euo pipefail

# Writes the launchd property list of the privileged power helper into the app bundle at
# Contents/Library/LaunchDaemons/<label>.plist, where SMAppService.daemon(plistName:) looks for it.
# The label differs between the debug and release app, so the file is produced from the build settings
# (Config/Identity.*.xcconfig) instead of being checked in twice. Run as an Xcode build phase of the app target.

: "${NOMAD_POWER_HELPER_LABEL:?NOMAD_POWER_HELPER_LABEL is not set}"
: "${NOMAD_POWER_HELPER_PRODUCT_NAME:?NOMAD_POWER_HELPER_PRODUCT_NAME is not set}"
: "${NOMAD_APP_BUNDLE_IDENTIFIER:?NOMAD_APP_BUNDLE_IDENTIFIER is not set}"
: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is not set}"
: "${CONTENTS_FOLDER_PATH:?CONTENTS_FOLDER_PATH is not set}"

DESTINATION_DIR="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchDaemons"
PLIST_PATH="$DESTINATION_DIR/$NOMAD_POWER_HELPER_LABEL.plist"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

mkdir -p "$DESTINATION_DIR"
rm -f "$PLIST_PATH"

"$PLIST_BUDDY" \
  -c "Add :Label string $NOMAD_POWER_HELPER_LABEL" \
  -c "Add :BundleProgram string Contents/Library/HelperTools/$NOMAD_POWER_HELPER_PRODUCT_NAME" \
  -c "Add :MachServices dict" \
  -c "Add :MachServices:$NOMAD_POWER_HELPER_LABEL bool true" \
  -c "Add :AssociatedBundleIdentifiers array" \
  -c "Add :AssociatedBundleIdentifiers:0 string $NOMAD_APP_BUNDLE_IDENTIFIER" \
  -c "Add :RunAtLoad bool true" \
  "$PLIST_PATH" >/dev/null

/usr/bin/plutil -lint "$PLIST_PATH" >/dev/null
