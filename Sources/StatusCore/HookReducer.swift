import Foundation

/// The fields this app reads from a Claude Code hook payload. Everything else is ignored.
public struct HookInput: Equatable, Sendable {
    public var event: String
    public var sessionId: String
    public var cwd: String?
    public var toolName: String?
    public var toolUseId: String?
    public var agentId: String?
    public var notificationType: String?
    public var message: String?
    public var source: String?
    public var errorType: String?
    public var serverName: String?

    public init(event: String, sessionId: String, cwd: String? = nil, toolName: String? = nil,
                toolUseId: String? = nil, agentId: String? = nil, notificationType: String? = nil,
                message: String? = nil, source: String? = nil, errorType: String? = nil,
                serverName: String? = nil) {
        self.event = event
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.toolUseId = toolUseId
        self.agentId = agentId
        self.notificationType = notificationType
        self.message = message
        self.source = source
        self.errorType = errorType
        self.serverName = serverName
    }

    public init?(json: [String: Any]) {
        func str(_ key: String) -> String? {
            guard let value = json[key] as? String, !value.isEmpty else { return nil }
            return value
        }
        guard let event = str("hook_event_name"), let sessionId = str("session_id") else { return nil }
        self.init(event: event, sessionId: sessionId, cwd: str("cwd"), toolName: str("tool_name"),
                  toolUseId: str("tool_use_id"), agentId: str("agent_id"),
                  notificationType: str("notification_type"), message: str("message"),
                  source: str("source"), errorType: str("error_type"),
                  serverName: str("server_name") ?? str("mcp_server_name"))
    }
}

public enum HookOutcome: Equatable, Sendable {
    case write(SessionRecord)
    case delete
    case ignore
}

/// Pure state machine: (previous record, hook event) -> new record.
///
/// | Event                                   | State                         |
/// |-----------------------------------------|-------------------------------|
/// | SessionStart                            | ready                         |
/// | UserPromptSubmit, Pre/PostToolUse       | working                       |
/// | PermissionRequest, Elicitation,         | needsInput                    |
/// | PreToolUse(AskUserQuestion),            |                               |
/// | Notification(permission/elicitation)    |                               |
/// | Notification(idle_prompt) while working | ready (recovers from Esc)     |
/// | Stop, StopFailure                       | ready + "done"                |
/// | SessionEnd                              | session removed               |
public enum HookReducer {
    /// The hook events the installer registers.
    public static let registeredEvents = [
        "SessionStart", "SessionEnd", "UserPromptSubmit",
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification",
        "Elicitation", "ElicitationResult",
        "Stop", "StopFailure",
    ]

    static let inputNotificationTypes: Set<String> = [
        "permission_prompt", "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input",
    ]

    public static func reduce(_ input: HookInput, existing: SessionRecord?, projectDir: String,
                              now: Double) -> HookOutcome {
        if input.event == "SessionEnd" { return .delete }

        var record = existing ?? SessionRecord(sessionId: input.sessionId, projectDir: projectDir, now: now)
        if !projectDir.isEmpty { record.projectDir = projectDir }
        record.updatedAt = now
        record.lastEvent = input.event

        func set(_ state: SessionState, reason: String? = nil) {
            if record.state != state { record.stateSince = now }
            record.state = state
            record.reason = state == .needsInput ? reason : nil
        }

        func waitOn(_ toolUseId: String?) {
            record.pendingToolUseId = toolUseId
            record.pendingAgentId = input.agentId ?? ""
        }

        func clearWait() {
            record.pendingToolUseId = nil
            record.pendingAgentId = nil
        }

        /// While blocked on the user, only the blocked agent's own activity means it was unblocked.
        /// Stops a background subagent's tool calls from hiding a pending permission prompt.
        func resumes(viaPre: Bool) -> Bool {
            guard record.state == .needsInput else { return true }
            guard let pending = record.pendingToolUseId else { return true }
            if input.toolUseId == pending { return true }
            return viaPre && (input.agentId ?? "") == (record.pendingAgentId ?? "")
        }

        switch input.event {
        case "SessionStart":
            // Auto-compaction mid-turn fires SessionStart(compact); that is not a fresh idle session.
            if input.source == "compact", existing != nil { break }
            set(.ready)
            record.turnStartedAt = nil
            record.finishedAt = nil
            record.outcome = nil
            clearWait()

        case "UserPromptSubmit":
            set(.working)
            record.turnStartedAt = now
            record.finishedAt = nil
            record.outcome = nil
            clearWait()

        case "PreToolUse":
            if input.toolName == "AskUserQuestion" {
                set(.needsInput, reason: "Claude has a question for you")
                waitOn(input.toolUseId)
            } else if resumes(viaPre: true) {
                set(.working)
                clearWait()
            }

        case "PostToolUse", "PostToolUseFailure":
            if resumes(viaPre: false) {
                set(.working)
                clearWait()
            }

        case "PermissionRequest":
            let tool = input.toolName.map { "Permission needed: \($0)" } ?? "Permission needed"
            set(.needsInput, reason: tool)
            waitOn(input.toolUseId)

        case "Elicitation":
            set(.needsInput, reason: "\(input.serverName ?? "An MCP server") needs input")
            waitOn(input.toolUseId)

        case "ElicitationResult":
            if record.state == .needsInput {
                set(.working)
                clearWait()
            }

        case "Notification":
            let type = input.notificationType ?? ""
            if inputNotificationTypes.contains(type) {
                let pending = record.state == .needsInput ? record.pendingToolUseId : nil
                set(.needsInput, reason: input.message ?? "Waiting for your input")
                if pending == nil { waitOn(nil) }
            } else if type == "idle_prompt", record.state == .working {
                // Claude has sat at the prompt for 60s+: the turn ended without Stop (e.g. Esc).
                set(.ready)
                record.outcome = "idle"
                clearWait()
            } else if existing != nil {
                return .ignore
            }

        case "Stop":
            set(.ready)
            record.finishedAt = now
            record.outcome = "done"
            clearWait()

        case "StopFailure":
            set(.ready)
            record.finishedAt = now
            record.outcome = "error:\(input.errorType ?? "unknown")"
            clearWait()

        default:
            if existing != nil { return .ignore }
        }
        return .write(record)
    }
}
