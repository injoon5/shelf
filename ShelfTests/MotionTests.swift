import CoreGraphics
import Testing
import UIKit
@testable import Shelf

struct CardMotionTests {
    private let height: CGFloat = 874
    private let width: CGFloat = 402

    @Test func aCardShrinksAsItTravelsAndNeverPastItsFloor() {
        #expect(CardMotion.scale(travel: 0, screenHeight: height) == 1)
        let near = CardMotion.scale(travel: 100, screenHeight: height)
        let far = CardMotion.scale(travel: 400, screenHeight: height)
        #expect(near < 1)
        #expect(far < near)
        #expect(CardMotion.scale(travel: 100_000, screenHeight: height) >= RunnerMetrics.trackMinScale)
    }

    @Test func pushedTheOtherWayItGrowsOnlyALittle() {
        let pushed = CardMotion.scale(travel: -10_000, screenHeight: height)
        #expect(pushed > 1)
        #expect(pushed <= 1 + RunnerMetrics.trackOvergrow)
    }

    @Test func travelAndScaleAreInverses() {
        for travel: CGFloat in [0, 50, 200, 600] {
            let scale = CardMotion.scale(travel: travel, screenHeight: height)
            #expect(abs(CardMotion.travel(scale: scale, screenHeight: height) - travel) < 0.001)
        }
    }

    @Test func theSlopIsTheScalesDerivative() {
        let travel: CGFloat = 150
        let step: CGFloat = 0.01
        let numeric = (CardMotion.scale(travel: travel + step, screenHeight: height)
            - CardMotion.scale(travel: travel, screenHeight: height)) / step
        #expect(abs(CardMotion.scaleSlope(travel: travel, screenHeight: height) - numeric) < 0.0001)
    }

    @Test func thePointUnderTheFingerStaysUnderIt() {
        let full = CardFrame(rect: CGRect(x: 0, y: 0, width: width, height: height), radius: 55)
        let finger = CGPoint(x: 201, y: 862)
        // Short of the top edge's limit (CardEdgeTests has the rest).
        let translation = CGPoint(x: 20, y: -150)
        let tracked = CardMotion.tracked(start: full, startScale: 1, finger: finger, translation: translation,
                                         direction: .up, screenHeight: height).frame
        let ratio = tracked.size.width / full.size.width
        #expect(ratio < 1)
        // The finger began at the card's bottom-centre and is still there.
        let now = CGPoint(x: finger.x + translation.x, y: finger.y + translation.y)
        let fraction = (now.y - tracked.rect.minY) / tracked.size.height
        #expect(abs(fraction - finger.y / height) < 0.001)
        #expect(abs(tracked.center.x - (now.x + (full.center.x - finger.x) * ratio)) < 0.001)
        #expect(abs(tracked.radius - 55 * ratio) < 0.001)
    }

    @Test(arguments: [120, 64, 30] as [CGFloat])
    func aCaughtCardCarriesOnFromItsOwnSize(caughtWidth: CGFloat) {
        let small = CardFrame(rect: CGRect(x: 100, y: 100, width: caughtWidth, height: caughtWidth * 2), radius: 16)
        let scale = small.size.width / width
        let still = CardMotion.tracked(start: small, startScale: scale, finger: small.center, translation: .zero,
                                       direction: .up, screenHeight: height)
        #expect(abs(still.frame.size.width - small.size.width) < 0.001)
        #expect(still.travel > 0)
        // Dragged down, toward full screen, it grows.
        let down = CardMotion.tracked(start: small, startScale: scale, finger: small.center,
                                      translation: CGPoint(x: 0, y: 200), direction: .up, screenHeight: height)
        #expect(down.frame.size.width > small.size.width)
    }

    @Test func aDragDownFromTheStatusBarCloses() {
        #expect(CloseDirection.down.travel(CGPoint(x: 0, y: 80)) == 80)
        #expect(CloseDirection.up.travel(CGPoint(x: 0, y: 80)) == -80)
    }

    @Test func releasesDecideByFlickThenByWhereTheCardWouldCoast() {
        // A flick decides it, whatever the distance.
        #expect(CardMotion.closes(travel: 5, velocity: RunnerMetrics.closeVelocity + 1))
        #expect(!CardMotion.closes(travel: 500, velocity: -RunnerMetrics.closeVelocity - 1))
        // A slow release closes only past the threshold.
        #expect(CardMotion.closes(travel: RunnerMetrics.closeTravel + 1, velocity: 0))
        #expect(!CardMotion.closes(travel: RunnerMetrics.closeTravel - 1, velocity: 0))
    }

