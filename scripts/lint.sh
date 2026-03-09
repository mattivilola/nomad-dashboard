#!/bin/zsh
set -euo pipefail

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat not installed; skipping lint." >&2
  exit 0
fi

SWIFT_VERSION="6.0"

if [[ -f .swift-version ]]; then
  SWIFT_VERSION="$(< .swift-version)"
fi

swiftformat App Packages --lint --swift-version "$SWIFT_VERSION" --cache ignore
