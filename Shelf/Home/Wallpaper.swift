import SwiftUI
import CoreImage

/// What sits behind the icons: Shelf's own photo, the user's, or a slow mesh
/// gradient.
@MainActor
struct Wallpaper: View {
    @Environment(ShelfSettings.self) private var settings
    /// The gradient stops drifting while something covers the Home Screen.
    var isPaused = false

    var body: some View {
        Group {
            if let picture = Self.picture(settings) {
                photo(Image(uiImage: picture))
            } else {
                MeshWallpaper(isPaused: isPaused)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private static let shipped = UIImage(resource: .wallpaper)

    /// The photo behind the icons, or nil for the gradient.
    static func picture(_ settings: ShelfSettings) -> UIImage? {
        #if DEBUG
        if let file = Demo.wallpaperFile { return file }
        #endif
        switch settings.wallpaper {
        case .gradient: return nil
        case .custom: return settings.customWallpaper ?? shipped
        case .photo: return shipped
        }
    }

    private static var tones: [String: ColorScheme] = [:]
    private static let imaging = CIContext()

    /// Whether what sits over a horizontal band of the screen (its top and
    /// bottom as fractions of the screen's height) wants light or dark
    /// content: the band's average brightness in the wallpaper, cropped the
    /// way it is drawn, and darkened by `dim`. Worked out once per photo;
    /// the gradient is dark in both modes.
    static func tone(_ settings: ShelfSettings, screen: CGSize, band: ClosedRange<CGFloat>, dim: Double = 0) -> ColorScheme {
        guard let picture = picture(settings), let image = CIImage(image: picture) else { return .dark }
        let key = "\(ObjectIdentifier(picture)) \(screen) \(band) \(dim)"
        if let known = tones[key] { return known }

        let full = image.extent
        let aspect = screen.width / max(screen.height, 1)
        let visible = full.width / full.height > aspect
            ? CGSize(width: full.height * aspect, height: full.height)
            : CGSize(width: full.width, height: full.width / aspect)
        // Core Image counts up from the bottom.
        let region = CGRect(x: full.midX - visible.width / 2,
                            y: full.midY + visible.height / 2 - band.upperBound * visible.height,
                            width: visible.width,
                            height: (band.upperBound - band.lowerBound) * visible.height)
        var pixel = [UInt8](repeating: 0, count: 4)
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: region)])
        imaging.render(average, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let luminance = (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
        let tone: ColorScheme = luminance * (1 - dim) > HomeMetrics.brightBackdrop ? .light : .dark
        tones[key] = tone
        return tone
    }

    /// Filled from the centre and clipped, the way Springboard crops a photo.
    private func photo(_ image: Image) -> some View {
        Color.black.overlay {
            image.resizable().scaledToFill()
        }
        .clipped()
    }
}

/// A 3×3 mesh in deep blue and violet. The corners stay put; the points
/// between them wander on a twenty-second loop.
private struct MeshWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var isPaused: Bool

    private static let light: [Color] = [
        Color(red: 0.36, green: 0.52, blue: 0.98), Color(red: 0.45, green: 0.44, blue: 0.96), Color(red: 0.62, green: 0.40, blue: 0.93),
        Color(red: 0.20, green: 0.38, blue: 0.92), Color(red: 0.40, green: 0.33, blue: 0.90), Color(red: 0.70, green: 0.42, blue: 0.88),
        Color(red: 0.11, green: 0.20, blue: 0.62), Color(red: 0.25, green: 0.19, blue: 0.68), Color(red: 0.44, green: 0.22, blue: 0.70),
    ]
    private static let dark: [Color] = [
        Color(red: 0.10, green: 0.17, blue: 0.48), Color(red: 0.16, green: 0.14, blue: 0.46), Color(red: 0.27, green: 0.13, blue: 0.44),
        Color(red: 0.05, green: 0.10, blue: 0.36), Color(red: 0.13, green: 0.09, blue: 0.36), Color(red: 0.25, green: 0.11, blue: 0.36),
        Color(red: 0.02, green: 0.03, blue: 0.14), Color(red: 0.05, green: 0.03, blue: 0.17), Color(red: 0.10, green: 0.04, blue: 0.20),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: Motion.wallpaperFrameInterval, paused: isPaused)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Motion.wallpaperDrift) / Motion.wallpaperDrift) * 2 * .pi
            let r = HomeMetrics.wallpaperReach
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + r * sin(t), 0], [1, 0],
                [0, 0.5 + r * cos(t)], [0.5 + r * cos(t + 1), 0.5 + r * sin(t + 2)], [1, 0.5 - r * cos(t)],
                [0, 1], [0.5 - r * sin(t), 1], [1, 1],
            ], colors: scheme == .dark ? Self.dark : Self.light)
        }
    }
}
