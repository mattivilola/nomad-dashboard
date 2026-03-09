#!/bin/zsh
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to bootstrap Nomad Dashboard." >&2
  exit 1
fi

brew bundle --file Brewfile

