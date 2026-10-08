<p align="center">
  <img src="docs/images/app-icon.png" width="112" alt="">
</p>

<h1 align="center">Claude Status Light</h1>

<p align="center">
  A menu bar light for Claude Code.<br>
  See when Claude is working, finished, or waiting for you, without checking the terminal.
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
    <img src="docs/images/states-light.png" width="480" alt="The menu bar light in each state: no session, ready, working, needs you">
  </picture>
</p>

## Install

Requires macOS 14 or later and [Claude Code](https://claude.com/claude-code).

### Option 1: Build it yourself

> [!NOTE]
> This needs Apple's Xcode Command Line Tools. If you don't have them, use [Option 2](#option-2-download-the-app) instead.
> Not sure? Run `xcode-select -p` in Terminal. If it prints a folder path, you have them.

The app is built on your own Mac, so there's no Apple security warning.

1. Build and install the app. This takes a minute or two.

   ```bash
   git clone https://github.com/urm1n/claude-status.git
   cd claude-status
   ./install.sh
   ```

2. When the app opens, click **Install Hooks** and allow notifications.
3. Restart Claude Code.

### Option 2: Download the app

No developer tools needed.

1. Download **[ClaudeStatusLight.dmg](https://github.com/urm1n/claude-status/releases/latest/download/ClaudeStatusLight.dmg)** and drag the app into **Applications**.
2. Open the app, click **Install Hooks**, and allow notifications.
3. Restart Claude Code.

> [!NOTE]
> **macOS says "Apple could not verify…"?** The app is free and not notarized, so macOS asks you to confirm once.
> Open **System Settings → Privacy & Security** and click **Open Anyway**. On macOS 14, right-click the app and choose **Open**.

## What the light means

| Light | Meaning |
|---|---|
| 🟢 Green | Claude finished and is waiting for your next prompt |
| 🟡 Yellow, spinning | Claude is working |
| 🔴 Red | Claude needs you: a permission prompt or a question |
| ✿ Plain flower | No Claude Code session is open |

Click the light to see your sessions and usage limits. You also get a notification when Claude finishes or needs you.

## Features

- **Multiple sessions.** The light shows the most urgent one, and the menu lists them all.
- **Notifications that clean up.** One per session, replaced and cleared automatically.
- **Usage limits.** Session and weekly usage with reset times, plus a warning at 90%.
- **Works wherever Claude Code runs:** Terminal, iTerm, Ghostty, Warp, VS Code, Cursor, and the Claude desktop app.
- **Light and private.** About 20 MB of memory, 0% CPU when idle, and offline by default.
- **Customizable.** Colors, sounds, accessibility shapes, and launch at login.

> [!TIP]
> **Using VS Code or Cursor?** To see usage limits there, click the light and choose **Show Usage from Anthropic…**

## Documentation

- [User guide](docs/guide.md): the menu, notifications, usage limits, and settings
- [Troubleshooting](docs/troubleshooting.md): fixes for common problems
- [How it works](docs/how-it-works.md): hooks, privacy, and what is stored
- [Contributing](CONTRIBUTING.md): building, testing, and development

## Update

- **Built it yourself:** in the `claude-status` folder, run `git pull && ./install.sh`.
- **Downloaded the app:** download the [latest release](https://github.com/urm1n/claude-status/releases/latest) and replace the app in Applications.

Your settings are kept.

## Uninstall

Click the light, choose **Uninstall Hooks…**, then move the app to the Trash. Your Claude Code settings are restored exactly as they were.

## Privacy

No analytics, no accounts, and no network access unless you turn on usage fetching, which only contacts Anthropic. Your prompts, code, and Claude's replies are never stored. [Details](docs/how-it-works.md#privacy)

## License

[MIT](LICENSE). Not affiliated with Anthropic.