    @Test func aCardLandsOnItsIconWhenItIsOnScreen() {
        let pill = CGRect(x: 161, y: 704, width: 79, height: 29)
        let icon = CGRect(x: 123, y: 89, width: 64, height: 64)
        let landing = CardMotion.landing(icon: icon, screenWidth: width, pill: pill, iconSize: 64)
        #expect(landing.frame == icon)
        #expect(!landing.fades)
    }

    @Test func anIconOnAnotherPageSendsTheCardOffThatSide() {
        let pill = CGRect(x: 161, y: 704, width: 79, height: 29)
        let right = CardMotion.landing(icon: CGRect(x: 525, y: 189, width: 64, height: 64), screenWidth: width, pill: pill, iconSize: 64)
        #expect(right.frame.minX >= width)
        #expect(right.frame.minY == 189)
        #expect(right.fades)
        let left = CardMotion.landing(icon: CGRect(x: -279, y: 89, width: 64, height: 64), screenWidth: width, pill: pill, iconSize: 64)
        #expect(left.frame.maxX <= 0)
    }

    @Test func anAppWithNoIconShrinksIntoThePill() {
        let pill = CGRect(x: 161, y: 704, width: 79, height: 29)
        let landing = CardMotion.landing(icon: nil, screenWidth: width, pill: pill, iconSize: 64)
        #expect(landing.frame.midX == pill.midX)
        #expect(landing.frame.midY == pill.midY)
        #expect(landing.fades)
    }

    @Test func progressAndThePicturesFade() {
        #expect(CardMotion.progress(width: width, iconSize: 64, screenWidth: width) == 1)
        #expect(CardMotion.progress(width: 64, iconSize: 64, screenWidth: width) == 0)
        #expect(CardMotion.progress(width: 10, iconSize: 64, screenWidth: width) == 0)
        #expect(CardMotion.contentOpacity(progress: 1) == 1)
        #expect(CardMotion.contentOpacity(progress: RunnerMetrics.contentFade.lowerBound) == 0)
        let middle = (RunnerMetrics.contentFade.lowerBound + RunnerMetrics.contentFade.upperBound) / 2
        #expect(abs(CardMotion.contentOpacity(progress: middle) - 0.5) < 0.001)
    }

    /// Springboard's Home Screen comes into focus as the card lands: the
    /// blur's radius holds while the card is big, then shrinks to nothing,
    /// and the dim lightens all the way down.
    @Test func theHomeScreenComesIntoFocusAsTheCardLands() {
        #expect(CardMotion.backdropBlurRadius(progress: 1) == RunnerMetrics.backdropBlurRadius)
        #expect(CardMotion.backdropBlurRadius(progress: RunnerMetrics.backdropBlurFull) == RunnerMetrics.backdropBlurRadius)
        // Twice the icon's size: about 8 points, as measured.
        #expect(abs(CardMotion.backdropBlurRadius(progress: 0.17) - 8) < 1)
        #expect(CardMotion.backdropBlurRadius(progress: 0) == 0)
        #expect(CardMotion.backdropDim(progress: 1) == RunnerMetrics.backdropDim)
        #expect(abs(CardMotion.backdropDim(progress: 0.17) - 0.2) < 0.03)
        #expect(CardMotion.backdropDim(progress: 0) == 0)
    }

    /// A card keeps the display's corners until it is nearly an icon, then
    /// takes the icon's.
    @Test func theCardKeepsTheDisplaysCornersUntilItIsNearlyAnIcon() {
        #expect(CardMotion.cornerRadius(size: CGSize(width: 402, height: 874), full: 55) == 55)
        #expect(CardMotion.cornerRadius(size: CGSize(width: 222, height: 330), full: 55) == 55)
        #expect(CardMotion.cornerRadius(size: CGSize(width: 64, height: 64), full: 55) == HomeMetrics.iconRadius(64))
        #expect(CardMotion.cornerRadius(size: CGSize(width: 120, height: 150), full: 55) == HomeMetrics.iconRadius(120))
    }

    /// Toward an icon below it, the card leans its bottom away; level with
    /// it, it doesn't lean; and it never leans when let go or when landed.
    @Test func theCardLeansTowardAnIconBelow() {
        let below = CardMotion.lean(centerY: 420, height: 400, targetY: 523, startProgress: 0.9, progress: 0.5)
        #expect(below < 0)
        #expect(CardMotion.lean(centerY: 420, height: 400, targetY: 420, startProgress: 0.9, progress: 0.5) == 0)
        #expect(CardMotion.lean(centerY: 420, height: 400, targetY: 523, startProgress: 0.9, progress: 0.9) == 0)
        #expect(CardMotion.lean(centerY: 523, height: 64, targetY: 523, startProgress: 0.9, progress: 0) == 0)
        #expect(CardMotion.lean(centerY: 0, height: 64, targetY: 874, startProgress: 1, progress: 0) == -RunnerMetrics.maxLean)
    }

