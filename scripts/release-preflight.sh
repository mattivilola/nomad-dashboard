#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/release-common.sh"
cd "$REPO_ROOT"

load_signing_env

require_command gh

assert_clean_worktree
assert_version_file_present
assert_release_tag_matches_head
assert_github_auth
assert_release_tag_exists_in_remote_repo

cat <<EOF
Release preflight passed
  Repository: $NOMAD_GITHUB_REPOSITORY
  Tag: $(release_tag)
EOF
