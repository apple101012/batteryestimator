#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Battery Usage"
BUNDLE_ID="com.apple101012.BatteryUsage"
VERSION="${VERSION:-1.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

/bin/cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

/usr/bin/swiftc \
  -O \
  -target "$(uname -m)-apple-macos13.0" \
  -framework AppKit \
  -framework ServiceManagement \
  "$ROOT_DIR/Sources/BatteryUsage/main.swift" \
  -o "$MACOS_DIR/$APP_NAME"

/usr/bin/codesign \
  --force \
  --sign - \
  --identifier "$BUNDLE_ID" \
  "$APP_PATH"

/usr/bin/xattr -cr "$APP_PATH" 2>/dev/null || true

echo "$APP_PATH"
