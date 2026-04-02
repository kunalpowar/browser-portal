#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-$HOME/Applications}"
APP_NAME="ChooseBrowser"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_DIR/$APP_NAME.app"
cp -R "$ROOT_DIR/dist/$APP_NAME.app" "$TARGET_DIR/$APP_NAME.app"

echo "Installed $TARGET_DIR/$APP_NAME.app"
