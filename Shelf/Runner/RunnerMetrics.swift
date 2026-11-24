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
    /// The most a card's flight moves on between two frames, in seconds: two
    /// frames at 60 Hz. A frame held up longer than that (the main thread
    /// building a card) costs the flight that time instead of skipping its
    /// motion (`CardClock`). Springboard shows every frame of its growth.
    static let maxFrameStep: Double = 1.0 / 30

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
    /// The app's picture gives way to its icon face as the card shrinks
    /// through this range of its progress (1 full screen, 0 the icon).
    /// Measured: Springboard's card shows only the app at 0.52, both at
    /// about 0.4 (half the icon's size again over its width), and only its
    /// icon by 0.3; the change takes two frames.
    static let contentFade: ClosedRange<CGFloat> = 0.28...0.42
    /// A card with no icon to land on (another page, or gone) fades out
    /// over the last of its progress.
    static let landingFade: CGFloat = 0.15

    // MARK: The open

    // Measured from the same recording's opens (Settings at 6.2 and 7.95 s,
    // Developer at 11.55 and 13.85 s, Weather at 16.75 s); the reference
    // README has the tables.

    /// The icon gives way to the launch surface as the card grows through
    /// this range of its progress, easing out: a quarter of the icon is
    /// left at 0.31 and a tenth at 0.38. Measured: Springboard's card shows
    /// all of its icon at 0.14, about a fifth at 0.31–0.34, under a tenth at
    /// 0.38 and none by 0.5, in all three apps. The close's crossfade
    /// (`contentFade`) in reverse, but earlier and wider.
    static let launchFade: ClosedRange<CGFloat> = 0.12...0.5
    /// Growing, the Home Screen behind blurs late and darkens early: the
    /// blur's radius is `backdropBlurRadius` × progress to this power, and
    /// the dim is `backdropDim` × progress. Measured: blur 2–3 points and
    /// brightness 0.9 at 0.14, 3–4 and 0.8 at 0.48, 6–10 and 0.68 at 0.66,
    /// 16–18 and 0.57 at 0.85. Shrinking, the blur stays until the card is
    /// small (`backdropBlurFull`): the two aren't mirror images.
    static let openBlurCurve: CGFloat = 2
    /// When a card turns back (caught growing, or let go short of
    /// closing), what it shows and the Home Screen's blur and dim go from
    /// where they were to the new direction's over this much progress, so
    /// nothing jumps between the open's curves and the close's.
    static let lookHandoff: CGFloat = 0.25

    // MARK: Launch snapshots

    /// JPEG quality of a snapshot on disk: small, and quick to decode.
    static let snapshotQuality: CGFloat = 0.85
    /// How many apps' snapshots stay decoded in memory.
    static let snapshotsInMemory = 3

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
    /// Growing out of its icon, the card leans the same way, away from the
    /// icon: this many radians per unit of (how far the icon is below its
    /// centre, in card heights) × (how far it still has to grow). Fitted to
    /// the cold Developer open (icon about 60 points below the card): its
    /// bottom edge narrower than its top by 4.8% at half the screen's
    /// width, 3.7% at 0.73, 1.7% at 0.9, which is 1.3–1.6 per unit; the
    /// Settings opens, from an icon level with the card, don't lean. Neither
    /// leans sideways.
    static let launchLean: CGFloat = 1.4
    /// Opening and landing, the card also turns about its vertical axis by
    /// the icon's place across: the side away from the icon goes back, by
    /// this many radians per unit of (how far the icon is to the side of
    /// its centre, in card widths) × (how far the card has come since it
    /// set off, landing; how far it still has to grow, opening). Fitted to
    /// one frame of a Photos close (icon at the top right, owner's iPhone
    /// 17, `real-device-photos-open-close.mp4` at 2.45 s): the icon 0.28
    /// card widths to its right, the card's right edge 2.3% taller than its
    /// left, about 0.086 radians. Its opens turn the same way.
    static let sideLean: CGFloat = 0.65
    static let maxLean: CGFloat = 0.14
    /// The distance of the eye from the screen for that lean, in points.
    static let leanPerspective: CGFloat = 500

    // MARK: Error screen

    static let errorIconSize: CGFloat = 64
    static let errorSpacing: CGFloat = 20
    static let errorHeadingSpacing: CGFloat = 6
    /// Below the icon, before the title.
    static let errorIconGap: CGFloat = 8
    static let errorPadding: CGFloat = 24
    /// Its column on a wide screen, or a wide sheet.
    static let errorWidth: CGFloat = 560
    /// Above the bottom of the safe area: the card's home indicator.
    static let errorButtonsBottom: CGFloat = 12
    static let errorBadgeSize: CGFloat = 22
    /// The ring of background that cuts the badge out of the icon.
    static let errorBadgeRim: CGFloat = 2
    static let errorBadgeOffset: CGFloat = 6
    /// The code block's fill: quieter than a grouped cell, light or dark.
    static let codeFillOpacity: Double = 0.6
    /// Lines shown on each side of the failing one.
    static let errorContext = 2
    static let codeRadius: CGFloat = 14
    static let codePadding: CGFloat = 12
    static let codeLineSpacing: CGFloat = 2
    static let gutterGap: CGFloat = 10
    static let failingLineOpacity: Double = 0.14
}
