import SwiftUI

/// Every spring, and every duration a person sees, in Shelf. Movement uses
/// springs so it can be interrupted from wherever it is; the few timing
/// curves here are for things that don't move (a fade, the jiggle's swing).
enum Motion {
    // MARK: Springs

    /// Icons sliding aside while one is dragged.
    static let reorder = Animation.spring(duration: 0.35, bounce: 0.15)
    /// Entering and leaving edit mode, the banner, search.
    static let standard = Animation.spring(duration: 0.4, bounce: 0.1)
    /// Small state changes: a press releasing, a dot appearing.
    static let quick = Animation.spring(duration: 0.25, bounce: 0)
    /// An icon refusing to open.
    static let shake = Animation.spring(duration: 0.12, bounce: 0.6)
    /// The install pie filling.
    static let pie = Animation.spring(duration: 0.5, bounce: 0)

    // MARK: UIKit springs

    /// A spring in the same terms as SwiftUI's, for UIKit and Core Animation.
    /// Every one of these is started from what is on screen (the layer's
    /// presentation), so any of them can be interrupted and retargeted.
    struct Spring: Sendable {
        var duration: Double
        var bounce: Double

        /// The duration to run, which a debug build can slow down.
        @MainActor
        var playedDuration: Double { duration * Self.slowdown }

        /// A starting speed (spring lengths per second) to match.
        @MainActor
        func played(velocity: CGFloat) -> CGFloat { velocity / Self.slowdown }

        @MainActor
        private static var slowdown: Double {
            #if DEBUG
            Demo.slowMotion
            #else
            1
            #endif
        }
    }

    /// An app's card growing out of its icon to full screen.
    static let cardOpen = Spring(duration: 0.4, bounce: 0.04)
    /// The card shrinking into its icon. Quicker than the open: Springboard's
    /// card reaches its icon in about 130 ms and has settled by about 320.
    static let cardClose = Spring(duration: 0.34, bounce: 0.1)
    /// A close let go of short: the card goes back to full screen.
    static let cardReturn = Spring(duration: 0.38, bounce: 0.1)
    /// The pill warping into the search field, and back.
    static let searchWarp = Spring(duration: 0.45, bounce: 0.18)
    /// The pill widening or narrowing for its page dots.
    static let pillResize = Spring(duration: 0.25, bounce: 0)

    /// What follows the cards every frame (the Home Screen's scale, blur
    /// and dim) runs at the display's full rate, 120 Hz on ProMotion.
    static let frameRate = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

    // MARK: Fades

    static let fade = Animation.easeOut(duration: 0.2)
    /// The app replacing its launch screen.
    static let launch = Animation.easeOut(duration: 0.18)
    /// The pill's label and page dots trading places.
    static let pillFade: TimeInterval = 0.2

    // MARK: Shake

    /// An icon refusing to open: out, back past the middle, half out, home.
    /// Each step's duration, in order.
    static let shakeSteps: [Double] = [0.07, 0.1, 0.1, 0.25]

    // MARK: Jiggle

    /// One full swing, there and back.
    static let jigglePeriod: Double = 0.26
    static var jiggle: Animation { .easeInOut(duration: jigglePeriod / 2).repeatForever(autoreverses: true) }

    // MARK: Durations

    /// Nothing that loads shows a spinner before this.
    static let spinnerDelay: Duration = .milliseconds(300)
    /// How far the pie creeps while a download is still running, and how.
    static let pieCreepTarget: Double = 0.85
    static let pieCreep = Animation.easeOut(duration: 2.5)
    static let bannerStay: Duration = .seconds(3)
    static let pageDotsStay: Duration = .seconds(1)
    static let copiedStay: Duration = .milliseconds(1500)
    static let pageFlipHold: Duration = .milliseconds(600)
    /// How long a landed card stays on its icon after the icon has been
    /// shown beneath it, so there is never a frame with neither.
    static let cardHandoff: Duration = .milliseconds(50)
    static let wallpaperDrift: Double = 20
}
