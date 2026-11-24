//
//  Motion.swift
//  Bridges: Core Motion (PLAN.md §4.5)
//
//  `CMMotionManager` in both forms models write:
//
//      let motion = CMMotionManager()
//      motion.deviceMotionUpdateInterval = 1 / 60
//      motion.startDeviceMotionUpdates(to: .main) { data, error in
//          guard let data else { return }
//          tilt = data.attitude.roll
//      }
//
//  and reading `motion.deviceMotion` (or `accelerometerData`…) from a
//  `Timer` or a `TimelineView` after `startDeviceMotionUpdates()`.
//
//  - Handlers run on the main actor, whatever queue the app names.
//  - Every update interval is clamped at 1/60 s or slower, so the app's code
//    keeps up; reading the interval gives the clamped value.
//  - The raw sensors need no permission (iOS asks for none). The pedometer,
//    the activity manager, the altimeter and headphone motion go through
//    the capability gate (`Fitness.swift`).
//  - Everything stops when the app's screen closes (`onTearDown`).
//  - The device's sensors, or the run's fake (`KilnFakeMotion`): a host or a
//    test provides one; a check reads `KilnFakeMotion.still()`.
//

import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif

@objc(KilnBridges_Motion)
final class MotionBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        values(r)
        motionManager(r)
        pedometer(r)
        altimeter(r)
        activity(r)
        headphones(r)
    }

    /// The fake this run reads, or nil for the device. A check without one
    /// gets a still device, the same one for the whole run.
    @MainActor static func fake(_ c: KCall) -> KilnFakeMotion? {
        if let f = c.context.provided(KilnFakeMotion.self) { return f }
        guard c.interp.headless || c.context.isStub else { return nil }
        let still = KilnFakeMotion.still()
        c.context.provide(still)
        return still
    }

    /// Seconds since boot: Core Motion's timestamps.
    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }

    /// Updates come at most this often.
    static let fastestInterval = 1.0 / 60

    // MARK: CMMotionManager

    static func motionManager(_ r: KRegistry) {
        r.type("CMMotionManager", .motion, support: .full,
               notes: "Handlers run on the main actor; update intervals are 1/60 s at the fastest. No permission needed.") { t in
            t.initializer("") { c in
                let m = KMotionManager(fake: fake(c), interp: c.interp)
                c.context.onTearDown { [weak m] in m?.stopAll() }
                return .native(.object("CMMotionManager", KRef(m)))
            }
            @MainActor func me(_ c: KCall) throws -> KMotionManager {
                guard let m = c.object(KMotionManager.self) else { throw c.fail("needs a CMMotionManager") }
                return m
            }
            t.staticMethod("availableAttitudeReferenceFrames", "") { c in
                let frames: [String]
                if fake(c) != nil {
                    frames = ["xArbitraryZVertical", "xArbitraryCorrectedZVertical", "xMagneticNorthZVertical", "xTrueNorthZVertical"]
                } else {
                    #if os(iOS) || os(watchOS) || os(visionOS)
                    let raw = CMMotionManager.availableAttitudeReferenceFrames()
                    frames = [("xArbitraryZVertical", CMAttitudeReferenceFrame.xArbitraryZVertical),
                              ("xArbitraryCorrectedZVertical", .xArbitraryCorrectedZVertical),
                              ("xMagneticNorthZVertical", .xMagneticNorthZVertical),
                              ("xTrueNorthZVertical", .xTrueNorthZVertical)].filter { raw.contains($0.1) }.map(\.0)
                    #else
                    frames = []
                    #endif
                }
                return .array(frames.map { KNativeEnum.value("CMAttitudeReferenceFrame", $0) })
            }

            for sensor in KMotionManager.Sensor.allCases {
                let name = sensor.name
                t.property("\(sensor.rawValue)UpdateInterval", { c in .double(try me(c).interval(sensor)) }, set: { c in
                    guard let s = c.args.first?.asDouble else { throw c.fail("the interval is a number of seconds") }
                    try me(c).setInterval(sensor, s)
                })
                t.property("is\(name)Available") { c in .bool(try me(c).available(sensor)) }
                t.property("is\(name)Active") { c in .bool(try me(c).active.contains(sensor)) }
                t.property(sensor.dataProperty) { c in try me(c).read(sensor) }
                t.method("start\(name)Updates", "") { c in try me(c).start(sensor, handler: nil, frame: nil); return .void }
                t.method("start\(name)Updates", "to:any withHandler:closure") { c in
                    try me(c).start(sensor, handler: c.function("withHandler"), frame: nil); return .void
                }
                if sensor == .deviceMotion {
                    t.method("startDeviceMotionUpdates", "using:CMAttitudeReferenceFrame") { c in
                        try me(c).start(sensor, handler: nil, frame: KNativeEnum.name(c["using"])); return .void
                    }
                    t.method("startDeviceMotionUpdates", "using:CMAttitudeReferenceFrame to:any withHandler:closure") { c in
                        try me(c).start(sensor, handler: c.function("withHandler"), frame: KNativeEnum.name(c["using"])); return .void
                    }
                }
                t.method("stop\(name)Updates", "") { c in try me(c).stop(sensor); return .void }
            }
            t.property("attitudeReferenceFrame") { c in KNativeEnum.value("CMAttitudeReferenceFrame", try me(c).frame) }
            t.property("showsDeviceMovementDisplay", { c in .bool(try me(c).showsDeviceMovementDisplay) }, set: { c in
                try me(c).showsDeviceMovementDisplay = c.interp.truthy(c.args.first ?? .bool(false))
            })
        }
    }
}

