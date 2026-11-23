import SwiftUI

/// Every spring, and every duration a person sees, in Shelf. Movement uses
/// springs so it can be interrupted from wherever it is; the few timing
/// curves here are for things that don't move (a fade, the jiggle's swing).
enum Motion {
    // MARK: Springs

    /// Icons sliding aside while one is dragged.
    static let reorder = Animation.spring(duration: 0.35, bounce: 0.15)
    /// Entering and leaving edit mode, the banner, a page flip, a sheet's
    /// own changes.
    static let standard = Animation.spring(duration: 0.4, bounce: 0.1)
    /// Small state changes: a press releasing, a dot appearing.
    static let quick = Animation.spring(duration: 0.25, bounce: 0)

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

        /// How many times slower than real every animation plays: 1, except
        /// in a debug build launched with `-ShelfSlowMotion`.
        @MainActor
        static var slowdown: Double {
            #if DEBUG
            Demo.slowMotion
            #else
            1
            #endif
        }
    }

    /// An app's card growing out of its icon to full screen.
    static let cardOpen = CardSprings(Spring(duration: 0.4, bounce: 0.04))
    /// The card shrinking into its icon after a swipe up lets go, fitted to
    /// Springboard's on an iPhone 17 (`real-device-open-close-swipe-up.mp4`,
    /// the second Developer close, started from its measured release: see
    /// `design/reference/springboard/README.md`). Each fits that close to
    /// within a few points a frame. The height closes fastest, so the card
    /// turns from portrait to square on the way; the width overshoots a
    /// little, so the tile settles into its slot. The centre barely bounces
    /// (fitted 0.16–0.2, but taken at 0.05, which fits as well), so a card
    /// on its way down to the dock never drops past it. Release to rest
    /// takes about 300 ms.
    static let cardClose = CardSprings(position: Spring(duration: 0.38, bounce: 0.05),
                                       width: Spring(duration: 0.44, bounce: 0.16),
                                       height: Spring(duration: 0.35, bounce: 0.1))
    /// A close let go of short: the card goes back to full screen.
    static let cardReturn = CardSprings(Spring(duration: 0.38, bounce: 0.1))
    /// The pill warping into the search field, and back.
    static let searchWarp = Spring(duration: 0.45, bounce: 0.18)
    /// The pill widening or narrowing for its page dots.
    static let pillResize = Spring(duration: 0.25, bounce: 0)
    /// Small state changes: a press releasing, a badge appearing.
    static let release = Spring(duration: 0.25, bounce: 0)
    /// Icons flowing to new places while one is dragged, and a dropped icon
    /// settling into its place.
    static let iconReorder = Spring(duration: 0.35, bounce: 0.15)
    /// An icon lifting under a long press, or settling back.
    static let iconLift = Spring(duration: 0.3, bounce: 0.15)
    /// The long-press menu opening out of its icon.
    static let menuOpen = Spring(duration: 0.35, bounce: 0.12)
    /// Entering and leaving edit mode: the badges, the buttons.
    static let editMode = Spring(duration: 0.4, bounce: 0.1)
    /// The install pie filling the rest of the way.
    static let pieFill = Spring(duration: 0.5, bounce: 0)

    /// What follows the cards every frame (the Home Screen's scale, blur
    /// and dim), the layer springs and the jiggle run at the display's full
    /// rate, 120 Hz on ProMotion (with `CADisableMinimumFrameDurationOnPhone`
    /// in Info.plist, without which an iPhone app stops at 60).
    static let frameRate = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)

    /// The springs a card flies on (`CardFlight`): one for its centre, one
    /// for its width (and its corner, which follows the width), one for its
    /// height.
    struct CardSprings: Sendable {
        var position: Spring
        var width: Spring
        var height: Spring

        init(position: Spring, width: Spring, height: Spring) {
            self.position = position
            self.width = width
            self.height = height
        }

        /// Everything on one spring.
        init(_ spring: Spring) {
            self.init(position: spring, width: spring, height: spring)
        }
    }

    // MARK: Fades

    static let fadeDuration: TimeInterval = 0.2
    /// The app replacing its launch screen.
    static let launch = Animation.easeOut(duration: 0.18)
    /// The pill's label and page dots trading places.
    static let pillFade: TimeInterval = 0.2

    // MARK: Shake

    /// An icon refusing to open: out, back past the middle, half out, home.
    /// Each step's duration, in order.
    static let shakeSteps: [Double] = [0.07, 0.1, 0.1, 0.25]
    /// The spring of every step but the last, and of the last.
    static let shakeStep = SwiftUI.Spring.snappy
    static let shakeHome = SwiftUI.Spring.bouncy

    // MARK: Jiggle

    /// One full swing, there and back.
    static let jigglePeriod: Double = 0.26

    // MARK: Durations

    /// Nothing that loads shows a spinner before this.
    static let spinnerDelay: Duration = .milliseconds(300)
    /// How far the pie creeps while a download is still running, and how.
    static let pieCreepTarget: Double = 0.85
    static let pieCreepDuration: TimeInterval = 2.5
    static let bannerStay: Duration = .seconds(3)
    static let pageDotsStay: Duration = .seconds(1)
    static let copiedStay: Duration = .milliseconds(1500)
    static let pageFlipHold: Duration = .milliseconds(600)
    /// How long a touch on an icon is held before it lifts and its menu
    /// opens: Springboard's icon lifts about 430 ms after touch-down
    /// (`icon-press-lift-menu-frames.png`).
    static let menuHold: TimeInterval = 0.43
    /// In edit mode, a touch held this long picks the icon up; a quicker
    /// swipe still turns the page.
    static let pickupHold: TimeInterval = 0.12
    /// A dragged icon held over a new place this long makes room there, so
    /// a finger sweeping across the grid doesn't shuffle everything it passes.
    static let reorderDwell: Duration = .milliseconds(120)
}
