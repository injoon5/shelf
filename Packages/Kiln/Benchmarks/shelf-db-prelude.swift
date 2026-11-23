// Shelf's `DB` helper from before PLAN.md §1.7, which `SourceRewriter`
// appended to an app that used `DB.`. Since §1.7 `DB` is a host bridge, and
// KilnBench and KilnDiff register one; this is kept for Tools/diff.sh's
// baseline engine (built with -DKILN_BASELINE), whose `db://` requests
// KilnDiff answers in memory through `Kiln.hostRequestHandler`.
enum DB {
    static func load(_ key: String) -> Data? {
        guard let (data, response) = try? URLSession.shared.data(for: DB.request(key, "GET")),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
    static func save(_ key: String, _ data: Data) {
        var request = DB.request(key, "PUT")
        request.httpBody = data
        _ = try? URLSession.shared.data(for: request)
    }
    static func remove(_ key: String) {
        _ = try? URLSession.shared.data(for: DB.request(key, "DELETE"))
    }
    static func request(_ key: String, _ method: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "db://data/")!)
        request.httpMethod = method
        request.setValue(key, forHTTPHeaderField: "DB-Key")
        return request
    }
}
