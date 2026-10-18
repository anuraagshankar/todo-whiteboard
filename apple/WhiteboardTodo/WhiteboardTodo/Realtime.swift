import Foundation

// Supabase Realtime over a plain WebSocket (its Phoenix channel protocol): every insert,
// update and delete on the notes table as it happens. Reconnects after a drop, and calls
// onSubscribed on each (re)subscribe so the app can catch up on what it missed.
final class Realtime {
    enum Change { case upsert(Note), delete(UUID) }

    var onSubscribed: () -> Void = {}
    var onChange: (Change) -> Void = { _ in }
    private var socket: URLSessionWebSocketTask?
    private var wanted = false
    private var ref = 0
    private var joinRef = ""

    func connect() {
        wanted = true
        guard socket == nil else { return }
        let url = URL(string: "wss://\(Supabase.host)/realtime/v1/websocket?apikey=\(Supabase.key)&vsn=1.0.0")!
        let socket = URLSession.shared.webSocketTask(with: url)
        self.socket = socket
        socket.resume()
        joinRef = "\(ref + 1)"
        send("realtime:notes", "phx_join", ["config": ["postgres_changes": [["event": "*", "schema": "public", "table": "notes"]]]])
        Task { await listen(socket) }
        Task { await heartbeat(socket) }
    }

    func disconnect() {
        wanted = false
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private func listen(_ socket: URLSessionWebSocketTask) async {
        while let message = try? await socket.receive() {
            if case .string(let text) = message { handle(Data(text.utf8)) }
        }
        guard socket === self.socket else { return } // closed on purpose
        self.socket = nil
        try? await Task.sleep(for: .seconds(3))
        if wanted { connect() }
    }

    private func heartbeat(_ socket: URLSessionWebSocketTask) async {
        while true {
            try? await Task.sleep(for: .seconds(25))
            guard socket === self.socket else { return }
            send("phoenix", "heartbeat", [:])
        }
    }

    private func send(_ topic: String, _ event: String, _ payload: [String: Any]) {
        ref += 1
        let message: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": "\(ref)", "join_ref": joinRef]
        if let data = try? JSONSerialization.data(withJSONObject: message) {
            socket?.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
        }
    }

    private func handle(_ data: Data) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        if message.event == "phx_reply", message.ref == joinRef, message.payload.status == "ok" { onSubscribed() }
        guard message.event == "postgres_changes", let change = message.payload.data else { return }
        if change.type == "DELETE" {
            if let id = change.oldID { onChange(.delete(id)) }
        } else if let note = change.record {
            onChange(.upsert(note))
        }
    }

    private struct Message: Decodable {
        let event: String
        let ref: String?
        let payload: Payload
    }

    private struct Payload: Decodable {
        let status: String?
        let data: ChangeData?
    }

    private struct ChangeData: Decodable {
        let type: String
        let record: Note?
        let oldID: UUID?

        private enum CodingKeys: String, CodingKey { case type, record, old_record }
        private struct Old: Decodable { let id: UUID }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decode(String.self, forKey: .type)
            record = try? c.decode(Note.self, forKey: .record) // empty for a delete
            oldID = (try? c.decode(Old.self, forKey: .old_record))?.id
        }
    }
}
