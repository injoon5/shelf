import CoreGraphics
import Foundation

/// Where an app's card is on screen: a rounded rectangle by its centre.
struct CardFrame: Equatable {
    var center: CGPoint
    var size: CGSize
    var radius: CGFloat

    init(center: CGPoint, size: CGSize, radius: CGFloat) {
        self.center = center
        self.size = size
        self.radius = radius
    }

    init(rect: CGRect, radius: CGFloat) {
        self.init(center: CGPoint(x: rect.midX, y: rect.midY), size: rect.size, radius: radius)
    }

    var rect: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// Which way a drag closes the card: up from the bottom edge (and when a
/// moving card is caught), or down from the status bar.
enum CloseDirection: Sendable {
    case up, down

    /// How far a drag of `translation` has gone toward closing.
    func travel(_ translation: CGPoint) -> CGFloat {
        self == .up ? -translation.y : translation.y
    }
}

/// The rules an app's card moves by, apart from any view, so they can be tested.
///
/// A drag is measured as travel toward closing. The card's scale is a
/// function of that travel alone, so a card caught anywhere in flight is
/// picked up at the travel that gives its current scale, and from then on
/// behaves as if it had been dragged there.
enum CardMotion {
    private static func reach(_ screenHeight: CGFloat) -> CGFloat {
        max(screenHeight * RunnerMetrics.trackTravel, 1)
    }

    /// The smallest a card caught at `startScale` gets: `trackMinScale` for
    /// one caught full screen, and as much smaller again for one caught
    /// smaller, so a card caught near its icon never jumps to the floor.
    static func floor(startScale: CGFloat) -> CGFloat {
        min(RunnerMetrics.trackMinScale, startScale * RunnerMetrics.trackMinScale)
    }

    /// The card's width, as a fraction of the screen's, after `travel`
    /// points toward closing. It shrinks quickly at first and ever more
    /// slowly toward `floor`; pushed the other way it grows only a little,
    /// resisting.
    static func scale(travel: CGFloat, screenHeight: CGFloat, floor: CGFloat = RunnerMetrics.trackMinScale) -> CGFloat {
        let reach = reach(screenHeight)
        if travel >= 0 { return floor + (1 - floor) * exp(-travel / reach) }
        return 1 + RunnerMetrics.trackOvergrow * (1 - exp(travel / reach))
    }

    /// How fast the scale changes per point of travel at `travel`.
    static func scaleSlope(travel: CGFloat, screenHeight: CGFloat, floor: CGFloat = RunnerMetrics.trackMinScale) -> CGFloat {
        let reach = reach(screenHeight)
        if travel >= 0 { return -(1 - floor) / reach * exp(-travel / reach) }
        return -RunnerMetrics.trackOvergrow / reach * exp(travel / reach)
    }

    /// The travel that gives `scale`: where a drag on a card that is
    /// already smaller than the screen starts from.
    static func travel(scale: CGFloat, screenHeight: CGFloat, floor: CGFloat = RunnerMetrics.trackMinScale) -> CGFloat {
        guard scale < 1 else { return 0 }
        let fraction = max((scale - floor) / (1 - floor), .ulpOfOne)
        return -reach(screenHeight) * log(fraction)
    }

    /// The card under a finger. `start` is the card when the touch began,
    /// at `startScale` of the screen's width; `finger` is where the touch
    /// began. The point under the finger stays under it as the card scales,
    /// until the card's leading edge (its top, closing upward; its bottom,
    /// closing downward) reaches the screen's edge zone (`edgeBand`). Past
    /// that the edge is rubber-banded toward the screen's edge and never
    /// reaches it, while the scale and the sideways movement go on
    /// following the finger. So a long swipe never carries the card off the
    /// screen, and `travel`, which decides the release, is the finger's.
    static func tracked(start: CardFrame, startScale: CGFloat, finger: CGPoint, translation: CGPoint,
                        direction: CloseDirection, screenHeight: CGFloat) -> (frame: CardFrame, travel: CGFloat) {
        // Worked out for a close upward; a close downward is its mirror image.
        let flip = { (y: CGFloat) in direction == .up ? y : screenHeight - y }
        let floor = floor(startScale: startScale)
        let startTravel = travel(scale: startScale, screenHeight: screenHeight, floor: floor)
        let travel = startTravel + direction.travel(translation)
        // Relative to the scale the travel gives back, not `startScale`: a
        // card caught growing past full screen has no travel of its own, and
        // must still be picked up at its own size.
        let base = scale(travel: startTravel, screenHeight: screenHeight, floor: floor)
        let ratio = scale(travel: travel, screenHeight: screenHeight, floor: floor) / max(base, .ulpOfOne)
        let size = CGSize(width: start.size.width * ratio, height: start.size.height * ratio)

        let fingerY = flip(finger.y)
        let movedY = -direction.travel(translation)
        let startTop = flip(start.center.y) - start.size.height / 2
        let band = edgeBand(startTop: startTop, finger: fingerY, startScale: startScale, screenHeight: screenHeight)
        let top = band.top(fingerY + movedY + (startTop - fingerY) * ratio, moved: -movedY)
        let center = CGPoint(x: finger.x + translation.x + (start.center.x - finger.x) * ratio,
                             y: flip(top + size.height / 2))
        return (CardFrame(center: center, size: size, radius: start.radius * ratio), travel)
    }

