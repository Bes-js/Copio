#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

APP_DIR="$PWD/dist/Copio.app"
DMG_PATH="${1:-$PWD/dist/Copio-local.dmg}"
BACKGROUND_SVG="$PWD/docs/dmg-background.svg"
BACKGROUND_PNG="$PWD/docs/dmg-background.png"
TEMP_DIR="$(mktemp -d)"
TEMP_DMG="$TEMP_DIR/Copio.dmg"
trap 'rm -rf "$TEMP_DIR"' EXIT
mkdir -p "${DMG_PATH:h}"
if [[ ! -d "$APP_DIR" ]]; then
  print -u2 "Build Copio first with ./scripts/build-app.sh"
  exit 1
fi
if [[ ! -x "$(command -v create-dmg)" ]]; then
  print -u2 "package-dmg.sh requires create-dmg. Install it with: brew install create-dmg"
  exit 1
fi
if [[ ! -f "$BACKGROUND_SVG" ]]; then
  print -u2 "Missing DMG background: $BACKGROUND_SVG"
  exit 1
fi

codesign --verify --deep --strict "$APP_DIR"
sips -s format png "$BACKGROUND_SVG" --out "$BACKGROUND_PNG" >/dev/null

create-dmg \
  --volname "Copio" \
  --volicon "$PWD/Sources/Copio/Resources/Copio.icns" \
  --background "$BACKGROUND_PNG" \
  --window-pos 240 160 \
  --window-size 720 460 \
  --icon-size 112 \
  --text-size 12 \
  --icon "Copio.app" 250 275 \
  --hide-extension "Copio.app" \
  --app-drop-link 475 275 \
  --no-internet-enable \
  --format UDZO \
  --hdiutil-quiet \
  "$TEMP_DMG" \
  "$APP_DIR" >/dev/null
mv -f "$TEMP_DMG" "$DMG_PATH"
print "$DMG_PATH"
