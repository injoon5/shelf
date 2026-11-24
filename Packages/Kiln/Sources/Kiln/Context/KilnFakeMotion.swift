//
//  KilnFakeMotion.swift
//  Kiln's run context: a motion source the host provides (PLAN.md §4.5)
//
//  The simulator has no motion sensors, and a check (`Kiln.validate`) must
//  never touch one. So Core Motion's bridges ask the run's context first:
//
//      context.provide(KilnFakeMotion.walking())      // the host, or a test
//
//  and read the fake instead of the device. Without one, a stub context
//  (a check) gets `KilnFakeMotion.still()`, and a real run reads the device.
//
//  A fake answers everything Core Motion would: the device's attitude as a
//  function of time (from which gravity, the accelerometer, the gyro and
//  the magnetometer follow), the pedometer, the altimeter, the motion
//  activity, and a pair of headphones.
//

import Foundation

@MainActor
public final class KilnFakeMotion {
    /// The device at one moment.
    public struct Reading: Sendable, Equatable {
        /// Radians, as `CMAttitude` reports them.
        public var roll: Double
        public var pitch: Double
        public var yaw: Double
        /// Radians per second around the device's x, y and z axes.
        public var rotationRate: SIMD3<Double>
        /// In g, gravity removed.
        public var userAcceleration: SIMD3<Double>
        /// Microtesla.
        public var magneticField: SIMD3<Double>

        public init(roll: Double = 0, pitch: Double = 0, yaw: Double = 0, rotationRate: SIMD3<Double> = .zero,
                    userAcceleration: SIMD3<Double> = .zero, magneticField: SIMD3<Double> = SIMD3(0, 22, -40)) {
            self.roll = roll
            self.pitch = pitch
            self.yaw = yaw
            self.rotationRate = rotationRate
            self.userAcceleration = userAcceleration
            self.magneticField = magneticField
        }
    }

    /// What the motion coprocessor thinks the person is doing.
    public enum Activity: String, Sendable, CaseIterable {
        case stationary, walking, running, cycling, automotive, unknown
    }

    /// The device's motion, by seconds since its updates started.
    public var reading: @MainActor (TimeInterval) -> Reading
    /// Whether the device has an accelerometer, a gyro, a magnetometer and
    /// device motion. False is the simulator's real answer.
    public var hasSensors = true

    /// Steps per second while live updates run.
    public var stepsPerSecond: Double
    /// What a pedometer query over the past finds, per hour.
    public var stepsPerHourBefore: Double
    public var metersPerStep: Double = 0.75
    public var floorsAscendedPerHour: Double = 0
    public var hasPedometer = true

    public var activity: Activity
    public var hasActivity = true

    /// Barometric pressure, kilopascals.
    public var pressure: Double = 101.3
    /// Above sea level, meters.
    public var altitude: Double = 32
    /// Meters per second, up: how relative altitude changes.
    public var climbPerSecond: Double = 0
    public var hasAltimeter = true

    /// AirPods (or other headphones that report motion) are connected.
    public var headphonesConnected = false
    /// The head's motion, by seconds since its updates started.
    public var headReading: @MainActor (TimeInterval) -> Reading

    public init(reading: @escaping @MainActor (TimeInterval) -> Reading = { _ in Reading() },
                stepsPerSecond: Double = 0, stepsPerHourBefore: Double = 0, activity: Activity = .stationary,
                headphonesConnected: Bool = false,
                headReading: @escaping @MainActor (TimeInterval) -> Reading = { _ in Reading() }) {
        self.reading = reading
        self.stepsPerSecond = stepsPerSecond
        self.stepsPerHourBefore = stepsPerHourBefore
        self.activity = activity
        self.headphonesConnected = headphonesConnected
        self.headReading = headReading
    }

    /// Flat on a table, face up, not moving: what a check gets.
    public static func still() -> KilnFakeMotion { KilnFakeMotion() }

    /// Held in a hand and rocked gently, as someone walks: tilts both ways,
    /// turns slowly, steps at a walking pace, climbs a little, and has
    /// headphones in that nod. What Shelf gives apps on the simulator.
    public static func walking() -> KilnFakeMotion {
        let fake = KilnFakeMotion(reading: { t in rocking(t, roll: 0.35, pitch: 0.25, turn: 0.15) },
                                  stepsPerSecond: 1.8, stepsPerHourBefore: 450, activity: .walking,
                                  headphonesConnected: true,
                                  headReading: { t in rocking(t, roll: 0.1, pitch: 0.3, turn: 0.4) })
        fake.floorsAscendedPerHour = 3
        fake.climbPerSecond = 0.05
        return fake
    }

    /// One reading, as `walking()` rocks: sines, and their derivatives as
    /// the rotation rate, so the gyro agrees with the attitude.
    public static func rocking(_ t: TimeInterval, roll: Double, pitch: Double, turn: Double) -> Reading {
        let wr = 1.3, wp = 0.9, wy = 0.4
        let r = roll * sin(wr * t)
        let p = pitch * sin(wp * t + 0.7)
        let y = turn * sin(wy * t)
        // Euler rates as body rates, near enough for small angles.
        let dr = roll * wr * cos(wr * t), dp = pitch * wp * cos(wp * t + 0.7), dy = turn * wy * cos(wy * t)
        let step = 0.06 * sin(2 * .pi * 1.8 * t)
        return Reading(roll: r, pitch: p, yaw: y, rotationRate: SIMD3(dp, dr, dy),
                       userAcceleration: SIMD3(0.01 * sin(3.1 * t), step, 0.02 * cos(2 * .pi * 1.8 * t)),
                       magneticField: SIMD3(22 * cos(y), 22 * sin(y), -40))
    }

    /// Steps between two dates, seen from `now` with live updates that
    /// began at `liveStart`: the past at `stepsPerHourBefore`, the live part
    /// at `stepsPerSecond`.
    func steps(from: Date, to: Date, liveStart: Date?) -> Double {
        guard to > from else { return 0 }
        let split = max(from, min(to, liveStart ?? to))
        let before = split.timeIntervalSince(from) / 3600 * stepsPerHourBefore
        let live = liveStart == nil ? 0 : to.timeIntervalSince(split) * stepsPerSecond
        return before + live
    }
}
