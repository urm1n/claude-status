import AppKit
import StatusCore

/// UserDefaults keys. The SwiftUI settings view binds to the same keys with @AppStorage.
enum Pref {
    static let notificationsEnabled = "notificationsEnabled"
    static let notifyDone = "notifyDone"
    static let notifyInput = "notifyInput"
    static let soundDone = "soundDone"
    static let soundInput = "soundInput"
    static let onlyWhenNotFrontmost = "onlyWhenNotFrontmost"
    static let minDoneSeconds = "minDoneSeconds"
    static let idleTimeoutMinutes = "idleTimeoutMinutes"
    static let symbolMode = "symbolMode"
    static let showWhenIdle = "showWhenIdle"
    static let colorReady = "colorReady"
    static let colorWorking = "colorWorking"
    static let colorInput = "colorInput"
    static let didOfferHookInstall = "didOfferHookInstall"
    static let fetchUsage = "fetchUsage"
    static let animateWorking = "animateWorking"

    static let defaultSound = "Default"
    /// Out of the box: a success chime when Claude finishes, an alert when it needs you.
    static let doneSoundDefault = "Glass"
    static let inputSoundDefault = "Funk"
    static let noSound = "None"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            notificationsEnabled: true,
            notifyDone: true,
            notifyInput: true,
            soundDone: doneSoundDefault,
            soundInput: inputSoundDefault,
            onlyWhenNotFrontmost: false,
            minDoneSeconds: 0,
            idleTimeoutMinutes: 5,
            symbolMode: false,
            showWhenIdle: true,
            colorReady: "",
            colorWorking: "",
            colorInput: "",
            fetchUsage: false,
            animateWorking: true,
        ])
    }

    static var defaults: UserDefaults { .standard }

    /// The settings that affect the menu bar light.
    static var lightSignature: [String] {
        [colorReady, colorWorking, colorInput].map { defaults.string(forKey: $0) ?? "" }
            + [symbolMode, showWhenIdle, animateWorking].map { String(defaults.bool(forKey: $0)) }
            + [String(defaults.integer(forKey: idleTimeoutMinutes))]
    }

    static var idleTimeout: TimeInterval {
        TimeInterval(max(1, defaults.integer(forKey: idleTimeoutMinutes)) * 60)
    }

    static func color(for state: SessionState) -> NSColor {
        switch state {
        case .ready: return NSColor(hex: defaults.string(forKey: colorReady)) ?? .systemGreen
        case .working: return NSColor(hex: defaults.string(forKey: colorWorking)) ?? .systemYellow
        case .needsInput: return NSColor(hex: defaults.string(forKey: colorInput)) ?? .systemRed
        }
    }

    /// "Default", "None", then the macOS system sounds (Basso, Blow, Glass, Ping...).
    static let soundNames: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let names = files.map { ($0 as NSString).deletingPathExtension }.sorted()
        return [defaultSound, noSound] + names
    }()
}

extension NSColor {
    convenience init?(hex: String?) {
        guard var hex = hex?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "" }
        func byte(_ component: CGFloat) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(rgb.redComponent), byte(rgb.greenComponent), byte(rgb.blueComponent))
    }

    var isLight: Bool {
        guard let rgb = usingColorSpace(.sRGB) else { return false }
        return 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent > 0.6
    }
}