/// One `CMMotionManager`: the device's, or the run's fake played on a timer.
@MainActor
final class KMotionManager {
    enum Sensor: String, CaseIterable {
        case accelerometer, gyro, magnetometer, deviceMotion

        /// `Accelerometer`, as in `startAccelerometerUpdates`.
        var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
        /// `accelerometerData`, `deviceMotion`.
        var dataProperty: String { self == .deviceMotion ? "deviceMotion" : rawValue + "Data" }
    }

    let fake: KilnFakeMotion?
    weak var interp: KInterpreter?
    private(set) var active: Set<Sensor> = []
    private var intervals: [Sensor: Double] = [:]
    private var timers: [Sensor: Timer] = [:]
    private var started: [Sensor: TimeInterval] = [:]
    private(set) var frame = "xArbitraryZVertical"
    var showsDeviceMovementDisplay = false
    #if os(iOS) || os(watchOS) || os(visionOS)
    private lazy var device: CMMotionManager = CMMotionManager()
    #endif

    init(fake: KilnFakeMotion?, interp: KInterpreter) {
        self.fake = fake
        self.interp = interp
    }

    func interval(_ s: Sensor) -> Double { intervals[s] ?? MotionBridges.fastestInterval }

    func setInterval(_ s: Sensor, _ seconds: Double) {
        let clamped = max(seconds, MotionBridges.fastestInterval)
        intervals[s] = clamped
        #if os(iOS) || os(watchOS) || os(visionOS)
        if fake == nil { apply(s, clamped) }
        #endif
        // A fake's timer follows a changed interval.
        if let handler = handlers[s], timers[s] != nil { schedule(s, handler) }
    }

    func available(_ s: Sensor) -> Bool {
        if let fake { return fake.hasSensors }
        #if os(iOS) || os(watchOS) || os(visionOS)
        switch s {
        case .accelerometer: return device.isAccelerometerAvailable
        case .gyro: return device.isGyroAvailable
        case .magnetometer: return device.isMagnetometerAvailable
        case .deviceMotion: return device.isDeviceMotionAvailable
        }
        #else
        return false
        #endif
    }

    private var handlers: [Sensor: KFunction] = [:]

    func start(_ s: Sensor, handler: KFunction?, frame: String?) {
        if let frame, s == .deviceMotion { self.frame = frame }
        stop(s)
        active.insert(s)
        started[s] = MotionBridges.uptime
        if let fake {
            guard fake.hasSensors else { return }
            guard let handler else { return }
            handlers[s] = handler
            if interp?.headless ?? true {
                // A check: one reading, now.
                deliver(s, handler)
            } else {
                schedule(s, handler)
            }
            return
        }
        #if os(iOS) || os(watchOS) || os(visionOS)
        startDevice(s, handler)
        #endif
    }

    func stop(_ s: Sensor) {
        timers[s]?.invalidate()
        timers[s] = nil
        handlers[s] = nil
        active.remove(s)
        #if os(iOS) || os(watchOS) || os(visionOS)
        if fake == nil {
            switch s {
            case .accelerometer: device.stopAccelerometerUpdates()
            case .gyro: device.stopGyroUpdates()
            case .magnetometer: device.stopMagnetometerUpdates()
            case .deviceMotion: device.stopDeviceMotionUpdates()
            }
        }
        #endif
    }

    func stopAll() {
        for s in Sensor.allCases where active.contains(s) || timers[s] != nil { stop(s) }
    }

    /// What `motion.deviceMotion` (or `accelerometerData`…) reads: nil until
    /// its updates have started.
    func read(_ s: Sensor) -> KV {
        guard active.contains(s) else { return .nilValue }
        if let fake { return fake.hasSensors ? sample(s, fake) : .nilValue }
        #if os(iOS) || os(watchOS) || os(visionOS)
        switch s {
        case .accelerometer: return device.accelerometerData.map(Self.convert) ?? .nilValue
        case .gyro: return device.gyroData.map(Self.convert) ?? .nilValue
        case .magnetometer: return device.magnetometerData.map(Self.convert) ?? .nilValue
        case .deviceMotion: return device.deviceMotion.map { KDeviceMotion.device($0).kv } ?? .nilValue
        }
        #else
        return .nilValue
        #endif
    }

    // MARK: The fake

