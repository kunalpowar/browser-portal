#!/usr/bin/env bash
set -euo pipefail

LATEST_TAG="$(git tag --list 'v*' --sort=-v:refname | head -n 1)"

if [[ -z "$LATEST_TAG" ]]; then
  echo "v0.1.0"
  exit 0
fi

VERSION="${LATEST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"

if [[ -z "${MAJOR:-}" || -z "${MINOR:-}" || -z "${PATCH:-}" ]]; then
  echo "Latest tag is not a simple semantic version: $LATEST_TAG" >&2
  exit 1
fi

echo "v${MAJOR}.${MINOR}.$((PATCH + 1))"
