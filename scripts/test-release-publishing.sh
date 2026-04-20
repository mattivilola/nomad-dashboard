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

  printf '%s' "$haystack" | grep -F "$needle" >/dev/null || fail "$description"
}

bootstrap_repo() {
  local repo_path="$1"

  mkdir -p "$repo_path/scripts" "$repo_path/Config"
  cp "$REPO_ROOT/scripts/release-common.sh" "$repo_path/scripts/release-common.sh"
  cp "$REPO_ROOT/scripts/release-preflight.sh" "$repo_path/scripts/release-preflight.sh"
  cp "$REPO_ROOT/scripts/sign-and-notarize.sh" "$repo_path/scripts/sign-and-notarize.sh"
  cp "$REPO_ROOT/scripts/publish-update.sh" "$repo_path/scripts/publish-update.sh"
  cp "$REPO_ROOT/scripts/check-release-setup.sh" "$repo_path/scripts/check-release-setup.sh"
  cp "$REPO_ROOT/scripts/setup-notary-profile.sh" "$repo_path/scripts/setup-notary-profile.sh"
  chmod +x "$repo_path/scripts/"*.sh

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
  local exit_code

  bootstrap_repo "$repo_path"
  echo "dirty" >> "$repo_path/README.md"

  set +e
  output="$(cd "$repo_path" && ./scripts/sign-and-notarize.sh 2>&1)"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "sign-and-notarize should reject a dirty working tree"
  fi

  assert_contains "$output" "clean git working tree" "dirty tree rejection should explain the clean-tree requirement"
}

run_missing_signing_config_test() {
  local repo_path="$TEST_ROOT/missing-config"
  local output
  local exit_code

  bootstrap_repo "$repo_path"

  set +e
  output="$(cd "$repo_path" && ./scripts/sign-and-notarize.sh 2>&1)"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "sign-and-notarize should fail when signing configuration is missing"
  fi

  assert_contains "$output" "NOMAD_TEAM_ID is not set" "missing signing config should explain the first required variable"
}

run_signing_config_does_not_require_sparkle_cli_test() {
  local repo_path="$TEST_ROOT/signing-config-without-sparkle-cli"
  local output

  bootstrap_repo "$repo_path"
  touch "$repo_path/sparkle_private_key.pem"

  output="$(
    cd "$repo_path" &&
      NOMAD_TEAM_ID="TEAM123456" \
      NOMAD_SIGNING_IDENTITY="Developer ID Application: Example Corp (TEAM123456)" \
      NOMAD_NOTARY_PROFILE="NomadDashboardNotary" \
      NOMAD_SPARKLE_PRIVATE_KEY_PATH="$repo_path/sparkle_private_key.pem" \
      NOMAD_SPARKLE_PUBLIC_ED_KEY="sparkle-public-key" \
      zsh -c 'set -e; source ./scripts/release-common.sh; assert_release_signing_config; echo OK'
  )"

  assert_contains "$output" "OK" "release signing config should not require Sparkle CLI tools before publish"
}

run_publish_auth_failure_test() {
  local repo_path="$TEST_ROOT/publish-auth-failure"
  local fake_bin="$repo_path/fake-bin"
  local output
  local exit_code

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

  (
    cd "$repo_path"
    git add Config/Signing.env fake-bin sparkle-bin sparkle_private_key.pem
    git commit -qm "Add publish prerequisites"
    git tag -fa v0.1.6 -m "Release v0.1.6" >/dev/null
  )

  set +e
  output="$(cd "$repo_path" && PATH="$fake_bin:$PATH" ./scripts/publish-update.sh 2>&1)"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "publish-update should fail when GitHub authentication is invalid"
  fi

  assert_contains "$output" "GitHub CLI authentication is invalid" "publish auth failure should explain how to fix gh authentication"
}

