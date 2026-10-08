# How it works

Claude Status Light has three parts:

```
┌────────────┐  hook event (JSON on stdin)   ┌──────────┐  writes   ┌─────────────────────────────────────────┐
│ Claude Code│ ────────────────────────────▶ │ csl-hook │ ────────▶ │ ~/.claude-status-light/sessions/<id>.json│
└────────────┘                               └──────────┘           └─────────────────────────────────────────┘
                                                                                   │ file system event
                                                                                   ▼
                                                                         ┌──────────────────┐
                                                                         │  menu bar app    │ ─▶ light + notifications
                                                                         └──────────────────┘
```

1. **Hooks.** Clicking *Install Hooks* adds one entry per event to `~/.claude/settings.json`. Each entry runs `~/.claude-status-light/bin/csl-hook`.
2. **`csl-hook`.** A small native helper (no shell scripts, no `jq`, no Node). For each event it reads the JSON payload, updates one small file for that session, and exits. It takes about 10 ms, prints nothing, and always exits 0, so it can't block, slow down or break Claude Code.
3. **The app.** It watches the sessions folder with a kernel file-system watcher, and each session's Claude process with a process-exit watcher. Nothing polls. The only timer is a one-shot timer, armed only while a session is "working", that handles stuck sessions.

## Events → light

| Claude Code hook event | Light |
|---|---|
| `SessionStart` | 🟢 ready |
| `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `ElicitationResult` | 🟡 working |
| `PermissionRequest`, `Elicitation`, `PreToolUse` for `AskUserQuestion`, `Notification` (`permission_prompt`, `elicitation_dialog`, `agent_needs_input`) | 🔴 needs you + notification |
| `Notification` (`idle_prompt`) while working | 🟢 ready (recovers from Esc) |
| `Stop`, `StopFailure` | 🟢 ready + "finished" notification |
| `SessionEnd`, or the Claude process exits | session removed |

With several sessions, the light shows the highest priority: **red > yellow > green > the flower mark (no session)**.

The state machine lives in [`Sources/StatusCore/HookReducer.swift`](../Sources/StatusCore/HookReducer.swift) and is covered by unit tests.

## Edge cases

| Situation | What happens |
|---|---|
| You press **Esc** mid-turn, or at a permission prompt (no hook fires) | While a session is yellow or red, the app watches its transcript (`transcript_path` from the hooks). After each write it reads the last 64 KB and checks whether the last conversation entry is Claude Code's `[Request interrupted by user…]` note, newer than the current turn. If so, it turns green within a second. Fallbacks: `idle_prompt` after ~60 s, then the idle timeout. |
| Terminal closed, Claude crashed | The app watches the Claude process and removes the session the moment it exits. |
| A **background subagent** keeps working while the main agent waits for permission | Stays red. Only the blocked agent's own activity, or the pending tool call finishing, clears it. |
| Parallel tool calls finish while a permission prompt is open | Stays red. Only the pending tool call clears it. |
| Auto-compaction mid-turn (`SessionStart` with `source: compact`) | Stays yellow. |
| Two sessions in the same folder | Tracked separately by `session_id`. |
| The app starts after Claude | Existing sessions load from disk or appear on their next event. |
| The app is quit or deleted | Hooks still exit instantly and quietly (`... || true`). |

## Usage limits

Two sources, and the menu shows whichever is newer:

1. **Status line (always on, offline).** Installing also sets Claude Code's `statusLine` to `csl-hook statusline`. After each reply Claude Code passes it JSON with `rate_limits.five_hour` and `rate_limits.seven_day` (`used_percentage`, `resets_at`) on Pro/Max plans. The helper saves that to `~/.claude-status-light/usage/statusline.json`. If you already had a status line, it's saved to `~/.claude-status-light/statusline-chain.json` and run with the same input, so your terminal looks exactly as before. Uninstall puts it back. The status line only runs in terminal sessions, not in the VS Code extension.
2. **Fetch from Anthropic (opt-in).** `GET https://api.anthropic.com/api/oauth/usage`, the endpoint behind `/usage`, authorized with the OAuth token Claude Code keeps in the Keychain item `Claude Code-credentials`. It's read with `/usr/bin/security find-generic-password`, exactly as Claude Code reads it. That tool is the only app on the item's access list, so macOS doesn't prompt, and it keeps working after app updates and Claude Code's token refreshes. The token is read per request and never stored, logged or refreshed: refreshing would rotate Claude Code's own login. It runs when you open the menu (at most once a minute), and every 5 minutes while a session is open.

## Notifications

- Every notification for a session uses the same identifier, `csl.session.<id>`, so a new one **replaces** the previous one.
- They're removed when the session goes back to working, when a new prompt is sent, or when the session ends.
- "Needs you" waits 0.4 s before posting. That way it shows Claude's own wording ("Claude needs your permission to use Bash"), and prompts that resolve instantly never notify.
- Clicking a notification brings the session's host app to the front. The hook records which app that is by walking up the process tree: Terminal, iTerm, Ghostty, VS Code, Cursor, the Claude desktop app, and so on.

## Files

| Path | What |
|---|---|
| `~/.claude-status-light/bin/csl-hook` | The helper the hooks run. The app keeps it in sync with its own copy, so moving or updating the app never breaks hooks. |
| `~/.claude-status-light/sessions/*.json` | One small file per open session |
| `~/.claude-status-light/backups/` | `settings.json` backups, the last 10 |
| `~/.claude-status-light/usage/statusline.json` | Latest usage from the status line (percentages and reset times only) |
| `~/.claude-status-light/statusline-chain.json` | Your own status line, if you had one, while the app wraps it |
| `~/Library/Preferences/com.claudestatuslight.app.plist` | App settings |

A session file looks like this. There are no prompts, code or replies in it:

```json
{
  "sessionId": "6f1c…",
  "projectDir": "/Users/you/code/my-app",
  "state": "needsInput",
  "reason": "Claude needs your permission to use Bash",
  "lastEvent": "Notification",
  "stateSince": 1791480435.4,
  "updatedAt": 1791480435.6,
  "claudePid": 39950,
  "appPid": 38779
}
```

## How settings.json is edited

- **Backup first**, every time, into `~/.claude-status-light/backups/`.
- **Append only.** Its own entries go at the end of each event's list, and other hooks are left in place.
- **Formatting kept.** An order-preserving JSON parser ([`JSONValue.swift`](../Sources/StatusCore/JSONValue.swift)) keeps your keys, their order, number spelling and layout. Installing and then uninstalling gives back a byte-identical file.
- **Own entries only.** They're recognised by the helper path in the command, and nothing else is touched.
- **Safe failure.** If the file isn't valid JSON, nothing is written. On uninstall, the app offers to restore the latest backup.
- **Symlinks kept.** A symlinked `settings.json` (dotfiles setups) stays a symlink.

It also sets `"statusLine": {"type": "command", "command": "\"$HOME/.claude-status-light/bin/csl-hook\" statusline 2>/dev/null"}`, keeping your status line's other options such as `padding`.

The hook entry it adds, once per event:

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "\"$HOME/.claude-status-light/bin/csl-hook\" 2>/dev/null || true",
      "timeout": 5
    }
  ]
}
```

## Command line

The helper also works as a small CLI:

```bash
~/.claude-status-light/bin/csl-hook status      # installed / not installed / outdated
~/.claude-status-light/bin/csl-hook install     # same as the menu item
~/.claude-status-light/bin/csl-hook uninstall
```
