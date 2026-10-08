import XCTest
@testable import StatusCore

final class UsageTests: XCTestCase {
    func testStatusLinePayload() {
        let json: [String: Any] = [
            "session_id": "s",
            "rate_limits": [
                "five_hour": ["used_percentage": 23.5, "resets_at": 1_738_425_600],
                "seven_day": ["used_percentage": 41.2, "resets_at": 1_738_857_600],
            ],
        ]
        let snapshot = UsageSnapshot.fromStatusLine(json, now: 1_738_420_000)
        XCTAssertEqual(snapshot?.session, UsageWindow(usedPercentage: 23.5, resetsAt: 1_738_425_600))
        XCTAssertEqual(snapshot?.weekly?.usedPercentage, 41.2)
        XCTAssertEqual(snapshot?.source, .statusLine)
        XCTAssertEqual(StatusLineRunner.compactLine(snapshot!, now: 1_738_420_000), "Session 24% · resets 1h 33m   Week 41%")
    }

    func testStatusLineWithoutLimits() {
        XCTAssertNil(UsageSnapshot.fromStatusLine(["session_id": "s"], now: 0), "API-key users have no rate_limits")
        XCTAssertNil(UsageSnapshot.fromStatusLine(["rate_limits": [String: Any]()], now: 0))
    }

    func testAnthropicPayload() {
        let json: [String: Any] = [
            "five_hour": ["utilization": 6.0, "resets_at": "2025-11-04T04:59:59.943648+00:00"],
            "seven_day": ["utilization": 35, "resets_at": "2025-11-06T03:59:59Z"],
            "seven_day_opus": ["utilization": 12.0, "resets_at": "2025-11-06T03:59:59.5+00:00"],
            "seven_day_sonnet": NSNull(),
            "seven_day_oauth_apps": NSNull(),
        ]
        let snapshot = UsageSnapshot.fromAnthropic(json, now: 0)
        XCTAssertEqual(snapshot?.session?.usedPercentage, 6)
        XCTAssertEqual(snapshot?.session?.resetsAt ?? 0, 1_762_232_399.943, accuracy: 0.01)
        XCTAssertEqual(snapshot?.weekly?.resetsAt, 1_762_401_599)
        XCTAssertEqual(snapshot?.weeklyByModel.keys.sorted(), ["Opus"])
        XCTAssertEqual(snapshot?.source, .anthropic)
    }

    func testShortDuration() {
        XCTAssertEqual(StatusLineRunner.shortDuration(30), "1m")
        XCTAssertEqual(StatusLineRunner.shortDuration(3 * 3600 + 5 * 60), "3h 5m")
        XCTAssertEqual(StatusLineRunner.shortDuration(2 * 86400 + 4 * 3600), "2d 4h")
    }
}

final class LimitWarningTests: XCTestCase {
    private func snapshot(session: Double, weekly: Double, sessionReset: Double = 5_000) -> UsageSnapshot {
        UsageSnapshot(session: UsageWindow(usedPercentage: session, resetsAt: sessionReset),
                      weekly: UsageWindow(usedPercentage: weekly, resetsAt: 900_000),
                      source: .statusLine, updatedAt: 0)
    }

    func testWarnsOncePerPeriodAt90Percent() {
        var warned: [String: Double] = [:]
        var result = LimitWarnings.due(in: snapshot(session: 85, weekly: 40), warned: warned, now: 1_000)
        XCTAssertTrue(result.warnings.isEmpty)

        result = LimitWarnings.due(in: snapshot(session: 90, weekly: 40), warned: result.warned, now: 1_000)
        XCTAssertEqual(result.warnings.map(\.key), ["session"])
        warned = result.warned

        result = LimitWarnings.due(in: snapshot(session: 97, weekly: 40), warned: warned, now: 2_000)
        XCTAssertTrue(result.warnings.isEmpty, "already warned in this window")

        // After the reset, the next window can warn again.
        result = LimitWarnings.due(in: snapshot(session: 92, weekly: 40, sessionReset: 23_000),
                                   warned: result.warned, now: 6_000)
        XCTAssertEqual(result.warnings.map(\.key), ["session"])
    }

    func testWeeklyAndExpiredWindows() {
        let result = LimitWarnings.due(in: snapshot(session: 99, weekly: 91, sessionReset: 500), warned: [:], now: 1_000)
        XCTAssertEqual(result.warnings.map(\.key), ["weekly"], "a session window that already reset is back to 0%")
        XCTAssertEqual(result.warnings.first?.name, "Weekly")
    }
}