run_release_preflight_missing_remote_tag_test() {
  local repo_path="$TEST_ROOT/release-preflight-missing-tag"
  local fake_bin="$TEST_ROOT/release-preflight-fake-bin"
  local output
  local exit_code

  bootstrap_repo "$repo_path"
  mkdir -p "$fake_bin"

  cat > "$fake_bin/gh" <<'EOF'
#!/bin/zsh
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi

if [[ "$1" == "api" ]]; then
  exit 1
fi

exit 1
EOF

  chmod +x "$fake_bin/gh"

  set +e
  output="$(cd "$repo_path" && PATH="$fake_bin:$PATH" ./scripts/release-preflight.sh 2>&1)"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "release-preflight should fail when the release tag has not been pushed"
  fi

  assert_contains "$output" "Push it first" "release preflight should explain that the tag must be pushed before release"
}

run_publish_missing_remote_tag_test() {
  local repo_path="$TEST_ROOT/publish-missing-remote-tag"
  local fake_bin="$repo_path/fake-bin"
  local output
  local exit_code

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
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi

if [[ "$1" == "api" ]]; then
  exit 1
fi

exit 1
EOF

  chmod +x "$repo_path/sparkle-bin/generate_appcast" "$fake_bin/gh"

  (
    cd "$repo_path"
    git add Config/Signing.env fake-bin sparkle-bin sparkle_private_key.pem
    git commit -qm "Add publish prerequisites"
    git tag -fa v0.1.6 -m "Release v0.1.6" >/dev/null
  )

  set +e
  output="$(cd "$repo_path" && PATH="$fake_bin:$PATH" ./scripts/publish-update.sh 2>&1)"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "publish-update should fail when the release tag has not been pushed"
  fi

  assert_contains "$output" "Push it first" "publish-update should explain that the tag must be pushed before publishing"
}

run_archive_secret_guard_test() {
  local repo_path="$TEST_ROOT/archive-secret-guard"
  local output
  local exit_code

  bootstrap_repo "$repo_path"
  mkdir -p "$repo_path/artifacts/NomadDashboard.xcarchive/Products/Applications/Nomad Dashboard.app/Contents"

  cat > "$repo_path/artifacts/NomadDashboard.xcarchive/Products/Applications/Nomad Dashboard.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>TankerkonigAPIKey</key>
  <string>leaked-key</string>
</dict>
</plist>
EOF

  set +e
  output="$(cd "$repo_path" && zsh -c 'source ./scripts/release-common.sh; assert_archive_has_no_tankerkonig_api_key' 2>&1)"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "assert_archive_has_no_tankerkonig_api_key should fail when the archive plist contains TankerkonigAPIKey"
  fi

  assert_contains "$output" "must not contain TankerkonigAPIKey" "archive secret guard should explain the rejected plist key"
}

run_archive_secret_guard_absent_key_set_e_test() {
  local repo_path="$TEST_ROOT/archive-secret-guard-no-key"
  local output

  bootstrap_repo "$repo_path"
  mkdir -p "$repo_path/artifacts/NomadDashboard.xcarchive/Products/Applications/Nomad Dashboard.app/Contents"

  cat > "$repo_path/artifacts/NomadDashboard.xcarchive/Products/Applications/Nomad Dashboard.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>ReliefWebAppName</key>
  <string>local-only-name</string>
</dict>
</plist>
EOF

  output="$(cd "$repo_path" && zsh -c 'set -e; source ./scripts/release-common.sh; assert_archive_has_no_tankerkonig_api_key; echo OK' 2>&1)"

  assert_contains "$output" "OK" "archive secret guard should succeed under set -e when TankerkonigAPIKey is absent"
}

