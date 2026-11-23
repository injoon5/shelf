import SwiftUI
import UIKit
import CoreImage

/// What sits behind the icons: Shelf's own photo, the user's, or a mesh
/// gradient. A layer whose contents are the picture, which never moves, so
/// it costs nothing per frame.
final class WallpaperView: UIView {
    private let settings: ShelfSettings

    init(settings: ShelfSettings) {
        self.settings = settings
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        // Filled from the centre and cropped, the way Springboard crops a photo.
        layer.contentsGravity = .resizeAspectFill
        layer.masksToBounds = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: WallpaperView, _) in
            view.setNeedsUpdateProperties()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateProperties() {
        super.updateProperties()
        // Reads the settings, so a new choice or a new photo redraws.
        let picture = Wallpaper.picture(settings) ?? Wallpaper.gradient(dark: traitCollection.userInterfaceStyle == .dark,
                                                                         size: bounds.size)
        layer.contents = picture?.cgImage
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsUpdateProperties()
    }
}

/// The wallpaper in SwiftUI, behind the first-run screen.
struct WallpaperBackground: UIViewRepresentable {
    @Environment(ShelfSettings.self) private var settings

    func makeUIView(context: Context) -> WallpaperView { WallpaperView(settings: settings) }
    func updateUIView(_ view: WallpaperView, context: Context) {}
}

/// The wallpaper's picture, and what it says about the content over it.
@MainActor
enum Wallpaper {
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
    /// The picture `tones` were worked out for. Held weakly and compared by
    /// identity, so a new photo can never be read as one that is gone.
    private static weak var tonesPicture: UIImage?
    private static let imaging = CIContext()

    /// Whether what sits over a horizontal band of the screen (its top and
    /// bottom as fractions of the screen's height) wants light or dark
    /// content: the band's average brightness in the wallpaper, cropped the
    /// way it is drawn, and darkened by `dim`. Worked out once per photo;
    /// the gradient is dark in both modes.
    static func tone(_ settings: ShelfSettings, screen: CGSize, band: ClosedRange<CGFloat>, dim: Double = 0) -> ColorScheme {
        guard let picture = picture(settings), let image = CIImage(image: picture) else { return .dark }
        if tonesPicture !== picture {
            tones = [:]
            tonesPicture = picture
        }
        let key = "\(screen) \(band) \(dim)"
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

    private static var gradients: [String: UIImage] = [:]

    /// The mesh gradient for one appearance, drawn once at `size` and kept:
    /// it doesn't move, so there is nothing to draw again.
    static func gradient(dark: Bool, size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let key = "\(dark) \(size)"
        if let known = gradients[key] { return known }
        let renderer = ImageRenderer(content: MeshWallpaper(dark: dark).frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = renderer.uiImage
        gradients[key] = image
        return image
    }
}

/// A 3×3 mesh in deep blue and violet. The corners stay put; the points
/// between them wander on a twenty-second loop.
private struct MeshWallpaper: View {
    var dark: Bool

    private static let lightColors: [Color] = [
        Color(red: 0.36, green: 0.52, blue: 0.98), Color(red: 0.45, green: 0.44, blue: 0.96), Color(red: 0.62, green: 0.40, blue: 0.93),
        Color(red: 0.20, green: 0.38, blue: 0.92), Color(red: 0.40, green: 0.33, blue: 0.90), Color(red: 0.70, green: 0.42, blue: 0.88),
        Color(red: 0.11, green: 0.20, blue: 0.62), Color(red: 0.25, green: 0.19, blue: 0.68), Color(red: 0.44, green: 0.22, blue: 0.70),
    ]
    private static let darkColors: [Color] = [
        Color(red: 0.10, green: 0.17, blue: 0.48), Color(red: 0.16, green: 0.14, blue: 0.46), Color(red: 0.27, green: 0.13, blue: 0.44),
        Color(red: 0.05, green: 0.10, blue: 0.36), Color(red: 0.13, green: 0.09, blue: 0.36), Color(red: 0.25, green: 0.11, blue: 0.36),
        Color(red: 0.02, green: 0.03, blue: 0.14), Color(red: 0.05, green: 0.03, blue: 0.17), Color(red: 0.10, green: 0.04, blue: 0.20),
    ]

    var body: some View {
        // The middle points sit off-centre, where the gradient that used to
        // drift started, so it reads the same, still.
        let r = HomeMetrics.wallpaperReach
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5 + r], [0.5 + r * cos(1), 0.5 + r * sin(2)], [1, 0.5 - r],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: dark ? Self.darkColors : Self.lightColors)
    }
}
