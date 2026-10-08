import XCTest
@testable import StatusCore

final class InterruptTests: XCTestCase {
    private func line(_ object: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    private func user(_ text: String, at time: String = "2026-10-08T18:22:52.819Z") -> String {
        line(["type": "user", "timestamp": time, "message": ["role": "user", "content": [["type": "text", "text": text]]]])
    }

    private let assistant = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Working on it"}]}}"#
    private let bookkeeping = #"{"type":"queue-operation","operation":"dequeue"}"#

    private func time(_ lines: [String], partial: Bool = false) -> Double? {
        TranscriptTail.interruptTime(tail: Data(lines.joined(separator: "\n").utf8), isPartial: partial)
    }

    func testDetectsInterruptAsLastEntry() {
        let result = time([user("fix the bug"), assistant, user("[Request interrupted by user]"), bookkeeping])
        XCTAssertEqual(result ?? 0, 1_791_483_772.819, accuracy: 0.001)
        XCTAssertNotNil(time([assistant, user("[Request interrupted by user for tool use]")]), "Esc at a permission prompt")
    }

    func testIgnoresOlderInterrupts() {
        XCTAssertNil(time([user("[Request interrupted by user]"), user("try again"), assistant]))
        XCTAssertNil(time([user("[Request interrupted by user]"), assistant]))
        XCTAssertNil(time([assistant, user("please mention [Request interrupted by user] in docs")]))
    }

    func testPartialFirstLineIsSkipped() {
        let cut = String(user("[Request interrupted by user]").dropFirst(10))
        XCTAssertNil(time([cut], partial: true))
        XCTAssertNotNil(time(["garbage", user("[Request interrupted by user]")], partial: true))
    }

    func testMarkInterruptedOnlyAppliesToTheExpectedState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("csl-int-\(UUID().uuidString)")
        setenv("CLAUDE_STATUS_LIGHT_DIR", dir.path, 1)
        defer {
            unsetenv("CLAUDE_STATUS_LIGHT_DIR")
            try? FileManager.default.removeItem(at: dir)
        }
        try FileManager.default.createDirectory(at: Paths.sessionsDir, withIntermediateDirectories: true)
        var record = SessionRecord(sessionId: "s1", projectDir: "/tmp/p", now: 100)
        record.state = .working
        record.lastEvent = "PreToolUse"
        HookRunner.writeAtomically(record, to: Paths.sessionFile(for: "s1"))

        XCTAssertFalse(HookRunner.markInterrupted(fileKey: "s1", ifUpdatedAt: 99), "a newer event won")
        XCTAssertTrue(HookRunner.markInterrupted(fileKey: "s1", ifUpdatedAt: 100, now: 105))

        let saved = try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: Paths.sessionFile(for: "s1")))
        XCTAssertEqual(saved.state, .ready)
        XCTAssertEqual(saved.lastEvent, HookReducer.interruptedEvent)
        XCTAssertEqual(saved.stateSince, 105)
        XCTAssertFalse(HookRunner.markInterrupted(fileKey: "s1", ifUpdatedAt: saved.updatedAt), "already ready")
    }

    func testHookRecordsTranscriptPath() {
        let input = HookInput(json: ["hook_event_name": "UserPromptSubmit", "session_id": "s",
                                     "transcript_path": "/Users/me/.claude/projects/x/s.jsonl"])!
        guard case .write(let record) = HookReducer.reduce(input, existing: nil, projectDir: "/p", now: 1) else {
            return XCTFail("expected a write")
        }
        XCTAssertEqual(record.transcriptPath, "/Users/me/.claude/projects/x/s.jsonl")
    }
}
