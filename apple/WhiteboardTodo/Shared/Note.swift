import Foundation

// A note: one row of the Supabase `notes` table (supabase/schema.sql), shared by the
// Mac app, the iPhone app and the widget. x/y are nil until it is first placed on the
// Mac canvas; h is nil while it grows with its content.
nonisolated struct Note: Codable, Identifiable, Equatable {
    enum Mode: String, Codable { case text, checklist }

    var id = UUID()
    var title = ""
    var mode = Mode.text
    var text = ""
    var items: [Item] = []
    var x: Double?
    var y: Double?
    var w = Note.width
    var h: Double?
    var z = 0

    static let width = 288.0 // includes the column reserved for item delete buttons
    static let height = 160.0 // starting (minimum) height on the Mac canvas

    private enum CodingKeys: CodingKey { case id, title, mode, text, items, x, y, w, h, z }

    // Optional fields are sent as null, so clearing h saves too.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(mode, forKey: .mode)
        try c.encode(text, forKey: .text)
        try c.encode(items, forKey: .items)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(w, forKey: .w)
        try c.encode(h, forKey: .h)
        try c.encode(z, forKey: .z)
    }
}

// A checkbox item, level 0 or 1: a level-1 item belongs to the nearest level-0 item
// above it. `id` only tells items apart on screen; it isn't saved.
nonisolated struct Item: Codable, Identifiable, Equatable {
    var id = UUID()
    var text = ""
    var done = false
    var level = 0

    private enum CodingKeys: CodingKey { case text, done, level }

    static func == (a: Item, b: Item) -> Bool { a.text == b.text && a.done == b.done && a.level == b.level }
}

nonisolated extension Note {
    func parent(of i: Int) -> Int? { items[..<i].lastIndex { $0.level == 0 } }

    // Shown nested: a sub-item whose parent is in the same (unmarked or marked) section.
    func isNested(_ i: Int) -> Bool {
        guard items[i].level == 1, let p = parent(of: i) else { return false }
        return items[p].done == items[i].done
    }

    // Unmarked top-level items with text: the widget's pills and its count badge.
    var todo: [Item] {
        items.indices.filter { !items[$0].done && !items[$0].text.isBlank && !isNested($0) }.map { items[$0] }
    }
}

nonisolated extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
