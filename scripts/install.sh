#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${TARGET_DIR:-$HOME/Applications}"
APP_NAME="ChooseBrowser"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT_DIR/scripts/build-app.sh"
mkdir -p "$TARGET_DIR"
rm -rf "$TARGET_DIR/$APP_NAME.app"
cp -R "$ROOT_DIR/dist/$APP_NAME.app" "$TARGET_DIR/$APP_NAME.app"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_DIR/$APP_NAME.app" >/dev/null 2>&1 || true
fi

echo "Installed $TARGET_DIR/$APP_NAME.app"
