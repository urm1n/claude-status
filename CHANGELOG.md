# Changelog

## Unreleased

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
