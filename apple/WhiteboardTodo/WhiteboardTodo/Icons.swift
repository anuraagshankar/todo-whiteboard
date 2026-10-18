import SwiftUI

// Line icons from web/app.js (ICONS), drawn from the same SVG path data on its 24×24 grid.
enum Icon {
    static let sun = path(circle(12, 12, 4) + "M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4")
    static let moon = path("M20 14.5A8 8 0 0 1 9.5 4 8 8 0 1 0 20 14.5z")
    static let checklist = path("M4 4h4a1 1 0 0 1 1 1v4a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1z" + "M4.5 7l1.2 1.2L8 5.8M3 15h6v6H3zM13 7h8M13 18h8")
    static let text = path("M4 6h16M4 12h16M4 18h10")
    static let trash = path("M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3")
    static let tick = path("M6 12.5l4 4 8-9")
    static let close = path("M6 6l12 12M18 6L6 18")
    static let back = path("M15 5l-7 7 7 7")
    static let plus = path("M12 5v14M5 12h14") // the + button, from web/index.html
    static let grip = path([8.5, 15.5].flatMap { x in [5.0, 12, 19].map { circle(x, $0, 2) } }.joined())
    static let broom = path(
        "M18 2l-3.4 7.5M11.4 11.4c.3-1.6 1.7-2.4 3.1-2s2.1 1.9 1.5 3.4zM13.4 13c-1 2.1-1.8 4.6-1.9 7.2" +
        "M11.4 11.4C9.2 13.6 7.4 16.6 6.4 20.2q1.4-1.2 2.6.4 1.1-1.6 2.5.3 1.1-1.6 2.5 0 1.1-1.4 2.6-.6C16.9 17.2 16.6 15 16 12.8"
    )

    // SVG <circle> as path data.
    private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String {
        "M\(cx - r) \(cy)a\(r) \(r) 0 1 0 \(2 * r) 0a\(r) \(r) 0 1 0 \(-2 * r) 0z"
    }

    // Parses SVG path data: the commands the icons use (M L H V C S Q A Z, absolute or
    // relative), with arcs circular and unrotated.
    private static func path(_ d: String) -> Path {
        var tokens: [String] = []
        var number = ""
        func flush() {
            if !number.isEmpty { tokens.append(number) }
            number = ""
        }
        for ch in d {
            if ch.isLetter {
                flush()
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                flush()
            } else if ch == "-" || (ch == "." && number.contains(".")) {
                flush()
                number = String(ch)
            } else {
                number.append(ch)
            }
        }
        flush()

        var path = Path()
        var i = 0
        var command = "M"
        var p = CGPoint.zero
        var start = CGPoint.zero
        var control: CGPoint? // last cubic control point, reflected by S
        func num() -> Double {
            i += 1
            return Double(tokens[i - 1])!
        }
        while i < tokens.count {
            if Double(tokens[i]) == nil {
                command = tokens[i]
                i += 1
            }
            let rel = command == command.lowercased()
            let from = p
            func point() -> CGPoint {
                let x = num(), y = num()
                return rel ? CGPoint(x: from.x + x, y: from.y + y) : CGPoint(x: x, y: y)
            }
            let previousControl = control
            control = nil
            switch command.uppercased() {
            case "M":
                p = point()
                start = p
                path.move(to: p)
                command = rel ? "l" : "L"
            case "L":
                p = point()
                path.addLine(to: p)
            case "H":
                p.x = (rel ? p.x : 0) + num()
                path.addLine(to: p)
            case "V":
                p.y = (rel ? p.y : 0) + num()
                path.addLine(to: p)
            case "C", "S":
                let c1 = command.uppercased() == "C" ? point() : previousControl.map { CGPoint(x: 2 * from.x - $0.x, y: 2 * from.y - $0.y) } ?? from
                let c2 = point()
                p = point()
                path.addCurve(to: p, control1: c1, control2: c2)
                control = c2
            case "Q":
                let c = point()
                p = point()
                path.addQuadCurve(to: p, control: c)
            case "A":
                let r = num()
                _ = (num(), num()) // ry (= rx) and rotation
                let large = num() == 1, sweep = num() == 1
                p = point()
                arc(&path, from: from, to: p, radius: r, large: large, sweep: sweep)
            default: // Z
                path.closeSubpath()
                p = start
            }
        }
        return path
    }

    // SVG arc endpoints to a center (SVG spec, appendix B.2.4, for rx = ry and no rotation).
    private static func arc(_ path: inout Path, from a: CGPoint, to b: CGPoint, radius: Double, large: Bool, sweep: Bool) {
        let hx = (a.x - b.x) / 2, hy = (a.y - b.y) / 2
        let d2 = hx * hx + hy * hy
        let r = max(radius, d2.squareRoot())
        let k = (large == sweep ? -1.0 : 1.0) * max(0, (r * r - d2) / d2).squareRoot()
        let center = CGPoint(x: (a.x + b.x) / 2 + k * hy, y: (a.y + b.y) / 2 - k * hx)
        let startAngle = atan2(a.y - center.y, a.x - center.x)
        let endAngle = atan2(b.y - center.y, b.x - center.x)
        path.addArc(center: center, radius: r, startAngle: .radians(startAngle), endAngle: .radians(endAngle), clockwise: !sweep)
    }
}

// An icon path scaled from the 24×24 grid into its frame (centered, like an SVG viewBox).
nonisolated struct IconShape: Shape {
    let path: Path

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        return path.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: rect.midX - 12 * s, ty: rect.midY - 12 * s))
    }
}

// A line icon `size` points square; `stroke` is in grid units, like the web's stroke-width.
struct IconView: View {
    let path: Path
    var size: CGFloat = 16
    var stroke: CGFloat = 1.8

    var body: some View {
        IconShape(path: path)
            .stroke(style: StrokeStyle(lineWidth: stroke * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}
