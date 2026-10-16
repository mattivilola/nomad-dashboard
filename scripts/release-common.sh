#!/bin/zsh

if [[ -n "${NOMAD_RELEASE_COMMON_LOADED:-}" ]]; then
  return 0
fi

NOMAD_RELEASE_COMMON_LOADED=1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/Config/Version.xcconfig"
CHANGELOG_FILE="$REPO_ROOT/CHANGELOG.md"
DEFAULT_SIGNING_ENV_FILE="$REPO_ROOT/Config/Signing.env"
ARTIFACTS_ROOT="$REPO_ROOT/artifacts"
ARCHIVE_PATH="$ARTIFACTS_ROOT/NomadDashboard.xcarchive"
ARCHIVE_APP_PATH="$ARCHIVE_PATH/Products/Applications/Nomad Dashboard.app"
DEFAULT_GITHUB_REPOSITORY="mattivilola/nomad-dashboard"
WIDGET_EXTENSION_NAME="NomadDashboardWidgets.appex"
WIDGET_BUNDLE_IDENTIFIER="com.iloapps.NomadDashboard.widgets"
APP_GROUP_ENTITLEMENT_KEY="com.apple.security.application-groups"
APP_SANDBOX_ENTITLEMENT_KEY="com.apple.security.app-sandbox"
ARCHIVE_PLUGINS_PATH="$ARCHIVE_APP_PATH/Contents/PlugIns"
ARCHIVE_WIDGET_PATH="$ARCHIVE_PLUGINS_PATH/$WIDGET_EXTENSION_NAME"
# The privileged power helper (Keep Awake with the lid closed). Its label is the app's bundle identifier plus
# ".PowerHelper" (Config/Identity.Release.xcconfig); the launchd plist is named after the label.
APP_BUNDLE_IDENTIFIER="com.iloapps.NomadDashboard"
POWER_HELPER_BINARY_NAME="NomadDashboardPowerHelper"
POWER_HELPER_LABEL="$APP_BUNDLE_IDENTIFIER.PowerHelper"
ARCHIVE_POWER_HELPER_PATH="$ARCHIVE_APP_PATH/Contents/Library/HelperTools/$POWER_HELPER_BINARY_NAME"
ARCHIVE_POWER_HELPER_PLIST_PATH="$ARCHIVE_APP_PATH/Contents/Library/LaunchDaemons/$POWER_HELPER_LABEL.plist"

fail() {
  echo "$1" >&2
  exit 1
}

log() {
  echo "$1"
}

require_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 || fail "Required command not found: $command_name"
}

load_signing_env() {
  local env_file="${NOMAD_SIGNING_ENV_FILE:-$DEFAULT_SIGNING_ENV_FILE}"

  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi

  : "${NOMAD_GITHUB_REPOSITORY:=$DEFAULT_GITHUB_REPOSITORY}"
  export NOMAD_GITHUB_REPOSITORY
}

read_xcconfig_value() {
  local key="$1"
  sed -n "s/^${key}[[:space:]]*=[[:space:]]*//p" "$VERSION_FILE" | head -n 1
}

release_version() {
  read_xcconfig_value MARKETING_VERSION
}

release_build_number() {
  read_xcconfig_value CURRENT_PROJECT_VERSION
}

release_tag() {
  printf 'v%s\n' "$(release_version)"
}

release_title() {
  printf 'Nomad Dashboard %s\n' "$(release_version)"
}

release_feed_url() {
  printf 'https://github.com/%s/releases/latest/download/appcast.xml\n' "$NOMAD_GITHUB_REPOSITORY"
}

release_download_url_prefix() {
  printf 'https://github.com/%s/releases/download/%s/\n' "$NOMAD_GITHUB_REPOSITORY" "$(release_tag)"
}

release_work_dir() {
  printf '%s/release/%s\n' "$ARTIFACTS_ROOT" "$(release_tag)"
}

release_basename() {
  printf 'NomadDashboard-%s\n' "$(release_version)"
}

release_zip_path() {
  printf '%s/%s.zip\n' "$(release_work_dir)" "$(release_basename)"
}

