import SwiftUI
import Observation

/// Whether icons are light or dark: with the system, or held at one
/// whatever the system does, as Springboard's Customize panel holds them.
/// Only the icons: labels, the dock's glass and the wallpaper always follow
/// the system.
enum IconAppearance: String, CaseIterable, Identifiable, Sendable {
    case automatic, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }

    /// The tone every icon is drawn in while the system is `style`. The one
    /// place this setting is read: the stage sets the result on the window
    /// (`IconToneTrait`), and every icon reads that.
    func tone(system style: UIUserInterfaceStyle) -> IconTone {
        switch self {
        case .automatic: IconTone(style)
        case .light: .light
        case .dark: .dark
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
    var iconAppearance: IconAppearance { didSet { defaults.set(iconAppearance.rawValue, forKey: Self.iconAppearanceKey) } }
    /// Whether the change prompt carries the app's full source.
    var includeSource: Bool { didSet { defaults.set(includeSource, forKey: "includeSource") } }
    var wallpaper: WallpaperChoice { didSet { defaults.set(wallpaper.rawValue, forKey: "wallpaper") } }
    /// The photo the user picked, when there is one.
    private(set) var customWallpaper: UIImage?

    private static let wallpaperSide: CGFloat = 3000
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let wallpaperURL = URL.applicationSupportDirectory.appending(path: "wallpaper.jpg")
    private static let iconAppearanceKey = "iconAppearance"
    /// What Icon Appearance replaced: Icon Style, Color or Clear (and before
    /// that Default, Dark and Tinted). None of them chose light or dark, so
    /// every one reads as Automatic.
    static let retiredIconStyleKey = "iconStyle"

    init(defaults: UserDefaults = Account.defaults) {
        self.defaults = defaults
        defaults.removeObject(forKey: Self.retiredIconStyleKey)
        iconAppearance = IconAppearance(rawValue: defaults.string(forKey: Self.iconAppearanceKey) ?? "") ?? .automatic
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
