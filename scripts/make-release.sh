#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Browser Portal"
ZIP_PREFIX="Browser.Portal"
RELEASE_DIR="$ROOT_DIR/dist/release"
TEMPLATE_PATH="$ROOT_DIR/packaging/homebrew/Casks/browser-portal.rb.template"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <version-tag> [repository-slug]" >&2
  exit 1
fi

VERSION_TAG="$1"
REPOSITORY_SLUG="${2:-${GITHUB_REPOSITORY:-kunalpowar/browser-portal}}"
APP_VERSION="${VERSION_TAG#v}"
BUILD_NUMBER="${GITHUB_RUN_NUMBER:-1}"
ZIP_NAME="$ZIP_PREFIX-$VERSION_TAG.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
SHA_PATH="$RELEASE_DIR/$ZIP_NAME.sha256"
CASK_PATH="$RELEASE_DIR/browser-portal.rb"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
DOWNLOAD_URL="https://github.com/$REPOSITORY_SLUG/releases/download/$VERSION_TAG/$ZIP_NAME"

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

APP_VERSION="$APP_VERSION" APP_BUILD="$BUILD_NUMBER" "$ROOT_DIR/scripts/build-app.sh"

ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" | awk '{print $1}' > "$SHA_PATH"

ZIP_SHA="$(cat "$SHA_PATH")"

sed \
  -e "s|__VERSION__|$APP_VERSION|g" \
  -e "s|__SHA256__|$ZIP_SHA|g" \
  -e "s|__DOWNLOAD_URL__|$DOWNLOAD_URL|g" \
  "$TEMPLATE_PATH" > "$CASK_PATH"

cat <<EOF
Release assets ready:
- $ZIP_PATH
- $SHA_PATH
- $CASK_PATH
EOF
