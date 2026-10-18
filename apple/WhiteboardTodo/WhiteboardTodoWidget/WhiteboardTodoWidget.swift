import WidgetKit
import SwiftUI

// Reads the checkbox lists straight from Supabase. The app reloads it after every change
// it saves or receives; otherwise iOS refreshes it on its own schedule (asked for every
// 15 minutes). If fetching fails (e.g. offline) it shows the lists it fetched last.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, notes: cached)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
        Task { completion(Entry(date: .now, notes: await load())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            let entry = Entry(date: .now, notes: await load())
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }

    private func load() async -> [Note] {
        guard let notes = try? await Supabase.notes(filter: "mode=eq.checklist") else { return cached }
        UserDefaults.standard.set(try? JSONEncoder().encode(notes), forKey: "notes")
        return notes
    }

    private var cached: [Note] {
        UserDefaults.standard.data(forKey: "notes").flatMap { try? JSONDecoder().decode([Note].self, from: $0) } ?? []
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let notes: [Note]
}

// Up to 4 checkbox lists, as cards in a 2×2 grid on a dotted background: each card has its
// title and a round badge counting its unmarked top-level items, then those items as one
// pill per row, as many as fit (long items are cut to the pill width). Sub-items, plain
// text notes and lists with nothing left to do are left out; lists past the first 4 become
// "+N more lists". Tapping a card opens that note.
struct WhiteboardTodoWidgetEntryView: View {
    let entry: Entry
    @Environment(\.palette) private var p
    private let maxLists = 4 // 2×2 grid

    var body: some View {
        let lists = entry.notes.filter { $0.mode == .checklist && !$0.todo.isEmpty }
        let hidden = lists.count - min(lists.count, maxLists)
        Group {
            if lists.isEmpty {
                VStack(spacing: 0) {
                    Text("All done!")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(p.text)
                    Text("Nothing left on your lists.")
                }
                .font(.system(size: 14))
                .foregroundStyle(p.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<2, id: \.self) { column in
                                let k = row * 2 + column
                                if k < lists.count {
                                    card(lists[k])
                                } else {
                                    Color.clear
                                }
                            }
                        }
                    }
                    if hidden > 0 {
                        Text("+\(hidden) more list\(hidden == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(p.muted)
                            .padding(.leading, 9)
                    }
                }
            }
        }
        .padding(10)
        .containerBackground(for: .widget) {
            ZStack {
                p.bg
                DotGrid().fill(p.dot)
            }
        }
    }

    private func card(_ note: Note) -> some View {
        let todo = note.todo
        return Link(destination: URL(string: "whiteboard://note/\(note.id)")!) {
            FitColumn(spacing: 4) {
                HStack(spacing: 6) {
                    Text(note.title.isEmpty ? "Title" : note.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(note.title.isEmpty ? p.muted : p.text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(todo.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(p.muted)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20)
                        .frame(height: 20)
                        .background(p.pill, in: .capsule)
                }
                .padding(.bottom, 2)
                ForEach(todo) { item in
                    Text(item.text)
                        .font(.system(size: 13))
                        .foregroundStyle(p.text)
                        .lineLimit(1)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(p.pill, in: .capsule)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(p.card, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(p.border) }
            .clipShape(.rect(cornerRadius: 12))
        }
    }
}

// Stacks its subviews top-down, moving any that don't fit whole out of sight (the card
// clips them), so a card shows as many pills as fit and its title never shrinks.
struct FitColumn: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        var fits = true
        for (i, view) in subviews.enumerated() {
            let height = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            fits = fits && (i == 0 || y + height <= bounds.maxY)
            view.place(at: CGPoint(x: bounds.minX, y: fits ? y : bounds.maxY + 100), proposal: ProposedViewSize(width: bounds.width, height: height))
            y += height + spacing
        }
    }
}

struct WhiteboardTodoWidget: Widget {
    let kind = "WhiteboardTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            WhiteboardTodoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Whiteboard")
        .description("Your current todos.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}
