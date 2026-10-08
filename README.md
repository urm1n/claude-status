<p align="center">
  <img src="docs/images/app-icon.png" width="128" alt="Claude Status Light icon">
</p>

<h1 align="center">Claude Status Light</h1>

<p align="center">
  A tiny macOS menu bar light that shows what <b>Claude Code</b> is doing,<br>
  so you can stop checking the terminal.
</p>

<p align="center">
  <a href="https://github.com/urm1n/claude-status/releases/latest"><img src="https://img.shields.io/github/v/release/urm1n/claude-status?label=download" alt="Latest release"></a>
  <a href="https://github.com/urm1n/claude-status/actions/workflows/ci.yml"><img src="https://github.com/urm1n/claude-status/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/states-dark.png">
    <img src="docs/images/states-light.png" width="480" alt="Menu bar light: the flower mark for no session, green for ready, yellow for working, red when Claude needs you">
  </picture>
</p>

Start a long task in Claude Code, switch to something else, and glance at the menu bar:

- 🟢 **Green**: Claude is done and waiting for your next prompt
- 🟡 **Yellow**: Claude is working (the flower spins slowly)
- 🔴 **Red**: Claude needs you (a permission prompt, a question, a form)
- ✿ **Plain flower**: no Claude Code session is open

You also get a notification when Claude **finishes** or **needs you**. Click it to jump back to the right terminal or editor. Click the light to see your **usage limits**: the current session (5-hour) window and the weekly limit, the same numbers as `/usage`.

- **One-click setup.** No account, no API key, no config files to edit.
- **Light.** About 15–25 MB of memory, 0% CPU when idle, and an app of under 3 MB.
- **Private.** Offline unless you turn on usage fetching. It never stores your prompts, code or Claude's replies.
- **Works where Claude Code runs:** Terminal, iTerm, Ghostty, Warp, VS Code, Cursor, and the Claude desktop app's Code tab.
- **Several sessions at once.** The light shows the most urgent one, and the menu lists them all.

---

## Quick start