    /// Where the rubber band starts and what it holds the card's edge
    /// short of, for one grab. Measured from the edge the card closes
    /// toward (the top, closing upward), so `limit` is a distance from it.
    struct EdgeBand: Equatable {
        /// The edge never comes nearer the screen's than this.
        var limit: CGFloat
        /// Nearer than this, it resists.
        var soft: CGFloat
        /// How far the finger travels before the band may engage: the card's
        /// edge first moves away from the screen's (the card shrinks around
        /// a finger near its far edge), and only on its way back is it held.
        var engagesAfter: CGFloat

        /// The edge for an unheld edge at `free`, `moved` points of finger
        /// travel toward closing into the grab.
        func top(_ free: CGFloat, moved: CGFloat) -> CGFloat {
            guard moved > engagesAfter, free < soft else { return free }
            let length = soft - limit
            let past = soft - free
            return limit + length * length / (past + length)
        }
    }

    /// The band for a card that started with its edge at `startTop`, under a
    /// finger at `finger` (both measured from the edge it closes toward).
    ///
    /// The limit is `trackEdge` from the screen's edge, or where the card
    /// already is if it started nearer (a full-screen card, or one caught up
    /// there), so a card is always picked up exactly where it is. The band
    /// begins `trackResistance` short of the limit, or where the edge turns
    /// back toward the screen's if that is nearer, so the edge's speed never
    /// jumps as it crosses in.
    static func edgeBand(startTop: CGFloat, finger: CGFloat, startScale: CGFloat, screenHeight: CGFloat) -> EdgeBand {
        let floor = floor(startScale: startScale)
        let startTravel = travel(scale: startScale, screenHeight: screenHeight, floor: floor)
        let reach = reach(screenHeight)
        // The free edge is finger + moved + (startTop - finger) * ratio. Its
        // speed toward the screen's edge per point of finger travel is
        // 1 - (finger - startTop) * |ratio'|, and |ratio'| only falls, so it
        // turns back once, where that is zero.
        let base = max(scale(travel: startTravel, screenHeight: screenHeight, floor: floor), .ulpOfOne)
        let lever = (finger - startTop) * (1 - floor) / (reach * base)
        let turn = lever > 1 ? max(reach * log(lever) - startTravel, 0) : 0
        let ratioAtTurn = scale(travel: startTravel + turn, screenHeight: screenHeight, floor: floor) / base
        let edgeAtTurn = finger - turn + (startTop - finger) * ratioAtTurn

        var limit = min(RunnerMetrics.trackEdge, startTop)
        let soft = min(limit + RunnerMetrics.trackResistance, edgeAtTurn)
        // A card whose edge never moves away first (a finger near that edge)
        // still gets a band, of a point, so it is held without a jolt.
        if soft - limit < 1 { limit = soft - 1 }
        return EdgeBand(limit: limit, soft: soft, engagesAfter: turn)
    }

    /// How fast the card under a finger is moving, per second, when the
    /// finger moves at `velocity`: the derivative of `tracked`, so the
    /// spring a release starts carries on at the card's own speed, never
    /// the finger's. A flick near the limit leaves the card's edge nearly
    /// still, and it mustn't fling the card off the screen.
    static func trackedVelocity(start: CardFrame, startScale: CGFloat, finger: CGPoint, translation: CGPoint,
                                velocity: CGPoint, direction: CloseDirection, screenHeight: CGFloat) -> CardVelocity {
        let step: CGFloat = 1.0 / 1000
        func frame(_ sign: CGFloat) -> CardFrame {
            let moved = CGPoint(x: translation.x + sign * velocity.x * step, y: translation.y + sign * velocity.y * step)
            return tracked(start: start, startScale: startScale, finger: finger, translation: moved,
                           direction: direction, screenHeight: screenHeight).frame
        }
        let ahead = frame(1), behind = frame(-1)
        let span = 2 * step
        return CardVelocity(center: CGPoint(x: (ahead.center.x - behind.center.x) / span,
                                            y: (ahead.center.y - behind.center.y) / span),
                            size: CGSize(width: (ahead.size.width - behind.size.width) / span,
                                         height: (ahead.size.height - behind.size.height) / span),
                            radius: (ahead.radius - behind.radius) / span)
    }

