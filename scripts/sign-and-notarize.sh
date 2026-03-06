#!/bin/zsh
set -euo pipefail

DRY_RUN="false"

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "Dry run: would codesign, notarize, and staple the release archive."
  exit 0
fi

echo "Load release credentials from Config/Signing.example.env and implement signing before production releases."