release_dmg_path() {
  printf '%s/%s.dmg\n' "$(release_work_dir)" "$(release_basename)"
}

release_appcast_path() {
  printf '%s/appcast.xml\n' "$(release_work_dir)"
}

release_notes_markdown_path() {
  printf '%s/RELEASE_NOTES.md\n' "$(release_work_dir)"
}

release_notes_text_path() {
  printf '%s/%s.txt\n' "$(release_work_dir)" "$(release_basename)"
}

release_notary_zip_path() {
  printf '%s/%s.notary.zip\n' "$(release_work_dir)" "$(release_basename)"
}

appcast_source_dir() {
  printf '%s/appcast-source\n' "$(release_work_dir)"
}

ensure_release_dirs() {
  mkdir -p "$ARTIFACTS_ROOT" "$(release_work_dir)" "$(appcast_source_dir)"
}

assert_clean_worktree() {
  local dirty_status
  dirty_status="$(git -C "$REPO_ROOT" status --short)"

  [[ -z "$dirty_status" ]] || fail $'Release commands require a clean git working tree.\nDirty paths:\n'"$dirty_status"
}

assert_release_tag_matches_head() {
  local exact_tag expected_tag

  exact_tag="$(git -C "$REPO_ROOT" describe --tags --exact-match HEAD 2>/dev/null || true)"
  expected_tag="$(release_tag)"

  [[ "$exact_tag" == "$expected_tag" ]] || fail "Expected HEAD to be tagged $expected_tag before releasing. Current exact tag: ${exact_tag:-none}."
}

assert_version_file_present() {
  [[ -f "$VERSION_FILE" ]] || fail "Missing $VERSION_FILE."
}

assert_changelog_present() {
  [[ -f "$CHANGELOG_FILE" ]] || fail "Missing $CHANGELOG_FILE."
}

extract_release_notes_markdown() {
  local version="$1"

  awk -v version="$version" '
    $0 ~ "^## \\[" version "\\] - " {printing=1; next}
    printing && /^## \[/ {exit}
    printing {print}
  ' "$CHANGELOG_FILE"
}

write_release_notes_files() {
  local markdown_notes text_notes

  ensure_release_dirs
  markdown_notes="$(extract_release_notes_markdown "$(release_version)")"
  [[ -n "${markdown_notes//[$'\n\r\t ']}" ]] || fail "Could not find CHANGELOG entry for $(release_version)."

  printf '## %s\n\n%s\n' "$(release_title)" "$markdown_notes" > "$(release_notes_markdown_path)"
  printf '%s\n' "$markdown_notes" > "$(release_notes_text_path)"
}

trimmed_value() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

assert_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "Missing required file: $path"
}

sparkle_bin_dir() {
  if [[ -n "${NOMAD_SPARKLE_BIN_DIR:-}" ]]; then
    printf '%s\n' "$NOMAD_SPARKLE_BIN_DIR"
    return
  fi

  local search_root found_dir

  for search_root in \
    "$REPO_ROOT/DerivedData" \
    "$HOME/Library/Developer/Xcode/DerivedData"
  do
    [[ -d "$search_root" ]] || continue

    found_dir="$(
      find "$search_root" \
        -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' \
        -type d \
        -print 2>/dev/null |
        head -n 1
    )"

    if [[ -n "$found_dir" ]]; then
      printf '%s\n' "$found_dir"
      return
    fi
  done

  fail "Could not find Sparkle CLI tools. Set NOMAD_SPARKLE_BIN_DIR or run 'make build' once to repopulate DerivedData/SourcePackages/artifacts."
}

generate_appcast_bin() {
  printf '%s/generate_appcast\n' "$(sparkle_bin_dir)"
}

sign_update_bin() {
  printf '%s/sign_update\n' "$(sparkle_bin_dir)"
}