    @Test func aReleasesSpeedIsBoundedByItsSpringsLength() {
        #expect(CardMotion.boundedVelocity(500, from: 0, to: 250) == 500)
        #expect(CardMotion.boundedVelocity(-500, from: 0, to: -250) == -500)
        #expect(CardMotion.boundedVelocity(100_000, from: 0, to: 2) == RunnerMetrics.maxSpringVelocity * 2)
        #expect(CardMotion.boundedVelocity(-100_000, from: 10, to: 8) == -RunnerMetrics.maxSpringVelocity * 2)
        #expect(CardMotion.boundedVelocity(500, from: 10, to: 10) == 0)
    }
}

/// PLAN.md §0.7: swiped up, the card's top edge is held on the screen.
struct CardEdgeTests {
    private let height: CGFloat = 874
    private let width: CGFloat = 402
    private var full: CardFrame { CardFrame(rect: CGRect(x: 0, y: 0, width: width, height: height), radius: 55) }

    /// A grab: the card when the finger landed, and where the finger landed.
    struct Grab: CustomTestStringConvertible {
        var card: CardFrame
        var finger: CGPoint
        var name: String
        var testDescription: String { name }
    }

    static let grabs: [Grab] = [
        // Full screen, from the home indicator's strip, middle and sides.
        Grab(card: CardFrame(rect: CGRect(x: 0, y: 0, width: 402, height: 874), radius: 55),
             finger: CGPoint(x: 201, y: 862), name: "full screen, middle"),
        Grab(card: CardFrame(rect: CGRect(x: 0, y: 0, width: 402, height: 874), radius: 55),
             finger: CGPoint(x: 30, y: 868), name: "full screen, left"),
        Grab(card: CardFrame(rect: CGRect(x: 0, y: 0, width: 402, height: 874), radius: 55),
             finger: CGPoint(x: 380, y: 845), name: "full screen, right"),
        // Caught on its way home, below the band, by its lower half.
        Grab(card: CardFrame(rect: CGRect(x: 80, y: 260, width: 200, height: 435), radius: 27),
             finger: CGPoint(x: 180, y: 600), name: "caught low"),
        // Caught inside the band, near its own top.
        Grab(card: CardFrame(rect: CGRect(x: 40, y: 30, width: 320, height: 696), radius: 44),
             finger: CGPoint(x: 200, y: 60), name: "caught by its top"),
        // Caught above the limit: still growing past full screen on the
        // open's spring.
        Grab(card: CardFrame(rect: CGRect(x: -4, y: -8, width: 410, height: 891), radius: 56),
             finger: CGPoint(x: 201, y: 700), name: "caught above the limit"),
    ]

    private func tracked(_ grab: Grab, _ translation: CGPoint, _ direction: CloseDirection = .up) -> CardFrame {
        CardMotion.tracked(start: grab.card, startScale: grab.card.size.width / width, finger: grab.finger,
                           translation: translation, direction: direction, screenHeight: height).frame
    }

    private func band(_ grab: Grab) -> CardMotion.EdgeBand {
        CardMotion.edgeBand(startTop: grab.card.rect.minY, finger: grab.finger.y,
                            startScale: grab.card.size.width / width, screenHeight: height)
    }

    @Test(arguments: grabs)
    func theTopNeverPassesTheLimit(grab: Grab) {
        let limit = band(grab).limit
        #expect(limit <= RunnerMetrics.trackEdge)
        #expect(limit <= grab.card.rect.minY)
        for dy in stride(from: CGFloat(0), through: -6000, by: -3) {
            for dx: CGFloat in [-250, 0, 250] {
                let top = tracked(grab, CGPoint(x: dx, y: dy)).rect.minY
                #expect(top >= limit, "\(top) above \(limit) at \(dy)")
            }
        }
    }

    /// A card swiped up from full screen never leaves the screen at all.
    @Test func aFullScreenCardStaysOnScreen() {
        let grab = Self.grabs[0]
        for dy in stride(from: CGFloat(0), through: -6000, by: -1) {
            #expect(tracked(grab, CGPoint(x: 0, y: dy)).rect.minY >= 0)
        }
    }

