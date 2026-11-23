import CoreGraphics
import Testing
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
        let finger = CGPoint(x: 201, y: 40)
        let translation = CGPoint(x: 20, y: 300)
        let tracked = CardMotion.tracked(start: full, startScale: 1, finger: finger, translation: translation,
                                         screenHeight: height).frame
        let ratio = tracked.size.width / full.size.width
        #expect(ratio < 1)
        // The finger began near the card's top-centre and is still there.
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
                                       screenHeight: height)
        #expect(abs(still.frame.size.width - small.size.width) < 0.001)
        #expect(still.travel > 0)
        // Dragged up, toward full screen, it grows.
        let up = CardMotion.tracked(start: small, startScale: scale, finger: small.center,
                                    translation: CGPoint(x: 0, y: -200), screenHeight: height)
        #expect(up.frame.size.width > small.size.width)
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

    @Test func springVelocityIsInSpringLengthsAndBounded() {
        #expect(CardMotion.springVelocity(500, from: 0, to: 250) == 2)
        #expect(CardMotion.springVelocity(500, from: 0, to: -250) == -2)
        #expect(CardMotion.springVelocity(500, from: 10, to: 10.5) == 0)
        #expect(CardMotion.springVelocity(100_000, from: 0, to: 2) == RunnerMetrics.maxSpringVelocity)
    }
}

struct SearchWarpTests {
    private let pill = CGRect(x: 161.67, y: 703.67, width: 78.67, height: 29.33)

    @Test func aPullMovesTheWarpInProportionAndStopsAtTheField() {
        #expect(SearchWarp.progress(pull: 0, from: 0) == 0)
        #expect(abs(SearchWarp.progress(pull: HomeMetrics.searchPullDistance / 2, from: 0) - 0.5) < 0.0001)
        #expect(SearchWarp.progress(pull: HomeMetrics.searchPullDistance * 3, from: 0) == 1)
        #expect(SearchWarp.progress(pull: -50, from: 0) == 0)
        // A warp caught halfway carries on from there.
        #expect(abs(SearchWarp.progress(pull: 0, from: 0.5) - 0.5) < 0.0001)
    }

    @Test func releasesOpenByFlickOrByDistance() {
        #expect(SearchWarp.opens(progress: 0.05, velocity: HomeMetrics.searchOpenVelocity + 1))
        #expect(!SearchWarp.opens(progress: 0.95, velocity: -HomeMetrics.searchOpenVelocity - 1))
        #expect(SearchWarp.opens(progress: HomeMetrics.searchOpenProgress + 0.01, velocity: 0))
        #expect(!SearchWarp.opens(progress: HomeMetrics.searchOpenProgress - 0.01, velocity: 0))
    }

    @Test func theFieldIsFullWidthOnThePillsLine() {
        let field = SearchWarp.field(screenWidth: 402, pill: pill)
        #expect(field.minX == HomeMetrics.searchSideInset)
        #expect(field.maxX == 402 - HomeMetrics.searchSideInset)
        #expect(abs(field.midY - pill.midY) < 0.0001)
        #expect(field.height == HomeMetrics.searchFieldHeight)
    }

    @Test func theKeyboardLiftsTheFieldJustAboveItself() {
        let field = SearchWarp.field(screenWidth: 402, pill: pill)
        #expect(SearchWarp.lift(field: field, keyboardTop: nil) == 0)
        let lift = SearchWarp.lift(field: field, keyboardTop: 520)
        #expect(abs(field.maxY + lift - (520 - HomeMetrics.searchKeyboardGap)) < 0.0001)
        // A keyboard below the field leaves it where it is.
        #expect(SearchWarp.lift(field: field, keyboardTop: 870) == 0)
    }

    @Test func theGlassWidthGivesTheProgressBack() {
        let field = SearchWarp.field(screenWidth: 402, pill: pill)
        for p: CGFloat in [0, 0.25, 0.6, 1] {
            let glass = pill.interpolated(to: field, p)
            #expect(abs(SearchWarp.progress(width: glass.width, pill: pill, field: field) - p) < 0.0001)
        }
    }
}
