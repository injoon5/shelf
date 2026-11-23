// Shelf's `DB` helper, as `SourceRewriter` appends it to an app that uses
// `DB.` (Shelf/Data/Prelude.swift). KilnBench answers its `db://` requests
// in memory. It goes away when `DB` becomes a host bridge (PLAN.md §1.7);
// then KilnBench registers that bridge instead.
enum DB {
    static func load(_ key: String) -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(for: DB.request(key, "GET")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
    static func save(_ key: String, _ data: Data) {
        var request = DB.request(key, "PUT")
        request.httpBody = data
        _ = try? await URLSession.shared.data(for: request)
    }
    static func remove(_ key: String) {
        _ = try? await URLSession.shared.data(for: DB.request(key, "DELETE"))
    }
    static func request(_ key: String, _ method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "db://data/")!)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "DB-Key")
        return request
    }
}
