#!/bin/zsh
set -euo pipefail

CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nomad-dashboard-probe.XXXXXX")"
trap 'rm -rf "$CACHE_ROOT"' EXIT

mkdir -p "$CACHE_ROOT/clang-module-cache" "$CACHE_ROOT/module-cache"

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/module-cache"

swift run \
  --package-path Packages/NomadCore \
  --scratch-path "$CACHE_ROOT/nomadcore" \
  NomadSourceProbe \
  "$@"
