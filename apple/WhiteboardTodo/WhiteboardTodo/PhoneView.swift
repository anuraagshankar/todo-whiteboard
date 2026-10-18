#if os(iOS)
import SwiftUI

// iPhone: a list of cards; tap one to open it full screen, press and hold for its menu,
// or press, hold and drag it to a new place in the list.
struct PhoneView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @Environment(\.scenePhase) private var phase
    @State private var open: UUID? // note open on the card screen
    @State private var added: UUID? // just added with +: its title gets the cursor
    @State private var frames: [UUID: CGRect] = [:] // each card, for placing the menu
    @State private var menu: UUID? // card the long-press menu is open for
    @State private var reorder: Reorder? // card being dragged to a new place
    @State private var holdStart = CGPoint.zero // where the current press and hold began
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var scrolled = Scrolled()

    private static let spacing: CGFloat = 12 // between cards
    private static let edgeZone: CGFloat = 60 // a dragged card held this close to the list's top or bottom scrolls it
    private static let edgeSpeed: CGFloat = 8 // points per frame

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
            let notes = store.ordered
            ScrollView {
                VStack(spacing: Self.spacing) {
                    ForEach(notes) { note in
                        let dragged = reorder?.id == note.id
                        NoteCard(note: note)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("phone")) } action: { frames[note.id] = $0 }
                            .shadow(color: dragged ? p.shadow : .clear, radius: 12, y: 8)
                            .offset(y: dragged ? reorder!.top - top(of: note.id, in: notes) : 0)
                            .zIndex(dragged ? 1 : 0)
                            .onTapGesture { if menu == nil { open = note.id } } // not when releasing a hold
                            .gesture(Hold { held(note.id, $0, at: $1, in: screen.frame(in: .named("phone"))) })
                    }
                }
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 80, trailing: 16)) // clear of the + button
                .frame(maxWidth: .infinity, minHeight: screen.size.height, alignment: .top)
                .background { DotGrid().fill(p.dot).ignoresSafeArea() } // the dots scroll with the cards
            }
            .scrollPosition($scroll)
            .scrollDisabled(reorder != nil)
            .onScrollGeometryChange(for: Scrolled.self) { g in // measured like scrollTo(y:): 0 at the top
                Scrolled(y: g.contentOffset.y + g.contentInsets.top,
                         max: max(0, g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom - g.containerSize.height))
            } action: { scrolled = $1 }
        }
        .task(id: reorder?.edge) { await autoscroll() }
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

    // Press and hold opens the card's menu; moving on from there drags the card instead,
    // and it takes the place nearest to where it is held.
    private func held(_ id: UUID, _ state: UIGestureRecognizer.State, at point: CGPoint, in bounds: CGRect) {
        switch state {
        case .began:
            holdStart = point
            menu = id
        case .changed:
            if reorder == nil {
                guard hypot(point.x - holdStart.x, point.y - holdStart.y) > 10, let frame = frames[id] else { return }
                menu = nil
                reorder = Reorder(id: id, grab: holdStart.y - frame.minY, list: frame.minY - top(of: id, in: store.ordered),
                                  start: scrolled.y, finger: point.y, scroll: scrolled.y)
            }
            reorder?.finger = point.y
            reorder?.edge = point.y < bounds.minY + Self.edgeZone ? -1 : point.y > bounds.maxY - Self.edgeZone ? 1 : 0
            follow()
        default: // ended or cancelled
            guard let r = reorder else { return }
            reorder = nil
            store.save(r.id)
        }
    }

    // A card's top in the list, measured from the first card's top.
    private func top(of id: UUID, in notes: [Note]) -> CGFloat {
        notes.prefix { $0.id != id }.reduce(0) { $0 + (frames[$1.id]?.height ?? 0) + Self.spacing }
    }

    // Moves the dragged card to the place in the list nearest to where it is held.
    private func follow() {
        guard let r = reorder else { return }
        let notes = store.ordered
        var slot: CGFloat = 0, best = 0, nearest = abs(r.top)
        for (k, note) in notes.filter({ $0.id != r.id }).enumerated() {
            slot += (frames[note.id]?.height ?? 0) + Self.spacing
            if abs(slot - r.top) < nearest {
                nearest = abs(slot - r.top)
                best = k + 1
            }
        }
        if notes.firstIndex(where: { $0.id == r.id }) != best { store.move(r.id, to: best) }
    }

    // While a dragged card is held near the top or bottom of the list, scrolls that way.
    private func autoscroll() async {
        while let r = reorder, r.edge != 0, !Task.isCancelled {
            let y = min(max(r.scroll + r.edge * Self.edgeSpeed, 0), scrolled.max)
            if y == r.scroll { return }
            reorder?.scroll = y
            scroll.scrollTo(y: y)
            follow()
            try? await Task.sleep(for: .milliseconds(16))
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

// UIKit's long press: unlike SwiftUI's gestures inside a ScrollView, it leaves scrolling
// and taps alone until the hold is recognized, then keeps reporting the finger as it moves
// (the list doesn't scroll meanwhile).
private struct Hold: UIGestureRecognizerRepresentable {
    let action: (UIGestureRecognizer.State, CGPoint) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let hold = UILongPressGestureRecognizer()
        hold.minimumPressDuration = 0.5
        hold.allowableMovement = 10
        return hold
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        action(recognizer.state, context.converter.location(in: .named("phone")))
    }
}

// A card being dragged to a new place in the list. y values are in the "phone" space.
private struct Reorder {
    let id: UUID
    let grab: CGFloat // finger to the card's top
    let list: CGFloat // the first card's top when the drag began
    let start: CGFloat // scroll offset when the drag began
    var finger: CGFloat
    var scroll: CGFloat // scroll offset now
    var edge: CGFloat = 0 // -1 held near the list's top, 1 near its bottom, else 0

    // The card's top, measured from the first card's top.
    var top: CGFloat { finger - grab - list + scroll - start }
}

// The list's scroll offset and how far it can scroll.
private struct Scrolled: Equatable {
    var y: CGFloat = 0
    var max: CGFloat = 0
}

// View-only card: the title and a preview of the first 5 lines (plain text, blank lines
// skipped) or the first 5 unmarked items (checkbox mode), then "+N more" for the rest.
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
                let lines = note.text.components(separatedBy: "\n").filter { !$0.isBlank }
                if !lines.isEmpty { Rule() }
                ForEach(Array(lines.prefix(preview).enumerated()), id: \.offset) { _, line in
                    row(Text(line.replacingOccurrences(of: "\t", with: "    ")))
                }
                more(lines.count, "line")
            } else {
                let items = note.items.indices.filter { !note.items[$0].done && !note.items[$0].text.isBlank }
                if !items.isEmpty { Rule() }
                ForEach(items.prefix(preview), id: \.self) { i in
                    HStack(alignment: .top, spacing: Metrics.gap) {
                        Checkbox(done: false)
                        row(Text(note.items[i].text))
                    }
                    .padding(.vertical, 1)
                    .padding(.leading, note.isNested(i) ? Metrics.indent : 0)
                }
                more(items.count, "item")
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

    @ViewBuilder private func more(_ count: Int, _ noun: String) -> some View {
        if count > preview {
            row(Text("+\(count - preview) more \(noun)\(count - preview == 1 ? "" : "s")")).foregroundStyle(p.muted)
        }
    }

    private func row(_ text: Text) -> some View {
        text.lineLimit(1).frame(height: Metrics.line, alignment: .leading)
    }
}
#endif
