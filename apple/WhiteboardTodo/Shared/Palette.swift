import SwiftUI

// Colors from web/style.css, for the current light or dark mode: @Environment(\.palette).
nonisolated struct Palette: Equatable {
    let bg, dot, note, card, border, shadow, text, muted, danger, pill: Color

    init(_ scheme: ColorScheme) {
        let dark = scheme == .dark
        bg = Color(dark ? 0x1c1c1e : 0xf5f5f7)
        dot = Color(dark ? 0x3a3a3c : 0xd2d2d7)
        note = Color(dark ? 0x2c2c2e : 0xffffff)
        card = note.opacity(0.5) // todo cards: the note color at 50%, so the dots show through
        border = Color(dark ? 0x3a3a3c : 0xd2d2d7)
        shadow = .black.opacity(dark ? 0.4 : 0.08)
        text = Color(dark ? 0xf5f5f7 : 0x1d1d1f)
        muted = Color(dark ? 0x98989d : 0x86868b)
        danger = Color(dark ? 0xff453a : 0xff3b30)
        pill = Color(dark ? 0x3a3a3c : 0xefeff4)
    }
}

nonisolated extension Color {
    init(_ hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}

extension EnvironmentValues {
    nonisolated var palette: Palette { Palette(colorScheme) }
}

// The dot grid behind the notes: a 1pt dot in the middle of every 24pt square.
nonisolated struct DotGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for y in stride(from: rect.minY + 12, to: rect.maxY, by: 24) {
            for x in stride(from: rect.minX + 12, to: rect.maxX, by: 24) {
                path.addEllipse(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
            }
        }
        return path
    }
}
