import SwiftUI

@main
struct WhiteboardTodoApp: App {
    @State private var store = Store()

    var body: some Scene {
        #if os(macOS)
        Window("Whiteboard", id: "main") {
            CanvasView().environment(store)
        }
        .defaultSize(width: 1200, height: 800)
        #else
        WindowGroup {
            PhoneView().environment(store)
        }
        #endif
    }
}
