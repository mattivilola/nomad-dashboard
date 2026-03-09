#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
SCHEME="NomadDashboard"
DESTINATION="platform=macOS,arch=$(uname -m)"

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

./scripts/xcodebuild-pretty.sh \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "$DESTINATION" \
  -derivedDataPath DerivedData \
  build
