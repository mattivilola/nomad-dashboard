#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
SCHEME="NomadDashboard"
ARCHIVE_PATH="artifacts/NomadDashboard.xcarchive"

mkdir -p artifacts

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive

