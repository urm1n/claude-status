import AppKit
import ServiceManagement
import StatusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    let usage = UsageStore()
    private var statusItem: StatusItemController!
    private(set) var notifier: Notifier!
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        notifier = Notifier(store: store)
        statusItem = StatusItemController(store: store, notifier: notifier, usage: usage, app: self)
        notifier.onPermissionChange = { [weak self] permission in
            self?.statusItem.permissionChanged()
            SettingsWindowController.shared.model.notificationPermission = permission
        }

        store.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem.refresh()
            self.usage.setActive(!self.store.records.isEmpty)
        }
        usage.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem.usageChanged()
            self.notifier.checkLimits(self.usage.current)
        }
        usage.start()
        store.onEvent = { [weak self] event in self?.notifier.handle(event) }
        store.start()

        // AppKit writes its own keys to UserDefaults too; react only when one of ours changed.
        var lastPrefs = Pref.lightSignature
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let prefs = Pref.lightSignature
                guard prefs != lastPrefs else { return }
                lastPrefs = prefs
                self?.store.scheduleTimeout()
                self?.statusItem.refresh()
            }
        }

        // Reduce Motion turned on/off in System Settings: start or stop the spin.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.statusItem.refresh() }
        }

        keepHooksCurrent()
        notifier.refreshPermission { [weak self] permission in
            // Already set up but never asked (e.g. installed from the CLI): ask now.
            if permission == .notDetermined, HooksInstaller.status() == .installed {
                self?.notifier.requestPermission()
            }
        }
        offerHookInstallOnFirstLaunch()
    }

    /// Opening the app again (Finder, Spotlight) shows Settings. This is also the way back in
    /// when the light is hidden while no session is running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Hooks

    private var helperSource: URL? { Bundle.main.url(forAuxiliaryExecutable: "csl-hook") }

    /// Keeps the helper copy in sync with this app version and refreshes outdated hook entries.
    private func keepHooksCurrent() {
        let status = HooksInstaller.status()
        guard status == .installed || status == .outdated, let helperSource else { return }
        _ = try? HelperInstaller.sync(from: helperSource)
        if status == .outdated { try? HooksInstaller.install() }
    }

    private func offerHookInstallOnFirstLaunch() {
        guard !Pref.defaults.bool(forKey: Pref.didOfferHookInstall),
              HooksInstaller.status() != .installed else { return }

        let alert = NSAlert()
        alert.messageText = "Connect Claude Status Light to Claude Code?"
        alert.informativeText = """
        This adds a small hook to ~/.claude/settings.json so the light can tell when Claude is working, \
        waiting for you, or done.

        Your other settings and hooks are kept as they are, and a backup is saved first. Nothing leaves your Mac.
        """
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        let response = alert.runModal()
        Pref.defaults.set(true, forKey: Pref.didOfferHookInstall)
        if response == .alertFirstButtonReturn { installHooks() }
    }

    func installHooks() {
        do {
            guard let helperSource else {
                throw CocoaError(.fileNoSuchFile, userInfo: [
                    NSLocalizedDescriptionKey: "The csl-hook helper is missing from the app bundle. Rebuild the app.",
                ])
            }
            try HelperInstaller.sync(from: helperSource)
            try HooksInstaller.install()
            statusItem.refresh()
            SettingsWindowController.shared.model.refresh()
            showInfo("Hooks installed",
                     "Start a new Claude Code session (or restart open ones) and it will show up in the light.")
            // Ask only after the setup dialog is gone, so the macOS prompt isn't missed behind it.
            ensureNotificationPermission()
        } catch {
            showError("Couldn’t install hooks", error)
        }
    }

    // MARK: Notification permission

    /// Never asked: show the macOS prompt. Turned off: offer to open System Settings.
    func ensureNotificationPermission() {
        notifier.refreshPermission { [weak self] permission in
            switch permission {
            case .notDetermined: self?.notifier.requestPermission()
            case .denied: self?.offerNotificationSettings()
            case .allowed, .unknown: break
            }
        }
    }

    /// The "Turn On" buttons: prompt if macOS still can, otherwise go straight to System Settings.
    func turnOnNotifications() {
        Pref.defaults.set(true, forKey: Pref.notificationsEnabled)
        notifier.refreshPermission { [weak self] permission in
            switch permission {
            case .notDetermined: self?.notifier.requestPermission()
            case .denied: Notifier.openSystemSettings()
            case .allowed: self?.notifier.sendTest()
            case .unknown: break
            }
        }
    }

    private func offerNotificationSettings() {
        let alert = NSAlert()
        alert.messageText = "Notifications are turned off"
        alert.informativeText = """
        macOS is blocking notifications from Claude Status Light, so you won’t be told when Claude \
        finishes or needs you.

        Turn on “Allow notifications” in System Settings → Notifications → Claude Status Light.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { Notifier.openSystemSettings() }
    }

    func uninstallHooks() {
        do {
            try HooksInstaller.uninstall()
            HelperInstaller.remove()
            store.removeAll() // emits .ended for each session, which clears its notifications
            SettingsWindowController.shared.model.refresh()
        } catch HooksInstaller.InstallError.unreadable(let detail) {
            offerRestore(detail)
        } catch {
            showError("Couldn’t uninstall hooks", error)
        }
    }

    private func offerRestore(_ detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "settings.json can’t be read"
        alert.informativeText = "\(detail)\n\nRestore the most recent backup made by Claude Status Light?"
        alert.addButton(withTitle: "Restore Backup")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if try HooksInstaller.restoreLatestBackup() == nil {
                showInfo("No backup found", "There is no backup in \(Paths.backupsDir.path).")
            } else {
                uninstallHooks()
            }
        } catch {
            showError("Couldn’t restore the backup", error)
        }
    }

    // MARK: Usage

    /// Explains what turning on usage fetching does before doing it (Keychain prompt, network).
    func enableUsageFetching() {
        let alert = NSAlert()
        alert.messageText = "Show usage from Anthropic?"
        alert.informativeText = """
        Claude Status Light will read the same numbers as Claude Code’s /usage command, using the login \
        Claude Code already saved on this Mac. macOS will ask once to allow access to “Claude Code-credentials” \
        in your Keychain: choose Always Allow.

        The login is only sent to Anthropic, never stored or shared. You can turn this off in Settings.
        """
        alert.addButton(withTitle: "Turn On")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Pref.defaults.set(true, forKey: Pref.fetchUsage)
        usage.settingChanged()
    }

    // MARK: Other actions

    func openSettings() {
        SettingsWindowController.shared.show(app: self)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
        } catch {
            showError("Couldn’t change Launch at Login",
                      error, hint: "Move the app to /Applications and try again.")
        }
        SettingsWindowController.shared.model.refresh()
    }

    private func showInfo(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate()
        alert.runModal()
    }

    private func showError(_ title: String, _ error: Error, hint: String? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = [error.localizedDescription, hint].compactMap { $0 }.joined(separator: "\n\n")
        NSApp.activate()
        alert.runModal()
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
