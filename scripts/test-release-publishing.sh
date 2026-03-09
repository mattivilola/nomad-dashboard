#!/bin/zsh
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nomad-dashboard-release-publish-tests.XXXXXX")"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
  rm -rf "$TEST_ROOT"
}

trap cleanup EXIT INT TERM

fail() {
  echo "release publishing test failed: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "$description"
}

bootstrap_repo() {
  local repo_path="$1"

  mkdir -p "$repo_path/scripts" "$repo_path/Config"
  cp "$REPO_ROOT/scripts/release-common.sh" "$repo_path/scripts/release-common.sh"
  cp "$REPO_ROOT/scripts/sign-and-notarize.sh" "$repo_path/scripts/sign-and-notarize.sh"
  cp "$REPO_ROOT/scripts/publish-update.sh" "$repo_path/scripts/publish-update.sh"

  cat > "$repo_path/Config/Version.xcconfig" <<'EOF'
MARKETING_VERSION = 0.1.6
CURRENT_PROJECT_VERSION = 6
EOF

  cat > "$repo_path/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]

### Added

- _Nothing yet_

### Changed

- _Nothing yet_

### Fixed

- _Nothing yet_

## [0.1.6] - 2026-03-09

### Added

- Ship signed release automation
EOF

  cat > "$repo_path/README.md" <<'EOF'
Nomad Dashboard
EOF

  (
    cd "$repo_path"
    git init -q
    git config user.name "Codex"
    git config user.email "codex@example.com"
    git add .
    git commit -qm "Initial scaffold"
    git tag -a v0.1.6 -m "Release v0.1.6"
  )
}

run_sign_dry_run_test() {
  local repo_path="$TEST_ROOT/sign-dry-run"
  local output

  bootstrap_repo "$repo_path"
  output="$(cd "$repo_path" && ./scripts/sign-and-notarize.sh --dry-run)"

  assert_contains "$output" "Version: 0.1.6" "sign dry run should report the release version"
  assert_contains "$output" "Tag: v0.1.6" "sign dry run should report the release tag"
  assert_contains "$output" "Sparkle ZIP:" "sign dry run should report the Sparkle zip path"
}

run_publish_dry_run_test() {
  local repo_path="$TEST_ROOT/publish-dry-run"
  local output

  bootstrap_repo "$repo_path"
  output="$(cd "$repo_path" && ./scripts/publish-update.sh --dry-run)"

  assert_contains "$output" "Repository: mattivilola/nomad-dashboard" "publish dry run should report the target repository"
  assert_contains "$output" "Appcast:" "publish dry run should report the appcast path"
  assert_contains "$output" "GitHub release v0.1.6" "publish dry run should report the GitHub release target"
}

run_dirty_tree_rejection_test() {
  local repo_path="$TEST_ROOT/dirty-tree"
  local output
  local status

  bootstrap_repo "$repo_path"
  echo "dirty" >> "$repo_path/README.md"

  set +e
  output="$(cd "$repo_path" && ./scripts/sign-and-notarize.sh 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    fail "sign-and-notarize should reject a dirty working tree"
  fi

  assert_contains "$output" "clean git working tree" "dirty tree rejection should explain the clean-tree requirement"
}

run_missing_signing_config_test() {
  local repo_path="$TEST_ROOT/missing-config"
  local output
  local status

  bootstrap_repo "$repo_path"

  set +e
  output="$(cd "$repo_path" && ./scripts/sign-and-notarize.sh 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    fail "sign-and-notarize should fail when signing configuration is missing"
  fi

  assert_contains "$output" "NOMAD_TEAM_ID is not set" "missing signing config should explain the first required variable"
}

run_publish_auth_failure_test() {
  local repo_path="$TEST_ROOT/publish-auth-failure"
  local fake_bin="$repo_path/fake-bin"
  local output
  local status

  bootstrap_repo "$repo_path"
  mkdir -p "$fake_bin"
  mkdir -p "$repo_path/sparkle-bin"
  touch "$repo_path/sparkle_private_key.pem"

  cat > "$repo_path/Config/Signing.env" <<EOF
export NOMAD_GITHUB_REPOSITORY="mattivilola/nomad-dashboard"
export NOMAD_SPARKLE_PRIVATE_KEY_PATH="$repo_path/sparkle_private_key.pem"
export NOMAD_SPARKLE_BIN_DIR="$repo_path/sparkle-bin"
EOF

  cat > "$repo_path/sparkle-bin/generate_appcast" <<'EOF'
#!/bin/zsh
exit 0
EOF

  cat > "$fake_bin/gh" <<'EOF'
#!/bin/zsh
exit 1
EOF

  chmod +x "$repo_path/sparkle-bin/generate_appcast" "$fake_bin/gh"

  set +e
  output="$(cd "$repo_path" && PATH="$fake_bin:$PATH" ./scripts/publish-update.sh 2>&1)"
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    fail "publish-update should fail when GitHub authentication is invalid"
  fi

  assert_contains "$output" "GitHub CLI authentication is invalid" "publish auth failure should explain how to fix gh authentication"
}

run_sign_dry_run_test
run_publish_dry_run_test
run_dirty_tree_rejection_test
run_missing_signing_config_test
run_publish_auth_failure_test

echo "release publishing tests passed"
