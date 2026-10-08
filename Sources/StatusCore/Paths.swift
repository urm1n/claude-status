import Foundation

/// Every location the app and the hook touch. Both overrides exist for tests.
public enum Paths {
    /// `~/.claude-status-light`, or `$CLAUDE_STATUS_LIGHT_DIR`.
    public static let baseDir: URL = {
        if let dir = ProcessInfo.processInfo.environment["CLAUDE_STATUS_LIGHT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude-status-light", isDirectory: true)
    }()

    /// `~/.claude/settings.json`, or `$CLAUDE_STATUS_LIGHT_SETTINGS`.
    public static let claudeSettings: URL = {
        if let file = ProcessInfo.processInfo.environment["CLAUDE_STATUS_LIGHT_SETTINGS"], !file.isEmpty {
            return URL(fileURLWithPath: file)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".claude/settings.json")
    }()

    public static var usesDefaultBaseDir: Bool {
        ProcessInfo.processInfo.environment["CLAUDE_STATUS_LIGHT_DIR"]?.isEmpty ?? true
    }

    public static var sessionsDir: URL { baseDir.appendingPathComponent("sessions", isDirectory: true) }
    public static var binDir: URL { baseDir.appendingPathComponent("bin", isDirectory: true) }
    public static var backupsDir: URL { baseDir.appendingPathComponent("backups", isDirectory: true) }
    public static var hookBinary: URL { binDir.appendingPathComponent("csl-hook") }
    public static var lockFile: URL { baseDir.appendingPathComponent(".lock") }

    public static func sessionFile(for sessionId: String) -> URL {
        sessionsDir.appendingPathComponent(safeFileName(for: sessionId) + ".json")
    }

    /// Session ids are UUIDs, but never trust input that becomes a path.
    public static func safeFileName(for sessionId: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = String(sessionId.unicodeScalars.filter { allowed.contains($0) && $0.isASCII }.prefix(80))
        return cleaned.isEmpty ? "unknown" : cleaned
    }
}
