import AppKit
import StatusCore
import SwiftUI

/// The settings window is created on demand and released on close, so SwiftUI costs no
/// memory while the app just sits in the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    let model = SettingsModel()
    private var window: NSWindow?

    func show(app: AppDelegate) {
        model.app = app
        model.refresh()
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Claude Status Light"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Coming back from System Settings: show the new permission state right away.
    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentViewController = nil
        window = nil
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    weak var app: AppDelegate?
    @Published var hookStatus: HooksInstaller.Status = .notInstalled
    @Published var launchAtLogin = false
    @Published var notificationPermission: Notifier.Permission = .unknown

    func refresh() {
        hookStatus = HooksInstaller.status()
        launchAtLogin = LoginItem.isEnabled
        app?.notifier.refreshPermission { [weak self] in self?.notificationPermission = $0 }
    }

    var hookStatusText: String {
        switch hookStatus {
        case .installed: return "Installed"
        case .notInstalled: return "Not installed"
        case .outdated: return "Needs update"
        case .unreadable: return "settings.json unreadable"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    @AppStorage(Pref.colorReady) private var colorReady = ""
    @AppStorage(Pref.colorWorking) private var colorWorking = ""
    @AppStorage(Pref.colorInput) private var colorInput = ""
    @AppStorage(Pref.symbolMode) private var symbolMode = false
    @AppStorage(Pref.showWhenIdle) private var showWhenIdle = true
    @AppStorage(Pref.animateWorking) private var animateWorking = true

    @AppStorage(Pref.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(Pref.notifyDone) private var notifyDone = true
    @AppStorage(Pref.notifyInput) private var notifyInput = true
    @AppStorage(Pref.soundDone) private var soundDone = Pref.defaultSound
    @AppStorage(Pref.soundInput) private var soundInput = Pref.defaultSound
    @AppStorage(Pref.onlyWhenNotFrontmost) private var onlyWhenNotFrontmost = false
    @AppStorage(Pref.minDoneSeconds) private var minDoneSeconds = 0

    @AppStorage(Pref.idleTimeoutMinutes) private var idleTimeoutMinutes = 5
    @AppStorage(Pref.fetchUsage) private var fetchUsage = false

    var body: some View {
        Form {
            Section("Menu bar light") {
                ColorPicker("Ready", selection: color($colorReady, .systemGreen), supportsOpacity: false)
                ColorPicker("Working", selection: color($colorWorking, .systemYellow), supportsOpacity: false)
                ColorPicker("Needs input", selection: color($colorInput, .systemRed), supportsOpacity: false)
                Toggle("Use a different shape per state (accessibility)", isOn: $symbolMode)
                Toggle("Spin the light while Claude is working", isOn: $animateWorking)
                    .disabled(symbolMode)
                Toggle("Show the light when no session is running", isOn: $showWhenIdle)
                if !showWhenIdle {
                    Text("While hidden, open Claude Status Light again from Finder or Spotlight to get back here.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Reset Colors") {
                    colorReady = ""
                    colorWorking = ""
                    colorInput = ""
                }
            }

            Section("Notifications") {
                permissionRow
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                Group {
                    Toggle("When Claude finishes", isOn: $notifyDone)
                    soundPicker($soundDone).disabled(!notifyDone)
                    Stepper(value: $minDoneSeconds, in: 0...600, step: 5) {
                        Text(minDoneSeconds == 0 ? "Notify after every turn"
                                                 : "Only if Claude worked at least \(minDoneSeconds)s")
                    }
                    .disabled(!notifyDone)
                    Toggle("When Claude needs input", isOn: $notifyInput)
                    soundPicker($soundInput).disabled(!notifyInput)
                    Toggle("Skip when that session’s terminal is in front", isOn: $onlyWhenNotFrontmost)
                }
                .disabled(!notificationsEnabled)
                Button("Open System Notification Settings…") { Notifier.openSystemSettings() }
            }

            Section {
                Stepper(value: $idleTimeoutMinutes, in: 1...120) {
                    Text("Treat a silent “working” session as ready after \(idleTimeoutMinutes) min")
                }
            } header: {
                Text("Sessions")
            } footer: {
                Text("Covers runs interrupted with Esc, where Claude Code never reports the turn ending.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Fetch usage from Anthropic", isOn: $fetchUsage)
                    .onChange(of: fetchUsage) { _, _ in model.app?.usage.settingChanged() }
            } header: {
                Text("Usage limits")
            } footer: {
                Text("""
                Session and weekly usage always come from Claude Code sessions in a terminal, offline. \
                Turn this on to also get them for VS Code and other editors: it reads the same numbers as /usage \
                with Claude Code’s saved login (macOS asks once for Keychain access). The login only goes to Anthropic.
                """)
                .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.app?.setLaunchAtLogin($0) }))
                LabeledContent("Claude Code hooks") {
                    HStack {
                        Text(model.hookStatusText).foregroundStyle(.secondary)
                        if model.hookStatus == .installed {
                            Button("Uninstall") { model.app?.uninstallHooks() }
                        } else {
                            Button("Install") { model.app?.installHooks() }
                        }
                    }
                }
                Button("Show Data Folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.baseDir])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 700)
    }

    @ViewBuilder
    private var permissionRow: some View {
        let permission = model.notificationPermission
        LabeledContent("macOS permission") {
            HStack {
                Label(permission.label, systemImage: permission == .allowed ? "checkmark.circle.fill" : "bell.slash.fill")
                    .foregroundStyle(permission == .allowed ? Color.green : Color.orange)
                switch permission {
                case .allowed:
                    Button("Send Test") { model.app?.notifier.sendTest() }
                case .notDetermined:
                    Button("Allow…") { model.app?.turnOnNotifications() }
                case .denied:
                    Button("Turn On…") { Notifier.openSystemSettings() }
                case .unknown:
                    EmptyView()
                }
            }
        }
        if permission == .denied {
            Text("macOS is blocking notifications from this app. Click Turn On…, then switch on “Allow notifications”.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func soundPicker(_ selection: Binding<String>) -> some View {
        Picker("Sound", selection: selection) {
            ForEach(Pref.soundNames, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: selection.wrappedValue) { _, name in
            if name != Pref.defaultSound && name != Pref.noSound { NSSound(named: NSSound.Name(name))?.play() }
        }
    }

    private func color(_ hex: Binding<String>, _ fallback: NSColor) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: hex.wrappedValue) ?? fallback) },
            set: { hex.wrappedValue = NSColor($0).hexString })
    }
}
