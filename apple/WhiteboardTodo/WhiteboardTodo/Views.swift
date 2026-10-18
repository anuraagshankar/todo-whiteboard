import SwiftUI

// Note sizes: the web's on Mac; bigger on iPhone, for reading and touch.
enum Metrics {
    #if os(iOS)
    static let title: CGFloat = 20
    static let text: CGFloat = 17
    static let box: CGFloat = 18
    static let gap: CGFloat = 12 // between box and text
    static let rowPadding: CGFloat = 6
    static let indent: CGFloat = 30 // sub-items
    static let itemInset: CGFloat = 16 // items sit right of the title, leaving room for the grips
    static let grip = CGSize(width: 28, height: line + 2 * rowPadding) // touch area, clear of the box
    static let gripIcon = CGSize(width: 12, height: 16)
    static let gripOffset = CGPoint(x: -30, y: 0) // nested: x + indent
    static let remove = CGSize(width: 28, height: line)
    static let removeIcon: CGFloat = 18
    static let footerIcon: CGFloat = 22
    static let footerPadding: CGFloat = 6
    #else
    static let title: CGFloat = 17
    static let text: CGFloat = 15
    static let box: CGFloat = 15
    static let gap: CGFloat = 8
    static let rowPadding: CGFloat = 2
    static let indent: CGFloat = 22
    static let itemInset: CGFloat = 0
    static let grip = CGSize(width: 11, height: 18)
    static let gripIcon = CGSize(width: 12, height: 14)
    static let gripOffset = CGPoint(x: -14, y: 3)
    static let remove = CGSize(width: 16, height: 21)
    static let removeIcon: CGFloat = 15
    static let footerIcon: CGFloat = 16
    static let footerPadding: CGFloat = 2
    #endif
    static let line = text * 1.4 // line height
}

// The minimal horizontal rule between a note's title, body and footer.
struct Rule: View {
    @Environment(\.palette) private var p

    var body: some View {
        p.border.frame(height: 1).padding(.vertical, 8)
    }
}

// Outlined, never filled: a thin gray square, with a gray tick inside when marked.
struct Checkbox: View {
    let done: Bool
    @Environment(\.palette) private var p

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .strokeBorder(p.muted, lineWidth: 1.5)
            .overlay {
                if done {
                    IconShape(path: Icon.tick)
                        .stroke(p.muted, style: StrokeStyle(lineWidth: (Metrics.box - 3) / 8, lineCap: .round, lineJoin: .round))
                        .padding(1.5)
                }
            }
            .frame(width: Metrics.box, height: Metrics.box)
            .padding(.top, (Metrics.line - Metrics.box) / 2) // centres the box on the first line of text
    }
}

// Round floating button (+, theme toggle): the same surface as the notes, so it follows the theme.
struct FloatingButton: View {
    let icon: Path
    let size: CGFloat
    let iconSize: CGFloat
    let stroke: CGFloat
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            IconView(path: icon, size: iconSize, stroke: stroke)
                .foregroundStyle(p.text)
                .frame(width: size, height: size)
                .background {
                    Circle().fill(p.note).shadow(color: p.shadow, radius: 4, y: 2)
                    Circle().strokeBorder(p.border)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

// Small icon button in a note's footer; darker on hover.
struct FooterButton: View {
    let icon: Path
    let help: String
    let action: () -> Void
    @Environment(\.palette) private var p
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IconView(path: icon, size: Metrics.footerIcon)
                .padding(Metrics.footerPadding)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(hovering ? p.text : p.muted)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
