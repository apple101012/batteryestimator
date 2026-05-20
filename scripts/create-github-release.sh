#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
TAG="v$VERSION"

"$ROOT_DIR/scripts/package-release.sh"

if ! /usr/bin/git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This folder is not a git repository yet." >&2
  exit 1
fi

/opt/homebrew/bin/gh release create "$TAG" \
  "$ROOT_DIR/dist/BatteryUsage-$VERSION.pkg" \
  "$ROOT_DIR/dist/BatteryUsage-$VERSION.zip" \
  --target main \
  --title "Battery Usage $VERSION" \
  --notes "Initial native macOS menu bar release. Download the pkg installer for the simplest install path."
