import Foundation

/// One app's key-value store while it is in use: the values in memory, behind
/// a lock, so `ShelfDBProtocol` can answer from any thread without waiting.
///
/// CONTRACT — signatures are fixed; bodies belong to the Data package.
final class DBSession: Sendable {
    let slug: String

    init(slug: String, entries: [String: JSONValue] = [:]) {
        self.slug = slug
    }

    func value(for key: String) -> JSONValue? { nil }
    func all() -> [String: JSONValue] { [:] }
    func set(_ value: JSONValue, for key: String) {}
    func remove(_ key: String) {}
}

/// Every app's data on the phone (plan §8.3): one JSON file per app in
/// `Application Support/data/`, local first, synced with the server in the
/// background.
///
/// CONTRACT — signatures are fixed; bodies belong to the Data package.
actor AppData {
    static let shared = AppData(root: URL.applicationSupportDirectory.appending(path: "data"), api: { Account.api })

    private let root: URL
    private let api: @Sendable () -> API?

    init(root: URL, api: @escaping @Sendable () -> API?) {
        self.root = root
        self.api = api
    }

    /// Opens an app's store. Pulls changes first, for at most `pullTimeout`;
    /// after that the app runs with what is on the phone.
    func open(_ slug: String, pullTimeout: Duration = .seconds(1)) async -> DBSession { DBSession(slug: slug) }

    /// The app closed: save, and push what is dirty.
    func close(_ session: DBSession) async {}

    /// A throwaway store for a preview, optionally starting from a copy of an
    /// app's real data. Nothing written to it is saved or synced.
    func scratch(copying slug: String?) async -> DBSession { DBSession(slug: slug ?? "preview") }

    /// Pulls every listed app's changes. Called after a library sync.
    func pull(_ slugs: [String]) async {}

    /// Pushes everything dirty. Called when Shelf goes to the background.
    func pushAll() async {}

    /// Bytes stored per app, for Settings.
    func usage() async -> [String: Int] { [:] }

    /// Delete Data: every key of one app, here and (as tombstones) on the server.
    func deleteAll(for slug: String) async {}

    /// Sign Out: every file, with nothing pushed.
    func reset() async {}
}
