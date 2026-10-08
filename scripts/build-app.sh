#!/usr/bin/env bash
# Builds "build/Claude Status Light.app".
#   scripts/build-app.sh              native arch (fast)
#   scripts/build-app.sh --universal  Apple Silicon + Intel (for releases)
# Signs ad-hoc by default; set SIGN_IDENTITY="Developer ID Application: ..." to sign for distribution.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_NAME="Claude Status Light"
APP="$ROOT/build/$APP_NAME.app"

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Building ($(uname -m)${ARCH_FLAGS:+, universal})"
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeStatusLight" "$APP/Contents/MacOS/"
cp "$BIN_DIR/csl-hook" "$APP/Contents/MacOS/"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ ! -f Resources/AppIcon.icns || Sources/ClaudeStatusLight/BrandMark.swift -nt Resources/AppIcon.icns \
      || scripts/make-icon.swift -nt Resources/AppIcon.icns ]]; then
    echo "==> Rendering app icon"
    mkdir -p build
    swiftc -parse-as-library scripts/make-icon.swift Sources/ClaudeStatusLight/BrandMark.swift -o build/make-icon
    build/make-icon build >/dev/null
    iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

echo "==> Signing"
IDENTITY="${SIGN_IDENTITY:--}"
OPTS=(--force --timestamp=none)
if [[ "$IDENTITY" != "-" ]]; then OPTS=(--force --timestamp --options runtime); fi
codesign "${OPTS[@]}" --sign "$IDENTITY" "$APP/Contents/MacOS/csl-hook"
codesign "${OPTS[@]}" --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "==> Done: $APP ($(du -sh "$APP" | cut -f1))"