run_setup_notary_profile_test() {
  local repo_path="$TEST_ROOT/setup-notary-profile"
  local fake_bin="$repo_path/fake-bin"
  local output

  bootstrap_repo "$repo_path"
  mkdir -p "$fake_bin"

  cat > "$repo_path/Config/Signing.env" <<'EOF'
export NOMAD_TEAM_ID="TEAM123456"
export NOMAD_NOTARY_PROFILE="NomadDashboardNotary"
EOF

  cat > "$fake_bin/xcrun" <<'EOF'
#!/bin/zsh
set -euo pipefail

STATE_FILE="${TEST_NOTARY_STATE_FILE:?}"

if [[ "$1" != "notarytool" ]]; then
  exit 1
fi

case "$2" in
  history)
    [[ "$3" == "--keychain-profile" ]] || exit 1
    [[ -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$4" ]] || exit 1
    exit 0
    ;;
  store-credentials)
    [[ "$3" == "NomadDashboardNotary" ]] || exit 1
    [[ "$4" == "--apple-id" ]] || exit 1
    [[ "$5" == "release@example.com" ]] || exit 1
    [[ "$6" == "--team-id" ]] || exit 1
    [[ "$7" == "TEAM123456" ]] || exit 1
    printf '%s\n' "$3" > "$STATE_FILE"
    exit 0
    ;;
esac

exit 1
EOF

  chmod +x "$fake_bin/xcrun"

  output="$(
    cd "$repo_path" &&
      PATH="$fake_bin:$PATH" \
      TEST_NOTARY_STATE_FILE="$repo_path/notary-profile.txt" \
      ./scripts/setup-notary-profile.sh --apple-id release@example.com
  )"

  assert_contains "$output" "Stored notary profile" "setup-notary-profile should report success after storing credentials"
  assert_contains "$output" "Profile: NomadDashboardNotary" "setup-notary-profile should print the configured profile name"
}

run_setup_notary_profile_requires_apple_id_test() {
  local repo_path="$TEST_ROOT/setup-notary-profile-missing-apple-id"
  local output
  local exit_code

  bootstrap_repo "$repo_path"

  cat > "$repo_path/Config/Signing.env" <<'EOF'
export NOMAD_TEAM_ID="TEAM123456"
export NOMAD_NOTARY_PROFILE="NomadDashboardNotary"
EOF

  set +e
  output="$(cd "$repo_path" && ./scripts/setup-notary-profile.sh 2>&1)"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "setup-notary-profile should require an Apple ID"
  fi

  assert_contains "$output" "make release-setup-notary APPLE_ID=you@example.com" "setup-notary-profile should explain how to provide the Apple ID"
}

run_release_check_setup_success_test() {
  local repo_path="$TEST_ROOT/release-check-setup-success"
  local fake_bin="$repo_path/fake-bin"
  local output

  bootstrap_repo "$repo_path"
  mkdir -p "$fake_bin" "$repo_path/sparkle-bin"
  touch "$repo_path/sparkle_private_key.pem"

  cat > "$repo_path/Config/Signing.env" <<EOF
export NOMAD_TEAM_ID="TEAM123456"
export NOMAD_SIGNING_IDENTITY="Developer ID Application: Example Corp (TEAM123456)"
export NOMAD_NOTARY_PROFILE="NomadDashboardNotary"
export NOMAD_GITHUB_REPOSITORY="mattivilola/nomad-dashboard"
export NOMAD_SPARKLE_PRIVATE_KEY_PATH="$repo_path/sparkle_private_key.pem"
export NOMAD_SPARKLE_PUBLIC_ED_KEY="sparkle-public-key"
export NOMAD_SPARKLE_BIN_DIR="$repo_path/sparkle-bin"
EOF

  cat > "$repo_path/sparkle-bin/generate_appcast" <<'EOF'
#!/bin/zsh
exit 0
EOF

  cat > "$repo_path/sparkle-bin/sign_update" <<'EOF'
#!/bin/zsh
exit 0
EOF

  cat > "$fake_bin/gh" <<'EOF'
#!/bin/zsh
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi
exit 1
EOF

  cat > "$fake_bin/security" <<'EOF'
#!/bin/zsh
if [[ "$1" == "find-identity" ]]; then
  echo '  1) ABCDEF1234567890 "Developer ID Application: Example Corp (TEAM123456)"'
  exit 0
fi
exit 1
EOF

  cat > "$fake_bin/xcrun" <<'EOF'
#!/bin/zsh
if [[ "$1" == "notarytool" && "$2" == "history" && "$3" == "--keychain-profile" && "$4" == "NomadDashboardNotary" ]]; then
  exit 0
fi
exit 1
EOF

  chmod +x \
    "$repo_path/sparkle-bin/generate_appcast" \
    "$repo_path/sparkle-bin/sign_update" \
    "$fake_bin/gh" \
    "$fake_bin/security" \
    "$fake_bin/xcrun"

  output="$(
    cd "$repo_path" &&
      PATH="$fake_bin:$PATH" \
      ./scripts/check-release-setup.sh
  )"

  assert_contains "$output" "OK   Signing environment configuration" "release-check-setup should validate signing config"
  assert_contains "$output" "OK   Developer ID signing identity" "release-check-setup should validate the signing identity"
  assert_contains "$output" "OK   GitHub CLI authentication" "release-check-setup should validate gh auth"
  assert_contains "$output" "OK   Sparkle CLI tools" "release-check-setup should validate Sparkle CLI tools"
  assert_contains "$output" "OK   Notary keychain profile" "release-check-setup should validate the notary profile"
  assert_contains "$output" "Release setup looks ready" "release-check-setup should report success when all checks pass"
}

