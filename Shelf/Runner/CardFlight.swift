import CoreGraphics
import SwiftUI

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
///
/// Core Animation runs one spring per key path, and a path or a bounds
/// changes width and height together. Springboard's card shrinks faster
/// than it travels, and its height faster than its width
/// (`design/reference/springboard/README.md`, the real-device close), so
/// the card's flight is several springs, one per property, solved in closed
/// form. Caught anywhere, it says exactly where it is and how fast it is
/// going, so nothing jumps when a finger catches it or its target moves.
struct CardFlight: Equatable, Sendable {
    let target: CardFrame
    private let x, y, width, height, radius: SpringValue

    /// From `start`, moving at `velocity` (points per second of played
    /// time), to `target` on `springs`. A debug build's slow motion is in
    /// `slowdown`: the springs run that many times longer.
    init(from start: CardFrame, velocity: CardVelocity, to target: CardFrame, springs: Motion.CardSprings,
         slowdown: Double = 1, at time: Double) {
        self.target = target
        func curve(_ spring: Motion.Spring) -> SwiftUI.Spring {
            SwiftUI.Spring(duration: spring.duration * slowdown, bounce: spring.bounce)
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

/// One value on its way to `target` on a spring, from `start` at `time`:
/// SwiftUI's spring, solved for any moment, as `ValueSpring` does.
struct SpringValue: Equatable, Sendable {
    let target: Double
    let spring: SwiftUI.Spring
    let start: Double
    let time: Double
    let velocity: Double

    init(from start: Double, to target: Double, velocity: Double, curve spring: SwiftUI.Spring, at time: Double) {
        self.target = target
        self.spring = spring
        self.start = start
        self.time = time
        self.velocity = velocity
    }

    func value(at now: Double) -> Double {
        start + spring.value(target: target - start, initialVelocity: velocity, time: max(now - time, 0))
    }

    func velocity(at now: Double) -> Double {
        spring.velocity(target: target - start, initialVelocity: velocity, time: max(now - time, 0))
    }

    /// Within `tolerance` of its target, and moving less than that in a
    /// frame at 120 Hz.
    func isSettled(at now: Double, tolerance: Double) -> Bool {
        abs(value(at: now) - target) <= tolerance && abs(velocity(at: now)) / 120 <= tolerance
    }
}
