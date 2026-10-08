import Foundation

/// One rate-limit window, e.g. the 5-hour session window or the weekly limit.
public struct UsageWindow: Codable, Equatable, Sendable {
    /// 0...100 (can exceed 100 when over the limit).
    public var usedPercentage: Double
    /// Unix epoch seconds; nil when the window hasn't started yet.
    public var resetsAt: Double?

    public init(usedPercentage: Double, resetsAt: Double?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

/// Subscription usage as Claude Code's `/usage` shows it.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public enum Source: String, Codable, Sendable {
        case statusLine
        case anthropic
    }

    /// The rolling 5-hour window ("current session").
    public var session: UsageWindow?
    /// The 7-day window across all models ("weekly limit").
    public var weekly: UsageWindow?
    /// Per-model weekly windows, when the account has them (e.g. "Opus", "Sonnet").
    public var weeklyByModel: [String: UsageWindow]
    public var source: Source
    public var updatedAt: Double

    public init(session: UsageWindow?, weekly: UsageWindow?, weeklyByModel: [String: UsageWindow] = [:],
                source: Source, updatedAt: Double) {
        self.session = session
        self.weekly = weekly
        self.weeklyByModel = weeklyByModel
        self.source = source
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { session == nil && weekly == nil && weeklyByModel.isEmpty }

    /// From the status line JSON: `rate_limits.five_hour` / `rate_limits.seven_day`,
    /// each `{ used_percentage, resets_at (epoch seconds) }`. Only Pro/Max sessions include it.
    public static func fromStatusLine(_ json: [String: Any], now: Double) -> UsageSnapshot? {
        guard let limits = json["rate_limits"] as? [String: Any] else { return nil }
        let snapshot = UsageSnapshot(session: window(limits["five_hour"]), weekly: window(limits["seven_day"]),
                                     source: .statusLine, updatedAt: now)
        return snapshot.isEmpty ? nil : snapshot
    }

    /// From the endpoint behind `/usage`: `five_hour`, `seven_day`, `seven_day_<model>`,
    /// each `{ utilization, resets_at (ISO 8601) }` or null.
    public static func fromAnthropic(_ json: [String: Any], now: Double) -> UsageSnapshot? {
        var byModel: [String: UsageWindow] = [:]
        for (key, value) in json where key.hasPrefix("seven_day_") {
            let model = String(key.dropFirst("seven_day_".count))
            guard ["opus", "sonnet"].contains(model), let window = window(value),
                  window.usedPercentage > 0 || window.resetsAt != nil else { continue }
            byModel[model.capitalized] = window
        }
        let snapshot = UsageSnapshot(session: window(json["five_hour"]), weekly: window(json["seven_day"]),
                                     weeklyByModel: byModel, source: .anthropic, updatedAt: now)
        return snapshot.isEmpty ? nil : snapshot
    }

    /// Accepts both shapes: `used_percentage` or `utilization`; epoch seconds or ISO 8601 dates.
    static func window(_ value: Any?) -> UsageWindow? {
        guard let dict = value as? [String: Any] else { return nil }
        guard let used = number(dict["used_percentage"]) ?? number(dict["utilization"]) else { return nil }
        return UsageWindow(usedPercentage: used, resetsAt: date(dict["resets_at"]))
    }

    static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    static func date(_ value: Any?) -> Double? {
        if let seconds = number(value) { return seconds > 1e12 ? seconds / 1000 : seconds }
        guard let string = value as? String else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date.timeIntervalSince1970 }
        // Microsecond precision ("…59.943648+00:00") isn't accepted by the formatter; trim to milliseconds.
        if let dot = string.firstIndex(of: "."),
           let zone = string[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            let fraction = string[string.index(after: dot)..<zone].prefix(3)
            let trimmed = string[..<dot] + "." + fraction + string[zone...]
            if let date = withFraction.date(from: String(trimmed)) { return date.timeIntervalSince1970 }
        }
        let plain = ISO8601DateFormatter()
        return plain.date(from: string)?.timeIntervalSince1970
    }
}

/// `csl-hook statusline`: Claude Code's status line command. Records the rate limits, then
/// shows the user's own status line (if they had one) or a compact usage line.
public enum StatusLineRunner {
    /// Returns the text to print when there's no chained command.
    public static func record(payload: Data, now: Double = Date().timeIntervalSince1970) -> String {
        guard let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
              let snapshot = UsageSnapshot.fromStatusLine(json, now: now) else { return "" }
        try? FileManager.default.createDirectory(at: Paths.usageDir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            let tmp = Paths.usageDir.appendingPathComponent(".statusline.\(getpid()).tmp")
            if (try? data.write(to: tmp)) != nil, rename(tmp.path, Paths.statusLineUsageFile.path) != 0 {
                try? FileManager.default.removeItem(at: tmp)
            }
        }
        return compactLine(snapshot, now: now)
    }

    /// e.g. "Session 23% · resets 2h 14m   Week 41%"
    public static func compactLine(_ snapshot: UsageSnapshot, now: Double) -> String {
        var parts: [String] = []
        if let session = snapshot.session {
            var part = "Session \(Int(session.usedPercentage.rounded()))%"
            if let reset = session.resetsAt, reset > now { part += " · resets \(shortDuration(reset - now))" }
            parts.append(part)
        }
        if let weekly = snapshot.weekly { parts.append("Week \(Int(weekly.usedPercentage.rounded()))%") }
        return parts.joined(separator: "   ")
    }

    public static func shortDuration(_ seconds: Double) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d \(hours % 24)h"
    }

    /// The user's previous status line command, saved when ours was installed.
    public static func chainedCommand() -> String? {
        guard let data = try? Data(contentsOf: Paths.statusLineChainFile),
              let value = try? JSONValue.parse(data) else { return nil }
        guard let command = value["command"]?.string, !command.isEmpty else { return nil }
        return command
    }
}
