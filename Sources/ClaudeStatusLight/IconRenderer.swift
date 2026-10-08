import AppKit
import StatusCore

enum IconRenderer {
    /// The menu bar image: the app's flower mark, filled with the state's color, or as a template
    /// image (tinted to match the menu bar) when no session is open.
    static func statusImage(for state: SessionState?) -> NSImage {
        let image: NSImage
        if let state {
            image = Pref.defaults.bool(forKey: Pref.symbolMode) ? symbol(for: state) : flower(for: state)
        } else {
            image = BrandMark.templateImage()
        }
        image.accessibilityDescription = "Claude: \(state?.label ?? "No session")"
        return image
    }

    /// Small flower for menu rows.
    static func dot(for state: SessionState) -> NSImage {
        flower(color: Pref.color(for: state), canvas: 12, markSize: 11, outline: 0.5)
    }

    /// The flower mark filled with the state's color. A faint outline keeps yellow and green
    /// readable on a light menu bar.
    private static func flower(for state: SessionState) -> NSImage {
        flower(color: Pref.color(for: state), canvas: 18, markSize: 15, outline: 0.7)
    }

    private static func flower(color: NSColor, canvas: CGFloat, markSize: CGFloat, outline: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: canvas, height: canvas), flipped: true) { rect in
            let inset = (rect.width - markSize) / 2
            let path = BrandMark.path(fitting: rect.insetBy(dx: inset, dy: inset))
            color.setFill()
            path.fill()
            path.lineWidth = outline
            NSColor.black.withAlphaComponent(0.3).setStroke()
            path.stroke()
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
            .withSymbolConfiguration(config) ?? flower(for: state)
    }
}
