#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
SCHEME="NomadDashboard"
ARCHIVE_PATH="artifacts/NomadDashboard.xcarchive"
DESTINATION="generic/platform=macOS"

mkdir -p artifacts

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

./scripts/xcodebuild-pretty.sh \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  archive
