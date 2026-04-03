#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Browser Portal"
EXECUTABLE_NAME="BrowserPortal"
BUILD_DIR="$ROOT_DIR/.build/release"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_DIR="$OUTPUT_DIR/$APP_NAME.app"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

swift build --configuration release --product "$EXECUTABLE_NAME" --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"

if [[ -x "$PLIST_BUDDY" ]]; then
  "$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_DIR/Contents/Info.plist"
  "$PLIST_BUDDY" -c "Set :CFBundleVersion $APP_BUILD" "$APP_DIR/Contents/Info.plist"
fi

echo "Built $APP_DIR"
