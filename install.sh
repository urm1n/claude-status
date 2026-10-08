#!/usr/bin/env bash
# One-step install from source: build, copy to /Applications, launch.
# On first launch the app asks before it adds its hooks to ~/.claude/settings.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claude Status Light"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are required. Installing..."
    xcode-select --install
    echo "Run ./install.sh again when that finishes."
    exit 1
fi

"$ROOT/scripts/build-app.sh"

DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"

if pgrep -x ClaudeStatusLight >/dev/null; then
    echo "==> Quitting the running copy"
    osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || pkill -x ClaudeStatusLight || true
    sleep 1
fi

echo "==> Installing to $DEST"
rm -rf "$DEST/$APP_NAME.app"
cp -R "$ROOT/build/$APP_NAME.app" "$DEST/"

open "$DEST/$APP_NAME.app"
echo
echo "Claude Status Light is running in your menu bar."
echo "If you haven't yet, click \"Install Hooks\" when it asks (or from its menu)."
