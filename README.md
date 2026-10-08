# Claude Status Light

A tiny macOS menu bar app that shows **one colored light** for what Claude Code is doing, and notifies you when Claude finishes or needs you.

| Light | Meaning |
|---|---|
| ◯ gray ring | No Claude Code session open |
| 🟢 green | Ready: Claude is idle, waiting for your next prompt (or just finished) |
| 🟡 yellow | Working: thinking, running tools, subagents |
| 🔴 red | Needs you: permission prompt, a question, an MCP form |

With several sessions open, the light shows the most urgent one (**red > yellow > green > gray**), and the menu lists every session with its folder, state and time in that state. Click a session to bring its terminal or editor to the front.

- **Light:** about 13 MB of memory, 0% CPU when idle, no polling. Everything is event driven.
- **Local only:** no network, no accounts, no API keys, no telemetry.
- **Native:** Swift + AppKit, a 1.5 MB app. No Electron, no Dock icon.
- Works with Claude Code in the terminal, VS Code / Cursor, and the desktop app's Code tab (anything that runs hooks from `~/.claude/settings.json`).

## Install

Requirements: macOS 14+ and Xcode or the Command Line Tools (`xcode-select --install`).

```bash
git clone <this repo> claude-status-light
cd claude-status-light
./install.sh
```

This builds the app, copies it to `/Applications`, and opens it. On first launch it asks to **Install Hooks**: click it and you're done. Start a new Claude Code session (or restart the ones already open) and it shows up in the light.

Then, optionally, open the menu and turn on **Launch at Login**.

<details>
<summary>Other ways to install</summary>

- **DMG:** `scripts/make-dmg.sh` builds a universal (Apple Silicon + Intel) `.dmg` in `build/`.
- **Homebrew:** a cask template is in [`Casks/claude-status-light.rb`](Casks/claude-status-light.rb), for when a release DMG is published.
- **Hooks from the command line:** `~/.claude-status-light/bin/csl-hook install | uninstall | status`.

</details>

## Notifications

- **Claude finished**: project folder and how long the turn took.
- **Claude needs you**: project folder and Claude's own reason ("Claude needs your permission to use Bash").

Each session has exactly one notification slot: a new one replaces the old one, and it's removed as soon as Claude gets back to work, you send a new prompt, or the session ends. Notification Center never fills up with stale Claude alerts. Clicking a notification focuses that session's terminal or editor.

In **Settings** you can turn each type on or off, pick a sound (or none) per type, skip "finished" for short turns (e.g. under 10s), and skip notifications while that session's terminal is already in front.

## Settings

Open the menu → **Settings…** (or launch the app again from Finder / Spotlight).

- Colors for each state, plus an **accessibility mode** that also changes the shape (✓, •••, !)
- Show or hide the gray light when no session is running
- Notification toggles, sounds, minimum turn length, "skip when terminal is in front"
- Idle timeout for stuck sessions (default 5 min)
- Launch at login
- Install / uninstall hooks

## How it works

```
Claude Code ──hook event (JSON on stdin)──▶ csl-hook ──writes──▶ ~/.claude-status-light/sessions/<session_id>.json
                                                                         │ (file system event, no polling)
                                                       menu bar app ◀────┘
```

1. **Install Hooks** adds one entry per event to `~/.claude/settings.json` that runs a tiny native helper, `~/.claude-status-light/bin/csl-hook`.
2. On each event the helper updates a small JSON file for that session, then exits. It takes about 10 ms, prints nothing, and always exits 0, so it can never slow down, block or break Claude Code (even if the app is quit or deleted).
3. The app watches that folder with a kernel file system watcher and watches each session's Claude process for exit. There are no timers ticking in the background.

| Hook event | Light |
|---|---|
| `SessionStart` | green |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse(Failure)`, `ElicitationResult` | yellow |
| `PermissionRequest`, `Elicitation`, `PreToolUse(AskUserQuestion)`, `Notification` (permission / input) | red + "needs you" |
| `Stop`, `StopFailure` | green + "finished" |
| `SessionEnd`, or the Claude process exits | session removed |

Edge cases handled:

- **Esc interrupts** (no `Stop` event): Claude Code's 60-second `idle_prompt` notification flips the session back to green. Failing that, a session that has been silent for the idle timeout counts as green.
- **Closed terminal / crash:** the session disappears the moment its Claude process exits.
- **Background subagents** don't hide a pending permission prompt: only the blocked agent's own activity clears red.
- **App started after Claude:** existing sessions are picked up from disk, or on their next event.
- **Same folder, several sessions:** tracked separately by `session_id`.

### What it stores

Only what's needed to draw the light: session id, project folder, state, a short reason, timestamps, and process ids. It never stores prompts, code, tool inputs, or Claude's responses. The hook ignores those fields.

### Your settings.json is safe

- A backup is saved to `~/.claude-status-light/backups/` before every change (the last 10 are kept).
- Install only **appends** its own entries. Your other hooks, settings, key order and formatting are left exactly as they were. Install followed by uninstall gives back a byte-identical file.
- Its entries are recognised by the helper path, and nothing else is touched.
- If `settings.json` can't be parsed, nothing is written. On uninstall the app offers to restore the latest backup.
- A symlinked `settings.json` (dotfiles) stays a symlink.

## Uninstall

1. Menu → **Uninstall Hooks…** (or `~/.claude-status-light/bin/csl-hook uninstall`)
2. Quit the app and delete `/Applications/Claude Status Light.app`
3. Optionally `rm -rf ~/.claude-status-light`

## Development

```bash
swift build                 # debug build of everything
swift test                  # state machine + settings.json merge tests
scripts/build-app.sh        # build/Claude Status Light.app (ad-hoc signed)
scripts/make-dmg.sh         # universal DMG; set SIGN_IDENTITY to sign for distribution
```

Layout:

- `Sources/StatusCore`: hook state machine (`HookReducer`), session model, order-preserving JSON, the settings.json installer. Foundation only.
- `Sources/csl-hook`: the helper Claude Code runs on each event, and the `install / uninstall / status` CLI.
- `Sources/ClaudeStatusLight`: the menu bar app (AppKit status item + menu, SwiftUI settings window loaded on demand).

For testing without touching your real setup, `CLAUDE_STATUS_LIGHT_DIR` and `CLAUDE_STATUS_LIGHT_SETTINGS` point the app and the helper at other locations.

### Signing and notarizing a release

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" VERSION=1.0.0 scripts/make-dmg.sh
xcrun notarytool submit build/ClaudeStatusLight-1.0.0.dmg --keychain-profile <profile> --wait
xcrun stapler staple build/ClaudeStatusLight-1.0.0.dmg
```

Without a Developer ID, the app is ad-hoc signed. That's fine for building it yourself. A downloaded unsigned build needs right-click → Open the first time.

## Not in v1

Usage / limit display, claude.ai web or the desktop chat (no hooks there), Windows / Linux, a floating "pill" window, or sending prompts to Claude.

## License

MIT