    /// Dragged down from the status bar, its bottom edge gets the same rule.
    @Test func theDragDownIsHeldAtTheBottomEdge() {
        let grab = Grab(card: full, finger: CGPoint(x: 201, y: 20), name: "status bar")
        for dy in stride(from: CGFloat(0), through: 6000, by: 2) {
            let frame = tracked(grab, CGPoint(x: 40, y: dy), .down)
            #expect(frame.rect.maxY <= height)
            // And the mirror image of a swipe up from the bottom edge.
            let mirror = tracked(Grab(card: full, finger: CGPoint(x: 201, y: height - 20), name: ""), CGPoint(x: 40, y: -dy))
            #expect(abs(frame.rect.maxY - (height - mirror.rect.minY)) < 0.001)
            #expect(abs(frame.center.x - mirror.center.x) < 0.001)
        }
    }

    @Test(arguments: grabs)
    func thePointUnderTheFingerHoldsUntilTheLimit(grab: Grab) {
        let band = band(grab)
        let fraction = (grab.finger.y - grab.card.rect.minY) / grab.card.size.height
        var held: CGFloat = 0
        for dy in stride(from: CGFloat(0), through: -3000, by: -1) {
            let frame = tracked(grab, CGPoint(x: 25, y: dy))
            let moved = -dy
            if moved > band.engagesAfter, frame.rect.minY < band.soft - 0.000_1 { break }
            let finger = CGPoint(x: grab.finger.x + 25, y: grab.finger.y + dy)
            #expect(abs((finger.y - frame.rect.minY) / frame.size.height - fraction) < 0.000_1)
            let across = (grab.finger.x - grab.card.rect.minX) / grab.card.size.width
            #expect(abs((finger.x - frame.rect.minX) / frame.size.width - across) < 0.000_1)
            held = moved
        }
        // It held for a while (unless the card was caught already inside the
        // band, its edge heading for the limit), and past the limit the
        // card lags the finger.
        if grab.card.rect.minY > band.soft + 1 || band.engagesAfter > 0 { #expect(held > 20) }
        let far = tracked(grab, CGPoint(x: 25, y: -held - 400))
        let finger = grab.finger.y - held - 400
        #expect((finger - far.rect.minY) / far.size.height < fraction - 0.05)
    }

    /// Crossing into the band, neither the card's edge nor its speed jumps:
    /// across the whole swipe the edge moves smoothly with the finger.
    @Test(arguments: grabs)
    func nothingJumpsWhenCrossingTheLimit(grab: Grab) {
        let step: CGFloat = 0.25
        var tops: [CGFloat] = []
        for dy in stride(from: CGFloat(0), through: -2500, by: -step) {
            tops.append(tracked(grab, CGPoint(x: 0, y: dy)).rect.minY)
        }
        let speeds = zip(tops.dropFirst(), tops).map { ($0 - $1) / step }
        // Never faster than the finger, so never a jump.
        #expect(speeds.allSatisfy { abs($0) <= 1.0001 })
        // And no kink: the speed changes only a little from one step to the
        // next (the band bends it, gently; a kink would change it by most of
        // the finger's speed at once).
        let kinks = zip(speeds.dropFirst(), speeds).map { abs($0 - $1) }
        #expect(kinks.max() ?? 0 < 0.05)
        // The band did engage, so this crossed it.
        let band = band(grab)
        #expect(tops.contains { $0 < band.soft - 1 })
    }

    @Test(arguments: grabs)
    func aCaughtCardIsPickedUpWhereItIs(grab: Grab) {
        let still = tracked(grab, .zero)
        #expect(still.isClose(to: grab.card, within: 0.000_1))
    }

    /// A long swipe still shrinks the card: the scale follows the finger
    /// past the limit, and so does its sideways movement.
    @Test func theScaleAndTheSidewaysMovementKeepFollowing() {
        let grab = Self.grabs[0]
        let near = tracked(grab, CGPoint(x: 0, y: -400))
        let far = tracked(grab, CGPoint(x: 0, y: -900))
        #expect(far.size.width < near.size.width - 30)
        let moved = tracked(grab, CGPoint(x: 120, y: -900))
        #expect(abs(moved.center.x - far.center.x - 120) < 0.001)
        #expect(abs(moved.center.y - far.center.y) < 0.001)
    }

    /// Measured on an iPhone 17: Springboard's card loses about 0.0016 of
    /// its width per point the finger rises at first, and its top edge
    /// moves down, away from the screen's top, while it does.
    @Test func itShrinksAtSpringboardsRateAndItsTopFirstMovesDown() {
        let grab = Self.grabs[0]
        let slope = (1 - tracked(grab, CGPoint(x: 0, y: -60)).size.width / width) / 60
        #expect(abs(slope - 0.0016) < 0.0002)
        let top = tracked(grab, CGPoint(x: 0, y: -100)).rect.minY
        #expect(top > 10)
    }
}

/// What a card does once the finger lets go.
struct CardReleaseTests {
    private let height: CGFloat = 874
    private let width: CGFloat = 402
    private var full: CardFrame { CardFrame(rect: CGRect(x: 0, y: 0, width: width, height: height), radius: 55) }
    private let finger = CGPoint(x: 201, y: 862)