assert_release_signing_config() {
  load_signing_env

  [[ -n "${NOMAD_TEAM_ID:-}" ]] || fail "NOMAD_TEAM_ID is not set. Configure it in Config/Signing.env."
  [[ -n "${NOMAD_SIGNING_IDENTITY:-}" ]] || fail "NOMAD_SIGNING_IDENTITY is not set. Configure it in Config/Signing.env."
  [[ -n "${NOMAD_NOTARY_PROFILE:-}" ]] || fail "NOMAD_NOTARY_PROFILE is not set. Configure it in Config/Signing.env."
  [[ -n "${NOMAD_SPARKLE_PRIVATE_KEY_PATH:-}" ]] || fail "NOMAD_SPARKLE_PRIVATE_KEY_PATH is not set. Configure it in Config/Signing.env."
  [[ -n "${NOMAD_SPARKLE_PUBLIC_ED_KEY:-}" ]] || fail "NOMAD_SPARKLE_PUBLIC_ED_KEY is not set. Configure it in Config/Signing.env."
  [[ -n "${NOMAD_GITHUB_REPOSITORY:-}" ]] || fail "NOMAD_GITHUB_REPOSITORY is not set."

  assert_file_exists "$NOMAD_SPARKLE_PRIVATE_KEY_PATH"
}

assert_publish_config() {
  load_signing_env

  [[ -n "${NOMAD_SPARKLE_PRIVATE_KEY_PATH:-}" ]] || fail "NOMAD_SPARKLE_PRIVATE_KEY_PATH is not set. Configure it in Config/Signing.env."
  [[ -n "${NOMAD_GITHUB_REPOSITORY:-}" ]] || fail "NOMAD_GITHUB_REPOSITORY is not set."

  assert_file_exists "$NOMAD_SPARKLE_PRIVATE_KEY_PATH"
  assert_file_exists "$(generate_appcast_bin)"
}

assert_github_auth() {
  gh auth status >/dev/null 2>&1 || fail "GitHub CLI authentication is invalid. Run 'gh auth login -h github.com' before publishing."
}

assert_github_repository_config() {
  load_signing_env
  [[ -n "${NOMAD_GITHUB_REPOSITORY:-}" ]] || fail "NOMAD_GITHUB_REPOSITORY is not set."
}

assert_release_tag_exists_in_remote_repo() {
  local expected_tag

  expected_tag="$(release_tag)"
  assert_github_repository_config

  gh api "repos/$NOMAD_GITHUB_REPOSITORY/git/ref/tags/$expected_tag" >/dev/null 2>&1 || fail "Tag $expected_tag is not available in $NOMAD_GITHUB_REPOSITORY yet. Push it first with 'git push origin $expected_tag' or 'git push origin --tags'."
}

assert_signing_identity_available() {
  security find-identity -v -p codesigning | grep -F "$NOMAD_SIGNING_IDENTITY" >/dev/null 2>&1 || fail "Developer ID identity '$NOMAD_SIGNING_IDENTITY' is not available in the current keychain."
}

assert_notary_profile_available() {
  xcrun notarytool history --keychain-profile "$NOMAD_NOTARY_PROFILE" >/dev/null 2>&1 || fail "Notary profile '$NOMAD_NOTARY_PROFILE' is not available or not valid. Run 'make release-setup-notary APPLE_ID=<apple-id>' or re-run 'xcrun notarytool store-credentials'."
}

plist_value() {
  local plist_path="$1"
  local key="$2"

  /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" 2>/dev/null
}

assert_archive_update_configuration() {
  local info_plist="$ARCHIVE_APP_PATH/Contents/Info.plist"
  local actual_feed actual_key expected_feed expected_key

  assert_file_exists "$info_plist"

  actual_feed="$(trimmed_value "$(plist_value "$info_plist" SUFeedURL)")"
  actual_key="$(trimmed_value "$(plist_value "$info_plist" SUPublicEDKey)")"
  expected_feed="$(release_feed_url)"
  expected_key="$(trimmed_value "$NOMAD_SPARKLE_PUBLIC_ED_KEY")"

  [[ "$actual_feed" == "$expected_feed" ]] || fail "Archived app has SUFeedURL='$actual_feed', expected '$expected_feed'."
  [[ "$actual_key" == "$expected_key" ]] || fail "Archived app has SUPublicEDKey='$actual_key', expected the configured public key."
}

