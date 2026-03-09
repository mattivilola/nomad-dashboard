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
  1. Extract the current release notes from CHANGELOG.md.
  2. Generate appcast.xml from $(release_zip_path).
  3. Publish $(release_zip_path), $(release_dmg_path), and $(release_appcast_path) to GitHub release $(release_tag) in ${NOMAD_GITHUB_REPOSITORY}.
EOF
  exit 0
fi

require_command gh
assert_clean_worktree
assert_version_file_present
assert_changelog_present
assert_release_tag_matches_head
assert_publish_config
assert_github_auth
ensure_release_dirs
write_release_notes_files

ZIP_PATH="$(release_zip_path)"
DMG_PATH="$(release_dmg_path)"
APPCAST_PATH="$(release_appcast_path)"
APPCAST_SOURCE_DIR="$(appcast_source_dir)"

assert_file_exists "$ZIP_PATH"
assert_file_exists "$DMG_PATH"

rm -rf "$APPCAST_SOURCE_DIR"
mkdir -p "$APPCAST_SOURCE_DIR"
cp "$ZIP_PATH" "$APPCAST_SOURCE_DIR/"
cp "$(release_notes_text_path)" "$APPCAST_SOURCE_DIR/"

"$(generate_appcast_bin)" \
  --ed-key-file "$NOMAD_SPARKLE_PRIVATE_KEY_PATH" \
  --download-url-prefix "$(release_download_url_prefix)" \
  --embed-release-notes \
  "$APPCAST_SOURCE_DIR"

cp "$APPCAST_SOURCE_DIR/appcast.xml" "$APPCAST_PATH"

gh release create "$(release_tag)" \
  --repo "$NOMAD_GITHUB_REPOSITORY" \
  --verify-tag \
  --title "$(release_title)" \
  --notes-file "$(release_notes_markdown_path)" \
  "$ZIP_PATH" \
  "$DMG_PATH" \
  "$APPCAST_PATH"

cat <<EOF
Published release assets
  Repository: $NOMAD_GITHUB_REPOSITORY
  Tag: $(release_tag)
  Appcast: $APPCAST_PATH
EOF
