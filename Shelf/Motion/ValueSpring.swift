import SwiftUI
import UIKit

/// One number on a spring, stepped every frame by a display link: for a
/// motion that many things follow at once and that isn't one property of
/// one layer. Search's warp is one: the glass, the label, the blur radius,
/// the fades and the list all follow its progress, so nothing can ever be
/// at two points of it.
///
/// The value set each frame is what's on screen, so there is no
/// presentation to read back: a finger that catches it, or a new target,
/// starts from `value` and `velocity` exactly as they are now.
@MainActor
final class ValueSpring {
    /// Called with every new value, animated or set.
    var onChange: (CGFloat) -> Void = { _ in }
    /// Called once the value has come to rest at its target.
    var onRest: (CGFloat) -> Void = { _ in }

    private(set) var value: CGFloat
    private var run: Run?
    private var link: CADisplayLink?

    /// One spring from `from` toward `target`, started at `start`.
    private struct Run {
        var from: CGFloat
        var target: CGFloat
        var velocity: CGFloat
        var spring: SwiftUI.Spring
        var start: CFTimeInterval
    }

    init(_ value: CGFloat) {
        self.value = value
    }

    var target: CGFloat { run?.target ?? value }
    var isMoving: Bool { run != nil }

    /// How fast the value is changing now, in units per second.
    var velocity: CGFloat {
        guard let run else { return 0 }
        return Self.sample(run, at: CACurrentMediaTime()).velocity
    }

    /// Sets the value at once, stopping any spring.
    func set(_ value: CGFloat) {
        stop()
        self.value = value
        onChange(value)
    }

    /// Stops where it is now.
    func stop() {
        if let run { value = Self.sample(run, at: CACurrentMediaTime()).value }
        run = nil
        link?.invalidate()
        link = nil
    }

    /// Springs to `target` from where the value is now. `velocity` is in
    /// units per second; nil keeps the speed it has.
    func animate(to target: CGFloat, _ spring: Motion.Spring, velocity: CGFloat? = nil) {
        let now = CACurrentMediaTime()
        let current = run.map { Self.sample($0, at: now) } ?? (value, 0)
        value = current.value
        run = Run(from: current.value, target: target, velocity: velocity.map(spring.played(velocity:)) ?? current.velocity,
                  spring: SwiftUI.Spring(duration: spring.playedDuration, bounce: spring.bounce), start: now)
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = Motion.frameRate
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        tick()
    }

    @objc private func tick() {
        guard let run else { return }
        // The frame about to be shown, not the one just gone.
        let time = link.map { $0.targetTimestamp } ?? CACurrentMediaTime()
        let sample = Self.sample(run, at: time)
        if Self.hasSettled(run, at: time) {
            self.run = nil
            link?.invalidate()
            link = nil
            value = run.target
            onChange(value)
            onRest(value)
            return
        }
        value = sample.value
        onChange(value)
    }

    /// Where a spring is, and how fast it is going, `time` after it started.
    private static func sample(_ run: Run, at time: CFTimeInterval) -> (value: CGFloat, velocity: CGFloat) {
        Self.sample(from: run.from, to: run.target, velocity: run.velocity, spring: run.spring, time: max(time - run.start, 0))
    }

    private static func hasSettled(_ run: Run, at time: CFTimeInterval) -> Bool {
        let span = run.target - run.from
        let elapsed = time - run.start
        let settling = run.spring.settlingDuration(target: span == 0 ? 1 : span, initialVelocity: run.velocity, epsilon: 0.0005)
        return elapsed >= settling
    }

    /// A spring from `from` to `to`, starting at `velocity` units per
    /// second: its value and velocity `time` seconds in.
    static func sample(from: CGFloat, to: CGFloat, velocity: CGFloat, spring: SwiftUI.Spring, time: TimeInterval)
        -> (value: CGFloat, velocity: CGFloat) {
        let span = Double(to - from)
        let value = spring.value(target: span, initialVelocity: Double(velocity), time: time)
        let speed = spring.velocity(target: span, initialVelocity: Double(velocity), time: time)
        return (from + CGFloat(value), CGFloat(speed))
    }
}