assert_archive_has_no_tankerkonig_api_key() {
  local info_plist="$ARCHIVE_APP_PATH/Contents/Info.plist"

  assert_file_exists "$info_plist"

  if /usr/libexec/PlistBuddy -c "Print :TankerkonigAPIKey" "$info_plist" >/dev/null 2>&1; then
    fail "Archived app must not contain TankerkonigAPIKey in Info.plist."
  fi
}

assert_archive_weatherkit_entitlement() {
  local entitlements

  entitlements="$(codesign -d --entitlements - "$ARCHIVE_APP_PATH" 2>&1)"
  [[ "$entitlements" == *"com.apple.developer.weatherkit"* ]] || fail "Archived app is missing the WeatherKit entitlement."
}

# The entitlements a code signature carries, as an XML plist on stdout.
signed_entitlements_xml() {
  local bundle_path="$1"

  /usr/bin/codesign -d --entitlements :- "$bundle_path" 2>/dev/null
}

# The first App Group in a signed bundle's entitlements, empty when there is none.
signed_app_group() {
  local bundle_path="$1"
  local app_group

  # Some macOS versions print plutil failures on stdout. Never mistake a failed extraction's
  # diagnostic for an entitlement value; the caller must see an empty group and reject it.
  app_group="$(signed_entitlements_xml "$bundle_path" |
    /usr/bin/plutil -extract "${APP_GROUP_ENTITLEMENT_KEY//./\\.}.0" raw -o - - 2>/dev/null)" || return 0
  printf '%s\n' "$app_group"
}

assert_archive_app_group_entitlement() {
  local app_group

  app_group="$(signed_app_group "$ARCHIVE_APP_PATH")"
  [[ -n "$app_group" ]] || fail "Archived app is missing the App Group entitlement ($APP_GROUP_ENTITLEMENT_KEY); the widgets could not share data with it."

  if [[ -n "${NOMAD_TEAM_ID:-}" ]]; then
    [[ "$app_group" == "$NOMAD_TEAM_ID."* ]] || fail "Archived app's App Group '$app_group' is not prefixed with the team ID $NOMAD_TEAM_ID."
  fi
}

# The widget extension must be embedded, signed with the same identity and hardened runtime as the app,
# sandboxed (WidgetKit requires it) and in the app's App Group.
assert_archive_widget_extension() {
  local info_plist="$ARCHIVE_WIDGET_PATH/Contents/Info.plist"
  local bundle_id signature_details app_group widget_group

  [[ -d "$ARCHIVE_WIDGET_PATH" ]] || fail "Archived app does not embed $WIDGET_EXTENSION_NAME in Contents/PlugIns."
  assert_file_exists "$info_plist"

  bundle_id="$(trimmed_value "$(plist_value "$info_plist" CFBundleIdentifier)")"
  [[ "$bundle_id" == "$WIDGET_BUNDLE_IDENTIFIER" ]] || fail "Widget extension has bundle ID '$bundle_id', expected '$WIDGET_BUNDLE_IDENTIFIER'."

  signed_entitlements_xml "$ARCHIVE_WIDGET_PATH" | grep -F "$APP_SANDBOX_ENTITLEMENT_KEY" >/dev/null ||
    fail "Widget extension is missing the App Sandbox entitlement ($APP_SANDBOX_ENTITLEMENT_KEY)."

  widget_group="$(signed_app_group "$ARCHIVE_WIDGET_PATH")"
  app_group="$(signed_app_group "$ARCHIVE_APP_PATH")"
  [[ -n "$widget_group" ]] || fail "Widget extension is missing the App Group entitlement ($APP_GROUP_ENTITLEMENT_KEY)."
  [[ "$widget_group" == "$app_group" ]] || fail "Widget extension App Group '$widget_group' differs from the app's '$app_group'."

  signature_details="$(/usr/bin/codesign -dv --verbose=4 "$ARCHIVE_WIDGET_PATH" 2>&1)"
  [[ "$signature_details" != *"Signature=adhoc"* ]] || fail "Widget extension is still ad-hoc signed."
  [[ "$signature_details" == *"(runtime)"* ]] || fail "Widget extension is not signed with the hardened runtime."
}

