/// The `DB` helper Shelf appends to an app's source (see `SourceRewriter`).
///
/// It is plain networking code that Kiln already runs: requests to the private
/// `db://` scheme are answered on the phone, on the main actor and at once, by
/// `ShelfDBProtocol.answerForKiln` through `Kiln.hostRequestHandler`, so `DB`
/// needs no `await` (app code calls it where it can't wait) and nothing leaves
/// the device. PLAN.md §1.7 replaces all of this with a `DB` host bridge.
///
/// The key travels in a header (`ShelfDBProtocol.keyHeader`), not the URL: a
/// URL would end the key at "?" or "#" and decode "%2F", and Kiln has no
/// percent-encoding to prevent it. A header carries any key as it is.
enum Prelude {
    static let db = #"""
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
            request.setValue(key, forHTTPHeaderField: "\#(ShelfDBProtocol.keyHeader)")
            return request
        }
    }
    """#
}
