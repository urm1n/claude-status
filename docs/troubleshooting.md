# Troubleshooting

- [`./install.sh` fails](#installsh-fails)
- ["Apple could not verify…" on first launch](#apple-could-not-verify-on-first-launch)
- [The light doesn't change while Claude is running](#the-light-doesnt-change-while-claude-is-running)
- [No notifications](#no-notifications)
- [Two notifications for everything](#two-notifications-for-everything)
- [Usage limits don't show](#usage-limits-dont-show)
- [The light stays yellow after pressing Esc](#the-light-stays-yellow-after-pressing-esc)
- [I can't see the light](#i-cant-see-the-light)
- [My terminal shows a new status line](#my-terminal-shows-a-new-status-line)
- [Does it slow Claude Code down?](#does-it-slow-claude-code-down)

## `./install.sh` fails

- **"Building needs Apple's Xcode Command Line Tools" or "git: command not found":** building needs those tools. Download the app instead (Option 2 in the README), or install the tools with `xcode-select --install` and run `./install.sh` again.
- **"You have not agreed to the Xcode license":** run `sudo xcodebuild -license accept`, then run `./install.sh` again.
- **Something else:** download the app instead (Option 2 in the README), or [open an issue](https://github.com/urm1n/claude-status/issues/new/choose) with the error.

## "Apple could not verify…" on first launch

The app is free and open source but not notarized by Apple, so macOS asks you to confirm it once.

- **macOS 15 or later:** open the app and click **Done** on the warning. Then open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to "Claude Status Light", and confirm with your password.
- **macOS 14:** right-click the app in Applications, choose **Open**, then **Open** again.
- **Any version:** run this once in Terminal, then open the app normally:

  ```bash
  xattr -dr com.apple.quarantine "/Applications/Claude Status Light.app"
  ```

## The light doesn't change while Claude is running

- Click the light. If it says **Hooks not installed**, choose **Install Hooks…**
- Restart Claude Code. Sessions only pick up hooks when they start.
- Check in Terminal: `~/.claude-status-light/bin/csl-hook status` should print `installed`.

## No notifications

- If macOS is blocking them, the menu shows **Notifications are off in macOS**. Choose **Turn On Notifications…** and switch on **Allow notifications**.
- Use **Settings → Notifications → Send Test** to check.
- A Focus mode, such as Do Not Disturb, hides banners.
- Make sure **Notifications** is checked in the menu, and check the per-type switches in Settings.

## Two notifications for everything

Another tool also hooks into Claude Code, for example a notifier script that uses `terminal-notifier`. Remove its entries from the `"hooks"` section of `~/.claude/settings.json`, or turn off notifications in one of the two tools.

## Usage limits don't show

- Usage limits need a Pro or Max plan. API-key accounts don't have them.
- **Terminal:** they appear after Claude's first reply. Restart sessions that were open before you installed or updated the app.
- **VS Code or Cursor:** click the light and choose **Show Usage from Anthropic…**
- **"Couldn't read Claude Code's login":** run `claude` once in a terminal to log in, then choose **Try Again**.
- **"Login expired":** use Claude Code once and it renews the login.

## The light stays yellow after pressing Esc

It should turn green within a second. Sessions that were open before you installed or updated the app need a restart first. As a fallback, it turns green after about a minute, or after the idle timeout in Settings.

## I can't see the light

- On a MacBook with a notch, a crowded menu bar can hide icons behind the notch. Quit another menu bar app, or use a menu bar manager such as Ice or Bartender.
- If you turned off **Show the light when no session is running**, it only appears while Claude runs. Open the app again from Applications to reach Settings.

## My terminal shows a new status line

That's how terminal sessions pass usage limits to the app. To remove it, choose **Uninstall Hooks…**, which also removes the status line. If you set your own `statusLine` in `~/.claude/settings.json`, the app wraps it the next time it starts, so your own status line shows instead.

## Does it slow Claude Code down?

No. Each hook takes about 10 ms, never blocks Claude, prints nothing, and always succeeds, even if the app is quit or deleted.

---

Still stuck? [Open an issue](https://github.com/urm1n/claude-status/issues/new/choose) and include the output of `~/.claude-status-light/bin/csl-hook status`.
