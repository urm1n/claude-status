import AppKit
import StatusCore

/// The menu bar light and its dropdown. The menu is rebuilt each time it opens, so nothing
/// ticks in the background just to keep "time in state" fresh.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: SessionStore
    private let notifier: Notifier
    private let usage: UsageStore
    private unowned let app: AppDelegate
    private var lastRendered: RenderKey?
    private var menuIsOpen = false
    private let animation = WorkingAnimation()

    private struct RenderKey: Equatable {
        let state: SessionState?
        let symbols: Bool
        let colors: [String]
        let spinning: Bool
        let percent: String
    }

    init(store: SessionStore, notifier: Notifier, usage: UsageStore, app: AppDelegate) {
        self.store = store
        self.notifier = notifier
        self.usage = usage
        self.app = app
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.behavior = []
        refresh()
    }

    func refresh() {
        let state = store.aggregateState
        // NSStatusItem persists visibility in UserDefaults; only write it when it actually changes.
        let visible = state != nil || Pref.defaults.bool(forKey: Pref.showWhenIdle)
        if statusItem.isVisible != visible { statusItem.isVisible = visible }

        let percent = Pref.defaults.bool(forKey: Pref.showUsagePercent) ? usage.sessionPercent.map { "\($0)%" } ?? "" : ""
        let key = RenderKey(state: state, symbols: Pref.defaults.bool(forKey: Pref.symbolMode),
                            colors: SessionState.allCases.map { Pref.color(for: $0).hexString },
                            spinning: state == .working && WorkingAnimation.isAllowed,
                            percent: percent)
        guard key != lastRendered, let button = statusItem.button else { return }
        let previous = lastRendered
        lastRendered = key

        if percent.isEmpty {
            statusItem.length = NSStatusItem.squareLength
            button.title = ""
            button.imagePosition = .imageOnly
        } else {
            statusItem.length = NSStatusItem.variableLength
            // Monospaced digits so the item doesn't jiggle as the number changes.
            button.attributedTitle = NSAttributedString(string: percent, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small) + 1, weight: .medium),
                .baselineOffset: 0.5,
            ])
            button.imagePosition = .imageLeading
        }

        let image = IconRenderer.statusImage(for: state)
        if key.spinning {
            // Keep an invisible image so the item keeps its size and accessibility label.
            let placeholder = NSImage(size: image.size)
            placeholder.accessibilityDescription = image.accessibilityDescription
            button.image = placeholder
            // Only the number changed: keep the spin going instead of restarting it.
            let sameLayout = previous?.spinning == true && previous?.colors == key.colors
                && previous?.percent.isEmpty == key.percent.isEmpty && previous?.symbols == key.symbols
            if !(sameLayout && animation.isRunning) {
                animation.start(on: button, color: Pref.color(for: .working), leading: !percent.isEmpty)
            }
        } else {
            animation.stop()
            button.image = image
        }
        button.toolTip = tooltip()
    }

    private func tooltip() -> String {
        let sessions = store.sortedSessions
        if sessions.isEmpty { return "Claude Status Light: no Claude Code sessions" }
        return sessions.map { "\($0.record.folderName): \($0.state.label)" }.joined(separator: "\n")
    }

    /// Rebuilds the menu if it's open, e.g. after the user allowed notifications in System Settings.
    func permissionChanged() {
        if menuIsOpen, let menu = statusItem.menu { menuNeedsUpdate(menu) }
    }

    /// New usage numbers arrived (status line or fetch): update the open menu in place.
    func usageChanged() {
        refresh() // the % next to the light
        if menuIsOpen, let menu = statusItem.menu { menuNeedsUpdate(menu) }
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        notifier.refreshPermission()
        usage.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hookStatus = HooksInstaller.status()

        if hookStatus != .installed {
            let warning = NSMenuItem(title: "Hooks not installed: the light can’t see Claude",
                                     action: nil, keyEquivalent: "")
            warning.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(item("Install Hooks…", #selector(installHooks)))
            menu.addItem(.separator())
        }

        let wantsNotifications = Pref.defaults.bool(forKey: Pref.notificationsEnabled)
        if wantsNotifications, notifier.permission == .denied || notifier.permission == .notDetermined {
            let warning = NSMenuItem(title: "Notifications are off in macOS", action: nil, keyEquivalent: "")
            warning.image = NSImage(systemSymbolName: "bell.slash.fill", accessibilityDescription: nil)
            warning.isEnabled = false
            menu.addItem(warning)
            menu.addItem(item("Turn On Notifications…", #selector(turnOnNotifications)))
            menu.addItem(.separator())
        }

        addUsageSection(to: menu)

        let sessions = store.sortedSessions
        if sessions.isEmpty {
            let empty = NSMenuItem(title: "No active Claude Code sessions", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: sessions.count == 1 ? "1 session" : "\(sessions.count) sessions",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for session in sessions { menu.addItem(sessionItem(session.record, state: session.state)) }
        }

        menu.addItem(.separator())
        let notifications = item("Notifications", #selector(toggleNotifications))
        notifications.state = Pref.defaults.bool(forKey: Pref.notificationsEnabled) ? .on : .off
        menu.addItem(notifications)
        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        if hookStatus == .installed {
            menu.addItem(item("Uninstall Hooks…", #selector(uninstallHooks)))
        }
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item("Quit Claude Status Light", #selector(quit), key: "q"))
    }

    private func addUsageSection(to menu: NSMenu) {
        if let snapshot = usage.current {
            let usageItem = NSMenuItem()
            usageItem.view = UsageMenuView(snapshot: snapshot)
            menu.addItem(usageItem)
            if usage.fetchEnabled, let error = usage.fetchError, snapshot.source == .statusLine {
                menu.addItem(note("Couldn’t refresh from Anthropic: \(error.message)"))
                if error == .loginExpired { menu.addItem(item("Renew Login (one tiny Claude request)", #selector(renewLogin))) }
            }
        } else if usage.fetchEnabled {
            if let error = usage.fetchError {
                menu.addItem(note("Usage unavailable: \(error.message)"))
                menu.addItem(error == .loginExpired
                    ? item("Renew Login (one tiny Claude request)", #selector(renewLogin))
                    : item("Try Again", #selector(retryUsage)))
            } else {
                menu.addItem(note("Loading usage…"))
            }
        } else {
            menu.addItem(note("Usage limits appear after Claude replies in a terminal session"))
            menu.addItem(item("Show Usage from Anthropic…", #selector(enableUsage)))
        }
        menu.addItem(.separator())
    }

    private func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: text, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        item.isEnabled = false
        return item
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func sessionItem(_ record: SessionRecord, state: SessionState) -> NSMenuItem {
        let item = NSMenuItem(title: record.folderName, action: #selector(focusSession(_:)), keyEquivalent: "")
        item.target = self
        item.image = IconRenderer.dot(for: state)
        item.representedObject = record.appPid.map { NSNumber(value: $0) }
        item.toolTip = record.projectDir

        var detail = "\(state.label) · \(Format.elapsed(since: record.stateSince))"
        if state == .ready, record.state == .working { detail = "Ready (no activity) · \(Format.elapsed(since: record.updatedAt))" }
        if state == .ready, let outcome = record.outcome, outcome.hasPrefix("error:") {
            detail += " · stopped: " + outcome.dropFirst("error:".count).replacingOccurrences(of: "_", with: " ")
        }
        let title = NSMutableAttributedString(string: record.folderName,
                                              attributes: [.font: NSFont.menuFont(ofSize: 0)])
        title.append(NSAttributedString(string: "   " + detail, attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        if state == .needsInput, let reason = record.reason {
            title.append(NSAttributedString(string: "\n" + reason, attributes: [
                .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        item.attributedTitle = title
        return item
    }

    // MARK: Actions

    @objc private func focusSession(_ sender: NSMenuItem) {
        AppFocus.activate(pid: (sender.representedObject as? NSNumber)?.int32Value)
    }

    @objc private func toggleNotifications() {
        let enable = !Pref.defaults.bool(forKey: Pref.notificationsEnabled)
        Pref.defaults.set(enable, forKey: Pref.notificationsEnabled)
        if enable { app.ensureNotificationPermission() }
    }

    @objc private func turnOnNotifications() { app.turnOnNotifications() }
    @objc private func enableUsage() { app.enableUsageFetching() }
    @objc private func retryUsage() { usage.refresh(force: true) }
    @objc private func renewLogin() { usage.renewLogin() }

    @objc private func toggleLaunchAtLogin() { app.setLaunchAtLogin(!LoginItem.isEnabled) }
    @objc private func installHooks() { app.installHooks() }
    @objc private func uninstallHooks() { app.uninstallHooks() }
    @objc private func openSettings() { app.openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