    private func velocity(after translation: CGPoint, at speed: CGPoint) -> CardVelocity {
        CardMotion.trackedVelocity(start: full, startScale: 1, finger: finger, translation: translation, velocity: speed,
                                   direction: .up, screenHeight: height)
    }

    /// The springs start at the card's own speed, the derivative of where
    /// the finger put it: at the limit, a flick leaves its top all but still.
    @Test func theSpringsStartAtTheCardsSpeedNotTheFingers() {
        let speed = CGPoint(x: 0, y: -3000)
        let long = velocity(after: CGPoint(x: 0, y: -700), at: speed)
        let top = long.center.y - long.size.height / 2
        #expect(abs(top) < 150)
        #expect(abs(long.center.y) < 1500)
        // Still shrinking at the finger's pace.
        #expect(long.size.width < -300)
        // Before the limit it is the plain derivative: compare a small step.
        let short = CGPoint(x: 0, y: -40)
        let v = velocity(after: short, at: CGPoint(x: 0, y: -1000))
        let a = CardMotion.tracked(start: full, startScale: 1, finger: finger, translation: short,
                                   direction: .up, screenHeight: height).frame
        let b = CardMotion.tracked(start: full, startScale: 1, finger: finger, translation: CGPoint(x: 0, y: -41),
                                   direction: .up, screenHeight: height).frame
        #expect(abs(v.center.y - (b.center.y - a.center.y) * 1000) < 1)
        #expect(abs(v.size.width - (b.size.width - a.size.width) * 1000) < 1)
    }

    /// A flick lets go of a card still most of the screen: it shrinks
    /// almost in place and then glides onto its icon, wherever that is. It
    /// never flies off the top, and never drops past an icon below it.
    @Test(arguments: [CGRect(x: 308, y: 90, width: 64, height: 64),    // top row, right
                      CGRect(x: 30, y: 391, width: 64, height: 64),    // middle, left
                      CGRect(x: 169, y: 773, width: 64, height: 64)])  // the dock
    func aFlickGlidesOntoItsIcon(icon: CGRect) {
        let translation = CGPoint(x: 0, y: -130)
        let start = CardMotion.tracked(start: full, startScale: 1, finger: finger, translation: translation,
                                       direction: .up, screenHeight: height).frame
        let flight = CardFlight(from: start, velocity: velocity(after: translation, at: CGPoint(x: 0, y: -3000)),
                                to: CardFrame(rect: icon, radius: HomeMetrics.iconRadius(64)), springs: Motion.cardClose, at: 0)
        var lowest = start.center.y, highest = start.center.y
        for frame in stride(from: 0.0, through: 0.6, by: 1.0 / 120).map(flight.frame(at:)) {
            #expect(frame.rect.minY >= 0)
            lowest = max(lowest, frame.center.y)
            highest = min(highest, frame.center.y)
        }
        // Up a little with the speed it had, at most, and past the icon by no
        // more than its settle.
        #expect(highest > min(start.center.y, icon.midY) - 30)
        #expect(lowest < max(start.center.y, icon.midY) + 4)
        // Nearly home by about 300 ms after the finger lets go, as
        // Springboard's is (within 2% of the way across; Shelf's within 5%).
        let distance = hypot(start.center.x - icon.midX, start.center.y - icon.midY)
        #expect(flight.frame(at: 0.3).isClose(to: flight.target, within: max(3, distance * 0.05)))
        #expect(flight.isSettled(at: 0.6))
    }

    /// Its height closes faster than its width, so the card turns from
    /// portrait to square on the way, as Springboard's does.
    @Test func itTurnsSquareOnTheWay() {
        let flight = CardFlight(from: full, velocity: .zero, to: CardFrame(rect: CGRect(x: 169, y: 400, width: 64, height: 64), radius: 15),
                                springs: Motion.cardClose, at: 0)
        let middle = flight.frame(at: 0.1)
        let heightLeft = (middle.size.height - 64) / (height - 64)
        let widthLeft = (middle.size.width - 64) / (width - 64)
        #expect(heightLeft < widthLeft)
        #expect(middle.size.height / middle.size.width < height / width)
    }

