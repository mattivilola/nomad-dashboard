#!/bin/zsh
set -euo pipefail

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed. Run 'make bootstrap' first." >&2
  exit 1
fi

xcodegen generate

