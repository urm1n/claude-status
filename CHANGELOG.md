# Changelog

## Unreleased

- The usage panel shows the clock time a limit resets as well as the countdown: "Resets in 4h 22m · at 2:34 PM". The 90% warning does too.

## 1.1.0 (2026-10-09)

- **Limit warning**: one notification when the session or weekly limit reaches 90% used, with time to reset. On by default (Settings → Usage limits).
- **Usage % next to the light** (optional, off by default): shows current session usage beside the flower. It drops to 0% on its own when the window resets.
- **Distinct sounds by default**: "Hero" when Claude finishes, "Ping" when it needs you. Change them in Settings → Notifications.
- **Pressing Esc turns the light green right away.** No hook fires when you stop Claude, so the app watches the session transcript for Claude Code's interrupt note. This also covers pressing Esc at a permission prompt. Before, the light stayed yellow for up to a minute.
- **The flower spins slowly (clockwise) while Claude is working.** It's a Core Animation layer, so it costs no CPU. It's off with Reduce Motion or shape mode, and there's a toggle in Settings.
- **New icon**: an orange flower mark. The app icon uses it, and so does the menu bar light: a flower in green, yellow or red instead of a circle, and a plain flower when no session is open.

- **Usage limits in the menu**: current session (5-hour) and weekly usage, with bars, percentages and reset times, like `/usage`.
  - Terminal sessions: read from Claude Code's status line, offline. Your existing status line is wrapped and keeps working, and it's restored on uninstall.
  - VS Code and other editors: opt-in **Fetch usage from Anthropic**, using Claude Code's saved login. It's read the same way Claude Code reads it, so there are no Keychain prompts.
- Reinstalling or upgrading hooks updates them in place instead of moving them to the end of `settings.json`.

- Notifications no longer silently stay off. The app asks for permission after setup, so the macOS prompt isn't hidden behind the setup dialog.
- If macOS blocks notifications, the menu shows **Notifications are off in macOS → Turn On Notifications…**, which opens the app's own page in System Settings.
- Settings shows the macOS permission state, with **Allow…**, **Turn On…** or **Send Test** buttons.

## 1.0.0 (2026-10-08)

First release.

- Menu bar light: gray (no session), green (ready), yellow (working), red (needs you). The most urgent session wins.
- Session list in the menu with folder, state and time in state. Click a session to focus its terminal or editor.
- "Finished" and "needs you" notifications, with one slot per session that replaces and clears itself.
- Settings: colors, accessibility shapes, sounds, minimum turn length, skip when the terminal is in front, idle timeout, launch at login.
- One-click hook install that backs up `settings.json`, only adds its own entries, and restores the file exactly on uninstall.
- Recovers from Esc interrupts, closed terminals and crashes. Background subagents never hide a pending permission prompt.
- About 13 MB of memory, 0% CPU when idle, and no network access.
