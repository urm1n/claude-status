import AppKit

/// The app's mark: the eight-petal flower from `Resources/AppIcon.svg`, drawn from its SVG path
/// so it stays sharp at menu bar size. Also used by `scripts/make-icon.swift` for the app icon.
enum BrandMark {
    static let color = NSColor(srgbRed: 0xE6 / 255, green: 0x6F / 255, blue: 0x46 / 255, alpha: 1)

    /// The `d` attribute of the flower in AppIcon.svg (1024 × 1024 canvas, y pointing down).
    static let svgPath = """
    M657.842 234.286C693.951 198.177 752.474 198.211 788.59 234.328C825.86 271.598 825.884 330.142 789.791 366.235\
    L774.616 381.41C754.023 402.003 761.007 418.698 790.062 418.698H811.522C862.588 418.698 903.945 460.104 903.945 511.18\
    C903.945 563.888 862.566 605.302 811.522 605.302H790.062C760.938 605.302 754.072 622.046 774.616 642.59L789.791 657.765\
    C825.9 693.874 825.866 752.396 789.75 788.513C752.479 825.783 693.936 825.807 657.842 789.714L642.668 774.539\
    C622.074 753.945 605.379 760.93 605.379 789.984V811.444C605.379 862.51 563.974 903.868 512.897 903.868\
    C460.189 903.868 418.775 862.489 418.775 811.444V789.984C418.775 760.86 402.032 753.995 381.487 774.539L366.313 789.714\
    C330.203 825.823 271.681 825.789 235.565 789.672C198.294 752.402 198.27 693.858 234.364 657.765L249.538 642.59\
    C270.132 621.996 263.147 605.302 234.093 605.302H212.633C161.567 605.302 120.209 563.896 120.209 512.82\
    C120.209 460.112 161.589 418.698 212.633 418.698H234.093C263.217 418.698 270.083 401.954 249.538 381.41L234.364 366.235\
    C198.255 330.126 198.289 271.604 234.405 235.487C271.676 198.217 330.219 198.193 366.313 234.286L381.487 249.461\
    C402.081 270.055 418.775 263.07 418.775 234.015V212.556C418.775 161.49 460.181 120.132 511.257 120.132\
    C563.966 120.132 605.379 161.512 605.379 212.556V234.015C605.379 263.14 622.123 270.006 642.668 249.461L657.842 234.286Z
    """

    /// The flower in SVG coordinates. Parsed once.
    static let shape: NSBezierPath = parse(svgPath)

    /// The flower scaled to fit `rect`, for drawing in a flipped (y-down) context.
    static func path(fitting rect: NSRect) -> NSBezierPath {
        let bounds = shape.bounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var transform = AffineTransform.identity
        transform.translate(x: rect.midX, y: rect.midY)
        transform.scale(scale)
        transform.translate(x: -bounds.midX, y: -bounds.midY)
        let path = shape.copy() as! NSBezierPath
        path.transform(using: transform)
        return path
    }

    /// Monochrome menu bar version: macOS tints it to match the menu bar.
    static func templateImage(size: CGFloat = 18, markSize: CGFloat = 15) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let inset = (rect.width - markSize) / 2
            NSColor.black.setFill()
            path(fitting: rect.insetBy(dx: inset, dy: inset)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: SVG path parsing (M, L, H, V, C, S, Q, Z; absolute and relative)

    static func parse(_ data: String) -> NSBezierPath {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        var tokens = tokenize(data)[...]
        var command: Character = "M"
        var current = NSPoint.zero
        var start = NSPoint.zero
        var lastControl: NSPoint?

        func number() -> CGFloat {
            if case .number(let value)? = tokens.first { tokens.removeFirst(); return value }
            return 0
        }
        func point(relative: Bool) -> NSPoint {
            let x = number(), y = number()
            return relative ? NSPoint(x: current.x + x, y: current.y + y) : NSPoint(x: x, y: y)
        }

        while let token = tokens.first {
            let remaining = tokens.count
            if case .command(let c) = token {
                command = c
                tokens.removeFirst()
            }
            defer { if tokens.count == remaining { tokens.removeFirst() } } // malformed data: always make progress
            let relative = command.isLowercase
            switch command.uppercased().first! {
            case "M":
                current = point(relative: relative)
                start = current
                path.move(to: current)
                command = relative ? "l" : "L" // further pairs are implicit line-tos
                lastControl = nil
            case "L":
                current = point(relative: relative)
                path.line(to: current)
                lastControl = nil
            case "H":
                current.x = relative ? current.x + number() : number()
                path.line(to: current)
                lastControl = nil
            case "V":
                current.y = relative ? current.y + number() : number()
                path.line(to: current)
                lastControl = nil
            case "C":
                let c1 = point(relative: relative), c2 = point(relative: relative), end = point(relative: relative)
                path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                lastControl = c2
                current = end
            case "S":
                let c1 = lastControl.map { NSPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = point(relative: relative), end = point(relative: relative)
                path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                lastControl = c2
                current = end
            case "Q":
                let control = point(relative: relative), end = point(relative: relative)
                let c1 = NSPoint(x: current.x + 2 / 3 * (control.x - current.x), y: current.y + 2 / 3 * (control.y - current.y))
                let c2 = NSPoint(x: end.x + 2 / 3 * (control.x - end.x), y: end.y + 2 / 3 * (control.y - end.y))
                path.curve(to: end, controlPoint1: c1, controlPoint2: c2)
                lastControl = nil
                current = end
            case "Z":
                path.close()
                current = start
                lastControl = nil
            default:
                break // unsupported command: its arguments are skipped one by one
            }
        }
        return path
    }

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        var numberText = ""
        func flush() {
            if let value = Double(numberText) { tokens.append(.number(CGFloat(value))) }
            numberText = ""
        }
        for char in data {
            if char.isLetter && char != "e" && char != "E" {
                flush()
                tokens.append(.command(char))
            } else if char == "-" && !numberText.isEmpty && !numberText.hasSuffix("e") && !numberText.hasSuffix("E") {
                flush()
                numberText = "-"
            } else if char == "." && numberText.contains(".") && !numberText.contains("e") {
                flush()
                numberText = "."
            } else if char.isNumber || char == "." || char == "-" || char == "e" || char == "E" || char == "+" {
                numberText.append(char)
            } else {
                flush()
            }
        }
        flush()
        return tokens
    }
}
