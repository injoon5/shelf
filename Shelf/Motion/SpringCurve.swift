import Foundation

/// A damped spring solved in closed form: the spring SwiftUI's
/// `Spring(duration:bounce:)` and `CASpringAnimation(perceptualDuration:bounce:)`
/// describe, as a function of time.
///
/// Core Animation runs one spring per key path, and a path or a bounds
/// changes width and height together. An app's card needs more than that:
/// Springboard's card shrinks faster than it travels, and its height faster
/// than its width (`design/reference/springboard/README.md`, the real-device
/// close). So the card's flight is several of these, one per property, read
/// every frame. Being closed-form, a spring caught anywhere says exactly
/// where it is and how fast it is going, so nothing jumps when a finger
/// catches it or a new target replaces the old.
struct SpringCurve: Equatable, Sendable {
    /// The undamped angular frequency, in radians per second.
    let omega: Double
    /// 1 is critically damped; below 1 it bounces.
    let dampingRatio: Double

    /// The spring that runs `duration` seconds (perceptually) with `bounce`,
    /// in SwiftUI's terms: stiffness (2π / duration)², and a damping ratio of
    /// 1 − bounce (or 1 / (1 + bounce) for a negative, flattened bounce).
    init(duration: Double, bounce: Double) {
        omega = 2 * .pi / max(duration, 0.001)
        dampingRatio = bounce >= 0 ? 1 - min(bounce, 0.999) : 1 / (1 + max(bounce, -0.999))
    }

    /// Where a spring that started `displacement` from its target, moving at
    /// `velocity` (units per second, positive away from zero), is `t` seconds
    /// later, and how fast it is moving then.
    func state(displacement x0: Double, velocity v0: Double, at t: Double) -> (displacement: Double, velocity: Double) {
        let t = max(t, 0)
        let w = omega, z = dampingRatio
        if abs(z - 1) < 1e-6 {
            // Critically damped.
            let decay = exp(-w * t)
            let b = v0 + w * x0
            return ((x0 + b * t) * decay, (b - w * (x0 + b * t)) * decay)
        }
        if z < 1 {
            let wd = w * (1 - z * z).squareRoot()
            let decay = exp(-z * w * t)
            let b = (v0 + z * w * x0) / wd
            let c = cos(wd * t), s = sin(wd * t)
            let x = decay * (x0 * c + b * s)
            let v = decay * ((-x0 * wd * s + b * wd * c) - z * w * (x0 * c + b * s))
            return (x, v)
        }
        let root = (z * z - 1).squareRoot()
        let r1 = -w * (z - root), r2 = -w * (z + root)
        let c2 = (v0 - r1 * x0) / (r2 - r1)
        let c1 = x0 - c2
        let e1 = exp(r1 * t), e2 = exp(r2 * t)
        return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
    }
}

/// One value on its way to `target` along a `SpringCurve`, from `start`.
struct SpringValue: Equatable, Sendable {
    let target: Double
    let curve: SpringCurve
    let start: Double
    let time: Double
    let velocity: Double

    init(from start: Double, to target: Double, velocity: Double, curve: SpringCurve, at time: Double) {
        self.target = target
        self.curve = curve
        self.start = start
        self.time = time
        self.velocity = velocity
    }

    func value(at now: Double) -> Double {
        target + curve.state(displacement: start - target, velocity: velocity, at: now - time).displacement
    }

    func velocity(at now: Double) -> Double {
        curve.state(displacement: start - target, velocity: velocity, at: now - time).velocity
    }

    /// Within `tolerance` of its target, and moving less than that in a
    /// frame at 120 Hz.
    func isSettled(at now: Double, tolerance: Double) -> Bool {
        let state = curve.state(displacement: start - target, velocity: velocity, at: now - time)
        return abs(state.displacement) <= tolerance && abs(state.velocity) / 120 <= tolerance
    }
}
