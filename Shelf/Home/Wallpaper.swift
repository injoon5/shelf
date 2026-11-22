import SwiftUI

/// What sits behind the icons: the user's photo, or a slow mesh gradient.
struct Wallpaper: View {
    @Environment(ShelfSettings.self) private var settings
    /// The gradient stops drifting while something covers the Home Screen.
    var isPaused = false

    var body: some View {
        Group {
            if let photo = settings.wallpaper {
                // Filled from the centre and clipped, the way Springboard crops a photo.
                Color.black.overlay {
                    Image(uiImage: photo).resizable().scaledToFill()
                }
                .clipped()
            } else {
                MeshWallpaper(isPaused: isPaused)
            }
        }
        .ignoresSafeArea()
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
    /// How far a point strays from its place, as a fraction of the screen.
    private static let reach: Float = 0.12
    private static let frameInterval: Double = 1 / 30

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: isPaused)) { context in
            let t = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Motion.wallpaperDrift) / Motion.wallpaperDrift) * 2 * .pi
            let r = Self.reach
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5 + r * sin(t), 0], [1, 0],
                [0, 0.5 + r * cos(t)], [0.5 + r * cos(t + 1), 0.5 + r * sin(t + 2)], [1, 0.5 - r * cos(t)],
                [0, 1], [0.5 - r * sin(t), 1], [1, 1],
            ], colors: scheme == .dark ? Self.dark : Self.light)
        }
    }
}
