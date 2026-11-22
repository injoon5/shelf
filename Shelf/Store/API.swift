import Foundation

/// The ij5.dev API, as Shelf uses it. One value per (site, token) pair.
///
/// CONTRACT — signatures are fixed; bodies belong to the Store package.
/// Every method throws `API.Failure` and nothing else.
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

        enum Status: Equatable, Sendable {
            case waiting
            /// The key installed this slug.
            case used(slug: String?)
            /// Expired, revoked or unknown.
            case expired
        }
    }

    // MARK: Apps

    func apps(ifNoneMatch etag: String?) async throws -> Listing { throw Failure.offline }
    func app(_ slug: String) async throws -> AppFull { throw Failure.offline }
    /// `PUT /api/apps/{slug}`: creates or replaces the app.
    func install(slug: String, name: String, icon: String?, tint: Tint, source: String) async throws -> AppMeta { throw Failure.offline }
    func revert(_ slug: String) async throws -> AppMeta { throw Failure.offline }

    // MARK: App data

    func changes(for slug: String, since rev: Int) async throws -> DataChanges { throw Failure.offline }
    /// The batch write. Returns the server's new `rev`.
    func push(to slug: String, set: [String: JSONValue], delete: [String]) async throws -> Int { throw Failure.offline }

    // MARK: Install keys

    /// A key for one new app (`slug == nil`) or one update of `slug`.
    func mintKey(for slug: String?) async throws -> InstallKey { throw Failure.offline }
    func keyStatus(_ id: String) async throws -> InstallKey.Status { throw Failure.offline }
    func revokeKey(_ id: String) async throws { throw Failure.offline }
}
