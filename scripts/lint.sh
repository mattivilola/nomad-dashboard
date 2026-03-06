#!/bin/zsh
set -euo pipefail

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat not installed; skipping lint." >&2
  exit 0
fi

swiftformat --lint App Packages

