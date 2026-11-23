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

    // The numbers marked "measured" come from Springboard on an iPhone 17
    // (`design/reference/springboard/real-device-open-close-swipe-up.mp4`,
    // the Settings and Developer closes); the README there has the method
    // and the tables. A screen recording can't show the finger, so the
    // finger's travel is read from the card's bottom edge, which starts
    // under it.

    /// The smallest a card gets under the finger, as a fraction of the screen.
    /// Not measured: the recorded swipes are flicks that let go above 0.8.
    static let trackMinScale: CGFloat = 0.3
    /// How quickly the card shrinks as the finger travels: travel of this
    /// fraction of the screen's height takes it about two-thirds of the way
    /// down to `trackMinScale`. Measured: Springboard's card loses 0.0016 of
    /// its width per point the finger rises, through the first 135 points
    /// (Settings, and both Developer closes), which is 0.7 / (0.5 × 874).
    static let trackTravel: CGFloat = 0.5
    /// The nearest a card's leading edge (its top, swiped up) comes to the
    /// screen's edge under a finger: the card stays on screen, whole. Not
    /// measured, inferred: in every recorded swipe the top edge only ever
    /// moved down, away from the screen's top, before the finger let go.
    static let trackEdge: CGFloat = 0
    /// How far short of `trackEdge` the edge starts to resist: the status
    /// bar's height on an iPhone 17. Inside it the edge is rubber-banded
    /// (the remaining distance d becomes d² / (d + overshoot)): it starts
    /// at the finger's speed and slows as it nears the limit, without ever
    /// reaching it. Inferred, like `trackEdge`, until a slow, long swipe is
    /// recorded (see the reference README).
    static let trackResistance: CGFloat = 62
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
    /// The most a release's speed may push a spring, in lengths of that
    /// spring per second, so a flick at a target a point away can't fling it.
    static let maxSpringVelocity: CGFloat = 30
    /// A card within this of its target, and moving less than this in a
    /// frame, has arrived.
    static let restTolerance: CGFloat = 0.5

    // MARK: Behind the card

    /// The Home Screen while an app is open: smaller, blurred and dimmed, and
    /// back to itself as the card lands. Springboard's is at about 0.9–0.95
    /// while a closing card is half the screen (measured); Shelf's scale
    /// follows the card's progress to this at full screen.
    static let backdropScale: CGFloat = 0.86
    /// The blur's radius, in points, while the card is at least
    /// `backdropBlurFull` of the way open; it shrinks in proportion below
    /// that and is gone when the card is its icon. Measured: matching a
    /// Gaussian blur of the settled Home Screen to each frame of the
    /// Developer close gives 16–20 points while the card is over half the
    /// screen, 8 at twice the icon's size, 4 just before it lands.
    static let backdropBlurRadius: CGFloat = 20
    static let backdropBlurFull: CGFloat = 0.45
    /// How dark the Home Screen behind is with the card full screen. It
    /// lightens with the card's progress to the power `backdropDimCurve`, so
    /// it is still 0.2 dark at twice the icon's size. Measured, the same way:
    /// brightness 0.5 behind a card of most of the screen, 0.7 at half,
    /// 0.8 at twice the icon, 0.9 just before it lands.
    static let backdropDim: CGFloat = 0.5
    static let backdropDimCurve: CGFloat = 0.6
    /// Where `PrivateLayerBlur` is unavailable: how strongly the system's
    /// regular blur shows instead, at full strength.
    static let backdropFallbackBlur: CGFloat = 0.85
    /// The app's picture gives way to its icon face as the card shrinks
    /// through this range of its progress (1 full screen, 0 the icon).
    /// Measured: Springboard's card shows only the app at 0.52, both at
    /// about 0.4 (half the icon's size again over its width), and only its
    /// icon by 0.3; the change takes two frames.
    static let contentFade: ClosedRange<CGFloat> = 0.28...0.42
    /// A card with no icon to land on (another page, or gone) fades out
    /// over the last of its progress.
    static let landingFade: CGFloat = 0.15

    // MARK: The card's lean

    /// On its way to an icon below it, Springboard's card leans back: its
    /// bottom edge narrower than its top, by 5–8% halfway (Developer,
    /// whose icon is 100 points below the card), and not at all when the
    /// icon is level with it (Settings). Shelf leans it about its horizontal
    /// axis by this many radians per unit of (how far the icon still is
    /// below the card's centre, in card heights) × (how much progress the
    /// card has lost since it was let go), up to `maxLean`. It starts at
    /// nothing when the finger lets go and is nothing again when it lands.
    /// Fitted to the two Developer closes (50° per unit).
    static let landingLean: CGFloat = 0.87
    static let maxLean: CGFloat = 0.14
    /// The distance of the eye from the screen for that lean, in points.
    static let leanPerspective: CGFloat = 500

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
