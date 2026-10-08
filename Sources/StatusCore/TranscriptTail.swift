import Foundation

/// Detects that the user stopped Claude (Esc / Ctrl+C, or Esc at a permission prompt).
///
/// No hook fires for that, but Claude Code appends a user message whose text starts with
/// "[Request interrupted by user" to the session transcript. This reads only the end of the
/// file, looks only at entry types and that marker, and keeps nothing.
public enum TranscriptTail {
    static let marker = "[Request interrupted by user"
    static let tailBytes = 64 * 1024

    /// When the transcript currently ends with an interrupt, the time it happened (epoch seconds).
    public static func interruptTime(_ url: URL) -> Double? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        return interruptTime(tail: data, isPartial: start > 0)
    }

    /// The last conversation entry (user or assistant, ignoring bookkeeping lines) is the marker.
    static func interruptTime(tail data: Data, isPartial: Bool) -> Double? {
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if isPartial, !lines.isEmpty { lines.removeFirst() } // probably cut mid-line
        for line in lines.reversed() {
            guard let entry = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String: Any],
                  let type = entry["type"] as? String else { continue }
            guard type == "user" || type == "assistant" else { continue }
            if (entry["isMeta"] as? Bool) == true { continue }
            guard type == "user", let message = entry["message"] as? [String: Any],
                  texts(in: message["content"]).contains(where: { $0.hasPrefix(marker) }) else { return nil }
            return (entry["timestamp"] as? String).flatMap(parseTimestamp) ?? Date().timeIntervalSince1970
        }
        return nil
    }

    static func parseTimestamp(_ string: String) -> Double? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)?.timeIntervalSince1970
    }

    private static func texts(in content: Any?) -> [String] {
        if let text = content as? String { return [text] }
        guard let blocks = content as? [[String: Any]] else { return [] }
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }
}
