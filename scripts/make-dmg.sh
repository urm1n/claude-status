#!/usr/bin/env bash
# Builds a universal app and packs it into build/ClaudeStatusLight-<version>.dmg.
# To notarize (needs an Apple Developer account):
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" VERSION=1.0.0 scripts/make-dmg.sh
#   xcrun notarytool submit build/ClaudeStatusLight-1.0.0.dmg --keychain-profile <profile> --wait
#   xcrun stapler staple build/ClaudeStatusLight-1.0.0.dmg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.0}"
export VERSION

"$ROOT/scripts/build-app.sh" --universal

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT/build/Claude Status Light.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$ROOT/build/ClaudeStatusLight-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Claude Status Light" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then codesign --sign "$SIGN_IDENTITY" "$DMG"; fi

echo "==> $DMG"
shasum -a 256 "$DMG"
