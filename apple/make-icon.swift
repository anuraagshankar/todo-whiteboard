// Generates the app icon: a whiteboard on an easel with post-it notes stuck on it. Writes the
// iPhone's three opaque 1024×1024 PNGs (default, dark, tinted; iOS rounds the corners) and
// the Mac sizes (Apple's rounded-square template, transparent outside) into AppIcon.appiconset.
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/make-icon apple/make-icon.swift
//   /tmp/make-icon apple/WhiteboardTodo/WhiteboardTodo/Assets.xcassets/AppIcon.appiconset
import AppKit

struct Colors {
    let bg, board, frame: UInt32
    let notes: [UInt32] // post-its: yellow, pink, blue
}

let postIts: [UInt32] = [0xffd84d, 0xff8fb1, 0x7cc8ff]
let light = Colors(bg: 0xc9d3e3, board: 0xffffff, frame: 0x86868b, notes: postIts) // web/style.css: --wallpaper, --note, --muted
let dark = Colors(bg: 0x101820, board: 0x2c2c2e, frame: 0x98989d, notes: postIts)
let tinted = Colors(bg: 0x000000, board: 0x333333, frame: 0xffffff, notes: [0xffffff, 0xbbbbbb, 0x888888]) // iOS recolors by brightness

func color(_ h: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat(h >> 16 & 0xff) / 255, green: CGFloat(h >> 8 & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: 1)
}

// The icon filling the square r: background, easel legs, board, tray, post-its. Proportions of
// the square's side, measured from the top.
func drawIcon(in r: NSRect, _ c: Colors) {
    let s = r.width
    func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: r.minX + x * s, y: r.maxY - (top + h) * s, width: w * s, height: h * s)
    }
    func point(_ x: CGFloat, _ top: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * s, y: r.maxY - top * s) }
    color(c.bg).setFill()
    r.fill()
    let line = 0.032 * s
    color(c.frame).setStroke()
    for (from, to) in [(point(0.31, 0.6), point(0.24, 0.85)), (point(0.69, 0.6), point(0.76, 0.85))] {
        let leg = NSBezierPath()
        leg.move(to: from)
        leg.line(to: to)
        leg.lineWidth = line
        leg.lineCapStyle = .round
        leg.stroke()
    }
    let board = NSBezierPath(roundedRect: rect(0.16, 0.18, 0.68, 0.46).insetBy(dx: line / 2, dy: line / 2), xRadius: 0.03 * s, yRadius: 0.03 * s)
    color(c.board).setFill()
    board.fill()
    board.lineWidth = line
    board.stroke()
    color(c.frame).setFill()
    NSBezierPath(roundedRect: rect(0.13, 0.625, 0.74, 0.045), xRadius: 0.0225 * s, yRadius: 0.0225 * s).fill()

    // Post-it notes stuck on the board, each a little tilted, with a soft shadow.
    for (note, (x, top, degrees)) in zip(c.notes, [(0.33, 0.33, -6.0), (0.61, 0.31, 5.0), (0.52, 0.5, -3.0)]) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: r.minX + x * s, yBy: r.maxY - top * s)
        transform.rotate(byDegrees: degrees)
        transform.concat()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSSize(width: 0, height: -0.008 * s)
        shadow.shadowBlurRadius = 0.014 * s
        shadow.set()
        color(note).setFill()
        let size = 0.17 * s
        NSBezierPath(roundedRect: NSRect(x: -size / 2, y: -size / 2, width: size, height: size), xRadius: 0.008 * s, yRadius: 0.008 * s).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

func png(_ pixels: Int, opaque: Bool, _ draw: (NSRect) -> Void) -> Data {
    // 32 bits per pixel even without alpha: Core Graphics can't draw into packed 24-bit RGB.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: opaque ? 3 : 4,
                               hasAlpha: !opaque, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Mac: the 824/1024 rounded square of Apple's icon template, with its drop shadow.
func macIcon(_ r: NSRect) {
    let k = r.width / 1024
    let body = NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185.4 * k, yRadius: 185.4 * k)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.shadowBlurRadius = 20 * k
    shadow.set()
    color(light.bg).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    drawIcon(in: body, light)
    NSGraphicsContext.restoreGraphicsState()
}

let dir = CommandLine.arguments[1]
func write(_ data: Data, _ name: String) { try! data.write(to: URL(fileURLWithPath: dir + "/" + name)) }

write(png(1024, opaque: true) { drawIcon(in: $0, light) }, "icon.png")
write(png(1024, opaque: true) { drawIcon(in: $0, dark) }, "icon-dark.png")
write(png(1024, opaque: true) { drawIcon(in: $0, tinted) }, "icon-tinted.png")
for pixels in [16, 32, 64, 128, 256, 512, 1024] {
    write(png(pixels, opaque: false, macIcon), "mac-\(pixels).png")
}
