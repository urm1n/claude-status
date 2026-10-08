#!/usr/bin/env bash
# Regenerates docs/images/*.png from the app's drawing code (icons, light states, usage panel).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The app target is an executable, so compile its sources (minus main.swift) with the renderer.
for f in Sources/StatusCore/*.swift Sources/ClaudeStatusLight/*.swift; do
    [[ "$(basename "$f")" == main.swift ]] && continue
    sed '/^import StatusCore$/d' "$f" > "$WORK/$(basename "$f")"
done
cp scripts/docs-images/Render.swift "$WORK/"

mkdir -p build
swiftc -parse-as-library scripts/make-icon.swift Sources/ClaudeStatusLight/BrandMark.swift -o build/make-icon
build/make-icon build >/dev/null
swiftc -parse-as-library "$WORK"/*.swift -o "$WORK/render"
CLAUDE_STATUS_LIGHT_DIR="$WORK/data" "$WORK/render" docs/images
echo "==> docs/images updated"
