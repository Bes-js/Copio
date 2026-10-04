#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

RESOURCE_DIR="$PWD/Sources/Copio/Resources"
DOCS_DIR="$PWD/docs"
ICONSET_DIR="$(mktemp -d)/Copio.iconset"
mkdir -p "$ICONSET_DIR"
mkdir -p "$DOCS_DIR"
trap 'rm -rf "${ICONSET_DIR:h}"' EXIT

swift scripts/generate-icon.swift "$RESOURCE_DIR/Copio-icon-preview.png"
sips -z 192 192 "$RESOURCE_DIR/Copio-icon-preview.png" --out "$DOCS_DIR/copio-logo.png" >/dev/null
for base in 16 32 128 256 512; do
  sips -z "$base" "$base" "$RESOURCE_DIR/Copio-icon-preview.png" --out "$ICONSET_DIR/icon_${base}x${base}.png" >/dev/null
  doubled=$((base * 2))
  sips -z "$doubled" "$doubled" "$RESOURCE_DIR/Copio-icon-preview.png" --out "$ICONSET_DIR/icon_${base}x${base}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCE_DIR/Copio.icns"