# The power helper must be embedded with its launchd plist, signed by the release team with the hardened runtime
# and a secure timestamp, carry the label SMAppService looks for, and trust only clients of this team.
assert_archive_power_helper() {
  local signature_details embedded_team app_team

  [[ -x "$ARCHIVE_POWER_HELPER_PATH" ]] || fail "Archived app does not embed an executable power helper at Contents/Library/HelperTools/$POWER_HELPER_BINARY_NAME."
  assert_file_exists "$ARCHIVE_POWER_HELPER_PLIST_PATH"

  [[ "$(trimmed_value "$(plist_value "$ARCHIVE_POWER_HELPER_PLIST_PATH" Label)")" == "$POWER_HELPER_LABEL" ]] ||
    fail "Power helper launchd plist must have Label '$POWER_HELPER_LABEL'."
  [[ "$(trimmed_value "$(plist_value "$ARCHIVE_POWER_HELPER_PLIST_PATH" BundleProgram)")" == "Contents/Library/HelperTools/$POWER_HELPER_BINARY_NAME" ]] ||
    fail "Power helper launchd plist must point BundleProgram at Contents/Library/HelperTools/$POWER_HELPER_BINARY_NAME."
  [[ "$(trimmed_value "$(plist_value "$ARCHIVE_POWER_HELPER_PLIST_PATH" "MachServices:$POWER_HELPER_LABEL")")" == "true" ]] ||
    fail "Power helper launchd plist must expose the Mach service '$POWER_HELPER_LABEL'."
  [[ "$(trimmed_value "$(plist_value "$ARCHIVE_POWER_HELPER_PLIST_PATH" AssociatedBundleIdentifiers:0)")" == "$APP_BUNDLE_IDENTIFIER" ]] ||
    fail "Power helper launchd plist must associate the app '$APP_BUNDLE_IDENTIFIER'."

  signature_details="$(/usr/bin/codesign -dv --verbose=4 "$ARCHIVE_POWER_HELPER_PATH" 2>&1)"
  [[ "$signature_details" != *"Signature=adhoc"* ]] || fail "Power helper is still ad-hoc signed."
  [[ "$signature_details" == *"(runtime)"* ]] || fail "Power helper is not signed with the hardened runtime."
  [[ "$signature_details" == *"Timestamp="* ]] || fail "Power helper is not signed with a secure timestamp."
  [[ "$signature_details" == *"Identifier=$POWER_HELPER_LABEL"* ]] || fail "Power helper must be signed with the identifier '$POWER_HELPER_LABEL'."

  if [[ -n "${NOMAD_TEAM_ID:-}" ]]; then
    [[ "$signature_details" == *"TeamIdentifier=$NOMAD_TEAM_ID"* ]] || fail "Power helper is not signed by team $NOMAD_TEAM_ID."

    # The helper only accepts clients of the team named in its embedded Info.plist, and the app names the same team.
    embedded_team="$(/usr/bin/strings -a "$ARCHIVE_POWER_HELPER_PATH" | grep -A1 '<key>NomadClientTeamIdentifier</key>' | tail -n 1 | sed -E 's/.*<string>(.*)<\/string>.*/\1/')"
    [[ "$embedded_team" == "$NOMAD_TEAM_ID" ]] || fail "Power helper trusts team '$embedded_team', expected $NOMAD_TEAM_ID."
    app_team="$(trimmed_value "$(plist_value "$ARCHIVE_APP_PATH/Contents/Info.plist" NomadTeamIdentifier)")"
    [[ "$app_team" == "$NOMAD_TEAM_ID" ]] || fail "Archived app has NomadTeamIdentifier '$app_team', expected $NOMAD_TEAM_ID."
  fi
}

