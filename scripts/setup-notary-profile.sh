#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/release-common.sh"
cd "$REPO_ROOT"

APPLE_ID="${APPLE_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apple-id)
      [[ $# -ge 2 ]] || fail "Missing value for --apple-id."
      APPLE_ID="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: ./scripts/setup-notary-profile.sh [--apple-id you@example.com]

Creates or refreshes the notarytool keychain profile configured in
Config/Signing.env. The app-specific password is entered interactively by
notarytool and is not stored in the repository.
EOF
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

require_command xcrun
load_signing_env

[[ -n "${NOMAD_TEAM_ID:-}" ]] || fail "NOMAD_TEAM_ID is not set. Configure it in Config/Signing.env first."
[[ -n "${NOMAD_NOTARY_PROFILE:-}" ]] || fail "NOMAD_NOTARY_PROFILE is not set. Configure it in Config/Signing.env first."
[[ -n "${APPLE_ID:-}" ]] || fail "APPLE_ID is required. Run 'make release-setup-notary APPLE_ID=you@example.com'."

if xcrun notarytool history --keychain-profile "$NOMAD_NOTARY_PROFILE" >/dev/null 2>&1; then
  cat <<EOF
Notary profile already works
  Profile: $NOMAD_NOTARY_PROFILE
  Team ID: $NOMAD_TEAM_ID
EOF
  exit 0
fi

xcrun notarytool store-credentials "$NOMAD_NOTARY_PROFILE" \
  --apple-id "$APPLE_ID" \
  --team-id "$NOMAD_TEAM_ID"

assert_notary_profile_available

cat <<EOF
Stored notary profile
  Profile: $NOMAD_NOTARY_PROFILE
  Team ID: $NOMAD_TEAM_ID
EOF
