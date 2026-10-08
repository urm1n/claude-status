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

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
