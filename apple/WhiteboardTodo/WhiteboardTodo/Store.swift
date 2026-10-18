import SwiftUI
#if os(iOS)
import WidgetKit
#endif

// All notes, shared by every view and synced with Supabase (supabase/schema.sql).
// A change saves shortly after it's made; changes from other devices arrive over
// Realtime. If two devices change the same note, the last save wins.
@Observable final class Store {
    private(set) var notes: [Note] = []
    @ObservationIgnored var canvas = CGSize.zero // Mac: the visible canvas, for placing new notes
    @ObservationIgnored var heights: [UUID: Double] = [:] // Mac: each note's height on the canvas
    @ObservationIgnored private var topZ = 0
    @ObservationIgnored private var timers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var sending: [UUID: Int] = [:]
    @ObservationIgnored private var queues: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var deleted: Set<UUID> = [] // deleted here, so late echoes of their saves are ignored
    @ObservationIgnored private let realtime = Realtime()

    private let saveDelay = Duration.milliseconds(500) // after the last change

    func note(_ id: UUID) -> Note? { notes.first { $0.id == id } }

    // A note to edit: every change made through it is saved.
    func binding(_ id: UUID) -> Binding<Note> {
        Binding { self.note(id) ?? Note(id: id) } set: { new in self.update(id) { $0 = new } }
    }

    func update(_ id: UUID, save: Bool = true, _ change: (inout Note) -> Void) {
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return }
        change(&notes[i])
        if save { self.save(id) }
    }

    func add(_ note: Note) {
        notes.append(note)
        save(note.id)
    }

    func remove(_ id: UUID) {
        notes.removeAll { $0.id == id }
        timers.removeValue(forKey: id)?.cancel()
        deleted.insert(id)
        send(id) { try await Supabase.delete(id) }
    }

    // Notes in list order (iPhone list and widget).
    var ordered: [Note] { notes.sorted { $0.position < $1.position } }

    // Moves a note to `index` in list order (counted without it); saved with save().
    func move(_ id: UUID, to index: Int) {
        let others = ordered.filter { $0.id != id }
        let before = index > 0 ? others[index - 1].position : nil
        let after = index < others.count ? others[index].position : nil
        let position: Double
        switch (before, after) {
        case let (b?, a?): position = (b + a) / 2
        case let (b?, nil): position = b + 1
        case let (nil, a?): position = a - 1
        default: return
        }
        update(id, save: false) { $0.position = position }
    }

    // Brings a note to the front of the canvas (saved with the move or resize that follows).
    func raise(_ id: UUID) {
        topZ += 1
        let z = topZ
        update(id, save: false) { $0.z = z }
    }

    func save(_ id: UUID) {
        timers[id]?.cancel()
        timers[id] = Task {
            try? await Task.sleep(for: saveDelay)
            guard !Task.isCancelled else { return }
            timers[id] = nil
            guard let note = note(id) else { return }
            send(id) { try await Supabase.upsert(note) }
        }
    }

    // Saves every pending change now.
    func flush() {
        for (id, timer) in timers {
            timer.cancel()
            if let note = note(id) { send(id) { try await Supabase.upsert(note) } }
        }
        timers = [:]
    }

    // Requests for one note go out one at a time, in order.
    private func send(_ id: UUID, _ request: @escaping () async throws -> Void) {
        sending[id, default: 0] += 1
        let previous = queues[id]
        queues[id] = Task {
            await previous?.value
            do { try await request() } catch { print("Sync failed:", error.localizedDescription) }
            sending[id, default: 1] -= 1
            #if os(iOS)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
    }

    private func unsaved(_ id: UUID) -> Bool { timers[id] != nil || sending[id, default: 0] > 0 }

    // A row from the database: a new note, a change made on another device, or an echo
    // of a save from here. Echoes, and rows for notes with changes still being saved
    // here, are ignored.
    private func apply(_ row: Note) {
        if deleted.contains(row.id) { return }
        if let i = notes.firstIndex(where: { $0.id == row.id }) {
            if unsaved(row.id) || notes[i] == row { return }
            notes[i] = row
        } else {
            notes.append(row)
        }
        topZ = max(topZ, row.z)
    }

    // Loads every note; again each time Realtime (re)connects, e.g. after the Mac wakes
    // from sleep, to catch up on changes missed while disconnected.
    private func load() async {
        do {
            let rows = try await Supabase.notes()
            let ids = Set(rows.map(\.id))
            rows.forEach(apply)
            notes.removeAll { !ids.contains($0.id) && !unsaved($0.id) }
            changed()
        } catch {
            print("Sync failed:", error.localizedDescription)
        }
    }

    // Keeps the widget showing what's here.
    private func changed() {
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func start() {
        realtime.onSubscribed = { [weak self] in Task { await self?.load() } }
        realtime.onChange = { [weak self] change in
            guard let self else { return }
            switch change {
            case .upsert(let row): apply(row)
            case .delete(let id): notes.removeAll { $0.id == id }
            }
            changed()
        }
        realtime.connect()
    }

    #if os(iOS)
    // Going to the background: saves what's pending (with time granted to finish) and
    // closes the Realtime connection until the app is back.
    func pause() {
        let task = UIApplication.shared.beginBackgroundTask()
        flush()
        realtime.disconnect()
        Task {
            for queue in queues.values { await queue.value }
            UIApplication.shared.endBackgroundTask(task)
        }
    }
    #endif
}

#if os(macOS)
// Mac canvas placement.
extension Store {
    private static let gap = 16.0 // minimum space kept between a new note and existing ones
    private static let step = 24.0 // grid the empty-space search walks, matches the dot grid

    func addNote() {
        var note = Note()
        let spot = findSpot()
        note.x = spot.x
        note.y = spot.y
        add(note)
    }

    // Notes added on the iPhone have no position yet: they get the first free spot.
    func placeNew() {
        guard canvas != .zero else { return }
        for id in notes.filter({ $0.x == nil }).map(\.id) {
            let spot = findSpot()
            update(id) {
                $0.x = spot.x
                $0.y = spot.y
            }
        }
    }

    // First free spot scanning rows from the top-left of the visible canvas.
    // If the canvas is full, falls back to a cascade from the top-left.
    private func findSpot() -> CGPoint {
        let step = Store.step, gap = Store.gap
        let placed = notes.filter { $0.x != nil }
        func overlaps(_ x: Double, _ y: Double, _ n: Note) -> Bool {
            let nx = n.x!, ny = n.y!, nh = heights[n.id] ?? Note.height
            return x < nx + n.w + gap && x + Note.width + gap > nx && y < ny + nh + gap && y + Note.height + gap > ny
        }
        for y in stride(from: step, through: canvas.height - Note.height - step, by: step) {
            for x in stride(from: step, through: canvas.width - Note.width - step, by: step) {
                if !placed.contains(where: { overlaps(x, y, $0) }) { return CGPoint(x: x, y: y) }
            }
        }
        let offset = step + Double(placed.count % 10) * step
        return CGPoint(x: offset, y: offset)
    }
}
#endif
