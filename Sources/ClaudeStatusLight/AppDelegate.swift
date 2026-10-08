import AppKit
import ServiceManagement
import StatusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private var statusItem: StatusItemController!
    private var notifier: Notifier!
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        notifier = Notifier(store: store)
        statusItem = StatusItemController(store: store, app: self)

        store.onChange = { [weak self] in self?.statusItem.refresh() }
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

        keepHooksCurrent()
        notifier.requestAuthorization()
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
        } catch {
            showError("Couldn’t install hooks", error)
        }
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
