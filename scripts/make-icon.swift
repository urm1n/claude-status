// Renders the app icon from the flower mark (Resources/AppIcon.svg) into an .iconset.
// scripts/build-app.sh compiles this together with Sources/ClaudeStatusLight/BrandMark.swift:
//   swiftc -parse-as-library scripts/make-icon.swift Sources/ClaudeStatusLight/BrandMark.swift -o build/make-icon
//   build/make-icon <output dir>     → <output dir>/AppIcon.iconset
import AppKit

@main
struct MakeIcon {
    static func main() throws {
        let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build")
        let iconset = out.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for base in [16, 32, 128, 256, 512] {
            try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
            try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
        }
        print(iconset.path)
    }

    /// macOS icon grid: an 824-pt rounded tile centred on a 1024 canvas, with a soft shadow.
    /// The flower keeps its proportion from the SVG (784 of 1024 → ~77% of the tile).
    static func render(_ px: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 1024, height: 1024)
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.current = context
        // Draw y-down like the SVG.
        context.cgContext.translateBy(x: 0, y: 1024)
        context.cgContext.scaleBy(x: 1, y: -1)

        let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 20
        shadow.shadowOffset = NSSize(width: 0, height: 10) // y-down context: positive is downwards
        shadow.set()
        NSColor.black.setFill()
        tilePath.fill()
        NSGraphicsContext.restoreGraphicsState()

        let markSize = tile.width * (783.736 / 1024)
        let markRect = NSRect(x: tile.midX - markSize / 2, y: tile.midY - markSize / 2, width: markSize, height: markSize)
        BrandMark.color.setFill()
        BrandMark.path(fitting: markRect).fill()

        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }
}
