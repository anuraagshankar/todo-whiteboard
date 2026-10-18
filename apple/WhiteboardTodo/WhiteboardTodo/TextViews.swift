import SwiftUI

#if os(macOS)
typealias PlatformTextView = NSTextView
typealias PlatformFont = NSFont
typealias PlatformColor = NSColor
#else
typealias PlatformTextView = ItemTextView
typealias PlatformFont = UIFont
typealias PlatformColor = UIColor
#endif

// Keys a checkbox item handles itself (see Note editing in NoteEditor).
enum ItemKey: Equatable { case up, down, enter(caret: Int), tab, backtab, deleteEmpty }

// A native text view sized to its content, so notes grow instead of scrolling.
// Checkbox items pass `onKey` (returns true if it handled the key): an item stays one
// wrapping line, so pasted line breaks become spaces. Plain text keeps Tab as a tab
// character, 4 spaces wide, through normal editing so Cmd+Z undoes it.
struct EditorText {
    @Binding var text: String
    let id: UUID
    let cursor: Cursor
    var color: Color
    var strike = false
    var readOnly = false
    var onKey: ((ItemKey) -> Bool)?

    private let size = Metrics.text
    private let lineHeight = Metrics.line

    private var attributes: [NSAttributedString.Key: Any] {
        let font = PlatformFont.systemFont(ofSize: size)
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = lineHeight
        style.maximumLineHeight = lineHeight
        style.tabStops = []
        style.defaultTabInterval = 4 * (" " as NSString).size(withAttributes: [.font: font]).width
        return [
            .font: font,
            .foregroundColor: PlatformColor(color),
            .paragraphStyle: style,
            .baselineOffset: (lineHeight - (font.ascender - font.descender)) / 2,
            .strikethroughStyle: strike ? NSUnderlineStyle.single.rawValue : 0,
        ]
    }

    // Applies color and strikethrough when they change, or after the text was replaced.
    private func style(_ view: PlatformTextView, _ coordinator: Coordinator, force: Bool = false) {
        guard force || coordinator.style != Style(color: color, strike: strike) else { return }
        coordinator.style = Style(color: color, strike: strike)
        let attributes = attributes
        view.typingAttributes = attributes
        #if os(macOS)
        let storage = view.textStorage!
        #else
        let storage = view.textStorage
        #endif
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
    }

    struct Style: Equatable {
        let color: Color
        let strike: Bool
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: EditorText
        var style: Style?

        init(_ parent: EditorText) { self.parent = parent }
    }
}

// Moves the cursor into a text view by id once it's on screen: an item just added by
// Enter, or the next one for Up/Down.
final class Cursor {
    private struct Ref { weak var view: PlatformTextView? }
    private var views: [UUID: Ref] = [:]
    private var pending: (id: UUID, caret: Int?)?

    func register(_ view: PlatformTextView, _ id: UUID) {
        views[id] = Ref(view: view)
        if pending?.id == id { DispatchQueue.main.async { self.apply() } }
    }

    // caret: UTF-16 offset, or nil for the end.
    func move(to id: UUID, caret: Int? = nil) {
        views = views.filter { $0.value.view != nil }
        pending = (id, caret)
        DispatchQueue.main.async { self.apply() }
    }

    private func apply() {
        guard let (id, caret) = pending, let view = views[id]?.view, view.window != nil else { return }
        pending = nil
        #if os(macOS)
        view.window?.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: caret ?? (view.string as NSString).length, length: 0))
        #else
        view.becomeFirstResponder()
        view.selectedRange = NSRange(location: caret ?? (view.text as NSString).length, length: 0)
        #endif
    }
}

#if os(macOS)
extension EditorText: NSViewRepresentable {
    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.focusRingType = .none
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.string = text
        style(view, context.coordinator, force: true)
        cursor.register(view, id)
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text {
            view.string = text
            style(view, context.coordinator, force: true)
        } else {
            style(view, context.coordinator)
        }
        cursor.register(view, id)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return CGSize(width: width, height: max(layout.usedRect(for: container).height, lineHeight))
    }
}

extension EditorText.Coordinator: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        let view = notification.object as! NSTextView
        if parent.onKey != nil, view.string.contains("\n") {
            // Pasted line breaks become spaces: an item is a single (wrapping) line.
            let selection = view.selectedRanges
            view.string = view.string.replacingOccurrences(of: "\n", with: " ")
            view.selectedRanges = selection
            style = nil
        }
        parent.text = view.string
    }

    func textView(_ view: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?) -> Bool {
        !parent.readOnly
    }

    func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard let onKey = parent.onKey else { return false }
        switch selector {
        case #selector(NSResponder.moveUp(_:)): return onKey(.up)
        case #selector(NSResponder.moveDown(_:)): return onKey(.down)
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)),
             #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            return onKey(.enter(caret: view.selectedRange().location))
        case #selector(NSResponder.insertTab(_:)): return onKey(.tab)
        case #selector(NSResponder.insertBacktab(_:)): return onKey(.backtab)
        case #selector(NSResponder.deleteBackward(_:)) where view.string.isEmpty: return onKey(.deleteEmpty)
        default: return false
        }
    }
}
#else
// Backspace on an empty item reaches no delegate method, so it's caught here.
final class ItemTextView: UITextView {
    var onDeleteEmpty: (() -> Bool)?

    override func deleteBackward() {
        if text.isEmpty, onDeleteEmpty?() == true { return }
        super.deleteBackward()
    }
}

extension EditorText: UIViewRepresentable {
    func makeUIView(context: Context) -> ItemTextView {
        let view = ItemTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.text = text
        update(view, context)
        style(view, context.coordinator, force: true)
        return view
    }

    func updateUIView(_ view: ItemTextView, context: Context) {
        update(view, context)
        if view.text != text {
            view.text = text
            style(view, context.coordinator, force: true)
        } else {
            style(view, context.coordinator)
        }
    }

    private func update(_ view: ItemTextView, _ context: Context) {
        context.coordinator.parent = self
        view.isEditable = !readOnly
        view.onDeleteEmpty = onKey.map { onKey in { onKey(.deleteEmpty) } }
        cursor.register(view, id)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: ItemTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let height = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: width, height: max(height, lineHeight))
    }
}

extension EditorText.Coordinator: UITextViewDelegate {
    func textViewDidChange(_ view: UITextView) {
        parent.text = view.text
    }

    func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard let onKey = parent.onKey else { return true }
        switch text {
        case "\n":
            _ = onKey(.enter(caret: range.location))
            return false
        case "\t":
            _ = onKey(.tab)
            return false
        default:
            guard text.contains("\n"), let start = view.position(from: view.beginningOfDocument, offset: range.location),
                  let end = view.position(from: start, offset: range.length), let range = view.textRange(from: start, to: end) else { return true }
            // Pasted line breaks become spaces: an item is a single (wrapping) line.
            view.replace(range, withText: text.replacingOccurrences(of: "\n", with: " "))
            parent.text = view.text
            return false
        }
    }
}
#endif
