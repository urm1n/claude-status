import AppKit
import StatusCore
import UserNotifications

/// Native notifications with one fixed identifier per session, so a new notification
/// replaces the previous one and stale ones are removed as soon as the session moves on.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// nil when running outside an app bundle (e.g. `swift run`), where the API is unavailable.
    private let center: UNUserNotificationCenter?
    private weak var store: SessionStore?

    /// Used for "only notify when the terminal is not frontmost" when the hosting app is unknown.
    private static let terminalBundleIds: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.github.wez.wezterm", "net.kovidgoyal.kitty", "org.alacritty", "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "com.anthropic.claudefordesktop",
    ]

    init(store: SessionStore) {
        self.store = store
        center = Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
        super.init()
        center?.delegate = self
    }

    // MARK: Permission

    enum Permission {
        case unknown, notDetermined, allowed, denied

        var label: String {
            switch self {
            case .unknown: return "Checking…"
            case .notDetermined: return "Not asked yet"
            case .allowed: return "Allowed"
            case .denied: return "Off"
            }
        }
    }

    /// Last known macOS permission; refreshed at launch, when the menu or Settings open, and after asking.
    private(set) var permission: Permission = .unknown
    var onPermissionChange: ((Permission) -> Void)?

    func refreshPermission(then done: ((Permission) -> Void)? = nil) {
        guard let center else { return }
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let alerts = settings.alertSetting
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.update(Self.permission(status: status, alerts: alerts))
                    done?(self.permission)
                }
            }
        }
    }

    /// Shows the macOS prompt if the user was never asked. Otherwise it just reports the current state.
    func requestPermission(then done: ((Permission) -> Void)? = nil) {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.refreshPermission(then: done) }
            }
        }
    }

    private func update(_ new: Permission) {
        guard new != permission else { return }
        permission = new
        onPermissionChange?(new)
    }

    private static func permission(status: UNAuthorizationStatus, alerts: UNNotificationSetting) -> Permission {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        default: return alerts == .disabled ? .denied : .allowed
        }
    }

    /// Opens this app's page in System Settings → Notifications.
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        let appPage = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")
        let general = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        if let appPage, NSWorkspace.shared.open(appPage) { return }
        if let general { NSWorkspace.shared.open(general) }
    }

    func sendTest() {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude Status Light"
        content.body = "Notifications are working. You'll see these when Claude finishes or needs you."
        content.sound = .default
        center.add(UNNotificationRequest(identifier: "csl.test", content: content, trigger: nil))
    }

    private func identifier(_ key: String) -> String { "csl.session.\(key)" }

    func handle(_ event: SessionStore.Event) {
        switch event {
        case .finished(let key, let record):
            clear(key)
            notifyFinished(key: key, record: record)
        case .needsInput(let key, _):
            // Permission prompts fire PermissionRequest then Notification; wait a beat so the
            // banner carries Claude's own wording and auto-resolved prompts never notify.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let record = self.store?.records[key], record.state == .needsInput else { return }
                    self.notifyInput(key: key, record: record)
                }
            }
        case .resumed(let key, _), .ended(let key):
            clear(key)
        }
    }

    func clear(_ key: String) {
        center?.removeDeliveredNotifications(withIdentifiers: [identifier(key)])
        center?.removePendingNotificationRequests(withIdentifiers: [identifier(key)])
    }

    private var enabled: Bool { Pref.defaults.bool(forKey: Pref.notificationsEnabled) }

    /// e.g. "Session limit 90% used" / "10% left · resets in 1h 12m". One per window and period.
    func checkLimits(_ snapshot: UsageSnapshot?) {
        let now = Date().timeIntervalSince1970
        let sent = Pref.defaults.dictionary(forKey: Pref.limitWarningsSent) as? [String: Double] ?? [:]
        let (warnings, updated) = LimitWarnings.due(in: snapshot, warned: sent, now: now)
        if updated != sent { Pref.defaults.set(updated, forKey: Pref.limitWarningsSent) }
        guard enabled, Pref.defaults.bool(forKey: Pref.notifyLimits), let center else { return }

        for warning in warnings {
            let used = Int(warning.window.usedPercentage.rounded())
            let content = UNMutableNotificationContent()
            content.title = used >= 100 ? "\(warning.name) limit reached" : "\(warning.name) limit \(used)% used"
            var parts: [String] = []
            if used < 100 { parts.append("\(100 - used)% left") }
            if let reset = warning.window.resetsAt, reset > now {
                let seconds = reset - now
                if seconds < 24 * 3600 {
                    parts.append("resets in \(StatusLineRunner.shortDuration(seconds))")
                } else {
                    let formatter = DateFormatter()
                    formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
                    parts.append("resets \(formatter.string(from: Date(timeIntervalSince1970: reset)))")
                }
            }
            content.body = parts.joined(separator: " · ").capitalizedFirst
            content.threadIdentifier = "limits"
            switch Pref.defaults.string(forKey: Pref.soundInput) ?? Pref.defaultSound {
            case Pref.defaultSound: content.sound = .default
            case Pref.noSound: content.sound = nil
            case let name: NSSound(named: NSSound.Name(name))?.play()
            }
            center.add(UNNotificationRequest(identifier: "csl.limit.\(warning.key)", content: content, trigger: nil))
        }
    }

    private func notifyFinished(key: String, record: SessionRecord) {
        guard enabled, Pref.defaults.bool(forKey: Pref.notifyDone), !shouldSkipForFocus(record) else { return }
        var body = record.folderName
        if let outcome = record.outcome, outcome.hasPrefix("error:") {
            let kind = outcome.dropFirst("error:".count).replacingOccurrences(of: "_", with: " ")
            post(key: key, record: record, title: "Claude stopped", body: "\(body) · \(kind)",
                 sound: Pref.defaults.string(forKey: Pref.soundDone))
            return
        }
        let minimum = Double(Pref.defaults.integer(forKey: Pref.minDoneSeconds))
        if let duration = record.turnDuration {
            if duration < minimum { return }
            body += " · \(Format.duration(duration))"
        }
        post(key: key, record: record, title: "Claude finished", body: body,
             sound: Pref.defaults.string(forKey: Pref.soundDone))
    }

    private func notifyInput(key: String, record: SessionRecord) {
        guard enabled, Pref.defaults.bool(forKey: Pref.notifyInput), !shouldSkipForFocus(record) else { return }
        let reason = record.reason ?? "Waiting for your input"
        post(key: key, record: record, title: "Claude needs you", body: "\(record.folderName): \(reason)",
             sound: Pref.defaults.string(forKey: Pref.soundInput))
    }

    private func shouldSkipForFocus(_ record: SessionRecord) -> Bool {
        guard Pref.defaults.bool(forKey: Pref.onlyWhenNotFrontmost),
              let front = NSWorkspace.shared.frontmostApplication else { return false }
        if let appPid = record.appPid { return front.processIdentifier == appPid }
        return Self.terminalBundleIds.contains(front.bundleIdentifier ?? "")
    }

    private func post(key: String, record: SessionRecord, title: String, body: String, sound: String?) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.threadIdentifier = key
        if let appPid = record.appPid { content.userInfo = ["appPid": Int(appPid)] }

        switch sound ?? Pref.defaultSound {
        case Pref.defaultSound: content.sound = .default
        case Pref.noSound: content.sound = nil
        case let name: NSSound(named: NSSound.Name(name))?.play()
        }

        let id = identifier(key)
        center.removeDeliveredNotifications(withIdentifiers: [id])
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let pid = response.notification.request.content.userInfo["appPid"] as? Int
        await MainActor.run { AppFocus.activate(pid: pid.map(Int32.init)) }
    }
}

enum AppFocus {
    /// Brings the session's terminal / editor to the front.
    @MainActor
    static func activate(pid: Int32?) {
        guard let pid, let app = NSRunningApplication(processIdentifier: pid) else { return }
        NSApp.yieldActivation(to: app)
        app.activate()
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return total % 60 == 0 ? "\(minutes)m" : "\(minutes)m \(total % 60)s" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func elapsed(since timestamp: Double) -> String {
        let seconds = max(0, Date().timeIntervalSince1970 - timestamp)
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        if total < 3600 { return "\(total / 60)m" }
        return "\(total / 3600)h \(total % 3600 / 60)m"
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
