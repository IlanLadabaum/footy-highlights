#!/bin/bash
# Builds a Release copy of Footy Highlights (ad-hoc signed) into build/Release/.
# This is the .app that will go into the downloadable DMG later (M5).
#
#   scripts/build-app.sh            build only
#   scripts/build-app.sh --install  build, then copy to /Applications (replacing an older copy)
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Footy Highlights.app"
OUT="build/Release"

if command -v xcodegen >/dev/null; then xcodegen generate --quiet; fi

xcodebuild -project FootyHighlights.xcodeproj -scheme FootyHighlights -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
    ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build -quiet

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "build/DerivedData/Build/Products/Release/$APP_NAME" "$OUT/"
codesign --verify --deep "$OUT/$APP_NAME"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$OUT/$APP_NAME/Contents/Info.plist")
echo "Built $OUT/$APP_NAME (version $VERSION, $(lipo -archs "$OUT/$APP_NAME/Contents/MacOS/Footy Highlights"))"

if [[ "${1:-}" == "--install" ]]; then
    osascript -e 'quit app "Footy Highlights"' 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME"
    cp -R "$OUT/$APP_NAME" /Applications/
    echo "Installed /Applications/$APP_NAME"
fi
