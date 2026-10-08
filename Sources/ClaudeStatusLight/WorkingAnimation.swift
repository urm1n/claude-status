import AppKit
import QuartzCore

/// Slowly spins the flower in the menu bar while Claude is working.
///
/// It's a Core Animation layer on the status item button, so macOS's render server animates it
/// and this app redraws nothing per frame. The flower has eight petals, so one turn loops seamlessly.
@MainActor
final class WorkingAnimation {
    private var layer: CAShapeLayer?

    /// Seconds per full turn: slow enough to read as "busy", not "loading spinner".
    private let period: CFTimeInterval = 6

    static var isAllowed: Bool {
        Pref.defaults.bool(forKey: Pref.animateWorking)
            && !Pref.defaults.bool(forKey: Pref.symbolMode)
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `leading`: the image sits at the left with text after it (usage %), instead of centered.
    func start(on button: NSStatusBarButton, color: NSColor, leading: Bool = false) {
        stop()
        button.wantsLayer = true
        guard let host = button.layer else { return }

        let size: CGFloat = 18, mark: CGFloat = 15
        // Right after launch the button may not be laid out yet; assume a square menu bar item.
        let thickness = NSStatusBar.system.thickness
        let bounds = button.bounds.isEmpty ? CGRect(x: 0, y: 0, width: thickness, height: thickness) : button.bounds
        let shape = CAShapeLayer()
        if leading {
            // Where the button draws its (placeholder) image; stays put as the text changes.
            button.layoutSubtreeIfNeeded()
            let imageRect = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? .zero
            let midX = imageRect.isEmpty ? 3 + size / 2 : imageRect.midX
            shape.frame = CGRect(x: midX - size / 2, y: (bounds.height - size) / 2, width: size, height: size)
            shape.autoresizingMask = [.layerMaxXMargin, .layerMinYMargin, .layerMaxYMargin]
        } else {
            shape.frame = CGRect(x: (bounds.width - size) / 2, y: (bounds.height - size) / 2, width: size, height: size)
            shape.autoresizingMask = [.layerMinXMargin, .layerMaxXMargin, .layerMinYMargin, .layerMaxYMargin]
        }
        let inset = (size - mark) / 2
        shape.path = BrandMark.path(fitting: NSRect(x: inset, y: inset, width: mark, height: mark)).cgPath
        shape.fillColor = color.cgColor
        shape.strokeColor = NSColor.black.withAlphaComponent(0.3).cgColor
        shape.lineWidth = 0.7
        shape.contentsScale = button.window?.backingScaleFactor ?? 2

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = 2 * Double.pi // clockwise: the status item's layer is flipped (y down)
        spin.duration = period
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        shape.add(spin, forKey: "spin")

        host.addSublayer(shape)
        layer = shape
    }

    func stop() {
        layer?.removeFromSuperlayer()
        layer = nil
    }

    var isRunning: Bool { layer != nil }
}