run_release_check_setup_reports_missing_notary_profile_test() {
  local repo_path="$TEST_ROOT/release-check-setup-missing-notary-profile"
  local fake_bin="$repo_path/fake-bin"
  local output
  local exit_code

  bootstrap_repo "$repo_path"
  mkdir -p "$fake_bin" "$repo_path/sparkle-bin"
  touch "$repo_path/sparkle_private_key.pem"

  cat > "$repo_path/Config/Signing.env" <<EOF
export NOMAD_TEAM_ID="TEAM123456"
export NOMAD_SIGNING_IDENTITY="Developer ID Application: Example Corp (TEAM123456)"
export NOMAD_NOTARY_PROFILE="NomadDashboardNotary"
export NOMAD_GITHUB_REPOSITORY="mattivilola/nomad-dashboard"
export NOMAD_SPARKLE_PRIVATE_KEY_PATH="$repo_path/sparkle_private_key.pem"
export NOMAD_SPARKLE_PUBLIC_ED_KEY="sparkle-public-key"
export NOMAD_SPARKLE_BIN_DIR="$repo_path/sparkle-bin"
EOF

  cat > "$repo_path/sparkle-bin/generate_appcast" <<'EOF'
#!/bin/zsh
exit 0
EOF

  cat > "$repo_path/sparkle-bin/sign_update" <<'EOF'
#!/bin/zsh
exit 0
EOF

  cat > "$fake_bin/gh" <<'EOF'
#!/bin/zsh
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi
exit 1
EOF

  cat > "$fake_bin/security" <<'EOF'
#!/bin/zsh
if [[ "$1" == "find-identity" ]]; then
  echo '  1) ABCDEF1234567890 "Developer ID Application: Example Corp (TEAM123456)"'
  exit 0
fi
exit 1
EOF

  cat > "$fake_bin/xcrun" <<'EOF'
#!/bin/zsh
if [[ "$1" == "notarytool" && "$2" == "history" ]]; then
  echo "Error: HTTP status code: 403. A required agreement is missing or has expired." >&2
  exit 1
fi
exit 1
EOF

  chmod +x \
    "$repo_path/sparkle-bin/generate_appcast" \
    "$repo_path/sparkle-bin/sign_update" \
    "$fake_bin/gh" \
    "$fake_bin/security" \
    "$fake_bin/xcrun"

  set +e
  output="$(
    cd "$repo_path" &&
      PATH="$fake_bin:$PATH" \
      ./scripts/check-release-setup.sh 2>&1
  )"
  exit_code=$?
  set -e

  if [[ "$exit_code" -eq 0 ]]; then
    fail "release-check-setup should fail when the notary profile is invalid"
  fi

  assert_contains "$output" "FAIL Notary keychain profile" "release-check-setup should report a failing notary profile check"
  assert_contains "$output" "required agreement is missing or has expired" "release-check-setup should surface Apple agreement failures from notarytool"
  assert_contains "$output" "Release setup check failed" "release-check-setup should report an overall failure summary"
}

run_sign_dry_run_test
run_publish_dry_run_test
run_dirty_tree_rejection_test
run_missing_signing_config_test
run_signing_config_does_not_require_sparkle_cli_test
run_publish_auth_failure_test
run_release_preflight_missing_remote_tag_test
run_publish_missing_remote_tag_test
run_archive_secret_guard_test
run_archive_secret_guard_absent_key_set_e_test
run_setup_notary_profile_test
run_setup_notary_profile_requires_apple_id_test
run_release_check_setup_success_test
run_release_check_setup_reports_missing_notary_profile_test

echo "release publishing tests passed"
