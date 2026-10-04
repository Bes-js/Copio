#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --triple arm64-apple-macosx --scratch-path .build-arm64
swift build -c release --triple x86_64-apple-macosx --scratch-path .build-x86_64
APP_DIR="$PWD/dist/Copio.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
lipo -create ".build-arm64/release/Copio" ".build-x86_64/release/Copio" -output "$APP_DIR/Contents/MacOS/Copio"
ditto ".build-arm64/release/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/Copio"
cp "Sources/Copio/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "Sources/Copio/Resources/Copio.icns" "$APP_DIR/Contents/Resources/Copio.icns"
codesign --force --sign - "$APP_DIR"
touch "$APP_DIR"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
echo "$APP_DIR"
