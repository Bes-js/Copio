#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if [[ $# -ne 2 ]]; then
  print -u2 "Usage: ./scripts/generate-appcast.sh <release-directory> <tag>"
  print -u2 "Example: ./scripts/generate-appcast.sh dist/release-v1.1.0 v1.1.0"
  exit 1
fi

RELEASE_DIR="${1:A}"
TAG="$2"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Copio/Resources/Info.plist)"
if [[ "$TAG" != "v$VERSION" ]]; then
  print -u2 "Tag must be v$VERSION to match the current app version"
  exit 1
fi
ARCHIVE="$RELEASE_DIR/Copio-$VERSION.dmg"
TOOL="$PWD/.build-arm64/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [[ ! -f "$ARCHIVE" ]]; then
  print -u2 "Missing release archive: $ARCHIVE"
  exit 1
fi
if [[ ! -x "$TOOL" ]]; then
  print -u2 "Resolve the Sparkle package first with swift package resolve"
  exit 1
fi

"$TOOL" --account Bes-js-Copio \
  --download-url-prefix "https://github.com/Bes-js/Copio/releases/download/$TAG/" \
  --link "https://github.com/Bes-js/Copio/releases/tag/$TAG" \
  -o "$RELEASE_DIR/appcast.xml" "$RELEASE_DIR"
print "$RELEASE_DIR/appcast.xml"
