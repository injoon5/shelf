import SwiftUI
import Observation

/// How icons are drawn. It mirrors the system's Home Screen options, which
/// Shelf has no way to read.
enum IconStyle: String, CaseIterable, Identifiable, Sendable {
    case automatic, standard, dark, clear, tinted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .standard: "Default"
        case .dark: "Dark"
        case .clear: "Clear"
        case .tinted: "Tinted"
        }
    }

    /// Automatic follows light and dark mode.
    func resolved(for scheme: ColorScheme) -> IconStyle {
        self == .automatic ? (scheme == .dark ? .dark : .standard) : self
    }
}

/// Shelf's preferences, kept in Shelf's own defaults suite.
@MainActor
@Observable
final class ShelfSettings {
    var iconStyle: IconStyle { didSet { defaults.set(iconStyle.rawValue, forKey: "iconStyle") } }
    /// The one colour Tinted icons take.
    var accent: Tint { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    /// Whether the change prompt carries the app's full source.
    var includeSource: Bool { didSet { defaults.set(includeSource, forKey: "includeSource") } }
    /// The photo wallpaper, when there is one. Changing it redraws the Home Screen.
    private(set) var wallpaper: UIImage?

    private static let wallpaperSide: CGFloat = 3000
    @ObservationIgnored private let defaults = Account.defaults
    @ObservationIgnored private let wallpaperURL = URL.applicationSupportDirectory.appending(path: "wallpaper.jpg")

    init() {
        iconStyle = IconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .automatic
        accent = Tint(rawValue: defaults.string(forKey: "accent") ?? "") ?? .blue
        includeSource = defaults.object(forKey: "includeSource") as? Bool ?? true
        wallpaper = UIImage(contentsOfFile: wallpaperURL.path)
    }

    /// Sets the photo wallpaper, or goes back to the built-in one with nil.
    func setWallpaper(_ data: Data?) {
        guard let data, let image = UIImage(data: data) else {
            try? FileManager.default.removeItem(at: wallpaperURL)
            wallpaper = nil
            return
        }
        // Photos are far larger than any screen; keep what a screen can show.
        let fitted = image.preparingThumbnail(of: image.size.fitted(longest: Self.wallpaperSide)) ?? image
        try? FileManager.default.createDirectory(at: wallpaperURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fitted.jpegData(compressionQuality: 0.9)?.write(to: wallpaperURL, options: .atomic)
        wallpaper = fitted
    }
}

private extension CGSize {
    /// This size scaled down so its longer side is at most `longest`.
    func fitted(longest: CGFloat) -> CGSize {
        let factor = min(1, longest / max(width, height, 1))
        return CGSize(width: width * factor, height: height * factor)
    }
}
