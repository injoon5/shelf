import Foundation
import Kiln

/// Each app's own folder, `Application Support/files/{slug}/` (plan §1.7,
/// §4.1): what `URL.documentsDirectory`, `FileManager` and the rest resolve
/// into when the app runs. Files stay on the phone: `DB` is what syncs. The
/// folder goes with the app.
struct AppFiles: Sendable {
    var root: URL

    static let standard = AppFiles(root: URL.applicationSupportDirectory.appending(path: "files", directoryHint: .isDirectory))

    /// The app's folder; nil for a slug that could name somewhere else.
    func folder(for slug: String) -> URL? {
        SlugFolder.isFileSafe(slug) ? root.appending(path: slug, directoryHint: .isDirectory) : nil
    }

    /// The folder as Kiln's context holds it.
    func kiln(for slug: String) -> KilnFiles? {
        folder(for: slug).map(KilnFiles.init(root:))
    }

    /// Bytes the app keeps in its folder.
    func usage(of slug: String) -> Int {
        folder(for: slug).map(KilnFiles.size(of:)) ?? 0
    }

    func remove(_ slug: String) {
        guard let folder = folder(for: slug) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }
}
