import Foundation

// The notes table over Supabase's REST API. No login: the publishable key, built into
// the apps as in web/app.js, can read and edit every note.
nonisolated enum Supabase {
    static let host = "pgwitomfqzskpilqiklr.supabase.co"
    static let key = "sb_publishable_72x2Nmm-9RHHzrm956unPA_jgDc-F3o"

    // Notes in list order (oldest first); `filter` narrows them, e.g. "mode=eq.checklist".
    static func notes(filter: String = "") async throws -> [Note] {
        let data = try await send("notes?select=*&order=created_at" + (filter.isEmpty ? "" : "&" + filter))
        return try JSONDecoder().decode([Note].self, from: data)
    }

    static func upsert(_ note: Note) async throws {
        try await send("notes", method: "POST", body: JSONEncoder().encode(note), prefer: "resolution=merge-duplicates,return=minimal")
    }

    static func delete(_ id: UUID) async throws {
        try await send("notes?id=eq.\(id)", method: "DELETE")
    }

    @discardableResult
    private static func send(_ path: String, method: String = "GET", body: Data? = nil, prefer: String? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://\(host)/rest/v1/\(path)")!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, 200..<300 ~= status else {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
        return data
    }
}
