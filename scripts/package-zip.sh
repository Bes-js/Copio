#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

APP_DIR="$PWD/dist/Copio.app"
ZIP_PATH="${1:-$PWD/dist/Copio-local.zip}"
mkdir -p "${ZIP_PATH:h}"
if [[ ! -d "$APP_DIR" ]]; then
  print -u2 "Build Copio first with ./scripts/build-app.sh"
  exit 1
fi

codesign --verify --deep --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
print "$ZIP_PATH"