    /// Retargeted mid-flight (its icon moved), the card carries on from
    /// where it is at the speed it has.
    @Test func aNewTargetCarriesOnFromWhereItIs() {
        let first = CardFlight(from: full, velocity: .zero, to: CardFrame(rect: CGRect(x: 30, y: 90, width: 64, height: 64), radius: 15),
                               springs: Motion.cardClose, at: 0)
        let now = 0.08
        let second = CardFlight(from: first.frame(at: now), velocity: first.velocity(at: now),
                                to: CardFrame(rect: CGRect(x: 308, y: 90, width: 64, height: 64), radius: 15),
                                springs: Motion.cardClose, at: now)
        #expect(second.frame(at: now).isClose(to: first.frame(at: now), within: 0.000_1))
        let v1 = first.velocity(at: now), v2 = second.velocity(at: now)
        #expect(abs(v1.center.x - v2.center.x) < 0.01 && abs(v1.size.width - v2.size.width) < 0.01)
    }
}

/// The card's face and the stage it flies over, in UIKit.
@MainActor
@Suite struct CardFaceTests {
    private let screen = CGSize(width: 402, height: 874)

    /// Caught mid-flight, even above the limit (still growing past full
    /// screen on the open's spring), a card is picked up exactly where it is
    /// on screen. It has no Core Animation animations whose presentation
    /// could differ from its model: what it shows is what it was placed at.
    @Test func aCardCaughtMidFlightIsPickedUpWhereItIs() {
        let face = CardFaceView(face: IconFace(AppMeta(slug: "a", name: "A", version: "1")), iconSize: 64, screen: screen, fullRadius: 55)
        // Grown past full screen, above the limit, on its way back.
        face.place(CardFrame(rect: CGRect(x: -6, y: -12, width: 414, height: 898), radius: 57))
        let full = CardFrame(rect: CGRect(origin: .zero, size: screen), radius: 55)
        face.fly(to: full, Motion.cardOpen, velocity: CardVelocity(center: .zero, size: CGSize(width: 40, height: 80), radius: 0))
        #expect(!face.step(at: 0))
        #expect(!face.step(at: 1.0 / 120))
        #expect(face.shown.rect.minY < 0)
        #expect(face.layer.animationKeys() == nil)
        #expect(face.layer.position == face.shown.center)
        let caught = face.freeze()
        #expect(caught == face.shown)
        #expect(!face.isMoving)
        let picked = CardMotion.tracked(start: caught, startScale: caught.size.width / screen.width,
                                        finger: CGPoint(x: 201, y: 860), translation: .zero, direction: .up,
                                        screenHeight: screen.height).frame
        #expect(picked.isClose(to: caught, within: 0.000_1))
    }

    private func makeFace(iconSize: CGFloat = 62) -> CardFaceView {
        CardFaceView(face: IconFace(AppMeta(slug: "a", name: "A", version: "1")), iconSize: iconSize, screen: screen, fullRadius: 55)
    }

    /// The same centre and size; the corner is drawn for the size.
    private func samePlace(_ a: CardFrame, _ b: CardFrame) -> Bool {
        a.isClose(to: CardFrame(center: b.center, size: b.size, radius: a.radius), within: 0.000_1)
    }

    /// Weather's slot, top row, second column.
    private let icon = CardFrame(rect: CGRect(x: 124, y: 90, width: 62, height: 62), radius: HomeMetrics.iconRadius(62))
    private var full: CardFrame { CardFrame(rect: CGRect(origin: .zero, size: screen), radius: 55) }

    /// However late the first frame after the tap is (a cold open holds up
    /// the main thread while the card is built), it shows the card on its
    /// icon, and the next shows it grown by no more than a frame's worth:
    /// every frame of the growth is seen, as Springboard's is. (The user's
    /// "this is wrong": on the display's clock, the first frame anyone saw
    /// was a card already most of the way to full screen.)
    @Test(arguments: [0.0, 0.09, 0.5, 1000])
    func theCardsFirstFrameIsItsIcon(hitch: Double) {
        let face = makeFace()
        face.place(icon)
        face.fly(to: full, Motion.cardOpen, leansFrom: CGPoint(x: icon.center.x, y: icon.center.y))
        let start = 50.0
        #expect(!face.step(at: start + hitch))
        #expect(face.shown.isClose(to: icon, within: 0.000_1))
        #expect(face.lean == .none)
        #expect(!face.step(at: start + hitch + 0.3))
        let reference = CardFlight(from: icon, velocity: .zero, to: full, springs: Motion.cardOpen,
                                   slowdown: Motion.Spring.slowdown, at: 0)
        #expect(samePlace(face.shown, reference.frame(at: RunnerMetrics.maxFrameStep)))
        // Frame by frame at 60 Hz, it runs on the display's time.
        #expect(!face.step(at: start + hitch + 0.3 + 1.0 / 60))
        #expect(samePlace(face.shown, reference.frame(at: RunnerMetrics.maxFrameStep + 1.0 / 60)))
    }

