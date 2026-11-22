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
    /// began. The point under the finger stays under it as the card scales.
    static func tracked(start: CardFrame, startScale: CGFloat, finger: CGPoint, translation: CGPoint,
                        direction: CloseDirection, screenHeight: CGFloat) -> (frame: CardFrame, travel: CGFloat) {
        let floor = floor(startScale: startScale)
        let travel = travel(scale: startScale, screenHeight: screenHeight, floor: floor) + direction.travel(translation)
        let ratio = scale(travel: travel, screenHeight: screenHeight, floor: floor) / max(startScale, .ulpOfOne)
        let center = CGPoint(x: finger.x + translation.x + (start.center.x - finger.x) * ratio,
                             y: finger.y + translation.y + (start.center.y - finger.y) * ratio)
        let size = CGSize(width: start.size.width * ratio, height: start.size.height * ratio)
        return (CardFrame(center: center, size: size, radius: start.radius * ratio), travel)
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

    /// How much of the app's own picture shows at `progress`; below the
    /// range it has given way to the icon's face.
    static func contentOpacity(progress: CGFloat) -> CGFloat {
        let range = RunnerMetrics.contentFade
        return min(max((progress - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }

    /// A speed in points per second, as a spring from `from` to `to` wants
    /// it: in lengths of that spring per second, and bounded.
    static func springVelocity(_ velocity: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let distance = to - from
        guard abs(distance) >= 1 else { return 0 }
        let limit = RunnerMetrics.maxSpringVelocity
        return min(max(velocity / distance, -limit), limit)
    }
}
