#!/bin/sh
# Xcode Cloud sets CI_BUILD_NUMBER. TestFlight rejects an upload whose
# CFBundleVersion (CURRENT_PROJECT_VERSION) was already used.
set -eu

if [ -z "${CI_BUILD_NUMBER:-}" ]; then
  exit 0
fi

case "$CI_BUILD_NUMBER" in
  *[!0-9]*)
    echo "Unexpected CI_BUILD_NUMBER: $CI_BUILD_NUMBER" >&2
    exit 1
    ;;
esac

cd "$(dirname "$0")/.."
sed -i '' "s/CURRENT_PROJECT_VERSION = 1;/CURRENT_PROJECT_VERSION = ${CI_BUILD_NUMBER};/g" \
  NudgeDeck.xcodeproj/project.pbxproj
