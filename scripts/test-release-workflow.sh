#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nomad-dashboard-release-tests.XXXXXX")"
RELEASE_DATE="$(date +%F)"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT

fail() {
  echo "release workflow test failed: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

assert_equals() {
  local actual="$1"
  local expected="$2"
  local message="$3"

  [[ "$actual" == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

bootstrap_repo() {
  local repo_path="$1"
  local version="$2"
  local build="$3"
  local changelog_body="$4"

  mkdir -p "$repo_path/Config" "$repo_path/scripts"
  cp "$REPO_ROOT/scripts/prepare-release.sh" "$repo_path/scripts/prepare-release.sh"
  chmod +x "$repo_path/scripts/prepare-release.sh"

  cat > "$repo_path/Config/Version.xcconfig" <<EOF
MARKETING_VERSION = $version
CURRENT_PROJECT_VERSION = $build
EOF

  cat > "$repo_path/CHANGELOG.md" <<EOF
# Changelog

All notable changes to Nomad Dashboard will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

$changelog_body
EOF

  cat > "$repo_path/README.md" <<'EOF'
# Test Repo
EOF

  (
    cd "$repo_path"
    git init -q
    git config user.name "Nomad Dashboard Tests"
    git config user.email "nomad-dashboard-tests@example.com"
    git add .
    git commit -qm "Initial scaffold"
  )
}

read_version_file() {
  local repo_path="$1"
  sed -n 'p' "$repo_path/Config/Version.xcconfig"
}

run_patch_release_test() {
  local repo_path="$TEST_ROOT/patch-release"

  bootstrap_repo "$repo_path" "0.1.0" "1" $'### Added\n\n- Add dashboard footer version display\n\n### Changed\n\n- Improve release command ergonomics\n\n### Fixed\n\n- _Nothing yet_'

  (
    cd "$repo_path"
    ./scripts/prepare-release.sh patch >/dev/null
  )

  local version_contents changelog latest_commit tag_name
  version_contents="$(read_version_file "$repo_path")"
  changelog="$(cat "$repo_path/CHANGELOG.md")"
  latest_commit="$(git -C "$repo_path" log -1 --pretty=%s)"
  tag_name="$(git -C "$repo_path" tag --list 'v0.1.1')"

  assert_contains "$version_contents" "MARKETING_VERSION = 0.1.1" "patch release should bump semantic version"
  assert_contains "$version_contents" "CURRENT_PROJECT_VERSION = 2" "patch release should increment build number"
  assert_contains "$changelog" "## [0.1.1] - $RELEASE_DATE" "patch release should add a dated changelog section"
  assert_contains "$changelog" "- Add dashboard footer version display" "patch release should move Unreleased notes into the release section"
  assert_contains "$changelog" "## [Unreleased]" "patch release should recreate the Unreleased section"
  assert_equals "$latest_commit" "Release v0.1.1" "patch release should create a release commit"
  assert_equals "$tag_name" "v0.1.1" "patch release should create a matching tag"
}

run_minor_release_test() {
  local repo_path="$TEST_ROOT/minor-release"

  bootstrap_repo "$repo_path" "0.1.0" "1" $'### Added\n\n- _Nothing yet_\n\n### Changed\n\n- _Nothing yet_\n\n### Fixed\n\n- _Nothing yet_'

  (
    cd "$repo_path"
    git tag -a v0.1.0 -m "Release v0.1.0" >/dev/null
    echo "draft" > notes.txt
    git add notes.txt
    git commit -qm "Add release notes drafting"
    ./scripts/prepare-release.sh minor >/dev/null
  )

  local version_contents changelog latest_commit tag_name
  version_contents="$(read_version_file "$repo_path")"
  changelog="$(cat "$repo_path/CHANGELOG.md")"
  latest_commit="$(git -C "$repo_path" log -1 --pretty=%s)"
  tag_name="$(git -C "$repo_path" tag --list 'v0.2.0')"

  assert_contains "$version_contents" "MARKETING_VERSION = 0.2.0" "minor release should bump the minor version"
  assert_contains "$version_contents" "CURRENT_PROJECT_VERSION = 2" "minor release should increment build number"
  assert_contains "$changelog" "## [0.2.0] - $RELEASE_DATE" "minor release should add a changelog section"
  assert_contains "$changelog" "### Changed" "minor release should draft a Changed section when Unreleased is empty"
  assert_contains "$changelog" "- Add release notes drafting" "minor release should draft notes from commits since the latest tag"
  assert_equals "$latest_commit" "Release v0.2.0" "minor release should create a release commit"
  assert_equals "$tag_name" "v0.2.0" "minor release should create a matching tag"
}

run_major_release_test() {
  local repo_path="$TEST_ROOT/major-release"

  bootstrap_repo "$repo_path" "0.1.0" "1" $'### Added\n\n- _Nothing yet_\n\n### Changed\n\n- _Nothing yet_\n\n### Fixed\n\n- _Nothing yet_'

  (
    cd "$repo_path"
    echo "power" > power.txt
    git add power.txt
    git commit -qm "Add power diagnostics"
    ./scripts/prepare-release.sh major >/dev/null
  )

  local version_contents changelog latest_commit tag_name
  version_contents="$(read_version_file "$repo_path")"
  changelog="$(cat "$repo_path/CHANGELOG.md")"
  latest_commit="$(git -C "$repo_path" log -1 --pretty=%s)"
  tag_name="$(git -C "$repo_path" tag --list 'v1.0.0')"

  assert_contains "$version_contents" "MARKETING_VERSION = 1.0.0" "major release should bump the major version"
  assert_contains "$version_contents" "CURRENT_PROJECT_VERSION = 2" "major release should increment build number"
  assert_contains "$changelog" "## [1.0.0] - $RELEASE_DATE" "major release should add a changelog section"
  assert_contains "$changelog" "- Initial scaffold" "major release should fall back to all commit subjects when no prior release tag exists"
  assert_contains "$changelog" "- Add power diagnostics" "major release should include post-initial commits in the generated notes"
  assert_equals "$latest_commit" "Release v1.0.0" "major release should create a release commit"
  assert_equals "$tag_name" "v1.0.0" "major release should create a matching tag"
}

run_dirty_tree_test() {
  local repo_path="$TEST_ROOT/dirty-tree"

  bootstrap_repo "$repo_path" "0.1.0" "1" $'### Added\n\n- _Nothing yet_\n\n### Changed\n\n- _Nothing yet_\n\n### Fixed\n\n- _Nothing yet_'

  local original_version original_changelog
  original_version="$(cat "$repo_path/Config/Version.xcconfig")"
  original_changelog="$(cat "$repo_path/CHANGELOG.md")"

  (
    cd "$repo_path"
    echo "dirty" >> README.md
    if ./scripts/prepare-release.sh patch >/dev/null 2>&1; then
      fail "dirty tree release should abort"
    fi
  )

  local version_contents changelog latest_commit tag_name
  version_contents="$(cat "$repo_path/Config/Version.xcconfig")"
  changelog="$(cat "$repo_path/CHANGELOG.md")"
  latest_commit="$(git -C "$repo_path" log -1 --pretty=%s)"
  tag_name="$(git -C "$repo_path" tag --list 'v0.1.1')"

  assert_equals "$version_contents" "$original_version" "dirty tree release should not edit the version file"
  assert_equals "$changelog" "$original_changelog" "dirty tree release should not edit the changelog"
  assert_equals "$latest_commit" "Initial scaffold" "dirty tree release should not create a release commit"
  assert_equals "$tag_name" "" "dirty tree release should not create a tag"
}

run_patch_release_test
run_minor_release_test
run_major_release_test
run_dirty_tree_test

echo "release workflow tests passed"

