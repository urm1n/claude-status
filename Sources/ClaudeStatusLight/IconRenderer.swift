import AppKit
import StatusCore

enum IconRenderer {
    /// The menu bar image. Colored states are drawn with a faint outline so yellow and green stay
    /// readable on a light menu bar; "no session" is a template ring that follows the menu bar color.
    static func statusImage(for state: SessionState?) -> NSImage {
        let image = Pref.defaults.bool(forKey: Pref.symbolMode) ? symbol(for: state) : circle(for: state)
        image.accessibilityDescription = "Claude: \(state?.label ?? "No session")"
        return image
    }

    /// Small dot for menu rows.
    static func dot(for state: SessionState) -> NSImage {
        let color = Pref.color(for: state)
        return NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            color.setFill()
            path.fill()
            NSColor.black.withAlphaComponent(0.2).setStroke()
            path.lineWidth = 0.5
            path.stroke()
            return true
        }
    }

    private static func circle(for state: SessionState?) -> NSImage {
        let color = state.map(Pref.color(for:))
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let diameter: CGFloat = 12
            let frame = NSRect(x: (rect.width - diameter) / 2, y: (rect.height - diameter) / 2,
                               width: diameter, height: diameter)
            if let color {
                let path = NSBezierPath(ovalIn: frame)
                color.setFill()
                path.fill()
                let edge = NSBezierPath(ovalIn: frame.insetBy(dx: 0.35, dy: 0.35))
                edge.lineWidth = 0.7
                NSColor.black.withAlphaComponent(0.3).setStroke()
                edge.stroke()
            } else {
                let ring = NSBezierPath(ovalIn: frame.insetBy(dx: 1, dy: 1))
                ring.lineWidth = 1.6
                NSColor.black.withAlphaComponent(0.55).setStroke()
                ring.stroke()
            }
            return true
        }
        image.isTemplate = color == nil
        return image
    }

    /// Accessibility mode: a different shape per state, not just a different color.
    private static func symbol(for state: SessionState?) -> NSImage {
        let name: String
        switch state {
        case nil: name = "circle.dashed"
        case .ready: name = "checkmark.circle.fill"
        case .working: name = "ellipsis.circle.fill"
        case .needsInput: name = "exclamationmark.circle.fill"
        }
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let state {
            let fill = Pref.color(for: state)
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [fill.isLight ? .black : .white, fill]))
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? circle(for: state)
        image.isTemplate = state == nil
        return image
    }
}