    /// Whether a card let go of at `travel`, moving at `velocity` toward
    /// closing (pt/s, negative is back toward full screen), closes. A flick
    /// either way decides it; otherwise where the card would coast to does.
    static func closes(travel: CGFloat, velocity: CGFloat) -> Bool {
        if velocity > RunnerMetrics.closeVelocity { return true }
        if velocity < -RunnerMetrics.closeVelocity { return false }
        return travel + velocity * RunnerMetrics.releaseProjection > RunnerMetrics.closeTravel
    }

    /// Where a closing card lands, and whether it fades as it does.
    ///
    /// It lands on its icon when the icon is on screen. An icon on another
    /// page has no frame to land on that anyone can see, so the card leaves
    /// past that side of the screen, at its row; an app with no icon at all
    /// shrinks into the pill.
    static func landing(icon: CGRect?, screenWidth: CGFloat, pill: CGRect, iconSize: CGFloat) -> (frame: CGRect, fades: Bool) {
        if let icon {
            if icon.midX >= 0, icon.midX <= screenWidth { return (icon, false) }
            let x = icon.midX < 0 ? -icon.width : screenWidth
            return (CGRect(x: x, y: icon.minY, width: icon.width, height: icon.height), true)
        }
        return (CGRect(x: pill.midX - iconSize / 2, y: pill.midY - iconSize / 2, width: iconSize, height: iconSize), true)
    }

    /// How open a card of `width` is: 1 at full screen, 0 at icon size.
    static func progress(width: CGFloat, iconSize: CGFloat, screenWidth: CGFloat) -> CGFloat {
        min(max((width - iconSize) / max(screenWidth - iconSize, 1), 0), 1)
    }

    /// The blur's radius over the Home Screen behind a card at `progress`.
    static func backdropBlurRadius(progress: CGFloat) -> CGFloat {
        RunnerMetrics.backdropBlurRadius * min(max(progress / RunnerMetrics.backdropBlurFull, 0), 1)
    }

    /// How dark the Home Screen behind a card at `progress` is.
    static func backdropDim(progress: CGFloat) -> CGFloat {
        RunnerMetrics.backdropDim * pow(min(max(progress, 0), 1), RunnerMetrics.backdropDimCurve)
    }

    /// The corner a card of `size` is drawn with: the display's, as long as
    /// that fits, and the icon's for its size below that. Springboard's card
    /// keeps the display's corners until it is nearly an icon (55 points at
    /// 222 wide, measured), which reads rounder than corners scaled down
    /// with the card.
    static func cornerRadius(size: CGSize, full: CGFloat) -> CGFloat {
        min(full, HomeMetrics.iconRadius(min(size.width, size.height)))
    }

    /// The angle, in radians about its horizontal axis, a landing card at
    /// `center` and `height` leans by on its way to `targetY`, having been
    /// let go at `startProgress` and now at `progress`. Negative leans its
    /// bottom away, toward an icon below.
    static func lean(centerY: CGFloat, height: CGFloat, targetY: CGFloat, startProgress: CGFloat, progress: CGFloat) -> CGFloat {
        let below = (targetY - centerY) / max(height, 1)
        let lost = max(startProgress - progress, 0)
        let lean = -RunnerMetrics.landingLean * below * lost
        return min(max(lean, -RunnerMetrics.maxLean), RunnerMetrics.maxLean)
    }

    /// The angle a card growing out of an icon at `iconY` leans by, at
    /// `center` and `height` and `progress`: the side toward the icon
    /// away, as the landing's does, by as much again as its distance from
    /// the icon in card heights, less as it grows. Negative leans its bottom
    /// away, from an icon below. It starts at nothing, centred on its icon.
    static func openingLean(centerY: CGFloat, height: CGFloat, iconY: CGFloat, progress: CGFloat) -> CGFloat {
        let below = (iconY - centerY) / max(height, 1)
        let lean = -RunnerMetrics.launchLean * below * (1 - min(max(progress, 0), 1))
        return min(max(lean, -RunnerMetrics.maxLean), RunnerMetrics.maxLean)
    }

    /// The angle, in radians about its vertical axis, a card at `centerX`
    /// and `width` turns by with an icon at `iconX`: the side away from the
    /// icon goes back, by `amount` (how far it has gone since it set off,
    /// landing; how far it still has to grow, opening). Negative brings
    /// its right side forward, toward an icon on the right.
    static func sideLean(centerX: CGFloat, width: CGFloat, iconX: CGFloat, amount: CGFloat) -> CGFloat {
        let toward = (iconX - centerX) / max(width, 1)
        let lean = -RunnerMetrics.sideLean * toward * min(max(amount, 0), 1)
        return min(max(lean, -RunnerMetrics.maxLean), RunnerMetrics.maxLean)
    }

