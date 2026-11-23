import Foundation

/// The library on disk: `index.json` and one `{slug}.swift` per app, under
/// `Application Support/apps/`. Offline, this is the whole library.
struct AppCache: Sendable {
    private let sources: SlugFolder

    init(root: URL) {
        sources = SlugFolder(root: root, fileExtension: "swift")
    }

    static let standard = AppCache(root: URL.applicationSupportDirectory.appending(path: "apps"))

    /// The folder that holds `index.json` and the sources.
    var root: URL { sources.root }

    private var indexURL: URL { root.appending(path: "index.json") }
    private var deletionsURL: URL { root.appending(path: "deletions.json") }

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
        try sources.write(try encoder.encode(index), to: indexURL)
    }

    /// Deletions the server hasn't heard about yet, oldest first: made
    /// offline, or cut off by a quit. The next sync sends them before it
    /// lists apps. Kept beside the index, so Sign Out drops them with it.
    func readDeletions() -> [String] {
        guard let data = try? Data(contentsOf: deletionsURL),
              let slugs = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return slugs
    }

    func writeDeletions(_ slugs: [String]) throws {
        if slugs.isEmpty {
            try? FileManager.default.removeItem(at: deletionsURL)
        } else {
            try sources.write(try JSONEncoder().encode(slugs), to: deletionsURL)
        }
    }

    func source(for slug: String) -> String? {
        sources.read(slug).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Whether a source file is on disk, without reading it.
    func hasSource(for slug: String) -> Bool {
        sources.contains(slug)
    }

    func writeSource(_ source: String, for slug: String) throws {
        try sources.write(Data(source.utf8), for: slug)
    }

    func removeSource(for slug: String) {
        sources.remove(slug)
    }

    /// The slugs of every source file on disk, listed or not.
    func sourceSlugs() -> [String] {
        sources.slugs()
    }

    /// Sign Out: the index, the queued deletions and every source.
    func removeAll() {
        sources.removeAll()
    }
}
