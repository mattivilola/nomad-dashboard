#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/release-common.sh"
cd "$REPO_ROOT"

DRY_RUN="false"

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
fi

load_signing_env

if [[ "$DRY_RUN" == "true" ]]; then
  print_release_summary
  cat <<EOF
Dry run steps
  1. Archive the app with release signing and Sparkle metadata overrides.
  2. Verify the archive is Developer ID signed and contains the release feed/public key.
  3. Notarize a temporary ZIP submission for the archived app.
  4. Staple the archived app bundle, repackage the final Sparkle ZIP, and create the versioned DMG.
  5. Notarize and staple the DMG.
EOF
  exit 0
fi

require_command codesign
require_command ditto
require_command hdiutil
require_command security
require_command xcrun

assert_clean_worktree
assert_version_file_present
assert_release_tag_matches_head
assert_release_signing_config
assert_signing_identity_available
assert_notary_profile_available
ensure_release_dirs

TEMP_NOTARY_ZIP="$(release_notary_zip_path)"
FINAL_ZIP_PATH="$(release_zip_path)"
FINAL_DMG_PATH="$(release_dmg_path)"
SPARKLE_FRAMEWORK_PATH="$ARCHIVE_APP_PATH/Contents/Frameworks/Sparkle.framework"

codesign_item() {
  local path="$1"

  /usr/bin/codesign \
    --force \
    --sign "$NOMAD_SIGNING_IDENTITY" \
    --timestamp \
    --options runtime \
    --preserve-metadata=identifier,entitlements,flags \
    "$path"
}

resign_sparkle_components() {
  [[ -d "$SPARKLE_FRAMEWORK_PATH" ]] || return 0

  local version_root="$SPARKLE_FRAMEWORK_PATH/Versions/B"
  local autoupdate="$version_root/Autoupdate"
  local updater_app="$version_root/Updater.app"
  local downloader_xpc="$version_root/XPCServices/Downloader.xpc"
  local installer_xpc="$version_root/XPCServices/Installer.xpc"

  [[ -f "$autoupdate" ]] && codesign_item "$autoupdate"

  if [[ -d "$downloader_xpc" ]]; then
    [[ -f "$downloader_xpc/Contents/MacOS/Downloader" ]] && codesign_item "$downloader_xpc/Contents/MacOS/Downloader"
    codesign_item "$downloader_xpc"
  fi

  if [[ -d "$installer_xpc" ]]; then
    [[ -f "$installer_xpc/Contents/MacOS/Installer" ]] && codesign_item "$installer_xpc/Contents/MacOS/Installer"
    codesign_item "$installer_xpc"
  fi

  if [[ -d "$updater_app" ]]; then
    [[ -f "$updater_app/Contents/MacOS/Updater" ]] && codesign_item "$updater_app/Contents/MacOS/Updater"
    codesign_item "$updater_app"
  fi

  codesign_item "$SPARKLE_FRAMEWORK_PATH"
  codesign_item "$ARCHIVE_APP_PATH"
}

./scripts/archive-release.sh
resign_sparkle_components

codesign --verify --deep --strict --verbose=2 "$ARCHIVE_APP_PATH"
assert_archive_is_not_adhoc
assert_archive_update_configuration
assert_archive_has_no_tankerkonig_api_key
assert_archive_weatherkit_entitlement

rm -f "$TEMP_NOTARY_ZIP" "$FINAL_ZIP_PATH" "$FINAL_DMG_PATH"

ditto -c -k --sequesterRsrc --keepParent "$ARCHIVE_APP_PATH" "$TEMP_NOTARY_ZIP"
xcrun notarytool submit "$TEMP_NOTARY_ZIP" --keychain-profile "$NOMAD_NOTARY_PROFILE" --wait

xcrun stapler staple "$ARCHIVE_APP_PATH"
xcrun stapler validate "$ARCHIVE_APP_PATH"

ditto -c -k --sequesterRsrc --keepParent "$ARCHIVE_APP_PATH" "$FINAL_ZIP_PATH"
./scripts/create-dmg.sh --app-path "$ARCHIVE_APP_PATH" --output-path "$FINAL_DMG_PATH"
xcrun notarytool submit "$FINAL_DMG_PATH" --keychain-profile "$NOMAD_NOTARY_PROFILE" --wait
xcrun stapler staple "$FINAL_DMG_PATH"
xcrun stapler validate "$FINAL_DMG_PATH"

cat <<EOF
Signed and notarized release artifacts
  Sparkle ZIP: $FINAL_ZIP_PATH
  DMG: $FINAL_DMG_PATH
EOF
