#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Battery Usage"
VERSION="${VERSION:-1.0.2}"
BUILD_DIR="$ROOT_DIR/build"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_PATH="$DIST_DIR/BatteryUsage-$VERSION.pkg"
ZIP_PATH="$DIST_DIR/BatteryUsage-$VERSION.zip"

mkdir -p "$DIST_DIR"
"$ROOT_DIR/scripts/build-app.sh" >/dev/null

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications"
/usr/bin/ditto --norsrc "$APP_PATH" "$PKG_ROOT/Applications/$APP_NAME.app"

/usr/bin/pkgbuild \
  --root "$PKG_ROOT" \
  --install-location "/" \
  --identifier "com.apple101012.BatteryUsage.pkg" \
  --version "$VERSION" \
  --filter '(^|/)\._.*' \
  --filter '(^|/)\.DS_Store$' \
  "$PKG_PATH"

rm -f "$ZIP_PATH"
(
  cd "$BUILD_DIR"
  COPYFILE_DISABLE=1 /usr/bin/ditto -c -k --norsrc --keepParent "$APP_NAME.app" "$ZIP_PATH"
)

echo "Built:"
echo "  $APP_PATH"
echo "  $PKG_PATH"
echo "  $ZIP_PATH"
