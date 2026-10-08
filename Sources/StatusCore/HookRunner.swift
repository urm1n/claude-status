import Darwin
import Foundation

/// What `csl-hook` does per event: parse stdin, update one small JSON file, exit.
/// Every failure is swallowed. A status light must never break Claude Code.
public enum HookRunner {
    public static func handle(payload: Data, environment: [String: String],
                              now: Double = Date().timeIntervalSince1970) {
        guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let input = HookInput(json: json) else { return }

        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.sessionsDir, withIntermediateDirectories: true)

        // Parallel tool calls fire hooks concurrently; serialize the read-modify-write.
        let lockFd = open(Paths.lockFile.path, O_CREAT | O_RDWR, 0o644)
        if lockFd >= 0 { flock(lockFd, LOCK_EX) }
        defer {
            if lockFd >= 0 {
                flock(lockFd, LOCK_UN)
                close(lockFd)
            }
        }

        let file = Paths.sessionFile(for: input.sessionId)
        let existing = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(SessionRecord.self, from: $0) }
        let projectDir = environment["CLAUDE_PROJECT_DIR"].flatMap { $0.isEmpty ? nil : $0 } ?? input.cwd ?? ""

        switch HookReducer.reduce(input, existing: existing, projectDir: projectDir, now: now) {
        case .ignore:
            return
        case .delete:
            try? fm.removeItem(at: file)
        case .write(var record):
            let (claude, appPid) = ProcessTree.locateClaude()
            if let claude {
                record.claudePid = claude.pid
                record.claudePidStart = claude.startTime
            }
            if let appPid { record.appPid = appPid }
            writeAtomically(record, to: file)
        }
    }

    static func writeAtomically(_ record: SessionRecord, to file: URL) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        let tmp = file.deletingLastPathComponent()
            .appendingPathComponent(".\(file.lastPathComponent).\(getpid()).tmp")
        do {
            try data.write(to: tmp)
            if rename(tmp.path, file.path) != 0 { try? FileManager.default.removeItem(at: tmp) }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }
}
