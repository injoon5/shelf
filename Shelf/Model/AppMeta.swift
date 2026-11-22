import Foundation

/// What the server lists for an app: everything except its source.
struct AppMeta: Codable, Identifiable, Hashable, Sendable {
    var slug: String
    /// The label under the icon.
    var name: String
    /// An SF Symbol name, or nil for the generic glyph.
    var icon: String?
    var tint: Tint
    /// A hash of the app's content. Opaque: only ever compared for equality.
    var version: String
    /// Epoch milliseconds.
    var updatedAt: Int
    /// Whether the server holds an earlier version to go back to.
    var revertible: Bool

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, icon, tint, version, revertible
        case updatedAt = "updated_at"
    }

    init(slug: String, name: String, icon: String? = nil, tint: Tint = .blue,
         version: String = "", updatedAt: Int = 0, revertible: Bool = false) {
        self.slug = slug
        self.name = name
        self.icon = icon
        self.tint = tint
        self.version = version
        self.updatedAt = updatedAt
        self.revertible = revertible
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        name = try c.decode(String.self, forKey: .name)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        tint = try c.decodeIfPresent(Tint.self, forKey: .tint) ?? .blue
        version = try c.decode(String.self, forKey: .version)
        updatedAt = try c.decodeIfPresent(Int.self, forKey: .updatedAt) ?? 0
        revertible = try c.decodeIfPresent(Bool.self, forKey: .revertible) ?? false
    }
}

/// An app with its source, as `GET /api/apps/{slug}` returns it.
struct AppFull: Decodable, Sendable {
    var meta: AppMeta
    var source: String

    private enum CodingKeys: String, CodingKey { case source }

    init(meta: AppMeta, source: String) {
        self.meta = meta
        self.source = source
    }

    init(from decoder: Decoder) throws {
        meta = try AppMeta(from: decoder)
        source = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .source)
    }
}

/// An app as the phone holds it: the server's listing, plus what is on disk.
struct CachedApp: Codable, Identifiable, Hashable, Sendable {
    /// What the server last listed.
    var meta: AppMeta
    /// The version whose source is on disk, or nil when none has downloaded yet.
    /// It lags `meta.version` when a download failed; the next sync retries.
    var cachedVersion: String?
    /// The blue dot: added or updated, and not opened since.
    var isNew: Bool = false

    var id: String { meta.slug }
    var slug: String { meta.slug }
    /// There is source to run, even if it is not the newest.
    var isRunnable: Bool { cachedVersion != nil }
    var isCurrent: Bool { cachedVersion == meta.version }
}

/// `index.json`: everything the Home Screen needs before the first frame.
struct LibraryIndex: Codable, Equatable, Sendable {
    /// The list's ETag. It is kept only when every source is current, so a
    /// failed download can never hide behind a `304`.
    var etag: String?
    var apps: [CachedApp] = []
    var syncedAt: Date?
}
