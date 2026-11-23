import CoreGraphics
import Foundation

/// How fast each part of a card is changing, per second: its centre, its
/// width and height, and its corner radius.
struct CardVelocity: Equatable, Sendable {
    var center: CGPoint
    var size: CGSize
    var radius: CGFloat

    static let zero = CardVelocity(center: .zero, size: .zero, radius: 0)

    func scaled(by factor: CGFloat) -> CardVelocity {
        CardVelocity(center: CGPoint(x: center.x * factor, y: center.y * factor),
                     size: CGSize(width: size.width * factor, height: size.height * factor),
                     radius: radius * factor)
    }
}

/// A card on its way somewhere with no finger on it: each of its centre's
/// x and y, its width, its height and its corner on a spring of its own,
/// solved for any moment. The stage reads it every frame.
struct CardFlight: Equatable, Sendable {
    let target: CardFrame
    private let x, y, width, height, radius: SpringValue

    /// From `start`, moving at `velocity` (points per second of played
    /// time), to `target` on `springs`. A debug build's slow motion is in
    /// `slowdown`: the springs run that many times longer.
    init(from start: CardFrame, velocity: CardVelocity, to target: CardFrame, springs: Motion.CardSprings,
         slowdown: Double = 1, at time: Double) {
        self.target = target
        func curve(_ spring: Motion.Spring) -> SpringCurve {
            SpringCurve(duration: spring.duration * slowdown, bounce: spring.bounce)
        }
        func value(_ from: CGFloat, _ to: CGFloat, _ speed: CGFloat, _ spring: Motion.Spring) -> SpringValue {
            SpringValue(from: from, to: to, velocity: CardMotion.boundedVelocity(speed, from: from, to: to),
                        curve: curve(spring), at: time)
        }
        x = value(start.center.x, target.center.x, velocity.center.x, springs.position)
        y = value(start.center.y, target.center.y, velocity.center.y, springs.position)
        width = value(start.size.width, target.size.width, velocity.size.width, springs.width)
        height = value(start.size.height, target.size.height, velocity.size.height, springs.height)
        // The corner follows the width, so the outline keeps its shape.
        radius = value(start.radius, target.radius, velocity.radius, springs.width)
    }

    func frame(at time: Double) -> CardFrame {
        CardFrame(center: CGPoint(x: x.value(at: time), y: y.value(at: time)),
                  size: CGSize(width: max(width.value(at: time), 1), height: max(height.value(at: time), 1)),
                  radius: max(radius.value(at: time), 0))
    }

    func velocity(at time: Double) -> CardVelocity {
        CardVelocity(center: CGPoint(x: x.velocity(at: time), y: y.velocity(at: time)),
                     size: CGSize(width: width.velocity(at: time), height: height.velocity(at: time)),
                     radius: radius.velocity(at: time))
    }

    /// Every part within `tolerance` points of its target and all but still.
    func isSettled(at time: Double, tolerance: CGFloat = RunnerMetrics.restTolerance) -> Bool {
        [x, y, width, height, radius].allSatisfy { $0.isSettled(at: time, tolerance: tolerance) }
    }
}
