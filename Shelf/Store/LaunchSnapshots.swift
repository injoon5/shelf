import CryptoKit
import Foundation

/// Where each app's launch snapshot lives (plan §0.8): one folder per app,
/// `Caches/Snapshots/{slug}/`, a picture per appearance and text size side
/// by side. Caches, because the system may clear them and the app opens
/// fine without one. Delete App and Sign Out clear them (`AppCleanup`).
///
/// A snapshot is only shown while it is fresh: taken from the same source,
/// in the same light or dark, at the same text size. All three are in its
/// file name (`Key`), so finding a fresh one is one look in the folder, and
/// a picture of an older source is deleted when a newer one is written.
struct LaunchSnapshots: Sendable {
    var root: URL

    static let standard = LaunchSnapshots(root: URL.cachesDirectory.appending(path: "Snapshots"))

    /// What a snapshot must match to stand in for the app.
    struct Key: Hashable, Sendable {
        /// `revision(of:)` the source it was taken from.
        var revision: String
        var dark: Bool
        /// The text size, as UIKit names it (`UIContentSizeCategory`'s raw value).
        var textSize: String

        static let fileExtension = "jpg"

        /// `{revision}-{light|dark}-{text size}.jpg`. The text size loses
        /// UIKit's prefix (`UICTContentSizeCategoryL` is `L`), and anything
        /// that isn't a letter or digit, so it can't leave the folder.
        var fileName: String {
            "\(revision)-\(dark ? "dark" : "light")-\(Self.short(textSize)).\(Self.fileExtension)"
        }

        /// The key a file name was written for, or nil for anything else.
        init?(fileName: String) {
            guard fileName.hasSuffix("." + Self.fileExtension) else { return nil }
            let parts = fileName.dropLast(Self.fileExtension.count + 1).split(separator: "-")
            guard parts.count == 3, parts[1] == "dark" || parts[1] == "light", !parts[0].isEmpty, !parts[2].isEmpty else { return nil }
            revision = String(parts[0])
            dark = parts[1] == "dark"
            textSize = String(parts[2])
        }

        init(revision: String, dark: Bool, textSize: String) {
            self.revision = revision
            self.dark = dark
            self.textSize = textSize
        }

        /// Whether a snapshot written as `self` stands in for `other`. A key
        /// read back from a file name has the short text size.
        func matches(_ other: Key) -> Bool {
            revision == other.revision && dark == other.dark && Self.short(textSize) == Self.short(other.textSize)
        }

        private static func short(_ textSize: String) -> String {
            let name = textSize.hasPrefix("UICTContentSizeCategory") ? String(textSize.dropFirst("UICTContentSizeCategory".count)) : textSize
            let kept = name.unicodeScalars.filter { ("a"..."z").contains($0) || ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
            return kept.isEmpty ? "unspecified" : String(String.UnicodeScalarView(kept))
        }
    }

    /// The source's revision: the first 16 hex digits of its SHA-256. The
    /// server's `version` hashes more than the source (the name, the icon),
    /// and a picture only goes stale when the code does.
    static func revision(of source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Nil for a slug that could name a folder outside `root`.
    func folder(for slug: String) -> URL? {
        SlugFolder.isFileSafe(slug) ? root.appending(path: slug, directoryHint: .isDirectory) : nil
    }

    /// Where `slug`'s snapshot for `key` is written.
    func file(for slug: String, _ key: Key) -> URL? {
        folder(for: slug)?.appending(path: key.fileName, directoryHint: .notDirectory)
    }

    /// The fresh snapshot for `key`, if there is one.
    func fresh(_ slug: String, _ key: Key) -> URL? {
        guard let folder = folder(for: slug),
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return nil }
        guard let name = names.first(where: { Key(fileName: $0)?.matches(key) == true }) else { return nil }
        return folder.appending(path: name, directoryHint: .notDirectory)
    }

    /// Writes `picture` (already encoded) as `slug`'s snapshot for `key`,
    /// and deletes the app's snapshots of any other source: they can never
    /// be fresh again.
    func write(_ picture: Data, for slug: String, _ key: Key) throws {
        guard let folder = folder(for: slug), let file = file(for: slug, key) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try picture.write(to: file, options: .atomic)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in names where name != key.fileName && Key(fileName: name)?.revision != key.revision {
            try? FileManager.default.removeItem(at: folder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    func remove(_ slug: String) {
        guard let folder = folder(for: slug) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
