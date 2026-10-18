import SwiftUI

// The note editor: title, rule, body, rule, footer. Shared by the Mac note and the
// iPhone card screen. `natural` gets the height it needs to show all its content.
struct NoteEditor: View {
    let id: UUID
    var focusTitle = false
    var natural: Binding<CGFloat>?
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @State private var cursor = Cursor()
    @State private var header: CGFloat = 0
    @State private var content: CGFloat = 0
    @State private var footer: CGFloat = 0
    @State private var viewport: CGFloat = 0
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    var body: some View {
        let note = store.binding(id)
        let mode = note.wrappedValue.mode
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                TextField("Title", text: note.title, prompt: Text("Title").foregroundStyle(p.muted))
                    .textFieldStyle(.plain)
                    .font(.system(size: Metrics.title, weight: .semibold))
                    .foregroundStyle(p.text)
                    .padding(.vertical, 2)
                    .focused($titleFocused)
                Rule()
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { header = $0 }

            ScrollView {
                Group {
                    if mode == .text {
                        TextBody(id: id, cursor: cursor, viewport: viewport, height: $content)
                    } else {
                        ChecklistBody(id: id, cursor: cursor, height: $content)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: viewport, alignment: .topLeading)
                .padding(.leading, 16)
            }
            .padding(.leading, -16) // reaches into the left margin so the item grips aren't clipped
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { viewport = $0 }

            VStack(spacing: 0) {
                Rule()
                HStack(spacing: 6) {
                    FooterButton(
                        icon: mode == .text ? Icon.text : Icon.checklist,
                        help: mode == .text ? "Plain text mode (click for checkboxes)" : "Checkbox mode (click for plain text)"
                    ) { note.wrappedValue.setMode(mode == .text ? .checklist : .text) }
                    if mode == .checklist {
                        FooterButton(icon: Icon.broom, help: "Delete marked items") { note.wrappedValue.clearDone() }
                    }
                    Spacer()
                    FooterButton(icon: Icon.trash, help: "Delete note") { confirmDelete = true }
                }
                .padding(.horizontal, 2 - Metrics.footerPadding) // icons inset as on the web, whatever the touch area
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { footer = $0 }
        }
        .onChange(of: header + content + footer, initial: true) { natural?.wrappedValue = $1 }
        .onAppear { titleFocused = focusTitle }
        .alert("Delete this note?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.remove(id) }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// Plain text mode: one text view that grows with its content.
private struct TextBody: View {
    let id: UUID
    let cursor: Cursor
    let viewport: CGFloat
    @Binding var height: CGFloat
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p

    var body: some View {
        VStack(spacing: 0) {
            EditorText(text: store.binding(id).text, id: id, cursor: cursor, color: p.text)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
            // The text fills the body on the web, so a click below it also puts the cursor in it.
            Color.clear
                .contentShape(.rect)
                .frame(height: max(0, viewport - height))
                .onTapGesture { cursor.move(to: id) }
        }
    }
}

// Checkbox mode: unmarked items, then the marked ones below a rule. A sub-item is shown
// nested only when its parent is in the same section.
private struct ChecklistBody: View {
    let id: UUID
    let cursor: Cursor
    @Binding var height: CGFloat
    @Environment(Store.self) private var store
    @Environment(\.palette) private var p
    @State private var frames: [UUID: CGRect] = [:] // each row, in its section
    @State private var drag: Drag?

    // An item being dragged by its grip, with its sub-items if it's a parent.
    private struct Drag {
        let done: Bool
        let block: [UUID]
        var drop: Drop?
    }

    private struct Drop {
        let above: UUID?
        let below: UUID?
        let level: Int
        let y: CGFloat // the drop line, in the section
    }

    var body: some View {
        let note = store.note(id) ?? Note(id: id)
        VStack(spacing: 0) {
            section(note, done: false)
            if note.items.contains(where: \.done) {
                Rule()
                section(note, done: true)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
        // There's always an unmarked item to type in (not saved until it's typed in).
        .onChange(of: note.items.contains { !$0.done }, initial: true) { _, active in
            if !active { store.update(id, save: false) { $0.items.append(Item()) } }
        }
    }

    private func section(_ note: Note, done: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(note.items.filter { $0.done == done }) { item in
                let i = note.items.firstIndex { $0.id == item.id }!
                ItemRow(
                    text: Binding { item.text } set: { new in edit { $0.items[index(item.id, in: $0)].text = new } },
                    item: item,
                    nested: note.isNested(i),
                    cursor: cursor,
                    grip: grip(item.id, done: done),
                    dragging: drag?.block.contains(item.id) == true,
                    onToggle: { edit { $0.toggle(index(item.id, in: $0)) } },
                    onRemove: { edit { $0.removeItem(index(item.id, in: $0)) } },
                    onKey: { key($0, item.id) }
                )
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(done)) } action: { frames[item.id] = $0 }
            }
        }
        .overlay(alignment: .topLeading) {
            if let drag, drag.done == done, let drop = drag.drop {
                RoundedRectangle(cornerRadius: 1)
                    .fill(p.muted)
                    .frame(height: 2)
                    .padding(.leading, drop.level == 1 ? Metrics.indent : 0)
                    .offset(y: drop.y - 1)
            }
        }
        .coordinateSpace(.named(done))
        .padding(.leading, Metrics.itemInset)
    }

    private func edit(_ change: (inout Note) -> Void) { store.update(id, change) }

    private func index(_ itemID: UUID, in note: Note) -> Int { note.items.firstIndex { $0.id == itemID }! }

    private func key(_ key: ItemKey, _ itemID: UUID) -> Bool {
        guard var note = store.note(id), let i = note.items.firstIndex(where: { $0.id == itemID }) else { return false }
        if key == .up || key == .down {
            // Up/Down always jump to the item above or below, cursor at its end, in
            // on-screen order, never between wrapped lines.
            let order = note.items.filter { !$0.done } + note.items.filter(\.done)
            let next = order.firstIndex { $0.id == itemID }! + (key == .up ? -1 : 1)
            if order.indices.contains(next) { cursor.move(to: order[next].id) }
            return true
        }
        if note.items[i].done { return false } // marked items are read-only

        switch key {
        case .enter(let caret):
            note.split(i, at: caret)
            cursor.move(to: note.items[i + 1].id, caret: 0)
        case .tab, .backtab:
            guard note.indent(i, out: key == .backtab) else { return true }
        case .deleteEmpty:
            let active = note.items.filter { !$0.done }
            guard active.count > 1 else { return false }
            let pos = active.firstIndex { $0.id == itemID }!
            note.removeItem(i)
            if pos > 0 { cursor.move(to: active[pos - 1].id) } else { cursor.move(to: active[pos + 1].id, caret: 0) }
        default:
            return false
        }
        edit { $0 = note }
        return true
    }

    // Drag an item by its grip to reorder it within its section; a parent carries its
    // sub-items. Dragging right of where it started makes it a sub-item, left makes it
    // top-level, where allowed: a drop inside a group is always a sub-item, the first
    // item of a section can't be one, and a parent with sub-items stays top-level (so
    // it only lands between groups).
    private func grip(_ itemID: UUID, done: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(done))
            .onChanged { value in
                guard let note = store.note(id), let i = note.items.firstIndex(where: { $0.id == itemID }) else { return }
                if drag == nil {
                    var end = i + 1
                    if note.items[i].level == 0 { while end < note.items.count && note.items[end].level == 1 { end += 1 } }
                    drag = Drag(done: done, block: note.items[i..<end].map(\.id))
                }
                guard var d = drag, value.translation != .zero else { return }
                let hasSubs = d.block.count > 1
                let section = note.items.indices.filter { note.items[$0].done == done }
                let rows = section.filter { !d.block.contains(note.items[$0].id) }
                var k = rows.filter { (frames[note.items[$0].id]?.midY ?? 0) < value.location.y }.count
                if hasSubs { while k < rows.count && note.isNested(rows[k]) { k += 1 } }
                let above = k > 0 ? rows[k - 1] : nil
                let below = k < rows.count ? rows[k] : nil
                let dx = value.translation.width
                var level = dx > 24 ? 1 : dx < -24 ? 0 : note.items[i].level
                if hasSubs || above == nil { level = 0 } else if let below, note.isNested(below) { level = 1 }
                let bottom = section.compactMap { frames[note.items[$0].id]?.maxY }.max() ?? 0
                d.drop = Drop(
                    above: above.map { note.items[$0].id },
                    below: below.map { note.items[$0].id },
                    level: level,
                    y: below.flatMap { frames[note.items[$0].id]?.minY } ?? bottom
                )
                drag = d
            }
            .onEnded { _ in
                if let drag, let drop = drag.drop {
                    edit { $0.move(drag.block, above: drop.above, below: drop.below, level: drop.level) }
                }
                drag = nil
            }
    }
}

// One checkbox item: grip (in the margin), box, wrapping text, and × in its own column
// that the text never flows into. The grip and × show on hover (always on iPhone).
private struct ItemRow<Grip: Gesture>: View {
    @Binding var text: String
    let item: Item
    let nested: Bool
    let cursor: Cursor
    let grip: Grip
    let dragging: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void
    let onKey: (ItemKey) -> Bool
    @Environment(\.palette) private var p
    @State private var hoverRow = false
    @State private var hoverGrip = false
    @State private var hoverRemove = false

    private var controls: Bool {
        #if os(macOS)
        hoverRow || hoverGrip || dragging
        #else
        true
        #endif
    }

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.gap) {
            Button(action: onToggle) { Checkbox(done: item.done).contentShape(.rect) }
                .buttonStyle(.plain)
                .accessibilityLabel(item.done ? "Unmark" : "Mark")
            EditorText(
                text: $text, id: item.id, cursor: cursor,
                color: item.done ? p.muted : p.text, strike: item.done, readOnly: item.done, onKey: onKey
            )
            Button(action: onRemove) {
                IconView(path: Icon.close, size: Metrics.removeIcon, stroke: 2.2)
                    .frame(width: Metrics.remove.width, height: Metrics.remove.height)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(hoverRemove ? p.text : p.muted)
            .onHover { hoverRemove = $0 }
            .opacity(controls ? 1 : 0)
            .help("Delete item")
        }
        .padding(.vertical, Metrics.rowPadding)
        .padding(.leading, nested ? Metrics.indent : 0)
        .contentShape(.rect)
        .onHover { hoverRow = $0 }
        .overlay(alignment: .topLeading) {
            // Its own hover keeps it showing once the pointer moves off the row onto it.
            IconShape(path: Icon.grip)
                .fill(p.muted)
                .frame(width: Metrics.gripIcon.width, height: Metrics.gripIcon.height)
                .opacity(controls ? 1 : 0)
                .frame(width: Metrics.grip.width, height: Metrics.grip.height)
                .contentShape(.rect)
                .onHover { hoverGrip = $0 }
                #if os(macOS)
                .pointerStyle(.grabIdle)
                #endif
                .gesture(grip)
                .help("Drag to reorder")
                .offset(x: Metrics.gripOffset.x + (nested ? Metrics.indent : 0), y: Metrics.gripOffset.y)
        }
        .opacity(dragging ? 0.4 : 1)
    }
}
