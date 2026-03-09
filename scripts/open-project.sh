#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

open "$PROJECT"

