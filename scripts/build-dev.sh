#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
SCHEME="NomadDashboard"
DESTINATION="platform=macOS,arch=$(uname -m)"

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

BUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Debug
  -destination "$DESTINATION"
  -derivedDataPath DerivedData
  build
)

if [[ "${CI:-}" == "true" ]]; then
  BUILD_ARGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
fi

./scripts/xcodebuild-pretty.sh "${BUILD_ARGS[@]}"