    /// At every point of an open and a close, the app's picture is exactly
    /// the card: as wide, its top at the card's top, cropped at the bottom
    /// by the outline that clips the whole card. A snapshot fading in over
    /// the launch surface is the same size and in the same place.
    @Test func thePictureIsAlwaysTheCard() throws {
        let face = makeFace()
        face.place(icon)
        face.show(UIView())
        let opening = CardFlight(from: icon, velocity: .zero, to: full, springs: Motion.cardOpen, at: 0)
        let closing = CardFlight(from: full, velocity: .zero, to: icon, springs: Motion.cardClose, at: 0)
        let frames = stride(from: 0.0, through: 0.6, by: 1.0 / 60).flatMap { [opening.frame(at: $0), closing.frame(at: $0)] }
        for frame in frames + [CardFrame(rect: CGRect(x: -6, y: -12, width: 414, height: 898), radius: 57)] {
            face.place(frame)
            let picture = face.content.frame
            let outline = try #require((face.layer.mask as? CAShapeLayer)?.path?.boundingBox)
            let card = IconArtView.centered(frame.size)
            #expect(abs(outline.minX - card.minX) < 0.01 && abs(outline.maxX - card.maxX) < 0.01)
            #expect(abs(outline.minY - card.minY) < 0.01 && abs(outline.maxY - card.maxY) < 0.01)
            #expect(abs(picture.minX - card.minX) < 0.01 && abs(picture.maxX - card.maxX) < 0.01)
            #expect(abs(picture.minY - card.minY) < 0.01)
            #expect(picture.maxY >= card.maxY - 0.01)
            #expect(face.layer.position == frame.center)
        }
        face.setContentOpacity(1)
        let snapshot = UIView()
        face.show(snapshot, fading: true)
        #expect(snapshot.superview === face.content)
        #expect(snapshot.frame == face.content.bounds)
        // The surface stays under it, opaque, until it has faded in.
        #expect(face.content.subviews.count == 2)
    }

    /// The icon's face is gone once the picture covers the card, opening
    /// (past the crossfade's end, 0.5) and closing alike, and is back as
    /// soon as any of it shows through.
    @Test func theIconIsGoneOnceThePictureCoversTheCard() {
        let face = makeFace()
        for step in 0...100 {
            let progress = CGFloat(step) / 100
            for opening in [true, false] {
                let look = CardMotion.look(progress: progress, opening: opening)
                face.setContentOpacity(look.content)
                let covered = progress >= (opening ? RunnerMetrics.launchFade.upperBound : RunnerMetrics.contentFade.upperBound)
                if covered { #expect(look.content == 1) }
                #expect(face.showsArt == (look.content < 1))
                if progress <= (opening ? RunnerMetrics.launchFade.lowerBound : RunnerMetrics.contentFade.lowerBound) {
                    #expect(face.showsArt)
                }
            }
        }
    }

    /// The card lands where its icon will be once the Home Screen behind it
    /// is back at full size, not where the icon is drawn while the Home
    /// Screen is scaled back behind it. (The user's "it goes down, not to
    /// the icon": behind a card at 80% the Home Screen is at 0.9, which put
    /// the landing for Timer, top right, 37 points low and 13 in, and the
    /// card sat there until it swapped for the icon above it.)
    @Test func aCardLandsWhereItsIconWillBeNotWhereItIsDrawn() throws {
        let cache = AppCache(root: temporaryFolder())
        let apps = ["timer", "habits"].map { CachedApp(meta: AppMeta(slug: $0, name: $0.capitalized, version: "1"), cachedVersion: "1") }
        let library = LibraryStore(demo: apps, dock: ["habits"], cache: cache)
        let stage = StageController(model: HomeModel(), library: library, settings: ShelfSettings())
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: screen)
        window.rootViewController = stage
        window.isHidden = false
        defer { window.isHidden = true }
        stage.view.layoutIfNeeded()
        let geometry = stage.geometry
        try #require(geometry.size.width > 0)

        for slug in ["timer", "habits"] {
            let slot = try #require(library.layout.slot(of: slug))
            let icon = geometry.iconFrame(at: slot, dockCount: library.layout.dock.count, page: 0)
            stage.setBackdrop(1)
            let landing = stage.landing(for: slug)
            #expect(landing.frame == icon)
            #expect(!landing.fades)
            stage.setBackdrop(0)
        }
    }
}

/// The clock a card's flight runs on.
struct CardClockTests {
    @Test func itRunsOnTheDisplaysTimeButNeverJumps() {
        var clock = CardClock()
        // The first frame shows where it set off.
        #expect(clock.advance(to: 10) == 0)
        #expect(abs(clock.advance(to: 10 + 1.0 / 60) - 1.0 / 60) < 1e-12)
        // A frame held up 90 ms moves it on by two frames' worth.
        #expect(abs(clock.advance(to: 10 + 1.0 / 60 + 0.09) - (1.0 / 60 + RunnerMetrics.maxFrameStep)) < 1e-12)
        // Never backwards.
        let now = clock.now
        #expect(clock.advance(to: 5) == now)
        // Paused, the next frame shows where it stopped.
        clock.pause()
        #expect(clock.advance(to: 99) == now)
        #expect(abs(clock.advance(to: 99 + 1.0 / 120) - (now + 1.0 / 120)) < 1e-12)
    }
}

struct SpringValueTests {
    // The card's springs never bounce negatively (overdamped), where
    // SwiftUI's velocity and value disagree.
    @Test(arguments: [0.0, 0.05, 0.16, 0.3])
    func itStartsWhereAndAsFastAsItWasToldAndSettles(bounce: Double) {
        let value = SpringValue(from: 100, to: 0, velocity: -400, curve: .init(duration: 0.3, bounce: bounce), at: 2)
        #expect(abs(value.value(at: 2) - 100) < 1e-9)
        #expect(abs(value.velocity(at: 2) + 400) < 1e-6)
        #expect(value.isSettled(at: 5, tolerance: 0.5))
        #expect(!value.isSettled(at: 2.05, tolerance: 0.5))
        // Its velocity is its value's derivative.
        let t = 2.07, dt = 1e-6
        #expect(abs((value.value(at: t + dt) - value.value(at: t)) / dt - value.velocity(at: t)) < 0.01)
    }