# The power helper's project files; check they are still wired up.
assert_power_helper_project_configuration() {
  assert_file_exists "$REPO_ROOT/App/PowerHelper/generate-launchd-plist.sh"
  assert_file_exists "$REPO_ROOT/Config/PowerHelper.Release.xcconfig"
  grep -F "NOMAD_APP_BUNDLE_IDENTIFIER = $APP_BUNDLE_IDENTIFIER" "$REPO_ROOT/Config/Identity.Release.xcconfig" >/dev/null ||
    fail "Config/Identity.Release.xcconfig must set NOMAD_APP_BUNDLE_IDENTIFIER = $APP_BUNDLE_IDENTIFIER."
  grep -F 'PRODUCT_BUNDLE_IDENTIFIER = $(NOMAD_POWER_HELPER_LABEL)' "$REPO_ROOT/Config/PowerHelper.Release.xcconfig" >/dev/null ||
    fail "Config/PowerHelper.Release.xcconfig must use the helper label as its bundle identifier."
  grep -F 'PRODUCT_BUNDLE_IDENTIFIER = $(NOMAD_APP_BUNDLE_IDENTIFIER)' "$REPO_ROOT/Config/Release.xcconfig" >/dev/null ||
    fail "Config/Release.xcconfig must take its bundle identifier from NOMAD_APP_BUNDLE_IDENTIFIER."
}

# Every embedded widget extension, for re-signing and checks.
archive_widget_extensions() {
  [[ -d "$ARCHIVE_PLUGINS_PATH" ]] || return 0
  find "$ARCHIVE_PLUGINS_PATH" -maxdepth 1 -name '*.appex' -type d -print
}

# Release signing and the widgets depend on these project files; check they are still wired up.
assert_widget_project_configuration() {
  local entitlements

  for entitlements in "$REPO_ROOT/App/NomadDashboard.entitlements" "$REPO_ROOT/App/Widgets/NomadDashboardWidgets.entitlements"; do
    assert_file_exists "$entitlements"
    grep -F "$APP_GROUP_ENTITLEMENT_KEY" "$entitlements" >/dev/null || fail "${entitlements#$REPO_ROOT/} is missing the App Group entitlement."
    grep -F '$(APP_GROUP_IDENTIFIER)' "$entitlements" >/dev/null || fail "${entitlements#$REPO_ROOT/} must use \$(APP_GROUP_IDENTIFIER), the team-prefixed group from Config/*.xcconfig."
  done

  grep -F "$APP_SANDBOX_ENTITLEMENT_KEY" "$REPO_ROOT/App/Widgets/NomadDashboardWidgets.entitlements" >/dev/null ||
    fail "App/Widgets/NomadDashboardWidgets.entitlements is missing the App Sandbox entitlement."
  grep -F "PRODUCT_BUNDLE_IDENTIFIER = $WIDGET_BUNDLE_IDENTIFIER" "$REPO_ROOT/Config/Widgets.Release.xcconfig" >/dev/null ||
    fail "Config/Widgets.Release.xcconfig must set PRODUCT_BUNDLE_IDENTIFIER = $WIDGET_BUNDLE_IDENTIFIER."
  grep -F 'APP_GROUP_IDENTIFIER = $(TeamIdentifierPrefix)com.iloapps.NomadDashboard' "$REPO_ROOT/Config/Release.xcconfig" >/dev/null ||
    fail "Config/Release.xcconfig must set the team-prefixed APP_GROUP_IDENTIFIER."
}

assert_archive_is_not_adhoc() {
  local signature_details

  signature_details="$(codesign -dv --verbose=4 "$ARCHIVE_APP_PATH" 2>&1)"
  [[ "$signature_details" != *"Signature=adhoc"* ]] || fail "Archived app is still ad-hoc signed."
  [[ "$signature_details" != *"TeamIdentifier=not set"* ]] || fail "Archived app does not report a TeamIdentifier."
}

print_release_summary() {
  load_signing_env
  cat <<EOF
Release summary
  Version: $(release_version)
  Tag: $(release_tag)
  Repository: ${NOMAD_GITHUB_REPOSITORY}
  Feed URL: $(release_feed_url)
  Archive: $ARCHIVE_PATH
  App: $ARCHIVE_APP_PATH
  Sparkle ZIP: $(release_zip_path)
  DMG: $(release_dmg_path)
  Appcast: $(release_appcast_path)
EOF
}
