import Foundation

public enum SessionState: String, Codable, Sendable, CaseIterable {
    case ready
    case working
    case needsInput

    /// Red > Yellow > Green. "No session" (gray) is the absence of any state.
    public var priority: Int {
        switch self {
        case .ready: return 1
        case .working: return 2
        case .needsInput: return 3
        }
    }

    public var label: String {
        switch self {
        case .ready: return "Ready"
        case .working: return "Working"
        case .needsInput: return "Needs input"
        }
    }
}

/// What the hook writes to `~/.claude-status-light/sessions/<session_id>.json`.
/// Holds only state, ids, timestamps and the project folder. Never prompts, code or responses.
public struct SessionRecord: Codable, Equatable, Sendable {
    public var sessionId: String
    public var projectDir: String
    public var state: SessionState
    /// The hook event that produced this record.
    public var lastEvent: String
    /// Short, human readable reason for `needsInput` (e.g. "Claude needs your permission to use Bash").
    public var reason: String?
    public var updatedAt: Double
    public var stateSince: Double
    public var turnStartedAt: Double?
    /// Set when a turn ends (`Stop` / `StopFailure`).
    public var finishedAt: Double?
    /// "done", "error:<type>" or "idle".
    public var outcome: String?
    /// The tool call a permission prompt / question is waiting on.
    public var pendingToolUseId: String?
    /// The agent ("" = main thread) that is waiting on the user.
    public var pendingAgentId: String?
    public var claudePid: Int32?
    public var claudePidStart: Double?
    /// The GUI app hosting the session (Terminal, iTerm, VS Code...), used to focus it.
    public var appPid: Int32?
    /// Claude Code's transcript for this session. The app watches its tail for the interrupt
    /// marker, because no hook fires when the user stops Claude with Esc.
    public var transcriptPath: String?

    public init(sessionId: String, projectDir: String, now: Double) {
        self.sessionId = sessionId
        self.projectDir = projectDir
        self.state = .ready
        self.lastEvent = ""
        self.updatedAt = now
        self.stateSince = now
    }

    public var folderName: String {
        let name = (projectDir as NSString).lastPathComponent
        return name.isEmpty ? "Claude session" : name
    }

    public var turnDuration: Double? {
        guard let start = turnStartedAt, let end = finishedAt, end >= start else { return nil }
        return end - start
    }
}
