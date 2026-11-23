import SwiftUI
import UIKit

/// What an app opens on before it is built (plan §0.8): its last snapshot
/// when one is fresh, or else a plain surface shaped like its first screen
/// (`LaunchLayout`), as iOS opens a resumed app on its snapshot and a cold
/// one on its launch screen. No glyph and no tint: those are the icon's,
/// and the card crossfades away from the icon early in the open.
///
/// The surface is drawn at full-screen size; a card's face scales it.
final class LaunchSurfaceView: UIView {
    let layout: LaunchLayout
    private let bar: UINavigationBar?
    /// Where the bar sits. A card's face isn't laid out against the
    /// screen's safe area, so the stage says where the status bar ends.
    private let top: CGFloat?

    init(layout: LaunchLayout, top: CGFloat? = nil) {
        self.layout = layout
        self.top = top
        bar = layout.navigationBar ? UINavigationBar() : nil
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = layout.grouped ? .systemGroupedBackground : .systemBackground
        if let dark = layout.dark { overrideUserInterfaceStyle = dark ? .dark : .light }
        if let bar {
            // Empty: no title, no buttons. The system's own bar for the
            // appearance, which over a screen at rest is the background.
            bar.items = [UINavigationItem()]
            addSubview(bar)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let bar else { return }
        let y = top ?? safeAreaInsets.top
        bar.frame = CGRect(x: 0, y: y, width: bounds.width, height: bar.sizeThatFits(bounds.size).height)
    }
}

/// The surface in SwiftUI, for the New App preview, which never has a
/// snapshot: what is being tried has never run.
struct LaunchSurface: UIViewRepresentable {
    var layout: LaunchLayout

    func makeUIView(context: Context) -> LaunchSurfaceView {
        LaunchSurfaceView(layout: layout)
    }

    func updateUIView(_ view: LaunchSurfaceView, context: Context) {}
}

/// Each app's last snapshot, taken as its card closes, kept on disk in
/// `LaunchSnapshots` and the latest few in memory, so opening an app just
/// closed shows it at once.
///
/// Reading one back from disk is never done on the main thread in the
/// middle of an open: the file is read and decoded off it, and the card
/// takes the picture when it arrives (`AppCard.showSnapshot`), usually
/// while the icon still covers the surface.
@MainActor
final class LaunchSnapshotStore {
    let files: LaunchSnapshots
    private var recent: [(slug: String, key: LaunchSnapshots.Key, image: UIImage)] = []

    init(files: LaunchSnapshots) {
        self.files = files
    }

    /// Pictures still being written to disk.
    private var writing: Set<String> = []

    /// The fresh snapshot for `key`, if it is in memory. Only while its
    /// file is still there (or on its way): Delete App and Sign Out clear
    /// the files, and a picture of a signed-out account's app must go with
    /// them.
    func cached(_ slug: String, _ key: LaunchSnapshots.Key) -> UIImage? {
        guard let hit = recent.first(where: { $0.slug == slug && $0.key.matches(key) }) else { return nil }
        guard writing.contains(Self.id(slug, hit.key)) || files.fresh(slug, key) != nil else {
            forget(slug)
            return nil
        }
        return hit.image
    }

    private static func id(_ slug: String, _ key: LaunchSnapshots.Key) -> String { slug + "/" + key.fileName }

    /// The fresh snapshot for `key`, from memory or decoded from disk off
    /// the main thread at the screen's `scale`; nil if there is none.
    func load(_ slug: String, _ key: LaunchSnapshots.Key, scale: CGFloat) async -> UIImage? {
        if let image = cached(slug, key) { return image }
        let files = files
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let url = files.fresh(slug, key), let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
            // At the screen's scale: the file is pixels.
            let scaled = image.cgImage.map { UIImage(cgImage: $0, scale: scale, orientation: .up) } ?? image
            return scaled.preparingForDisplay() ?? scaled
        }.value
        if let image { remember(slug, key, image) }
        return image
    }

    /// Keeps `image` as `slug`'s snapshot for `key`, and writes it to disk
    /// off the main thread.
    func save(_ image: UIImage, for slug: String, _ key: LaunchSnapshots.Key) {
        remember(slug, key, image)
        let files = files, id = Self.id(slug, key)
        writing.insert(id)
        Task {
            await Task.detached(priority: .utility) {
                guard let data = image.jpegData(compressionQuality: RunnerMetrics.snapshotQuality) else { return }
                try? files.write(data, for: slug, key)
            }.value
            writing.remove(id)
        }
    }

    /// Forgets `slug`'s pictures in memory; the files go with Delete App.
    func forget(_ slug: String) {
        recent.removeAll { $0.slug == slug }
    }

    private func remember(_ slug: String, _ key: LaunchSnapshots.Key, _ image: UIImage) {
        recent.removeAll { $0.slug == slug }
        recent.insert((slug, key, image), at: 0)
        if recent.count > RunnerMetrics.snapshotsInMemory { recent.removeLast(recent.count - RunnerMetrics.snapshotsInMemory) }
    }
}

extension LaunchSnapshots.Key {
    /// The key for `source` under `traits`: its appearance and text size.
    init(source: String, traits: UITraitCollection) {
        var size = traits.preferredContentSizeCategory
        if size == .unspecified { size = .large }
        self.init(revision: LaunchSnapshots.revision(of: source), dark: traits.userInterfaceStyle == .dark,
                  textSize: size.rawValue)
    }
}
