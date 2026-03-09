#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
APP_PATH="DerivedData/Build/Products/Debug/Nomad Dashboard Dev.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/Nomad Dashboard Dev"

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

./scripts/build-dev.sh

if pgrep -f "$EXECUTABLE_PATH" >/dev/null 2>&1; then
  echo "Nomad Dashboard Dev is already running."
  echo "Quit the current menu bar instance first, then run 'make run' again to launch the latest build."
  exit 0
fi

open "$APP_PATH"