**You need:** a Mac on macOS 14 (Sonoma) or later, with [Claude Code](https://claude.com/claude-code) installed and logged in. Usage limits need a Claude Pro or Max plan.

1. **Download** [ClaudeStatusLight.dmg](https://github.com/urm1n/claude-status/releases/latest/download/ClaudeStatusLight.dmg), open it, and drag the app into **Applications**.
2. **Open it.** The first time, macOS blocks it; [here's the one-time fix](#first-launch-apple-could-not-verify).
3. **Click Install Hooks** when it asks to connect to Claude Code, and **Allow** notifications.
4. **Restart Claude Code** (any sessions that were already open).
5. **Use VS Code or Cursor?** Click the light → **Show Usage from Anthropic…** to see your usage limits there too.

That's it. The light turns green as soon as a Claude Code session starts. Optional: click the light → **Launch at Login**.

### First launch: "Apple could not verify…"

The app is free and open source but isn't notarized by Apple (that needs a paid developer account), so macOS asks you to confirm once.

**macOS 15 (Sequoia) and later**
1. Open the app, then click **Done** on the warning.
2. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to "Claude Status Light".
3. Confirm with your password. You won't be asked again.

**macOS 14 (Sonoma):** right-click the app in Applications → **Open** → **Open**.

**Or, on any version,** run this once in Terminal, then open the app normally:
```bash
xattr -dr com.apple.quarantine "/Applications/Claude Status Light.app"
```

### Or build it yourself

Needs the Xcode Command Line Tools (`xcode-select --install`). You won't see the warning above, because you built it.

```bash
git clone https://github.com/urm1n/claude-status.git
cd claude-status
./install.sh
```

## Using it

**Click the light** to see:

- **Usage limits**: session (5-hour) and weekly usage, with bars, percentages and reset times. Bars turn orange at 75% and red at 90%.
- **Every open session**, with its folder, its state, and how long it has been in that state. Click one to bring its terminal or editor to the front.
- Switches for **Notifications** and **Launch at Login**, plus **Settings…** and **Uninstall Hooks…**

### Notifications

| When | Sound (default) |
|---|---|
| Claude **finished** its turn ("Claude finished · my-project · 2m 13s") | Hero |
| Claude **needs you**: a permission prompt, a question ("Claude needs you · my-project: …") | Ping |
| A usage limit is **90% used** ("Session limit 90% used · 10% left · resets in 1h 12m") | Ping |

Each session has one notification slot. A new notification replaces the old one, and it clears itself once Claude gets back to work or you reply. Notification Center never fills up with stale alerts. The limit warning comes once per limit per period.

### Usage limits

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/usage-dark.png">
    <img src="docs/images/usage-light.png" width="312" alt="Usage panel: current session 24%, resets in 2h 14m; weekly limit 78%, resets Monday">
  </picture>
</p>

The numbers come from one of two places. The menu shows whichever is newer.

- **Terminal sessions (always on, offline).** Claude Code passes your usage to the app through its status line after every reply. If you already have a custom status line, it keeps showing exactly as before. If not, your terminal shows a short line like `Session 24% · resets 2h 13m   Week 41%`.
- **VS Code, Cursor and other editors (opt-in).** They don't run status lines, so turn on **Show Usage from Anthropic…** in the menu (or **Fetch usage from Anthropic** in Settings). It asks Anthropic for the same numbers `/usage` shows, using the login Claude Code already saved. No extra login, no prompts. It refreshes every 5 minutes while a session is open, and when you open the menu. It uses an endpoint Anthropic doesn't document, so it could stop working if they change it.

Want the number always visible? Turn on **Show session usage % next to the light** in Settings.

### Settings

| Setting | What it does |
|---|---|
| Colors | Your own color for ready / working / needs input |
| Different shape per state | Accessibility mode: ✓, •••, ! instead of colored flowers (see below) |
| Spin the light while Claude is working | On by default. Off automatically with Reduce Motion |
| Show the light when no session is running | Turn off to hide the plain flower when Claude isn't running |
| Notifications | Turn "finished" and "needs you" on or off, and pick a sound or silent for each |
| Only if Claude worked at least… | Skip "finished" for quick answers |
| Skip when that session's terminal is in front | No notification if you're already looking at it |
| Show session usage % next to the light | e.g. `23%` beside the flower. Off by default |
| Warn when a limit is 90% used | On by default |
| Fetch usage from Anthropic | Usage limits for VS Code and other editors. Off by default |
| Idle timeout | A "working" session with no activity for this long counts as ready (default 5 min) |
| Launch at login | Start with your Mac |

<details>
<summary>Accessibility mode (shapes as well as colors)</summary>
<br>
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/states-symbols-dark.png">
  <img src="docs/images/states-symbols-light.png" width="480" alt="Shape mode: flower mark, check mark, three dots, exclamation mark">
</picture>
</details>

## Updating

1. Download the [latest ClaudeStatusLight.dmg](https://github.com/urm1n/claude-status/releases/latest/download/ClaudeStatusLight.dmg).
2. Quit the app (click the light → **Quit**), then drag the new one into Applications and replace the old one.
3. Open it. If macOS blocks the new download, do the [first-launch step](#first-launch-apple-could-not-verify) once more. The app updates its hooks by itself and keeps your settings. Restart open Claude Code sessions to pick up any changes.

Built from source? Run `git pull && ./install.sh`. See what's new in the [changelog](CHANGELOG.md).

## Troubleshooting

<details>
<summary><b>The plain flower stays while Claude is running</b></summary>

- Click the light. If it says **Hooks not installed**, click **Install Hooks…**.
- Sessions only pick up the hooks when they start, so **restart Claude Code**.
- Check from Terminal: `~/.claude-status-light/bin/csl-hook status` should print `installed`.
</details>

<details>
<summary><b>I don't get notifications</b></summary>

- If macOS is blocking them, the menu shows **Notifications are off in macOS**. Click **Turn On Notifications…** and switch on **Allow notifications**.
- **Settings → Notifications → Send Test** shows whether they get through.
- A Focus mode (Do Not Disturb) hides banners.
- Check that **Notifications** is ticked in the menu, and the per-type switches in Settings.
</details>

<details>
<summary><b>I get two notifications for everything</b></summary>

Another tool has also hooked into Claude Code, for example a "notifier" script that uses `terminal-notifier`. Remove its entries from the `"hooks"` section of `~/.claude/settings.json`, or turn off notifications in one of the two tools.
</details>

<details>
<summary><b>Usage limits don't show</b></summary>

- They need a Pro or Max plan. API-key accounts have no usage limits.
- **Terminal:** they appear after Claude's first reply. Restart sessions that were open before you installed or updated the app.
- **VS Code / Cursor:** click the light → **Show Usage from Anthropic…**.
- *Couldn't read Claude Code's login*: run `claude` once in a terminal to log in, then click **Try Again**.
- *Login expired*: use Claude Code once and it renews the login.
</details>

<details>
<summary><b>The light stays yellow after I press Esc</b></summary>

It should turn green within a second. Sessions that were open before you installed or updated the app need a restart first. As a fallback it turns green after about a minute, or after the idle timeout in Settings.
</details>

<details>
<summary><b>I can't see the light at all</b></summary>

- On a MacBook with a notch, a crowded menu bar can hide icons behind the notch. Quit another menu bar app, or use a tool like Ice or Bartender.
- If you turned off **Show the light when no session is running**, it only appears while Claude runs. Open the app again from Applications to reach Settings.
</details>

<details>
<summary><b>My terminal shows a new status line</b></summary>

That's how terminal sessions pass usage limits to the app. If you'd rather not see it, uninstall the hooks (this also removes the status line) and reinstall later, or set your own `statusLine` in `~/.claude/settings.json`. The next time the app starts, it wraps yours and keeps showing it.
</details>

<details>
<summary><b>Does it slow Claude Code down?</b></summary>

No. Each hook takes about 10 ms, never blocks Claude, prints nothing, and always reports success, even if the app is quit or deleted.
</details>

## Privacy

- **No network access by default.** No analytics, no update checks, no accounts. The only request it can ever make is the opt-in usage fetch, to `api.anthropic.com`.
- With usage fetching on, Claude Code's saved login is read for each request and sent only to Anthropic. It's never stored, logged or refreshed by this app.
- It stores only what it needs for the light: session id, project folder, state, a short reason ("Permission needed: Bash"), timestamps, process ids, and your usage percentages.
- It never stores your prompts, code, tool inputs or Claude's replies.
- To notice when you press Esc, it reads the last few kilobytes of the active session's transcript and looks only for Claude Code's "interrupted" note. Nothing from it is kept.
- It changes `~/.claude/settings.json` only to add or remove its own hooks and status line. It backs the file up first and leaves everything else exactly as it was.

More detail in **[How it works](docs/how-it-works.md)**.

## Uninstall

1. Click the light → **Uninstall Hooks…** This removes its hooks and status line and restores your Claude settings exactly, including any status line you had before.
2. Quit the app and drag `/Applications/Claude Status Light.app` to the Trash.
3. Optional: delete `~/.claude-status-light`.

## Contributing

Bug reports, ideas and pull requests are welcome: see **[CONTRIBUTING.md](CONTRIBUTING.md)**. The original spec is in [docs/requirements.md](docs/requirements.md).

## License

[MIT](LICENSE). Not affiliated with Anthropic. "Claude" and "Claude Code" are Anthropic's names for their products.
