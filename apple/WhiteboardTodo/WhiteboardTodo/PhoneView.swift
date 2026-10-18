#if os(iOS)
import SwiftUI

// iPhone: a list of cards; tap one to open it full screen, press and hold for its menu.
struct PhoneView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var phase
    @State private var open: UUID? // note open on the card screen
    @State private var added: UUID? // just added with +: its title gets the cursor
    @State private var frames: [UUID: CGRect] = [:] // each card, for placing the menu
    @State private var menu: UUID? // card the long-press menu is open for

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let open, store.note(open) != nil {
                cardScreen(open)
            } else {
                list
            }
            if let menu, let frame = frames[menu] {
                menuView(menu, under: frame)
            }
        }
        .coordinateSpace(.named("phone"))
        .background(p.bg)
        .onOpenURL { url in // a card tapped on the widget: whiteboard://note/<id>
            menu = nil
            open = UUID(uuidString: url.lastPathComponent)
        }
        .onChange(of: phase, initial: true) {
            if phase == .active { store.start() } else if phase == .background { store.pause() }
        }
    }

    private var list: some View {
        GeometryReader { screen in
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(store.notes) { note in
                        NoteCard(note: note)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("phone")) } action: { frames[note.id] = $0 }
                            .onTapGesture { open = note.id }
                            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: 10) { menu = note.id }
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 80, trailing: 16)) // clear of the + button
                .frame(maxWidth: .infinity, minHeight: screen.size.height, alignment: .top)
                .background { DotGrid().fill(p.dot).ignoresSafeArea() } // the dots scroll with the cards
            }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingButton(icon: Icon.plus, size: 48, iconSize: 22, stroke: 2.2) {
                let note = Note()
                store.add(note)
                added = note.id
                open = note.id
            }
            .accessibilityLabel("Add note")
            .padding(16)
        }
    }

    private func cardScreen(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { open = nil } label: {
                IconView(path: Icon.back, size: 22, stroke: 2)
                    .frame(width: 36, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(p.text)
            .accessibilityLabel("Back")
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 0, trailing: 8))
            NoteEditor(id: id, focusTitle: added == id)
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16))
        }
        .id(id)
    }

    // Under the card (above it if there's no room below), right-aligned with it. Delete
    // here is immediate: the long press and menu are already the deliberate step.
    private func menuView(_ id: UUID, under card: CGRect) -> some View {
        GeometryReader { screen in
            let height: CGFloat = 44
            let below = card.maxY + 6
            Color.clear
                .contentShape(.rect)
                .onTapGesture { menu = nil }
            Button {
                menu = nil
                store.remove(id)
            } label: {
                HStack {
                    Text("Delete")
                    Spacer()
                    IconView(path: Icon.trash, size: 18, stroke: 1.8)
                }
                .font(.system(size: Metrics.text))
                .foregroundStyle(p.danger)
                .padding(.horizontal, 16)
                .frame(width: 180, height: height)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 12).fill(p.note).shadow(color: p.shadow, radius: 12, y: 8)
                RoundedRectangle(cornerRadius: 12).strokeBorder(p.border)
            }
            .offset(x: card.maxX - 180, y: below + height > screen.size.height ? card.minY - 6 - height : below)
        }
    }
}

// View-only card: the title and a preview of the first 5 lines (plain text, blank lines
// skipped) or the first 5 unmarked items (checkbox mode).
private struct NoteCard: View {
    let note: Note
    @Environment(\.palette) private var p
    private let preview = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(note.title.isEmpty ? "Title" : note.title)
                .font(.system(size: Metrics.title, weight: .semibold))
                .foregroundStyle(note.title.isEmpty ? p.muted : p.text)
            if note.mode == .text {
                let lines = note.text.components(separatedBy: "\n").filter { !$0.isBlank }.prefix(preview)
                if !lines.isEmpty { Rule() }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    row(Text(line.replacingOccurrences(of: "\t", with: "    ")))
                }
            } else {
                let items = note.items.indices.filter { !note.items[$0].done && !note.items[$0].text.isBlank }.prefix(preview)
                if !items.isEmpty { Rule() }
                ForEach(items, id: \.self) { i in
                    HStack(alignment: .top, spacing: Metrics.gap) {
                        Checkbox(done: false)
                        row(Text(note.items[i].text))
                    }
                    .padding(.vertical, 1)
                    .padding(.leading, note.isNested(i) ? Metrics.indent : 0)
                }
            }
        }
        .font(.system(size: Metrics.text))
        .foregroundStyle(p.text)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.card, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(p.border) }
        .contentShape(.rect)
    }

    private func row(_ text: Text) -> some View {
        text.lineLimit(1).frame(height: Metrics.line, alignment: .leading)
    }
}
#endif