    /// How much of the app's own picture shows at `progress`; below the
    /// range it has given way to the icon's face.
    static func contentOpacity(progress: CGFloat) -> CGFloat {
        let range = RunnerMetrics.contentFade
        return min(max((progress - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    /// How much of the launch surface shows over the icon on the way out
    /// of it at `progress`: it comes in fast and eases out, done within
    /// the first half of the growth.
    static func launchOpacity(progress: CGFloat) -> CGFloat {
        let range = RunnerMetrics.launchFade
        let x = min(max((progress - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        return 1 - (1 - x) * (1 - x)
    }

    /// What a card at `progress` shows, and how the Home Screen behind it
    /// looks, growing (`opening`) or shrinking.
    static func look(progress: CGFloat, opening: Bool) -> CardLook {
        let p = min(max(progress, 0), 1)
        if opening {
            return CardLook(content: launchOpacity(progress: p),
                            blur: RunnerMetrics.backdropBlurRadius * pow(p, RunnerMetrics.openBlurCurve),
                            dim: RunnerMetrics.backdropDim * p)
        }
        return CardLook(content: contentOpacity(progress: p),
                        blur: backdropBlurRadius(progress: p), dim: backdropDim(progress: p))
    }

    /// A speed in points per second, bounded for a spring from `from` to
    /// `to`: at most `maxSpringVelocity` spring lengths per second, so a
    /// flick at a target a point away can't fling it.
    static func boundedVelocity(_ velocity: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let limit = RunnerMetrics.maxSpringVelocity * abs(to - from)
        return min(max(velocity, -limit), limit)
    }
}

/// What a card shows over its icon face, and the Home Screen behind it.
///
/// Springboard's open and close aren't mirror images: growing, the app's
/// surface replaces the icon early and the Home Screen blurs late;
/// shrinking, the app's picture gives way to the icon late, and the blur
/// stays until the card is small.
struct CardLook: Equatable, Sendable {
    /// The opacity of the picture (the launch surface, or the app) over the icon.
    var content: CGFloat
    /// The blur's radius over the Home Screen, in points.
    var blur: CGFloat
    /// How dark the Home Screen is.
    var dim: CGFloat

    static func + (a: CardLook, b: CardLook) -> CardLook {
        CardLook(content: a.content + b.content, blur: a.blur + b.blur, dim: a.dim + b.dim)
    }

    static func - (a: CardLook, b: CardLook) -> CardLook {
        CardLook(content: a.content - b.content, blur: a.blur - b.blur, dim: a.dim - b.dim)
    }

    static func * (a: CardLook, k: CGFloat) -> CardLook {
        CardLook(content: a.content * k, blur: a.blur * k, dim: a.dim * k)
    }

    /// Each part kept in range.
    var clamped: CardLook {
        CardLook(content: min(max(content, 0), 1), blur: max(blur, 0), dim: min(max(dim, 0), 1))
    }
}

/// A card's look from the moment it set off in one direction: the
/// direction's own (`CardMotion.look`), plus whatever difference it had
/// from that when it turned, fading out over `lookHandoff` of progress. So
/// a card caught growing and swiped away carries on from what it showed,
/// and settles onto the close's curves on its way down.
struct LookHandoff: Equatable, Sendable {
    var opening: Bool
    var startProgress: CGFloat
    private var offset: CardLook

    init(from look: CardLook, at progress: CGFloat, opening: Bool) {
        self.opening = opening
        startProgress = progress
        offset = look - CardMotion.look(progress: progress, opening: opening)
    }

    /// An open from the icon, with nothing to carry.
    static let fromIcon = LookHandoff(from: CardMotion.look(progress: 0, opening: true), at: 0, opening: true)

    func look(at progress: CGFloat) -> CardLook {
        let left = max(1 - abs(progress - startProgress) / RunnerMetrics.lookHandoff, 0)
        return (CardMotion.look(progress: progress, opening: opening) + offset * left).clamped
    }
}

/// How a card is turned in depth, in radians: `back` about its horizontal
/// axis (negative takes its bottom away), `side` about its vertical axis
/// (negative brings its right side forward).
struct CardLean: Equatable, Sendable {
    var back: CGFloat
    var side: CGFloat

    static let none = CardLean(back: 0, side: 0)

    static func + (a: CardLean, b: CardLean) -> CardLean { CardLean(back: a.back + b.back, side: a.side + b.side) }
    static func - (a: CardLean, b: CardLean) -> CardLean { CardLean(back: a.back - b.back, side: a.side - b.side) }
    static func * (a: CardLean, k: CGFloat) -> CardLean { CardLean(back: a.back * k, side: a.side * k) }

    /// Each within `maxLean`.
    var limited: CardLean {
        CardLean(back: min(max(back, -RunnerMetrics.maxLean), RunnerMetrics.maxLean),
                 side: min(max(side, -RunnerMetrics.maxLean), RunnerMetrics.maxLean))
    }
}
