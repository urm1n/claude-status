import Foundation

/// Adds / removes this app's entries in `~/.claude/settings.json`.
/// - Backs the file up before every change.
/// - Merges: other hooks (and every other setting, in their original order) are left alone.
/// - Identifies its own entries by the helper path in the command, nothing else.
public enum HooksInstaller {
    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        /// Some of our entries exist but not exactly the current set (older version).
        case outdated
        case unreadable(String)
    }

    public enum InstallError: LocalizedError {
        case unreadable(String)
        case notAnObject(String)

        public var errorDescription: String? {
            switch self {
            case .unreadable(let detail):
                return "Claude Code's settings.json could not be parsed, so it was not changed. \(detail)"
            case .notAnObject(let what):
                return "Claude Code's settings.json has an unexpected shape (\(what)), so it was not changed."
            }
        }
    }

    public static let marker = "/.claude-status-light/bin/csl-hook"
    public static let timeoutSeconds = "5"

    /// `$HOME` keeps settings portable across machines; `|| true` keeps Claude Code quiet if the app was deleted.
    public static var hookCommand: String {
        let binary = Paths.usesDefaultBaseDir ? "$HOME\(marker)" : Paths.hookBinary.path
        return "\"\(binary)\" 2>/dev/null || true"
    }

    /// Status line command: records usage limits, then shows the user's own status line if they had one.
    public static var statusLineCommand: String {
        let binary = Paths.usesDefaultBaseDir ? "$HOME\(marker)" : Paths.hookBinary.path
        return "\"\(binary)\" statusline 2>/dev/null"
    }

    static func isOurStatusLine(_ value: JSONValue?) -> Bool {
        value.map(isOurs) ?? false
    }

    /// Ours, keeping display options (padding, refreshInterval…) from the status line it wraps.
    static func ourStatusLine(wrapping previous: JSONValue?) -> JSONValue {
        var value = previous?.members != nil ? previous! : .object([])
        value["type"] = .string("command")
        value["command"] = .string(statusLineCommand)
        return value
    }

    static func isOurs(_ hook: JSONValue) -> Bool {
        guard let command = hook["command"]?.string else { return false }
        return command.contains(marker) || (!Paths.usesDefaultBaseDir && command.contains(Paths.hookBinary.path))
    }

    static var ourGroup: JSONValue {
        .object([
            JSONMember("hooks", .array([
                .object([
                    JSONMember("type", .string("command")),
                    JSONMember("command", .string(hookCommand)),
                    JSONMember("timeout", .number(timeoutSeconds)),
                ]),
            ])),
        ])
    }

    // MARK: Pure transforms

    public static func status(of root: JSONValue) -> Status {
        guard let hooks = root["hooks"]?.members else { return .notInstalled }
        var found = 0
        var exact = Set<String>()
        for member in hooks {
            for group in member.value.array ?? [] {
                let ours = (group["hooks"]?.array ?? []).filter(isOurs)
                found += ours.count
                if group == ourGroup { exact.insert(member.key) }
            }
        }
        let statusLine = isOurStatusLine(root["statusLine"])
        if found == 0 { return statusLine ? .outdated : .notInstalled }
        let expected = Set(HookReducer.registeredEvents)
        return exact == expected && found == expected.count && statusLine ? .installed : .outdated
    }

    /// Removes our hooks, and puts back the user's own status line (`chain`) if ours replaced it.
    public static func removingOurs(from root: JSONValue, chain: JSONValue?) -> JSONValue {
        var result = removingOurHooks(from: root)
        if isOurStatusLine(result["statusLine"]) { result["statusLine"] = chain }
        return result
    }

    /// `keepEmpty` leaves emptied event lists and the `hooks` object in place, so a reinstall
    /// re-adds our entries where they were instead of moving them to the end of the file.
    static func removingOurHooks(from root: JSONValue, keepEmpty: Bool = false) -> JSONValue {
        guard var hooks = root["hooks"], let members = hooks.members else { return root }
        var changed = false
        for member in members {
            guard let groups = member.value.array else { continue }
            var newGroups: [JSONValue] = []
            var groupChanged = false
            for group in groups {
                guard let inner = group["hooks"]?.array else { newGroups.append(group); continue }
                let kept = inner.filter { !isOurs($0) }
                if kept.count == inner.count { newGroups.append(group); continue }
                groupChanged = true
                if !kept.isEmpty {
                    var copy = group
                    copy["hooks"] = .array(kept)
                    newGroups.append(copy)
                }
            }
            guard groupChanged else { continue }
            changed = true
            hooks[member.key] = newGroups.isEmpty && !keepEmpty ? nil : .array(newGroups)
        }
        guard changed else { return root }
        var result = root
        result["hooks"] = (hooks.members?.isEmpty ?? false) && !keepEmpty ? nil : hooks
        return result
    }

    /// Returns the new settings and the user's own status line that ours now wraps (to save as `chain`).
    public static func addingOurs(to root: JSONValue, chain: JSONValue?) throws -> (root: JSONValue, chain: JSONValue?) {
        guard root.members != nil else { throw InstallError.notAnObject("top level is not an object") }
        var result = removingOurHooks(from: root, keepEmpty: true)
        if isOurStatusLine(result["statusLine"]) { result["statusLine"] = chain }
        let usersStatusLine = result["statusLine"]
        var hooks = result["hooks"] ?? .object([])
        guard hooks.members != nil else { throw InstallError.notAnObject("\"hooks\" is not an object") }
        for event in HookReducer.registeredEvents {
            let existing = hooks[event]
            if let existing, existing.array == nil {
                throw InstallError.notAnObject("\"hooks.\(event)\" is not an array")
            }
            hooks[event] = .array((existing?.array ?? []) + [ourGroup])
        }
        // Events an older version hooked that this one doesn't: drop lists left empty.
        for member in hooks.members ?? [] where member.value.array?.isEmpty == true
            && root["hooks"]?[member.key]?.array?.isEmpty == false {
            hooks[member.key] = nil
        }
        result["hooks"] = hooks
        result["statusLine"] = ourStatusLine(wrapping: usersStatusLine)
        return (result, usersStatusLine)
    }

    // MARK: File operations

    public static func status(settings: URL = Paths.claudeSettings) -> Status {
        guard let data = try? Data(contentsOf: settings) else { return .notInstalled }
        do {
            return status(of: try JSONValue.parse(data))
        } catch {
            return .unreadable(String(describing: error))
        }
    }

    public static func install(settings: URL = Paths.claudeSettings) throws {
        let fm = FileManager.default
        var wrapped: JSONValue?
        try modify(settings: settings, createIfMissing: true) { root in
            let (updated, chain) = try addingOurs(to: root, chain: savedChain())
            wrapped = chain
            // Save the user's status line before settings.json stops containing it.
            if let chain {
                try fm.createDirectory(at: Paths.baseDir, withIntermediateDirectories: true)
                try Data(chain.serialized().utf8).write(to: Paths.statusLineChainFile, options: .atomic)
            }
            return updated
        }
        if wrapped == nil { try? fm.removeItem(at: Paths.statusLineChainFile) }
    }

    public static func uninstall(settings: URL = Paths.claudeSettings) throws {
        let chain = savedChain()
        try modify(settings: settings, createIfMissing: false) { removingOurs(from: $0, chain: chain) }
        try? FileManager.default.removeItem(at: Paths.statusLineChainFile)
    }

    static func savedChain() -> JSONValue? {
        (try? Data(contentsOf: Paths.statusLineChainFile)).flatMap { try? JSONValue.parse($0) }
    }

    /// Restores the newest backup over settings.json (keeping a copy of the current file first).
    @discardableResult
    public static func restoreLatestBackup(settings: URL = Paths.claudeSettings) throws -> URL? {
        guard let latest = backups().first else { return nil }
        let target = settings.resolvingSymlinksInPath()
        if let current = try? Data(contentsOf: target) { try backup(current) }
        try writeAtomically(try Data(contentsOf: latest), to: target)
        return latest
    }

    public static func backups() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Paths.backupsDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func modify(settings: URL, createIfMissing: Bool, _ transform: (JSONValue) throws -> JSONValue) throws {
        // Dotfile users often symlink settings.json; edit the real file, keep the link.
        let target = settings.resolvingSymlinksInPath()
        let original = try? Data(contentsOf: target)
        guard original != nil || createIfMissing else { return }

        let root: JSONValue
        if let original, !original.allSatisfy({ [0x20, 0x0A, 0x0D, 0x09].contains($0) }) {
            do { root = try JSONValue.parse(original) } catch {
                throw InstallError.unreadable(String(describing: error))
            }
        } else {
            root = .object([])
        }

        let updated = try transform(root)
        guard updated != root || original == nil else { return }

        if let original { try backup(original) }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let trailingNewline = original.map { $0.last == 0x0A } ?? true
        let text = updated.serialized() + (trailingNewline ? "\n" : "")
        try writeAtomically(Data(text.utf8), to: target)
    }

    static func backup(_ data: Data) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.backupsDir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = Paths.backupsDir.appendingPathComponent("settings-\(formatter.string(from: Date())).json")
        try data.write(to: url)
        for old in backups().dropFirst(10) { try? fm.removeItem(at: old) }
    }

    static func writeAtomically(_ data: Data, to target: URL) throws {
        let fm = FileManager.default
        let permissions = (try? fm.attributesOfItem(atPath: target.path))?[.posixPermissions]
        let tmp = target.deletingLastPathComponent()
            .appendingPathComponent(".\(target.lastPathComponent).csl-\(getpid()).tmp")
        try data.write(to: tmp)
        if let permissions { try? fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: tmp.path) }
        guard rename(tmp.path, target.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown)
        }
    }
}

/// Keeps `~/.claude-status-light/bin/csl-hook` identical to the copy shipped inside the app,
/// so moving or updating the app never breaks the hook command.
public enum HelperInstaller {
    @discardableResult
    public static func sync(from source: URL) throws -> Bool {
        let fm = FileManager.default
        let dest = Paths.hookBinary
        let sourceData = try Data(contentsOf: source)
        if let existing = try? Data(contentsOf: dest), existing == sourceData { return false }
        try fm.createDirectory(at: Paths.binDir, withIntermediateDirectories: true)
        let tmp = Paths.binDir.appendingPathComponent(".csl-hook.\(getpid()).tmp")
        try sourceData.write(to: tmp)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        guard rename(tmp.path, dest.path) == 0 else {
            try? fm.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown)
        }
        return true
    }

    public static func remove() {
        try? FileManager.default.removeItem(at: Paths.binDir)
    }
}
