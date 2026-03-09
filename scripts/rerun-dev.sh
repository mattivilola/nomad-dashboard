#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
APP_PATH="DerivedData/Build/Products/Debug/Nomad Dashboard Dev.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Nomad Dashboard Dev"

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

if pgrep -f "$EXECUTABLE_PATH" >/dev/null 2>&1; then
  pkill -f "$EXECUTABLE_PATH"
  sleep 1
fi

./scripts/build-dev.sh
open "$APP_PATH"
