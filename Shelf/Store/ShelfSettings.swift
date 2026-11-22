import SwiftUI
import Observation

/// How icons are drawn: in their own colours, or as clear glass. Both follow
/// light and dark mode, as the system's Home Screen icons do.
enum IconStyle: String, CaseIterable, Identifiable, Sendable {
    case color, clear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .color: "Color"
        case .clear: "Clear"
        }
    }
}

/// What is behind the icons.
enum WallpaperChoice: String, CaseIterable, Identifiable, Sendable {
    /// The photo Shelf ships with.
    case photo
    /// The slow mesh gradient.
    case gradient
    /// A photo the user picked.
    case custom

    var id: String { rawValue }
}

/// Shelf's preferences, kept in Shelf's own defaults suite.
@MainActor
@Observable
final class ShelfSettings {
    var iconStyle: IconStyle { didSet { defaults.set(iconStyle.rawValue, forKey: "iconStyle") } }
    /// Whether the change prompt carries the app's full source.
    var includeSource: Bool { didSet { defaults.set(includeSource, forKey: "includeSource") } }
    var wallpaper: WallpaperChoice { didSet { defaults.set(wallpaper.rawValue, forKey: "wallpaper") } }
    /// The photo the user picked, when there is one.
    private(set) var customWallpaper: UIImage?

    private static let wallpaperSide: CGFloat = 3000
    @ObservationIgnored private let defaults = Account.defaults
    @ObservationIgnored private let wallpaperURL = URL.applicationSupportDirectory.appending(path: "wallpaper.jpg")

    init() {
        // Styles Shelf no longer offers (Default, Dark, Tinted) come back as Color.
        iconStyle = IconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .color
        includeSource = defaults.object(forKey: "includeSource") as? Bool ?? true
        let picked = UIImage(contentsOfFile: wallpaperURL.path)
        let saved = WallpaperChoice(rawValue: defaults.string(forKey: "wallpaper") ?? "") ?? .photo
        wallpaper = saved == .custom && picked == nil ? .photo : saved
        customWallpaper = picked
    }

    /// Saves a picked photo and makes it the wallpaper.
    func setCustomWallpaper(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        // Photos are far larger than any screen; keep what a screen can show.
        let fitted = image.preparingThumbnail(of: image.size.fitted(longest: Self.wallpaperSide)) ?? image
        try? FileManager.default.createDirectory(at: wallpaperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fitted.jpegData(compressionQuality: 0.9)?.write(to: wallpaperURL, options: .atomic)
        customWallpaper = fitted
        wallpaper = .custom
    }
}

private extension CGSize {
    /// This size scaled down so its longer side is at most `longest`.
    func fitted(longest: CGFloat) -> CGSize {
        let factor = min(1, longest / max(width, height, 1))
        return CGSize(width: width * factor, height: height * factor)
    }
}
