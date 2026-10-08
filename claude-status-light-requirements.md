# Claude Status Light: Requirements

A tiny, open source macOS menu bar app that shows one colored circle so you always know what Claude Code is doing, without looking at the terminal.

---

## 1. Goal

Show Claude Code's current state as a single light in the Mac menu bar, and send a notification when Claude finishes work or needs input. It should run silently in the background and use almost no RAM or CPU.

## 2. Core principles

- **Light:** minimal RAM, near-zero CPU when idle, no polling loops that wake the CPU constantly.
- **Zero setup logic:** no login, no API keys, no backend, no accounts. It only reads what Claude Code already does on the user's machine.
- **Local only:** no network calls, no analytics, no data leaves the Mac.
- **Open source:** MIT license, simple codebase, easy for others to read and contribute.
- **Menu bar only:** no Dock icon, no main window.

## 3. Platform and tech

- macOS 14+ (Sonoma and later). Apple Silicon and Intel.
- Native Swift (SwiftUI plus AppKit `NSStatusItem`). No Electron, no web runtime.
- Works with Claude Code (terminal, and IDE or desktop Code tab if hooks fire there).
- Uses the user's existing Claude Code install. No separate login needed.

## 4. The light (menu bar icon)

One filled circle in the menu bar. Colors:

| State | Color | When |
|---|---|---|
| No session | Gray or white | No Claude Code session is open |
| Ready | Green | A session is open and Claude is idle, waiting for the next prompt |
| Working | Yellow | Claude is running (thinking, using tools, subagents active) |
| Needs input | Red | Claude is blocked on the user (permission prompt, question, waiting for a decision) |
| Done | Green | Claude finished its turn, goes back to Ready |

Rules:
- Colors must be readable in both light and dark menu bars.
- Optional accessibility mode: different shapes or a small symbol per state, for color-blind users.
- Clicking the icon opens a small menu (see section 8).

## 5. State rules

The app derives state from Claude Code hook events.

| Event | Resulting state |
|---|---|
| `SessionStart` | Green |
| `UserPromptSubmit` | Yellow |
| `PreToolUse` / `PostToolUse` | Yellow (keeps it alive while working) |
| `Notification` (permission or waiting for input) | Red |
| `Stop` (turn finished) | Green, plus "done" notification |
| `SessionEnd` | Remove that session |

Note: confirm the exact current hook names and payloads in the Claude Code docs before building.

### Multiple sessions

- Track each session separately by `session_id`.
- The icon shows the highest priority state across all sessions:
  **Red > Yellow > Green > Gray**
- A session needing input is never hidden by another session that is working.
- The dropdown lists each session with its folder name and state.

### Edge cases

- **Interrupted runs (Esc):** `Stop` may not fire, so yellow could get stuck. Add a safety timeout: if a session has had no events for N minutes (default 5, configurable), treat it as Green.
- **Crashed or closed terminal:** if the session's process is gone, remove the session and update the light.
- **App started after Claude:** sessions already running are picked up on their next event.
- **App quits or crashes:** hooks must fail silently and never slow down or break Claude Code.

## 6. Notifications

Send a native macOS notification when:
1. **Work is done** (`Stop`): "Claude finished" plus the project folder name.
2. **Input is needed** (`Notification`): "Claude needs you" plus a short reason if available.

### Auto clear of old notifications

- Every notification from the app uses a fixed identifier per session, so a new one **replaces** the old one instead of stacking.
- When the state changes, remove stale delivered notifications from the app:
  - Claude goes back to Working: clear the "needs input" and "done" notifications for that session.
  - A new prompt is submitted: clear that session's old notifications.
  - Session ends: clear everything for that session.
- Use `UNUserNotificationCenter` remove delivered notifications by identifier or thread.
- Never leave a pile of old Claude notifications in Notification Center.

### Customization

- Toggle each notification type on or off (done, input needed).
- Choose sound per type, or silent.
- Optional: only notify if the terminal is not the frontmost app.
- Optional: minimum run time before sending a "done" notification (for example, skip it if Claude worked under 10 seconds).

## 7. How it gets data (no logic needed)

- On first launch, the app offers one click "Install hooks".
- It safely adds its hooks to `~/.claude/settings.json`:
  - Back up the file first.
  - Merge, never overwrite existing user hooks.
  - Only touch its own entries.
- The hooks are tiny scripts that write session state to a small file or folder, for example `~/.claude-status-light/sessions/<session_id>.json`.
- The app watches that location with a file system event watcher (FSEvents or `DispatchSource`), not a polling timer. This keeps CPU near zero.
- Hook scripts must be fast (a few milliseconds), have no heavy dependencies, and always exit 0.
- An "Uninstall hooks" option removes only the app's entries and restores the backup if needed.

Not needed for v1: reading usage or session limits, OAuth tokens, Keychain access, or any Anthropic API. This keeps the app simple and avoids permission prompts.

## 8. Menu bar dropdown

- List of active sessions with folder name, state color, and time in current state.
- Toggle: notifications on or off.
- Button: Install or Uninstall hooks.
- Button: Settings.
- Launch at login toggle.
- Quit.

## 9. Settings

- Colors for each state (with sensible defaults).
- Optional symbol or shape mode for accessibility.
- Notification toggles and sounds.
- Idle timeout for stuck sessions.
- Launch at login.
- Show or hide the gray light when no session is running.

## 10. Performance targets

- RAM: under 30 MB resident.
- CPU: about 0% when idle, under 1% while updating.
- No timers firing more often than needed; prefer event driven updates.
- App size: small download (a few MB).
- No background network activity.
- Minimal energy impact in Activity Monitor.

## 11. Privacy and security

- Reads only its own state files and, if needed, the Claude Code settings file to install hooks.
- Does not read prompts, code, or responses. Only state, session id, and folder name.
- Does not store credentials or tokens.
- No telemetry.

## 12. Distribution

- Open source on GitHub, MIT license.
- Download as a `.dmg` from Releases, and install via Homebrew cask.
- Code signed and notarized if possible, so users do not hit Gatekeeper warnings.
- Clear README with install steps, screenshots, and a "how it works" section.

## 13. Out of scope for v1

- Session or weekly usage limit display (no official API; can come later as an opt-in).
- Claude.ai web chat or the regular Claude desktop chat (no hooks available).
- Windows or Linux.
- Floating pill or Dynamic Island style window (possible v2 idea).
- Controlling or sending prompts to Claude.

## 14. Possible later ideas (v2)

- Floating pill that expands when Claude is working or needs input.
- Small animation while working.
- Usage limit bar as an optional feature.
- Click a session to focus its terminal window.
- Per-project names and colors.

## 15. Acceptance criteria

1. Install the app, click "Install hooks", and no other setup is needed.
2. With no Claude Code session open, the light is gray or white.
3. Opening a session turns the light green.
4. Submitting a prompt turns it yellow.
5. A permission prompt or question turns it red and sends a notification.
6. Answering it turns the light yellow again and clears the old notification.
7. When Claude finishes, the light goes green and a "done" notification is sent, replacing any older ones.
8. With multiple sessions, the light shows the highest priority state.
9. Closing all sessions returns the light to gray or white.
10. A stuck yellow light recovers after the timeout.
11. Resource use stays within the targets in section 10.
12. Uninstalling hooks leaves the user's Claude Code settings intact.
