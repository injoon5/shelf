import Foundation

/// The library on disk: `index.json` and one `{slug}.swift` per app, under
/// `Application Support/apps/`. Offline, this is the whole library.
///
/// CONTRACT — signatures are fixed; bodies belong to the Store package.
struct AppCache: Sendable {
    /// The folder that holds `index.json` and the sources.
    var root: URL

    static let standard = AppCache(root: URL.applicationSupportDirectory.appending(path: "apps"))

    /// Synchronous, so the Home Screen can read it before its first frame.
    /// A missing or unreadable index is an empty library.
    func readIndex() -> LibraryIndex { LibraryIndex() }
    func writeIndex(_ index: LibraryIndex) throws {}

    func source(for slug: String) -> String? { nil }
    /// Atomic, with `.completeFileProtectionUntilFirstUserAuthentication`.
    func writeSource(_ source: String, for slug: String) throws {}
    func removeSource(for slug: String) {}
    /// Sign Out: the index and every source.
    func removeAll() {}
}
