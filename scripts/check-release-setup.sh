#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/release-common.sh"
cd "$REPO_ROOT"

failures=0

load_signing_env

print_check_result() {
  local result="$1"
  local label="$2"

  printf '%-4s %s\n' "$result" "$label"
}

print_indented_output() {
  local output="$1"

  [[ -n "${output//[$'\n\r\t ']}" ]] || return 0
  while IFS= read -r line; do
    printf '     %s\n' "$line"
  done <<< "$output"
}

run_check() {
  local label="$1"
  shift

  local output
  if output="$("$@" 2>&1)"; then
    print_check_result "OK" "$label"
    print_indented_output "$output"
  else
    print_check_result "FAIL" "$label"
    print_indented_output "$output"
    failures=$((failures + 1))
  fi
}

check_command() {
  require_command "$1"
}

assert_sparkle_cli_tools_available() {
  load_signing_env
  assert_file_exists "$(generate_appcast_bin)"
  assert_file_exists "$(sign_update_bin)"
}

check_notary_profile_available_verbose() {
  load_signing_env

  local output
  if output="$(xcrun notarytool history --keychain-profile "$NOMAD_NOTARY_PROFILE" 2>&1)"; then
    [[ -n "${output//[$'\n\r\t ']}" ]] && printf '%s\n' "$output"
    return 0
  fi

  [[ -n "${output//[$'\n\r\t ']}" ]] && printf '%s\n' "$output"
  fail "Notary profile '$NOMAD_NOTARY_PROFILE' is not available or not valid. Run 'make release-setup-notary APPLE_ID=<apple-id>' or re-run 'xcrun notarytool store-credentials'."
}

cat <<EOF
Release setup check
  Repository: $NOMAD_GITHUB_REPOSITORY
  Signing env: ${NOMAD_SIGNING_ENV_FILE:-$DEFAULT_SIGNING_ENV_FILE}
EOF

run_check "Required command: gh" check_command gh
run_check "Required command: xcrun" check_command xcrun
run_check "Required command: security" check_command security
run_check "Required command: xcodebuild" check_command xcodebuild
run_check "Required command: codesign" check_command codesign
run_check "Required command: hdiutil" check_command hdiutil
run_check "Required command: ditto" check_command ditto
run_check "Signing environment configuration" assert_release_signing_config
run_check "Developer ID signing identity" assert_signing_identity_available
run_check "GitHub CLI authentication" assert_github_auth
run_check "Sparkle CLI tools" assert_sparkle_cli_tools_available
run_check "Notary keychain profile" check_notary_profile_available_verbose

if [[ "$failures" -gt 0 ]]; then
  cat <<EOF
Release setup check failed
  Failing checks: $failures
EOF
  exit 1
fi

echo "Release setup looks ready"
