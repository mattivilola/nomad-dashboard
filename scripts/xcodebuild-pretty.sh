#!/bin/zsh
set -euo pipefail

if (($# == 0)); then
  echo "Usage: $0 <xcodebuild args...>" >&2
  exit 1
fi

if command -v xcbeautify >/dev/null 2>&1; then
  xcodebuild "$@" | xcbeautify
else
  xcodebuild -quiet "$@"
fi
