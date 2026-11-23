import Foundation

/// Where each app's launch snapshot lives (plan §0.8): one folder per app,
/// `Caches/Snapshots/{slug}/`, so a snapshot per appearance and text size
/// can sit side by side. Caches, because the system may clear them and the
/// app opens fine without one.
///
/// Nothing writes here yet. Delete App and Sign Out already clear it, so the
/// launch screen only has to write into `folder(for:)`.
struct LaunchSnapshots: Sendable {
    var root: URL

    static let standard = LaunchSnapshots(root: URL.cachesDirectory.appending(path: "Snapshots"))

    /// Nil for a slug that could name a folder outside `root`.
    func folder(for slug: String) -> URL? {
        SlugFolder.isFileSafe(slug) ? root.appending(path: slug, directoryHint: .isDirectory) : nil
    }

    func remove(_ slug: String) {
        guard let folder = folder(for: slug) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
