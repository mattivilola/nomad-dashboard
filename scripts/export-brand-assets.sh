#!/bin/zsh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRANDING_SOURCE="$REPO_ROOT/Branding/Source/NomadBrandRenderer.swift"
EXPORTS_DIR="$REPO_ROOT/Branding/Exports"
APP_ICONSET_DIR="$REPO_ROOT/App/Resources/Assets.xcassets/AppIcon.appiconset"
ICON_MASTER="$EXPORTS_DIR/NomadDashboard-icon-1024.png"
BACKGROUND_1X="$EXPORTS_DIR/NomadDashboard-dmg-background.png"
BACKGROUND_2X="$EXPORTS_DIR/NomadDashboard-dmg-background@2x.png"
BACKGROUND_TIFF="$EXPORTS_DIR/NomadDashboard-dmg-background.tiff"
CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nomad-brand-assets-cache.XXXXXX")"

cleanup() {
  rm -rf "$CACHE_ROOT"
}

trap cleanup EXIT

required_commands=(swift sips tiffutil)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
done

mkdir -p "$EXPORTS_DIR" "$APP_ICONSET_DIR"

export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/module-cache"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE"

swift "$BRANDING_SOURCE" --output-dir "$EXPORTS_DIR"

resize_icon() {
  local width="$1"
  local height="$2"
  local destination="$3"
  sips --resampleHeightWidth "$height" "$width" "$ICON_MASTER" --out "$destination" >/dev/null
}

resize_icon 16 16 "$APP_ICONSET_DIR/icon_16x16.png"
resize_icon 32 32 "$APP_ICONSET_DIR/icon_16x16@2x.png"
resize_icon 32 32 "$APP_ICONSET_DIR/icon_32x32.png"
resize_icon 64 64 "$APP_ICONSET_DIR/icon_32x32@2x.png"
resize_icon 128 128 "$APP_ICONSET_DIR/icon_128x128.png"
resize_icon 256 256 "$APP_ICONSET_DIR/icon_128x128@2x.png"
resize_icon 256 256 "$APP_ICONSET_DIR/icon_256x256.png"
resize_icon 512 512 "$APP_ICONSET_DIR/icon_256x256@2x.png"
resize_icon 512 512 "$APP_ICONSET_DIR/icon_512x512.png"
resize_icon 1024 1024 "$APP_ICONSET_DIR/icon_512x512@2x.png"

cat > "$APP_ICONSET_DIR/Contents.json" <<'EOF'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

tiffutil -cathidpicheck "$BACKGROUND_1X" "$BACKGROUND_2X" -out "$BACKGROUND_TIFF"

echo "Brand assets exported to $EXPORTS_DIR"
echo "App icon set updated in $APP_ICONSET_DIR"
