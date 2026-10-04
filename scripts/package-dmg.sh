#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

APP_DIR="$PWD/dist/Copio.app"
DMG_PATH="${1:-$PWD/dist/Copio-local.dmg}"
mkdir -p "${DMG_PATH:h}"
if [[ ! -d "$APP_DIR" ]]; then
  print -u2 "Build Copio first with ./scripts/build-app.sh"
  exit 1
fi

codesign --verify --deep --strict "$APP_DIR"
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT
ditto "$APP_DIR" "$STAGING_DIR/Copio.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -quiet -volname "Copio" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
print "$DMG_PATH"
