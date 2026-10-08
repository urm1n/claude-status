import AppKit
import StatusCore

/// The usage block at the top of the menu: one labelled bar per window, like Claude Code's `/usage`.
final class UsageMenuView: NSView {
    private struct Row {
        let title: String
        let window: UsageWindow
    }

    private let rows: [Row]
    private let footer: String
    private let now: Double

    private static let width: CGFloat = 300
    private static let inset: CGFloat = 14
    private static let rowHeight: CGFloat = 50
    private static let footerHeight: CGFloat = 22

    init(snapshot: UsageSnapshot, now: Double = Date().timeIntervalSince1970) {
        var rows: [Row] = []
        if let session = snapshot.session { rows.append(Row(title: "Current session", window: session)) }
        if let weekly = snapshot.weekly { rows.append(Row(title: "Weekly limit", window: weekly)) }
        for (model, window) in snapshot.weeklyByModel.sorted(by: { $0.key < $1.key }) {
            rows.append(Row(title: "Weekly · \(model)", window: window))
        }
        self.rows = rows
        self.now = now
        let source = snapshot.source == .anthropic ? "from Anthropic" : "from Claude Code"
        footer = "Updated \(Format.elapsed(since: snapshot.updatedAt)) ago · \(source)"
        let height = CGFloat(rows.count) * Self.rowHeight + Self.footerHeight + 6
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(rows.map { "\($0.title) \(Int($0.window.usedPercentage.rounded())) percent" }
            .joined(separator: ", "))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let titleFont = NSFont.menuFont(ofSize: 0)
        let smallFont = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        let barWidth = bounds.width - Self.inset * 2
        var y: CGFloat = 6

        for row in rows {
            let window = effective(row.window)
            let percent = "\(Int(window.usedPercentage.rounded()))%"
            draw(row.title, at: NSPoint(x: Self.inset, y: y), font: titleFont, color: .labelColor)
            let percentSize = (percent as NSString).size(withAttributes: [.font: titleFont])
            draw(percent, at: NSPoint(x: bounds.width - Self.inset - percentSize.width, y: y),
                 font: titleFont, color: .labelColor)

            let track = NSRect(x: Self.inset, y: y + 20, width: barWidth, height: 6)
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
            let fraction = min(max(window.usedPercentage / 100, 0), 1)
            if fraction > 0 {
                var fill = track
                fill.size.width = max(track.height, track.width * fraction)
                Self.color(for: window.usedPercentage).setFill()
                NSBezierPath(roundedRect: fill, xRadius: 3, yRadius: 3).fill()
            }

            draw(resetText(window), at: NSPoint(x: Self.inset, y: y + 29), font: smallFont, color: .secondaryLabelColor)
            y += Self.rowHeight
        }
        draw(footer, at: NSPoint(x: Self.inset, y: y + 2), font: smallFont, color: .tertiaryLabelColor)
    }

    /// A window whose reset time has passed has started over.
    private func effective(_ window: UsageWindow) -> UsageWindow {
        if let reset = window.resetsAt, reset <= now { return UsageWindow(usedPercentage: 0, resetsAt: nil) }
        return window
    }

    private func resetText(_ window: UsageWindow) -> String {
        guard let reset = window.resetsAt, reset > now else { return "Not started" }
        let seconds = reset - now
        if seconds < 24 * 3600 { return "Resets in \(StatusLineRunner.shortDuration(seconds))" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEjmm")
        return "Resets \(formatter.string(from: Date(timeIntervalSince1970: reset)))"
    }

    private static func color(for percent: Double) -> NSColor {
        if percent >= 90 { return .systemRed }
        if percent >= 75 { return .systemOrange }
        return .controlAccentColor
    }

    private func draw(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }
}
