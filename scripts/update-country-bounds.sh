#!/bin/zsh
set -euo pipefail

# Regenerates Packages/NomadCore/Sources/NomadCore/Resources/country-bounds.json (a bounding box per country,
# for framing a planned trip on a map) from the Natural Earth country shapes the visited-places map ships.
# Run it manually when those shapes change; the app itself never computes this. Extra arguments are passed
# to the script, e.g. `--output /tmp/country-bounds.json`.

SCRIPT_DIR="${0:A:h}"

CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nomad-dashboard-bounds.XXXXXX")"
trap 'rm -rf "$CACHE_ROOT"' EXIT

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH"

swift "$SCRIPT_DIR/update-country-bounds.swift" "$@"
