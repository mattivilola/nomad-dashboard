#!/bin/zsh
set -euo pipefail

PROJECT="NomadDashboard.xcodeproj"
SCHEME="NomadDashboard"
DESTINATION="platform=macOS,arch=$(uname -m)"
DEBUG_SIGNING_CONFIG="Config/Signing.debug.local.xcconfig"
CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nomad-dashboard-xcode.XXXXXX")"
PACKAGE_ROOT="$CACHE_ROOT/source-packages"
HOME_ROOT="$CACHE_ROOT/home"
XDG_CACHE_ROOT="$CACHE_ROOT/xdg-cache"

mkdir -p \
  "$PACKAGE_ROOT" \
  "$HOME_ROOT/Library/Caches" \
  "$HOME_ROOT/Library/Developer/Xcode/DerivedData" \
  "$XDG_CACHE_ROOT/clang/ModuleCache" \
  "$CACHE_ROOT/module-cache"

export CFFIXED_USER_HOME="$HOME_ROOT"
export HOME="$HOME_ROOT"
export XDG_CACHE_HOME="$XDG_CACHE_ROOT"
export CLANG_MODULE_CACHE_PATH="$XDG_CACHE_ROOT/clang/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/module-cache"

xcconfig_value() {
  local key="$1"
  [[ -f "$DEBUG_SIGNING_CONFIG" ]] || return 1

  awk -F '=' -v key="$key" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $2
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$DEBUG_SIGNING_CONFIG"
}

debug_signing_is_configured() {
  local team_id
  team_id="$(xcconfig_value "DEVELOPMENT_TEAM" || true)"

  [[ -n "$team_id" && "$team_id" != "YOURTEAMID" ]]
}

allow_provisioning_updates() {
  if [[ -n "${NOMAD_DEBUG_ALLOW_PROVISIONING_UPDATES+x}" ]]; then
    [[ "${NOMAD_DEBUG_ALLOW_PROVISIONING_UPDATES}" == "true" ]]
    return
  fi

  [[ "$(xcconfig_value "NOMAD_DEBUG_ALLOW_PROVISIONING_UPDATES" || true)" == "true" ]]
}

if [[ ! -d "$PROJECT" ]]; then
  ./scripts/generate-project.sh
fi

BUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration Debug
  -destination "$DESTINATION"
  -derivedDataPath DerivedData
  -clonedSourcePackagesDirPath "$PACKAGE_ROOT"
  build
)

if [[ "${CI:-}" == "true" ]]; then
  BUILD_ARGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
elif debug_signing_is_configured; then
  if allow_provisioning_updates; then
    echo "Using local debug signing overrides from $DEBUG_SIGNING_CONFIG with provisioning updates enabled"
    BUILD_ARGS+=(-allowProvisioningUpdates)
  else
    echo "Using local debug signing overrides from $DEBUG_SIGNING_CONFIG"
  fi
else
  echo "Using unsigned local debug build (create $DEBUG_SIGNING_CONFIG to enable signed WeatherKit testing)"
  BUILD_ARGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGNING_REQUIRED=NO
  )
fi

./scripts/xcodebuild-pretty.sh "${BUILD_ARGS[@]}"
