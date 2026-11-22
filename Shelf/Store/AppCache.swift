import Foundation

/// The library on disk: `index.json` and one `{slug}.swift` per app, under
/// `Application Support/apps/`. Offline, this is the whole library.
struct AppCache: Sendable {
    /// The folder that holds `index.json` and the sources.
    var root: URL

    static let standard = AppCache(root: URL.applicationSupportDirectory.appending(path: "apps"))

    enum Failure: Error, Equatable {
        /// A slug that can't be a file name (empty, hidden, or with a "/").
        case invalidSlug(String)
    }

    private var indexURL: URL { root.appending(path: "index.json") }

    /// Synchronous, so the Home Screen can read it before its first frame.
    /// A missing or unreadable index is an empty library.
    func readIndex() -> LibraryIndex {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(LibraryIndex.self, from: data) else { return LibraryIndex() }
        return index
    }

    func writeIndex(_ index: LibraryIndex) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try write(try encoder.encode(index), to: indexURL)
    }

    func source(for slug: String) -> String? {
        guard let url = sourceURL(slug) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Whether a source file is on disk, without reading it.
    func hasSource(for slug: String) -> Bool {
        guard let url = sourceURL(slug) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Atomic, with `.completeFileProtectionUntilFirstUserAuthentication`.
    func writeSource(_ source: String, for slug: String) throws {
        guard let url = sourceURL(slug) else { throw Failure.invalidSlug(slug) }
        try write(Data(source.utf8), to: url)
    }

    func removeSource(for slug: String) {
        guard let url = sourceURL(slug) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The slugs of every source file on disk, listed or not.
    func sourceSlugs() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".swift") }.map { String($0.dropLast(".swift".count)) }
    }

    /// Sign Out: the index and every source.
    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Private

    private func sourceURL(_ slug: String) -> URL? {
        guard Self.isFileSafe(slug) else { return nil }
        return root.appending(path: slug + ".swift", directoryHint: .notDirectory)
    }

    static func isFileSafe(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\0")
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
