#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ChooseBrowser"
TARGET_DIR="${TARGET_DIR:-$HOME/Applications}"
APP_PATH="$TARGET_DIR/$APP_NAME.app"
CONFIG_DIR="${CONFIG_DIR:-$HOME/Library/Application Support/ChooseBrowser}"
PREFERENCES_PATH="${PREFERENCES_PATH:-$HOME/Library/Preferences/dev.kunalpowar.choosebrowser.plist}"
SAVED_STATE_PATH="${SAVED_STATE_PATH:-$HOME/Library/Saved Application State/dev.kunalpowar.choosebrowser.savedState}"
CACHES_PATH="${CACHES_PATH:-$HOME/Library/Caches/dev.kunalpowar.choosebrowser}"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP_PATH" >/dev/null 2>&1 || true
fi

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  printf 'Would remove:\n%s\n%s\n%s\n%s\n%s\n' \
    "$APP_PATH" \
    "$CONFIG_DIR" \
    "$PREFERENCES_PATH" \
    "$SAVED_STATE_PATH" \
    "$CACHES_PATH"
  exit 0
fi

rm -rf \
  "$APP_PATH" \
  "$CONFIG_DIR" \
  "$PREFERENCES_PATH" \
  "$SAVED_STATE_PATH" \
  "$CACHES_PATH"

echo "Removed $APP_PATH and local ChooseBrowser data"
