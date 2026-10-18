import Foundation

// What the editor does to a note's items and mode, as in web/app.js.
extension Note {
    static let doneHeader = "# Done:"

    // Mode switching converts the content. Checkbox -> text, in on-screen order:
    //   - item
    //   \t- sub-item
    //   # Done:
    //   # marked item
    //   \t# marked sub-item
    // Text -> checkbox reads the same format back: one item per non-empty line,
    // a leading tab nests it, a leading "- " (or "# " after "# Done:") is stripped.
    mutating func setMode(_ new: Mode) {
        if mode == .checklist && new == .text { text = itemsText() }
        if mode == .text && new == .checklist { items = Note.items(from: text) }
        mode = new
    }

    private func itemsText() -> String {
        func lines(_ done: Bool, _ mark: String) -> [String] {
            items.indices.compactMap { i in
                items[i].done == done && !items[i].text.isBlank ? (isNested(i) ? "\t" : "") + mark + " " + items[i].text : nil
            }
        }
        let done = lines(true, "#")
        return (lines(false, "-") + (done.isEmpty ? [] : [Note.doneHeader] + done)).joined(separator: "\n")
    }

    private static func items(from text: String) -> [Item] {
        var items: [Item] = []
        var done = false
        var hasParent = false // a top-level item exists above, in the current section
        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == doneHeader {
                done = true
                hasParent = false
                continue
            }
            let nested = line.hasPrefix("\t") && hasParent
            var content = String(line.drop { $0.isWhitespace })
            if content.hasPrefix(done ? "# " : "- ") { content.removeFirst(2) }
            if content.isBlank { continue }
            items.append(Item(text: content, done: done, level: nested ? 1 : 0))
            if !nested { hasParent = true }
        }
        return items
    }

    // Marking a parent marks (or unmarks) all its sub-items with it.
    mutating func toggle(_ i: Int) {
        let done = !items[i].done
        items[i].done = done
        guard items[i].level == 0 else { return }
        var j = i + 1
        while j < items.count && items[j].level == 1 {
            items[j].done = done
            j += 1
        }
    }

    // Removes just this item (its sub-items stay, under the parent above it).
    mutating func removeItem(_ i: Int) {
        items.remove(at: i)
        fixLeadingSubItems()
    }

    // Footer button in checkbox mode: deletes every marked item, no confirmation.
    mutating func clearDone() {
        items.removeAll { $0.done }
        fixLeadingSubItems()
    }

    // A removed parent's sub-items with no parent left above become top-level.
    private mutating func fixLeadingSubItems() {
        for j in items.indices {
            guard items[j].level == 1 else { break }
            items[j].level = 0
        }
    }

    // Enter: a new item below, taking the text after the cursor (a UTF-16 offset, as in
    // the text views). On a parent that has sub-items, the new item becomes its first sub-item.
    mutating func split(_ i: Int, at caret: Int) {
        let text = items[i].text as NSString
        items[i].text = text.substring(to: caret)
        let level = items[i].level == 0 && i + 1 < items.count && items[i + 1].level == 1 ? 1 : items[i].level
        items.insert(Item(text: text.substring(from: caret), level: level), at: i + 1)
    }

    // Tab nests one level only, under an unmarked parent; Shift+Tab un-nests.
    // Returns false if nothing changed.
    mutating func indent(_ i: Int, out: Bool) -> Bool {
        if out {
            guard items[i].level == 1 else { return false }
            items[i].level = 0
        } else {
            guard items[i].level == 0, let p = parent(of: i), !items[p].done else { return false }
            items[i].level = 1
        }
        return true
    }

    // Drops the dragged block (an item, with its sub-items if it's a parent) at `level`:
    // a sub-item goes right after the row above it (same parent, or first sub-item of
    // that parent); a top-level item goes right before the row below.
    mutating func move(_ block: [UUID], above: UUID?, below: UUID?, level: Int) {
        guard let i = items.firstIndex(where: { $0.id == block[0] }) else { return }
        var moved = Array(items[i..<i + block.count])
        items.removeSubrange(i..<i + block.count)
        moved[0].level = level
        let rest = items
        let index = { (id: UUID?) in rest.firstIndex { $0.id == id } }
        let at = level == 1 ? index(above)! + 1 : index(below) ?? items.count
        items.insert(contentsOf: moved, at: at)
    }
}
