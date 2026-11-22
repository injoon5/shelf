import SwiftUI

/// The runner's sizes, kept out of its views like the Home Screen's.
enum RunnerMetrics {
    /// The strip along the top where a downward drag always closes the app,
    /// when the status bar is shorter than this.
    static let dismissStrip: CGFloat = 44
    /// The strip along the bottom where a swipe up closes the app, when the
    /// home indicator's safe area is shorter than this.
    static let homeEdge: CGFloat = 24

    // MARK: The card under a finger

    /// The smallest a card gets under the finger, as a fraction of the screen.
    static let trackMinScale: CGFloat = 0.3
    /// How quickly the card shrinks as the finger travels: travel of this
    /// fraction of the screen's height takes it about two-thirds of the way
    /// down to `trackMinScale`.
    static let trackTravel: CGFloat = 0.55
    /// How much a card can grow past full screen when pushed away from closing.
    static let trackOvergrow: CGFloat = 0.03
    /// A release faster than this toward closing closes; one this fast back
    /// toward full screen returns there, wherever the card is.
    static let closeVelocity: CGFloat = 300
    /// Otherwise the card closes if its travel, projected, passes this.
    static let closeTravel: CGFloat = 110
    /// How far ahead a release's speed is projected, in seconds.
    static let releaseProjection: CGFloat = 0.12
    /// A touch on a moving card that ends having moved less than this is a tap.
    static let tapSlop: CGFloat = 8
    /// The most a release's speed may push a spring, in spring lengths per
    /// second, so a flick at a target a point away can't fling it.
    static let maxSpringVelocity: CGFloat = 30
    /// A card within this of its target, and moving less than this in a
    /// frame, has arrived.
    static let restTolerance: CGFloat = 0.5

    // MARK: Behind the card

    /// The Home Screen while an app is open: smaller, blurred and dimmed, and
    /// back to itself as the card lands. Springboard's starts its return from
    /// about 0.75x; Shelf's backdrop is only ever seen around a moving card.
    static let backdropScale: CGFloat = 0.86
    /// How strongly a regular system blur shows over it.
    static let backdropBlur: CGFloat = 0.85
    static let backdropDim: CGFloat = 0.18
    /// The app's picture gives way to its icon face as the card shrinks
    /// through this range of its progress (1 full screen, 0 the icon).
    static let contentFade: ClosedRange<CGFloat> = 0.04...0.3
    /// A card with no icon to land on (another page, or gone) fades out
    /// over the last of its progress.
    static let landingFade: CGFloat = 0.15

    // MARK: Error screen

    static let errorIconSize: CGFloat = 60
    static let errorSpacing: CGFloat = 16
    static let errorPadding: CGFloat = 24
    /// Lines shown on each side of the failing one.
    static let errorContext = 2
    static let codeRadius: CGFloat = 14
    static let codePadding: CGFloat = 12
    static let codeLineSpacing: CGFloat = 2
    static let gutterGap: CGFloat = 10
    static let failingLineOpacity: Double = 0.16
}
