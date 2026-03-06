#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
SCHEME="NomadDashboard"

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath DerivedData \
  build

