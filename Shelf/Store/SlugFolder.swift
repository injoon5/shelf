import Foundation

/// A folder with one file per app, `{slug}.{fileExtension}`: the cached
/// sources, and each app's data. Slugs come from the server, so one that
/// could name a file outside the folder (empty, hidden, or with a "/")
/// names none.
struct SlugFolder: Sendable {
    var root: URL
    var fileExtension: String

    enum Failure: Error, Equatable {
        case invalidSlug(String)
    }

    func url(for slug: String) -> URL? {
        let isFileSafe = !slug.isEmpty && !slug.hasPrefix(".") && !slug.contains("/") && !slug.contains("\0")
        return isFileSafe ? root.appending(path: slug + "." + fileExtension, directoryHint: .notDirectory) : nil
    }

    func read(_ slug: String) -> Data? {
        url(for: slug).flatMap { try? Data(contentsOf: $0) }
    }

    func contains(_ slug: String) -> Bool {
        guard let url = url(for: slug) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func size(of slug: String) -> Int {
        guard let url = url(for: slug) else { return 0 }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
    }

    func write(_ data: Data, for slug: String) throws {
        guard let url = url(for: slug) else { throw Failure.invalidSlug(slug) }
        try write(data, to: url)
    }

    /// Writes any file in the folder, atomically, readable only once the
    /// phone has been unlocked since it started.
    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func remove(_ slug: String) {
        guard let url = url(for: slug) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func slugs() -> [String] {
        let suffix = "." + fileExtension
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(suffix) }.map { String($0.dropLast(suffix.count)) }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
