import Foundation

/// Brings the cache in line with the server (plan §4). It is the only writer
/// of `index.json` once the app is running.
///
/// CONTRACT — signatures are fixed; bodies belong to the Store package.
actor SyncEngine {
    /// What a sync reports while it runs, so icons can take their place first
    /// and fill in after.
    enum Event: Sendable {
        /// The server's list, merged with what is cached. Sent before any download.
        case listed([CachedApp])
        case downloading(slug: String)
        case finished(slug: String, ok: Bool)
    }

    private let cache: AppCache
    private let api: @Sendable () -> API?

    /// `api` returns nil while signed out.
    init(cache: AppCache, api: @escaping @Sendable () -> API?) {
        self.cache = cache
        self.api = api
    }

    /// One full sync. Returns the index as written.
    ///
    /// Throws `API.Failure` only when the list itself can't be fetched; the
    /// cache is then untouched. A source that fails to download does not
    /// throw: the app keeps its old version (or none) and the etag is dropped
    /// so the next sync tries again.
    func sync(onEvent: @escaping @Sendable (Event) -> Void = { _ in }) async throws -> LibraryIndex { cache.readIndex() }

    /// Downloads one app's source now: the tap on an icon that has none.
    func fetch(_ slug: String) async throws -> LibraryIndex { cache.readIndex() }

    /// Clears an app's blue dot.
    func markOpened(_ slug: String) -> LibraryIndex { cache.readIndex() }

    /// Sign Out: the cache, and every app's `@AppStorage` keys.
    func reset() {}
}
