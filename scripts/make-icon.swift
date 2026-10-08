// Renders Resources/AppIcon.icns. Run: swift scripts/make-icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(white: 0.20, alpha: 1), ending: NSColor(white: 0.08, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    // Three small lights (red, yellow, green) above one large glowing green light.
    let small = s * 0.075
    let colors: [NSColor] = [.systemRed, .systemYellow, .systemGreen]
    for (i, color) in colors.enumerated() {
        let x = s * 0.5 + CGFloat(i - 1) * small * 1.8 - small / 2
        color.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: s * 0.7, width: small, height: small)).fill()
    }
    let d = s * 0.36
    let light = NSRect(x: (s - d) / 2, y: s * 0.22, width: d, height: d)
    NSGradient(colors: [NSColor.systemGreen.withAlphaComponent(0.45), .clear])!
        .draw(in: NSBezierPath(ovalIn: light.insetBy(dx: -d * 0.25, dy: -d * 0.25)), relativeCenterPosition: .zero)
    NSGradient(starting: NSColor(red: 0.55, green: 1, blue: 0.6, alpha: 1),
               ending: NSColor(red: 0.1, green: 0.7, blue: 0.3, alpha: 1))!
        .draw(in: NSBezierPath(ovalIn: light), relativeCenterPosition: NSPoint(x: -0.3, y: 0.4))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print(iconset.path)
