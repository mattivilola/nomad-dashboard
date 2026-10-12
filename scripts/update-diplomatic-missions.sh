#!/bin/zsh
set -euo pipefail

# Regenerates Packages/NomadCore/Sources/NomadCore/Resources/diplomatic-missions.json from the
# Wikidata SPARQL endpoint (CC0). Run it manually before a release when the embassy data should be
# refreshed; the app itself never talks to Wikidata. Extra arguments are passed to the tool, e.g.
# `--output /tmp/missions.json` or `--help`.

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"

CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nomad-dashboard-missions.XXXXXX")"
trap 'rm -rf "$CACHE_ROOT"' EXIT

mkdir -p "$CACHE_ROOT/clang-module-cache" "$CACHE_ROOT/module-cache"

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/module-cache"

cd "$REPO_ROOT"

swift run \
  --package-path Packages/NomadCore \
  --scratch-path "$CACHE_ROOT/nomadcore" \
  NomadMissionDatasetBuilder \
  "$@"