    private func schedule(_ s: Sensor, _ handler: KFunction) {
        timers[s]?.invalidate()
        let box = KUnsafeSendable(handler)
        timers[s] = Timer.scheduledTimer(withTimeInterval: interval(s), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.deliver(s, box.value) }
        }
    }

    private func deliver(_ s: Sensor, _ handler: KFunction) {
        guard let fake, let interp else { return }
        interp.perform(handler, [sample(s, fake), .nilValue])
    }

    private func sample(_ s: Sensor, _ fake: KilnFakeMotion) -> KV {
        let now = MotionBridges.uptime
        let r = fake.reading(now - (started[s] ?? now))
        switch s {
        case .accelerometer:
            let g = KRotationMatrix.euler(roll: r.roll, pitch: r.pitch, yaw: r.yaw).gravity + r.userAcceleration
            return KSensorData(type: "CMAccelerometerData", vector: KMotionVector("CMAcceleration", g), timestamp: now).kv
        case .gyro:
            return KSensorData(type: "CMGyroData", vector: KMotionVector("CMRotationRate", r.rotationRate), timestamp: now).kv
        case .magnetometer:
            return KSensorData(type: "CMMagnetometerData", vector: KMotionVector("CMMagneticField", r.magneticField), timestamp: now).kv
        case .deviceMotion:
            return KDeviceMotion.fake(r, frame: frame, at: now).kv
        }
    }

    // MARK: The device

    #if os(iOS) || os(watchOS) || os(visionOS)
    private func apply(_ s: Sensor, _ seconds: Double) {
        switch s {
        case .accelerometer: device.accelerometerUpdateInterval = seconds
        case .gyro: device.gyroUpdateInterval = seconds
        case .magnetometer: device.magnetometerUpdateInterval = seconds
        case .deviceMotion: device.deviceMotionUpdateInterval = seconds
        }
    }

    private func startDevice(_ s: Sensor, _ handler: KFunction?) {
        apply(s, interval(s))
        let frames: [String: CMAttitudeReferenceFrame] = ["xArbitraryZVertical": .xArbitraryZVertical,
                                                          "xArbitraryCorrectedZVertical": .xArbitraryCorrectedZVertical,
                                                          "xMagneticNorthZVertical": .xMagneticNorthZVertical,
                                                          "xTrueNorthZVertical": .xTrueNorthZVertical]
        guard let handler else {
            switch s {
            case .accelerometer: device.startAccelerometerUpdates()
            case .gyro: device.startGyroUpdates()
            case .magnetometer: device.startMagnetometerUpdates()
            case .deviceMotion: device.startDeviceMotionUpdates(using: frames[frame] ?? .xArbitraryZVertical)
            }
            return
        }
        handlers[s] = handler
        let send: @Sendable (KUnsafeSendable<KV>, Error?) -> Void = { [weak self] value, error in
            let message = error.map { ($0 as NSError).localizedDescription }
            MainActor.assumeIsolated {
                guard let self, let interp = self.interp, self.handlers[s] != nil else { return }
                interp.perform(handler, [value.value, message.map { KBuiltins.errorValue($0) } ?? .nilValue])
            }
        }
        switch s {
        case .accelerometer:
            device.startAccelerometerUpdates(to: .main) { data, error in
                MainActor.assumeIsolated { send(KUnsafeSendable(data.map(Self.convert) ?? .nilValue), error) }
            }
        case .gyro:
            device.startGyroUpdates(to: .main) { data, error in
                MainActor.assumeIsolated { send(KUnsafeSendable(data.map(Self.convert) ?? .nilValue), error) }
            }
        case .magnetometer:
            device.startMagnetometerUpdates(to: .main) { data, error in
                MainActor.assumeIsolated { send(KUnsafeSendable(data.map(Self.convert) ?? .nilValue), error) }
            }
        case .deviceMotion:
            device.startDeviceMotionUpdates(using: frames[frame] ?? .xArbitraryZVertical, to: .main) { data, error in
                MainActor.assumeIsolated { send(KUnsafeSendable(data.map { KDeviceMotion.device($0).kv } ?? .nilValue), error) }
            }
        }
    }

    static func convert(_ d: CMAccelerometerData) -> KV {
        KSensorData(type: "CMAccelerometerData", vector: KMotionVector("CMAcceleration", d.acceleration.x, d.acceleration.y, d.acceleration.z),
                    timestamp: d.timestamp).kv
    }

    static func convert(_ d: CMGyroData) -> KV {
        KSensorData(type: "CMGyroData", vector: KMotionVector("CMRotationRate", d.rotationRate.x, d.rotationRate.y, d.rotationRate.z),
                    timestamp: d.timestamp).kv
    }

    static func convert(_ d: CMMagnetometerData) -> KV {
        KSensorData(type: "CMMagnetometerData", vector: KMotionVector("CMMagneticField", d.magneticField.x, d.magneticField.y, d.magneticField.z),
                    timestamp: d.timestamp).kv
    }
    #endif
}
