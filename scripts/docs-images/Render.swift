// Renders the README images in docs/images from the app's own drawing code.
// Run: scripts/make-docs-images.sh
import AppKit

@main
struct RenderDocs {
    @MainActor static func main() throws {
        let out = CommandLine.arguments[1]
        _ = NSApplication.shared
        Pref.registerDefaults()
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            try png(statesStrip(dark: dark, symbols: false), "\(out)/states-\(suffix).png")
            try png(statesStrip(dark: dark, symbols: true), "\(out)/states-symbols-\(suffix).png")
            try png(usagePanel(dark: dark), "\(out)/usage-\(suffix).png")
        }
        try? FileManager.default.removeItem(atPath: "\(out)/app-icon.png")
        try FileManager.default.copyItem(atPath: "build/AppIcon.iconset/icon_256x256@2x.png", toPath: "\(out)/app-icon.png")
    }

    static func png(_ rep: NSBitmapImageRep, _ path: String) throws {
        try? FileManager.default.removeItem(atPath: path)
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    }

    static func canvas(width: CGFloat, height: CGFloat, dark: Bool, draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: 10, yRadius: 10).addClip()
            (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()
            draw()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// A slice of menu bar with each light state and a caption under it.
    static func statesStrip(dark: Bool, symbols: Bool) -> NSBitmapImageRep {
        UserDefaults.standard.set(symbols, forKey: Pref.symbolMode)
        defer { UserDefaults.standard.removeObject(forKey: Pref.symbolMode) }
        let states: [(SessionState?, String)] = [(nil, "No session"), (.ready, "Ready"), (.working, "Working"),
                                                 (.needsInput, "Needs you")]
        let cell: CGFloat = 120, height: CGFloat = 64
        let foreground = dark ? NSColor.white : NSColor.black
        return canvas(width: cell * 4, height: height, dark: dark) {
            (dark ? NSColor(white: 0.2, alpha: 1) : NSColor(white: 0.88, alpha: 1)).setFill()
            NSRect(x: 0, y: height - 30, width: cell * 4, height: 30).fill()
            for (i, (state, label)) in states.enumerated() {
                let image = IconRenderer.statusImage(for: state)
                let rect = NSRect(x: CGFloat(i) * cell + (cell - 22) / 2, y: height - 30 + 4, width: 22, height: 22)
                if image.isTemplate { // what the menu bar does with template images
                    NSImage(size: image.size, flipped: false) { r in
                        image.draw(in: r)
                        foreground.set()
                        r.fill(using: .sourceAtop)
                        return true
                    }.draw(in: rect)
                } else {
                    image.draw(in: rect)
                }
                let text = NSAttributedString(string: label, attributes: [
                    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: foreground.withAlphaComponent(0.75),
                ])
                text.draw(at: NSPoint(x: CGFloat(i) * cell + (cell - text.size().width) / 2, y: 9))
            }
        }
    }

    /// The usage block from the menu, with sample numbers.
    static func usagePanel(dark: Bool) -> NSBitmapImageRep {
        let now = Date().timeIntervalSince1970
        let snapshot = UsageSnapshot(session: UsageWindow(usedPercentage: 23.5, resetsAt: now + 8040),
                                     weekly: UsageWindow(usedPercentage: 78, resetsAt: now + 3.6 * 86400),
                                     source: .anthropic, updatedAt: now - 130)
        let view = UsageMenuView(snapshot: snapshot, now: now)
        let pad: CGFloat = 6
        let size = NSSize(width: view.frame.width + pad * 2, height: view.frame.height + pad * 2)
        let viewRep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            view.cacheDisplay(in: view.bounds, to: viewRep)
        }
        return canvas(width: size.width, height: size.height, dark: dark) {
            viewRep.draw(in: NSRect(x: pad, y: pad, width: view.frame.width, height: view.frame.height))
        }
    }
}
