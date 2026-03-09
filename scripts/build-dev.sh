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
ORIGINAL_HOME="${HOME:-}"
ORIGINAL_CFFIXED_USER_HOME="${CFFIXED_USER_HOME-}"

mkdir -p \
  "$PACKAGE_ROOT" \
  "$HOME_ROOT/Library/Caches" \
  "$HOME_ROOT/Library/Developer/Xcode/DerivedData" \
  "$XDG_CACHE_ROOT/clang/ModuleCache" \
  "$CACHE_ROOT/module-cache"

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

configure_build_environment() {
  local mode="$1"

  export XDG_CACHE_HOME="$XDG_CACHE_ROOT"
  export CLANG_MODULE_CACHE_PATH="$XDG_CACHE_ROOT/clang/ModuleCache"
  export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/module-cache"

  if [[ "$mode" == "isolated-home" ]]; then
    export CFFIXED_USER_HOME="$HOME_ROOT"
    export HOME="$HOME_ROOT"
    return
  fi

  export HOME="$ORIGINAL_HOME"
  if [[ -n "$ORIGINAL_CFFIXED_USER_HOME" ]]; then
    export CFFIXED_USER_HOME="$ORIGINAL_CFFIXED_USER_HOME"
  else
    unset CFFIXED_USER_HOME
  fi
}

run_xcodebuild() {
  local log_file="$1"
  shift

  if command -v xcbeautify >/dev/null 2>&1; then
    xcodebuild "$@" 2>&1 | tee "$log_file" | xcbeautify
  else
    xcodebuild -quiet "$@" 2>&1 | tee "$log_file"
  fi
}

provisioning_failure_in_log() {
  local log_file="$1"

  grep -Eqi \
    "No profiles for|provisioning profiles matching|Automatic signing is disabled and unable to generate a profile|requires a provisioning profile|No signing certificate" \
    "$log_file"
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
  configure_build_environment "isolated-home"
  echo "Using unsigned CI debug build"
  run_xcodebuild "$CACHE_ROOT/build-ci.log" \
    "${BUILD_ARGS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
elif debug_signing_is_configured; then
  configure_build_environment "local-home"

  SIGNED_BUILD_ARGS=("${BUILD_ARGS[@]}")
  if allow_provisioning_updates; then
    echo "Using local debug signing overrides from $DEBUG_SIGNING_CONFIG with provisioning updates enabled"
    SIGNED_BUILD_ARGS+=(-allowProvisioningUpdates)
  else
    echo "Using local debug signing overrides from $DEBUG_SIGNING_CONFIG"
  fi

  if run_xcodebuild "$CACHE_ROOT/build-signed.log" "${SIGNED_BUILD_ARGS[@]}"; then
    exit 0
  else
    signed_status=$?
  fi

  if provisioning_failure_in_log "$CACHE_ROOT/build-signed.log"; then
    echo "Signed debug build could not provision com.iloapps.NomadDashboard.dev. Retrying as unsigned Debug build; WeatherKit will be unavailable."
    configure_build_environment "isolated-home"
    echo "Using unsigned local debug build (fallback after provisioning failure)"
    run_xcodebuild "$CACHE_ROOT/build-unsigned.log" \
      "${BUILD_ARGS[@]}" \
      CODE_SIGNING_ALLOWED=NO \
      CODE_SIGNING_REQUIRED=NO
    exit 0
  fi

  exit "$signed_status"
else
  configure_build_environment "isolated-home"
  echo "Using unsigned local debug build (create $DEBUG_SIGNING_CONFIG to enable signed WeatherKit testing)"
  run_xcodebuild "$CACHE_ROOT/build-unsigned.log" \
    "${BUILD_ARGS[@]}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO
fi
