#!/bin/bash
# Builds a release of Footy Highlights for GitHub Releases + Sparkle updates:
#   1. builds the Release app (scripts/build-app.sh),
#   2. packs it into build/dist/FootyHighlights-<version>.dmg (drag-to-Applications layout),
#   3. signs the DMG with the Sparkle EdDSA private key (from your login Keychain, via generate_appcast)
#      and writes build/dist/appcast.xml pointing at this release's download URL.
#
#   scripts/release.sh             build everything locally and stop (nothing is uploaded)
#   scripts/release.sh --publish   also create the GitHub Release v<version> with the DMG and appcast.xml
#
# Before each release: bump MARKETING_VERSION and CURRENT_PROJECT_VERSION in project.yml
# (Sparkle compares CURRENT_PROJECT_VERSION, so it must go up every release).
# Optional release notes: build/dist/FootyHighlights-<version>.md (embedded in the update dialog).
set -euo pipefail

cd "$(dirname "$0")/.."
REPO="IlanLadabaum/footy-highlights"
APP_NAME="Footy Highlights.app"
DIST="build/dist"
SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

PUBLIC_KEY=$(grep -E '^\s*SPARKLE_PUBLIC_ED_KEY:' project.yml | sed -E 's/.*: *"?([^"]*)"?/\1/')
if [[ -z "$PUBLIC_KEY" ]]; then
    echo "SPARKLE_PUBLIC_ED_KEY is empty in project.yml. Run $SPARKLE_BIN/generate_keys and paste the public key." >&2
    exit 1
fi

scripts/build-app.sh
APP="build/Release/$APP_NAME"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
TAG="v$VERSION"
DMG="$DIST/FootyHighlights-$VERSION.dmg"

# DMG with the app and an Applications shortcut to drag it onto.
mkdir -p "$DIST"
find "$DIST" -name '*.dmg' ! -name "$(basename "$DMG")" -delete
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Footy Highlights $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" -quiet
rm -rf "$STAGE"

# Sparkle feed: signs the DMG (EdDSA) and lists it with this release's download URL.
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
    --embed-release-notes --maximum-versions 1 -o "$DIST/appcast.xml" "$DIST"

echo "Release $VERSION ($BUILD) ready: $DMG and $DIST/appcast.xml"

if [[ "${1:-}" == "--publish" ]]; then
    NOTES="$DIST/FootyHighlights-$VERSION.md"
    if [[ -f "$NOTES" ]]; then NOTES_ARGS=(--notes-file "$NOTES"); else NOTES_ARGS=(--notes "Footy Highlights $VERSION"); fi
    gh release create "$TAG" "$DMG" "$DIST/appcast.xml" --repo "$REPO" --title "Footy Highlights $VERSION" "${NOTES_ARGS[@]}"
    echo "Published $TAG. Installed copies will see it at their next daily check."
else
    echo "Not uploaded. Run with --publish to create the GitHub Release $TAG."
fi
