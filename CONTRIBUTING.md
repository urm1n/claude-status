# Contributing

Thanks for helping. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

[Open an issue](https://github.com/urm1n/claude-status/issues/new/choose) and include:

- macOS version, and Apple Silicon or Intel
- Where you run Claude Code (Terminal, iTerm, VS Code, Cursor, desktop app…) and its version (`claude --version`)
- The output of `~/.claude-status-light/bin/csl-hook status`
- What the light showed vs. what you expected

## Development setup

You need macOS 14+ and Xcode (or the Command Line Tools). There are no third-party dependencies.

```bash
git clone https://github.com/urm1n/claude-status.git
cd claude-status
swift build          # build everything
swift test           # run the tests
./install.sh         # build the .app, put it in /Applications, launch it
```

### Project layout

| Path | What |
|---|---|
| `Sources/StatusCore/` | Shared logic, Foundation only: the hook state machine (`HookReducer`), the session model, process lookup, the order-preserving JSON parser and the `settings.json` installer |
| `Sources/csl-hook/` | The helper Claude Code runs on every hook event, also the `install / uninstall / status` CLI |
| `Sources/ClaudeStatusLight/` | The menu bar app: status item and menu (AppKit), notifications, and a SwiftUI settings window loaded only when opened |
| `Tests/StatusCoreTests/` | Unit tests for the state machine and the settings installer |
| `scripts/` | `build-app.sh` (the .app), `make-dmg.sh` (a universal DMG), `make-icon.swift` (app icon), `make-docs-images.sh` (README images) |
| `Resources/AppIcon.svg` | The logo. The flower path also lives in `BrandMark.swift`, which draws the menu bar icon and the app icon |
| `docs/` | [How it works](docs/how-it-works.md), the original [requirements](docs/requirements.md), images |

### Testing without touching your real setup

Two environment variables redirect everything:

```bash
export CLAUDE_STATUS_LIGHT_DIR=/tmp/csl-test               # instead of ~/.claude-status-light
export CLAUDE_STATUS_LIGHT_SETTINGS=/tmp/csl-settings.json  # instead of ~/.claude/settings.json

# Run the app against them
"build/Claude Status Light.app/Contents/MacOS/ClaudeStatusLight" &

# Fake some hook events
HOOK="build/Claude Status Light.app/Contents/MacOS/csl-hook"
echo '{"hook_event_name":"SessionStart","session_id":"demo","cwd":"/tmp/my-project"}' | "$HOOK"
echo '{"hook_event_name":"UserPromptSubmit","session_id":"demo"}' | "$HOOK"
echo '{"hook_event_name":"PermissionRequest","session_id":"demo","tool_name":"Bash","tool_use_id":"t1"}' | "$HOOK"
echo '{"hook_event_name":"PostToolUse","session_id":"demo","tool_use_id":"t1"}' | "$HOOK"
echo '{"hook_event_name":"Stop","session_id":"demo"}' | "$HOOK"
echo '{"hook_event_name":"SessionEnd","session_id":"demo"}' | "$HOOK"
```

To check memory and CPU: `footprint $(pgrep -x ClaudeStatusLight)` and `top -pid $(pgrep -x ClaudeStatusLight)`.

### Changing the logo or how the light looks

Update the path in `Sources/ClaudeStatusLight/BrandMark.swift` (and `Resources/AppIcon.svg`), then:

```bash
scripts/make-docs-images.sh   # app icon + every image in docs/images
scripts/build-app.sh          # rebuilds Resources/AppIcon.icns when BrandMark changes
```

## Ground rules

These keep the app what it promises to be:

- **Never break Claude Code.** The hook must stay fast, print nothing to stdout, and exit 0 on every path.
- **No polling.** Use file-system and process events. A timer is only OK when it's one-shot and armed only when needed.
- **No telemetry, no third-party dependencies.** No network by default; the opt-in usage fetch is the only request, and only to Anthropic.
- **Never refresh or store Claude Code's login.** Read it from the Keychain per request, and nothing else.
- **Privacy.** Never store prompts, code, tool inputs or responses.
- **settings.json.** Back it up, append only, touch only our own entries, and keep everything else byte-for-byte.
- If you change state logic, add a test in `HookReducerTests`.
- Check the [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) for current event names and payloads.

## Pull requests

1. Fork the repo and create a branch from `main`.
2. Make your change, and run `swift test` and `scripts/build-app.sh`.
3. Open a PR that says what changed and how you tested it. CI builds and tests every PR.

## Releasing (maintainers)

1. Update `CHANGELOG.md`.
2. Tag and push: `git tag v1.1.0 && git push origin v1.1.0`
3. The **Release** workflow builds a universal DMG and publishes a GitHub Release with `ClaudeStatusLight.dmg` (the stable "latest" link), `ClaudeStatusLight-<version>.dmg` and `SHA256SUMS.txt`.

Signing and notarizing need an Apple Developer ID. With one, build locally:

```bash
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" VERSION=1.1.0 scripts/make-dmg.sh
xcrun notarytool submit build/ClaudeStatusLight-1.1.0.dmg --keychain-profile <profile> --wait
xcrun stapler staple build/ClaudeStatusLight-1.1.0.dmg
```
