/// The `DB` helper Shelf appends to an app's source (see `SourceRewriter`).
///
/// It is plain networking code that Kiln already runs: requests to the private
/// `db://` scheme are answered on the phone by `ShelfDBProtocol`, so the
/// blocking `await` returns at once and nothing leaves the device.
enum Prelude {
    static let db = #"""
    enum DB {
        static func load(_ key: String) -> Data? {
            guard let url = URL(string: "db://data/" + key),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return data
        }
        static func save(_ key: String, _ data: Data) {
            var request = URLRequest(url: URL(string: "db://data/" + key)!)
            request.httpMethod = "PUT"
            request.httpBody = data
            _ = try? await URLSession.shared.data(for: request)
        }
        static func remove(_ key: String) {
            var request = URLRequest(url: URL(string: "db://data/" + key)!)
            request.httpMethod = "DELETE"
            _ = try? await URLSession.shared.data(for: request)
        }
    }
    """#
}
