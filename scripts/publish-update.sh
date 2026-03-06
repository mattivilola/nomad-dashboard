#!/bin/zsh
set -euo pipefail

DRY_RUN="false"

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run: would generate and publish the Sparkle appcast and release artifacts."
  exit 0
fi

echo "Configure Sparkle signing keys and GitHub release credentials before publishing updates."
