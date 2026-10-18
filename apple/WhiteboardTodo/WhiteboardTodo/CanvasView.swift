#if os(macOS)
import SwiftUI

// Mac: the free-form canvas of notes on a dot grid, with the theme toggle and + button.
struct CanvasView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.colorScheme) private var scheme
    @State private var theme: ColorScheme? // follows the system until toggled
    @State private var size = CGSize.zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            DotGrid()
                .fill(p.dot)
                .contentShape(.rect)
                .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
            ForEach(store.notes.filter { $0.x != nil }) { note in
                NoteView(id: note.id, canvas: size).zIndex(Double(note.z))
            }
        }
        .coordinateSpace(.named("canvas"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.bg)
        .onGeometryChange(for: CGSize.self, of: \.size) {
            size = $0
            store.canvas = $0
            store.placeNew()
        }
        .task(id: store.notes.filter { $0.x == nil }.map(\.id)) { store.placeNew() }
        .overlay(alignment: .topTrailing) {
            // Shows the mode a click switches to.
            FloatingButton(icon: scheme == .dark ? Icon.sun : Icon.moon, size: 36, iconSize: 18, stroke: 1.8) {
                theme = scheme == .dark ? .light : .dark
            }
            .help("Toggle light/dark mode")
            .padding(16)
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(icon: Icon.plus, size: 48, iconSize: 22, stroke: 2.2) { store.addNote() }
                .help("Add note")
                .padding(24)
        }
        .preferredColorScheme(theme)
        .task { store.start() }
    }
}

// A note on the canvas: dragged by its background, resized from any edge or corner. Its
// height follows its content, from the starting height up to 75% of the window, unless
// the height was resized.
private struct NoteView: View {
    let id: UUID
    let canvas: CGSize
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @State private var natural: CGFloat = 0
    @State private var start: (x: Double, y: Double, w: Double, h: Double)? // when a move or resize began
    @State private var moving = false

    var body: some View {
        if let note = store.note(id) {
            let height = note.h ?? min(max(natural + 20, Note.height), canvas.height * 0.75)
            NoteEditor(id: id, natural: $natural)
                .padding(EdgeInsets(top: 11, leading: 17, bottom: 9, trailing: 13)) // the web's padding, plus the 1pt border
                .frame(width: note.w, height: height)
                .background {
                    CardShadow(color: p.shadow)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(p.card)
                        .pointerStyle(moving ? .grabActive : .grabIdle)
                }
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.border) }
                .overlay(alignment: .top) { handle("n", note, height).frame(height: 8).padding(.horizontal, 8).offset(y: -4) }
                .overlay(alignment: .bottom) { handle("s", note, height).frame(height: 8).padding(.horizontal, 8).offset(y: 4) }
                .overlay(alignment: .leading) { handle("w", note, height).frame(width: 8).padding(.vertical, 8).offset(x: -4) }
                .overlay(alignment: .trailing) { handle("e", note, height).frame(width: 8).padding(.vertical, 8).offset(x: 4) }
                .overlay(alignment: .topLeading) { handle("nw", note, height).frame(width: 12, height: 12).offset(x: -5, y: -5) }
                .overlay(alignment: .topTrailing) { handle("ne", note, height).frame(width: 12, height: 12).offset(x: 5, y: -5) }
                .overlay(alignment: .bottomLeading) { handle("sw", note, height).frame(width: 12, height: 12).offset(x: -5, y: 5) }
                .overlay(alignment: .bottomTrailing) { handle("se", note, height).frame(width: 12, height: 12).offset(x: 5, y: 5) }
                .gesture(move(note, height))
                .offset(x: note.x ?? 0, y: note.y ?? 0)
                .onChange(of: height, initial: true) { store.heights[id] = $1 }
        }
    }

    // Tracked for the whole drag wherever the pointer goes, and ended on release
    // anywhere, even outside the note (CORRECTIONS.md 1-2).
    private func move(_ note: Note, _ height: Double) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
            .onChanged { value in
                if start == nil {
                    start = (note.x ?? 0, note.y ?? 0, note.w, height)
                    store.raise(id)
                    moving = true
                }
                guard let s = start else { return }
                store.update(id, save: false) {
                    $0.x = min(max(s.x + value.translation.width, 0), canvas.width - s.w)
                    $0.y = min(max(s.y + value.translation.height, 0), canvas.height - s.h)
                }
            }
            .onEnded { _ in
                start = nil
                moving = false
                store.save(id)
            }
    }

    // Invisible handle straddling an edge or corner. Never resizes below the default size
    // or past the canvas edges. Once the height has been dragged it is fixed: the note
    // stops growing with its content and the body scrolls instead. Releasing at the
    // minimum height makes it grow with its content again.
    private func handle(_ dir: String, _ note: Note, _ height: Double) -> some View {
        let positions: [String: FrameResizePosition] = [
            "n": .top, "s": .bottom, "e": .trailing, "w": .leading,
            "ne": .topTrailing, "nw": .topLeading, "se": .bottomTrailing, "sw": .bottomLeading,
        ]
        let clamp = { (v: Double, lo: Double, hi: Double) in min(max(v, lo), hi) }
        return Color.clear
            .contentShape(.rect)
            .pointerStyle(.frameResize(position: positions[dir]!))
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("canvas"))
                    .onChanged { value in
                        if start == nil {
                            start = (note.x ?? 0, note.y ?? 0, note.w, height)
                            store.raise(id)
                        }
                        guard let s = start else { return }
                        let dx = value.translation.width, dy = value.translation.height
                        store.update(id, save: false) { n in
                            if dir.contains("e") {
                                n.w = clamp(s.w + dx, Note.width, canvas.width - s.x)
                            } else if dir.contains("w") {
                                n.w = clamp(s.w - dx, Note.width, s.x + s.w)
                                n.x = s.x + s.w - n.w
                            }
                            if dir.contains("s") {
                                n.h = clamp(s.h + dy, Note.height, canvas.height - s.y)
                            } else if dir.contains("n") {
                                let h = clamp(s.h - dy, Note.height, s.y + s.h)
                                n.h = h
                                n.y = s.y + s.h - h
                            }
                        }
                    }
                    .onEnded { _ in
                        start = nil
                        store.update(id) { n in
                            if let h = n.h, h <= Note.height { n.h = nil }
                        }
                    }
            )
    }
}

// The note's drop shadow, drawn only outside it like a CSS box-shadow, since the
// see-through card would show it underneath.
private struct CardShadow: View {
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.black)
            .shadow(color: color, radius: 4, y: 2)
            .mask {
                Rectangle()
                    .padding(-20)
                    .overlay { RoundedRectangle(cornerRadius: 8).blendMode(.destinationOut) }
                    .compositingGroup()
            }
    }
}
#endif
