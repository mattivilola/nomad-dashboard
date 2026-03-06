#!/bin/zsh
set -euo pipefail

CACHE_ROOT="${TMPDIR:-/tmp}/nomad-dashboard-swiftpm"
mkdir -p "$CACHE_ROOT/clang-module-cache" "$CACHE_ROOT/module-cache"

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/module-cache"

swift test --package-path Packages/NomadCore --scratch-path "$CACHE_ROOT/nomadcore"
swift test --package-path Packages/NomadUI --scratch-path "$CACHE_ROOT/nomadui"
./scripts/test-release-workflow.sh
