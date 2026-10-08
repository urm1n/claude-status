import XCTest
@testable import StatusCore

final class HookReducerTests: XCTestCase {
    private var record: SessionRecord?
    private var clock = 1_000.0

    @discardableResult
    private func send(_ event: String, tool: String? = nil, toolUseId: String? = nil, agent: String? = nil,
                      notification: String? = nil, message: String? = nil, source: String? = nil,
                      error: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> HookOutcome {
        clock += 1
        let input = HookInput(event: event, sessionId: "s1", cwd: "/Users/me/project", toolName: tool,
                              toolUseId: toolUseId, agentId: agent, notificationType: notification,
                              message: message, source: source, errorType: error)
        let outcome = HookReducer.reduce(input, existing: record, projectDir: "/Users/me/project", now: clock)
        switch outcome {
        case .write(let new): record = new
        case .delete: record = nil
        case .ignore: break
        }
        return outcome
    }

    private var state: SessionState? { record?.state }

    func testNormalTurn() {
        send("SessionStart", source: "startup")
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(record?.folderName, "project")

        send("UserPromptSubmit")
        XCTAssertEqual(state, .working)
        let started = record?.turnStartedAt
        send("PreToolUse", tool: "Read", toolUseId: "t1")
        send("PostToolUse", tool: "Read", toolUseId: "t1")
        XCTAssertEqual(state, .working)
        XCTAssertEqual(record?.stateSince, started, "staying in a state must not reset its timer")

        send("Stop")
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(record?.outcome, "done")
        XCTAssertEqual(record?.turnDuration, 3)

        XCTAssertEqual(send("SessionEnd"), .delete)
    }

    func testPermissionPromptAndApproval() {
        send("UserPromptSubmit")
        send("PreToolUse", tool: "Bash", toolUseId: "t1")
        send("PermissionRequest", tool: "Bash", toolUseId: "t1")
        XCTAssertEqual(state, .needsInput)
        XCTAssertEqual(record?.reason, "Permission needed: Bash")

        send("Notification", notification: "permission_prompt", message: "Claude needs your permission to use Bash")
        XCTAssertEqual(state, .needsInput)
        XCTAssertEqual(record?.reason, "Claude needs your permission to use Bash")
        XCTAssertEqual(record?.pendingToolUseId, "t1", "the notification must not forget which tool is pending")

        send("PostToolUse", tool: "Bash", toolUseId: "t1")
        XCTAssertEqual(state, .working)
        XCTAssertNil(record?.reason)
    }

    func testBackgroundSubagentDoesNotHidePendingPrompt() {
        send("UserPromptSubmit")
        send("PermissionRequest", tool: "Bash", toolUseId: "main-1")
        send("PreToolUse", tool: "Grep", toolUseId: "sub-1", agent: "agent-a")
        send("PostToolUse", tool: "Grep", toolUseId: "sub-1", agent: "agent-a")
        XCTAssertEqual(state, .needsInput)

        // A parallel tool call of the main thread finishing doesn't clear it either.
        send("PostToolUse", tool: "Read", toolUseId: "main-0")
        XCTAssertEqual(state, .needsInput)

        // The main thread starting a new tool means it was unblocked (e.g. rejected with feedback).
        send("PreToolUse", tool: "Edit", toolUseId: "main-2")
        XCTAssertEqual(state, .working)
    }

    func testAskUserQuestion() {
        send("UserPromptSubmit")
        send("PreToolUse", tool: "AskUserQuestion", toolUseId: "q1")
        XCTAssertEqual(state, .needsInput)
        send("PostToolUse", tool: "AskUserQuestion", toolUseId: "q1")
        XCTAssertEqual(state, .working)
    }

    func testIdlePromptRecoversInterruptedRunButNeverHidesInput() {
        send("UserPromptSubmit")
        send("PreToolUse", tool: "Bash", toolUseId: "t1")
        send("Notification", notification: "idle_prompt", message: "Claude is waiting for your input")
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(record?.outcome, "idle")

        send("UserPromptSubmit")
        send("PermissionRequest", tool: "Bash", toolUseId: "t2")
        send("Notification", notification: "idle_prompt")
        XCTAssertEqual(state, .needsInput)
    }

    func testStopFailure() {
        send("UserPromptSubmit")
        send("StopFailure", error: "rate_limit")
        XCTAssertEqual(state, .ready)
        XCTAssertEqual(record?.outcome, "error:rate_limit")
    }

    func testCompactionKeepsWorking() {
        send("UserPromptSubmit")
        send("SessionStart", source: "compact")
        XCTAssertEqual(state, .working)
    }

    func testAppStartedMidSessionPicksUpOnNextEvent() {
        send("PostToolUse", tool: "Read", toolUseId: "x")
        XCTAssertEqual(state, .working)
    }

    func testIrrelevantEventsDoNotRewriteTheFile() {
        send("SessionStart")
        XCTAssertEqual(send("Notification", notification: "auth_success"), .ignore)
        XCTAssertEqual(send("SubagentStop"), .ignore)
    }

    func testElicitation() {
        send("UserPromptSubmit")
        send("Elicitation", toolUseId: "e1")
        XCTAssertEqual(state, .needsInput)
        send("ElicitationResult", toolUseId: "e1")
        XCTAssertEqual(state, .working)
    }

    func testParsingPayload() {
        let json: [String: Any] = [
            "hook_event_name": "Notification", "session_id": "abc", "cwd": "/tmp/x",
            "notification_type": "permission_prompt", "message": "hi", "prompt": "SECRET",
        ]
        let input = HookInput(json: json)
        XCTAssertEqual(input?.event, "Notification")
        XCTAssertEqual(input?.notificationType, "permission_prompt")
        XCTAssertNil(HookInput(json: ["hook_event_name": "Stop"]), "no session id -> ignored")
    }

    func testSafeFileName() {
        XCTAssertEqual(Paths.safeFileName(for: "../../etc/passwd"), "etcpasswd")
        XCTAssertEqual(Paths.safeFileName(for: "6f1c-ab_9"), "6f1c-ab_9")
        XCTAssertEqual(Paths.safeFileName(for: "///"), "unknown")
    }
}