    @Test func noBounceNeverOvershootsFromRest() {
        let value = SpringValue(from: 100, to: 0, velocity: 0, curve: .init(duration: 0.3, bounce: 0), at: 0)
        for t in stride(from: 0.0, through: 2, by: 0.01) {
            #expect(value.value(at: t) >= -1e-9)
        }
    }
}

struct SearchWarpTests {
    private let pill = CGRect(x: 161.67, y: 703.67, width: 78.67, height: 29.33)

    @Test func aPullMovesTheWarpInProportionAndStopsAtTheField() {
        #expect(SearchWarp.progress(pull: 0, from: 0) == 0)
        #expect(abs(SearchWarp.progress(pull: SearchMetrics.pullDistance / 2, from: 0) - 0.5) < 0.0001)
        #expect(SearchWarp.progress(pull: SearchMetrics.pullDistance * 3, from: 0) == 1)
        #expect(SearchWarp.progress(pull: -50, from: 0) == 0)
        // A warp caught halfway carries on from there.
        #expect(abs(SearchWarp.progress(pull: 0, from: 0.5) - 0.5) < 0.0001)
    }

    @Test func releasesOpenByFlickOrByDistance() {
        #expect(SearchWarp.opens(progress: 0.05, velocity: SearchMetrics.openVelocity + 1))
        #expect(!SearchWarp.opens(progress: 0.95, velocity: -SearchMetrics.openVelocity - 1))
        #expect(SearchWarp.opens(progress: SearchMetrics.openProgress + 0.01, velocity: 0))
        #expect(!SearchWarp.opens(progress: SearchMetrics.openProgress - 0.01, velocity: 0))
    }

    /// App Library's field and round ✕, on the pill's line.
    @Test func theFieldAndItsCloseButtonSitOnThePillsLine() {
        let field = SearchWarp.field(screenWidth: 402, pill: pill)
        let close = SearchWarp.close(screenWidth: 402, field: field)
        #expect(field.minX == SearchMetrics.sideInset)
        #expect(abs(close.maxX - (402 - SearchMetrics.sideInset)) < 0.0001)
        #expect(abs(close.minX - field.maxX - SearchMetrics.closeGap) < 0.0001)
        #expect(abs(field.midY - pill.midY) < 0.0001 && abs(close.midY - pill.midY) < 0.0001)
        #expect(field.height == SearchMetrics.fieldHeight && close.height == SearchMetrics.closeSize)
    }

    @Test func theKeyboardLiftsTheFieldJustAboveItself() {
        let field = SearchWarp.field(screenWidth: 402, pill: pill)
        #expect(SearchWarp.lift(field: field, keyboardTop: nil) == 0)
        let lift = SearchWarp.lift(field: field, keyboardTop: 520)
        #expect(abs(field.maxY + lift - (520 - SearchMetrics.keyboardGap)) < 0.0001)
        // A keyboard below the field leaves it where it is.
        #expect(SearchWarp.lift(field: field, keyboardTop: 870) == 0)
    }
}
