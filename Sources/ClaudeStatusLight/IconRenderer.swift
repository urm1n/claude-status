import AppKit
import StatusCore

enum IconRenderer {
    /// The menu bar image. Colored states are drawn with a faint outline so yellow and green stay
    /// readable on a light menu bar; "no session" is the app's flower mark as a template image,
    /// which macOS tints to match the menu bar.
    static func statusImage(for state: SessionState?) -> NSImage {
        let image: NSImage
        if let state {
            image = Pref.defaults.bool(forKey: Pref.symbolMode) ? symbol(for: state) : circle(for: state)
        } else {
            image = BrandMark.templateImage()
        }
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

    private static func circle(for state: SessionState) -> NSImage {
        let color = Pref.color(for: state)
        return NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let diameter: CGFloat = 12
            let frame = NSRect(x: (rect.width - diameter) / 2, y: (rect.height - diameter) / 2,
                               width: diameter, height: diameter)
            color.setFill()
            NSBezierPath(ovalIn: frame).fill()
            let edge = NSBezierPath(ovalIn: frame.insetBy(dx: 0.35, dy: 0.35))
            edge.lineWidth = 0.7
            NSColor.black.withAlphaComponent(0.3).setStroke()
            edge.stroke()
            return true
        }
    }

    /// Accessibility mode: a different shape per state, not just a different color.
    private static func symbol(for state: SessionState) -> NSImage {
        let name: String
        switch state {
        case .ready: name = "checkmark.circle.fill"
        case .working: name = "ellipsis.circle.fill"
        case .needsInput: name = "exclamationmark.circle.fill"
        }
        let fill = Pref.color(for: state)
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [fill.isLight ? .black : .white, fill]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? circle(for: state)
    }
}
