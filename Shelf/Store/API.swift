import Foundation

/// The ij5.dev API, as Shelf uses it. One value per (site, token) pair.
struct API: Sendable {
    var origin: URL
    var token: String
    /// Shelf's own session. It is ephemeral and separate from
    /// `URLSession.shared`, which apps use and where the `db` protocol lives.
    var session: URLSession = API.session

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    enum Failure: Error, Equatable, Sendable {
        /// `401`: the token is wrong or was rotated.
        case unauthorized
        /// No answer at all: offline, DNS, timeout.
        case offline
        /// Any other refusal, with the server's own sentence.
        case rejected(status: Int, message: String)
    }

    enum Listing: Equatable, Sendable {
        /// `304`: nothing changed since `etag`.
        case unchanged
        case apps([AppMeta], etag: String?)
    }

    struct DataChanges: Decodable, Equatable, Sendable {
        struct Change: Decodable, Equatable, Sendable {
            var key: String
            /// Nil is a tombstone: the key was deleted.
            var value: JSONValue?
            var rev: Int
        }
        var changes: [Change]
        var rev: Int
    }

    struct InstallKey: Decodable, Equatable, Sendable {
        /// `shelf_ik_{id}_{secret}`. Goes into a copied prompt and nowhere else.
        var key: String
        var id: String
        /// Epoch milliseconds.
        var expiresAt: Int

        var expires: Date { Date(timeIntervalSince1970: Double(expiresAt) / 1000) }

        enum Status: Equatable, Sendable {
            case waiting
            /// The key installed this slug.
            case used(slug: String?)
            /// Expired, revoked or unknown.
            case expired
        }

        enum CodingKeys: String, CodingKey {
            case key, id
            case expiresAt = "expires_at"
        }
    }

    // MARK: Apps

    func apps(ifNoneMatch etag: String?) async throws(Failure) -> Listing {
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = etag }
        let (data, response) = try await send("GET", ["apps"], headers: headers, accept: [304])
        if response.statusCode == 304 { return .unchanged }
        struct Body: Decodable { var apps: [AppMeta] }
        let body: Body = try decode(data, response)
        return .apps(body.apps, etag: response.value(forHTTPHeaderField: "ETag"))
    }

    func app(_ slug: String) async throws(Failure) -> AppFull {
        let (data, response) = try await send("GET", ["apps", slug])
        return try decode(data, response)
    }

    /// `PUT /api/apps/{slug}`: creates or replaces the app.
    func install(slug: String, name: String, icon: String?, tint: Tint, source: String) async throws(Failure) -> AppMeta {
        let body: JSONValue = .object([
            "name": .string(name),
            "icon": icon.map(JSONValue.string) ?? .null,
            "tint": .string(tint.rawValue),
            "source": .string(source),
        ])
        let (data, response) = try await send("PUT", ["apps", slug], body: body)
        return try decode(data, response)
    }

    func revert(_ slug: String) async throws(Failure) -> AppMeta {
        let (data, response) = try await send("POST", ["apps", slug, "revert"])
        return try decode(data, response)
    }

    /// Delete App: `DELETE /api/apps/{slug}?data=delete`. The server drops
    /// the app, every version Revert could reach, its `DB` data and its unused
    /// install keys. An app the server no longer has is already deleted, so a
    /// `404` returns like a success.
    func deleteApp(_ slug: String) async throws(Failure) {
        _ = try await send("DELETE", ["apps", slug], query: [URLQueryItem(name: "data", value: "delete")], accept: [404])
    }

    // MARK: App data

    func changes(for slug: String, since rev: Int) async throws(Failure) -> DataChanges {
        let query = [URLQueryItem(name: "since", value: String(max(rev, 0)))]
        let (data, response) = try await send("GET", ["apps", slug, "data"], query: query)
        return try decode(data, response)
    }

    /// The batch write. Returns the server's new `rev`.
    func push(to slug: String, set: [String: JSONValue], delete: [String]) async throws(Failure) -> Int {
        let body: JSONValue = .object(["set": .object(set), "delete": .array(delete.map(JSONValue.string))])
        let (data, response) = try await send("POST", ["apps", slug, "data"], body: body)
        struct Body: Decodable { var rev: Int }
        let result: Body = try decode(data, response)
        return result.rev
    }

    // MARK: Install keys

    /// A key for one new app (`slug == nil`) or one update of `slug`.
    func mintKey(for slug: String?) async throws(Failure) -> InstallKey {
        let body: JSONValue = .object(slug.map { ["slug": .string($0)] } ?? [:])
        let (data, response) = try await send("POST", ["install-keys"], body: body)
        return try decode(data, response)
    }

    func keyStatus(_ id: String) async throws(Failure) -> InstallKey.Status {
        let (data, response) = try await send("GET", ["install-keys", id], accept: [404])
        if response.statusCode == 404 { return .expired }
        struct Body: Decodable { var status: String; var slug: String? }
        let body: Body = try decode(data, response)
        switch body.status {
        case "waiting": return .waiting
        case "used": return .used(slug: body.slug)
        default: return .expired
        }
    }

    /// Revoking a key the server no longer knows is already done.
    func revokeKey(_ id: String) async throws(Failure) {
        _ = try await send("DELETE", ["install-keys", id], accept: [404])
    }
}

// MARK: - Transport

extension API {
    /// Path segments are percent-encoded one by one, so a slug or id can never
    /// add a segment or a query of its own.
    func url(_ path: [String], query: [URLQueryItem]? = nil) -> URL? {
        guard var components = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { return nil }
        var base = components.percentEncodedPath
        while base.hasSuffix("/") { base.removeLast() }
        let segments = ["api"] + path.map { $0.addingPercentEncoding(withAllowedCharacters: Self.segmentAllowed) ?? "" }
        components.percentEncodedPath = base + "/" + segments.joined(separator: "/")
        components.queryItems = query
        return components.url
    }

    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;?#%")
        return set
    }()

    /// Sends one request. Returns for any 2xx and for the statuses in `accept`;
    /// everything else becomes a `Failure`. The token goes into the header only,
    /// and no error ever carries the request.
    func send(
        _ method: String,
        _ path: [String],
        query: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: JSONValue? = nil,
        accept: Set<Int> = []
    ) async throws(Failure) -> (Data, HTTPURLResponse) {
        guard let url = url(path, query: query) else {
            throw .rejected(status: 0, message: "That site address isn't valid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.httpBody = body.json
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .offline
        }
        guard let http = response as? HTTPURLResponse else { throw .offline }

        let status = http.statusCode
        if (200..<300).contains(status) || accept.contains(status) { return (data, http) }
        if status == 401 { throw .unauthorized }
        throw .rejected(status: status, message: Self.message(in: data, status: status))
    }

    func decode<T: Decodable>(_ data: Data, _ response: HTTPURLResponse) throws(Failure) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw .rejected(status: response.statusCode, message: "The server's answer couldn't be read.")
        }
    }

    /// The server's own sentence from `{ "error": "…" }`, or a short generic one.
    static func message(in data: Data, status: Int) -> String {
        struct Body: Decodable { var error: String }
        if let body = try? JSONDecoder().decode(Body.self, from: data),
           !body.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return body.error
        }
        switch status {
        case 404: return "The server couldn't find that."
        case 500...: return "The server had a problem. Try again later."
        default: return "The server refused the request (\(status))."
        }
    }
}
