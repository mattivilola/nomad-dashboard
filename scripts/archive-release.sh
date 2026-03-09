#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/release-common.sh"
cd "$REPO_ROOT"

PROJECT="NomadDashboard.xcodeproj"
SCHEME="NomadDashboard"
DESTINATION="generic/platform=macOS"
BUILD_SETTINGS=()

mkdir -p "$ARTIFACTS_ROOT"
load_signing_env

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

if [[ -n "${NOMAD_TEAM_ID:-}" ]]; then
  BUILD_SETTINGS+=(DEVELOPMENT_TEAM="$NOMAD_TEAM_ID")
fi

if [[ -n "${NOMAD_SIGNING_IDENTITY:-}" ]]; then
  BUILD_SETTINGS+=(
    CODE_SIGN_IDENTITY="$NOMAD_SIGNING_IDENTITY"
    CODE_SIGN_STYLE=Manual
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
fi

if [[ -n "${NOMAD_SPARKLE_PUBLIC_ED_KEY:-}" ]]; then
  BUILD_SETTINGS+=(
    SPARKLE_PUBLIC_ED_KEY="$NOMAD_SPARKLE_PUBLIC_ED_KEY"
    SPARKLE_FEED_URL="$(release_feed_url)"
  )
fi

./scripts/xcodebuild-pretty.sh \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  "${BUILD_SETTINGS[@]}"
