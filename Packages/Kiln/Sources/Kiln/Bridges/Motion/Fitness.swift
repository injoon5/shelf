//
//  Fitness.swift
//  Bridges: Core Motion's Motion & Fitness half (PLAN.md §4.5)
//
//  `CMPedometer`, `CMAltimeter`, `CMMotionActivityManager` and
//  `CMHeadphoneMotionManager`: what iOS asks permission for. Each goes
//  through the run's capability gate (`.motion`) first, so an app the host
//  hasn't allowed gets what the device gives an app that isn't: a handler
//  with `CMErrorMotionActivityNotAuthorized` (105), `authorizationStatus()`
//  of `.denied`, and no updates.
//
//  Handlers run on the main actor (the device calls the pedometer's on a
//  queue of its own; apps wrap it in `DispatchQueue.main.async`, which works
//  too). Everything stops with the app's screen.
//

import Foundation
#if canImport(CoreMotion)
import CoreMotion
#endif

// MARK: - Values

@MainActor
final class KPedometerData {
    let start: Date, end: Date
    let steps: Int
    let distance: Double?
    let floorsUp: Int?, floorsDown: Int?
    let pace: Double?, cadence: Double?, averagePace: Double?

    init(start: Date, end: Date, steps: Int, distance: Double?, floorsUp: Int?, floorsDown: Int?,
         pace: Double?, cadence: Double?, averagePace: Double?) {
        self.start = start
        self.end = end
        self.steps = steps
        self.distance = distance
        self.floorsUp = floorsUp
        self.floorsDown = floorsDown
        self.pace = pace
        self.cadence = cadence
        self.averagePace = averagePace
    }

    var kv: KV { .native(.object("CMPedometerData", KRef(self))) }

    /// What the fake counts between two dates.
    static func fake(_ f: KilnFakeMotion, from: Date, to: Date, liveStart: Date?) -> KPedometerData {
        let steps = f.steps(from: from, to: to, liveStart: liveStart)
        let seconds = max(1, to.timeIntervalSince(from))
        let walking = f.stepsPerSecond > 0 && liveStart != nil
        return KPedometerData(start: from, end: to, steps: Int(steps), distance: steps * f.metersPerStep,
                              floorsUp: Int(seconds / 3600 * f.floorsAscendedPerHour), floorsDown: 0,
                              pace: walking ? 1 / (f.stepsPerSecond * f.metersPerStep) : nil,
                              cadence: walking ? f.stepsPerSecond : nil,
                              averagePace: steps > 0 ? seconds / (steps * f.metersPerStep) : nil)
    }

    #if os(iOS) || os(watchOS)
    static func device(_ d: CMPedometerData) -> KPedometerData {
        KPedometerData(start: d.startDate, end: d.endDate, steps: d.numberOfSteps.intValue, distance: d.distance?.doubleValue,
                       floorsUp: d.floorsAscended?.intValue, floorsDown: d.floorsDescended?.intValue,
                       pace: d.currentPace?.doubleValue, cadence: d.currentCadence?.doubleValue, averagePace: d.averageActivePace?.doubleValue)
    }
    #endif
}

@MainActor
final class KAltitudeData {
    /// "CMAltitudeData" or "CMAbsoluteAltitudeData".
    let type: String
    let relative: Double, pressure: Double
    let altitude: Double, accuracy: Double, precision: Double
    let timestamp: TimeInterval

    init(type: String, relative: Double = 0, pressure: Double = 0, altitude: Double = 0, accuracy: Double = 0, precision: Double = 0,
         timestamp: TimeInterval) {
        self.type = type
        self.relative = relative
        self.pressure = pressure
        self.altitude = altitude
        self.accuracy = accuracy
        self.precision = precision
        self.timestamp = timestamp
    }

    var kv: KV { .native(.object(type, KRef(self))) }
}

@MainActor
final class KMotionActivity {
    let kind: KilnFakeMotion.Activity
    let confidence: String
    let start: Date

    init(kind: KilnFakeMotion.Activity, confidence: String, start: Date) {
        self.kind = kind
        self.confidence = confidence
        self.start = start
    }

    var kv: KV { .native(.object("CMMotionActivity", KRef(self))) }

    #if os(iOS) || os(watchOS)
    static func device(_ a: CMMotionActivity) -> KMotionActivity {
        let kind: KilnFakeMotion.Activity = a.automotive ? .automotive : a.cycling ? .cycling : a.running ? .running
            : a.walking ? .walking : a.stationary ? .stationary : .unknown
        let confidence = a.confidence == .high ? "high" : a.confidence == .medium ? "medium" : "low"
        return KMotionActivity(kind: kind, confidence: confidence, start: a.startDate)
    }
    #endif
}

/// NSNumber, as Core Motion hands numbers over.
@MainActor private func number(_ d: Double?) -> KV { d.map { .native(.object("NSNumber", KRef(NSNumber(value: $0)))) } ?? .nilValue }
@MainActor private func number(_ i: Int?) -> KV { i.map { .native(.object("NSNumber", KRef(NSNumber(value: $0)))) } ?? .nilValue }

// MARK: - Bridges

extension MotionBridges {
    /// `authorizationStatus()` as the gate answers it; with no host gate, the device's.
    @MainActor static func authorization(_ c: KCall) -> KV {
        let caps = c.context.capabilities
        #if os(iOS) || os(watchOS)
        if caps.isUngated, fake(c) == nil {
            switch CMMotionActivityManager.authorizationStatus() {
            case .authorized: return .native(.implicit("authorized", []))
            case .denied: return .native(.implicit("denied", []))
            case .restricted: return .native(.implicit("restricted", []))
            default: return .native(.implicit("notDetermined", []))
            }
        }
        #endif
        switch caps.status(.motion) {
        case .allowed: return .native(.implicit("authorized", []))
        case .denied: return .native(.implicit("denied", []))
        case .notAsked: return .native(.implicit("notDetermined", []))
        }
    }

    /// Asks the gate for Motion & Fitness, then calls `then` if allowed, or
    /// `denied` with Core Motion's not-authorized error.
    @MainActor static func whenAllowed(_ c: KCall, denied: @escaping @MainActor (KV) -> Void, _ then: @escaping @MainActor () -> Void) {
        let headless = c.interp.headless
        c.context.capabilities.answer(.motion, headless: headless) { allowed in
            if allowed { then() } else { denied(KMotionErrors.error(KMotionErrors.notAuthorized)) }
        }
    }

    // MARK: CMPedometer

    static func pedometer(_ r: KRegistry) {
        r.type("CMPedometer", .motion, support: .full,
               notes: "Asks for Motion & Fitness first; a refused app's handler gets an error. The handler runs on the main actor.") { t in
            t.initializer("") { c in
                let p = KPedometer(fake: fake(c), interp: c.interp)
                c.context.onTearDown { [weak p] in p?.stopAll() }
                return .native(.object("CMPedometer", KRef(p)))
            }
            for name in ["isStepCountingAvailable", "isDistanceAvailable", "isFloorCountingAvailable", "isPaceAvailable",
                         "isCadenceAvailable", "isPedometerEventTrackingAvailable"] {
                t.staticMethod(name, "") { c in
                    if let f = fake(c) { return .bool(f.hasPedometer) }
                    #if os(iOS) || os(watchOS)
                    switch name {
                    case "isStepCountingAvailable": return .bool(CMPedometer.isStepCountingAvailable())
                    case "isDistanceAvailable": return .bool(CMPedometer.isDistanceAvailable())
                    case "isFloorCountingAvailable": return .bool(CMPedometer.isFloorCountingAvailable())
                    case "isPaceAvailable": return .bool(CMPedometer.isPaceAvailable())
                    case "isCadenceAvailable": return .bool(CMPedometer.isCadenceAvailable())
                    default: return .bool(CMPedometer.isPedometerEventTrackingAvailable())
                    }
                    #else
                    return .bool(false)
                    #endif
                }
            }
            t.staticMethod("authorizationStatus", "") { c in authorization(c) }
            @MainActor func me(_ c: KCall) throws -> KPedometer {
                guard let p = c.object(KPedometer.self) else { throw c.fail("needs a CMPedometer") }
                return p
            }
            t.method("queryPedometerData", "from:Date to:Date withHandler:closure") { c in
                guard let from = c.date("from"), let to = c.date("to") else { throw c.fail("needs two dates") }
                let p = try me(c), handler = c.function("withHandler")
                whenAllowed(c, denied: { p.call(handler, [.nilValue, $0]) }) { p.query(from: from, to: to, handler) }
                return .void
            }
            t.method("startUpdates", "from:Date withHandler:closure") { c in
                guard let from = c.date("from") else { throw c.fail("needs a date") }
                let p = try me(c), handler = c.function("withHandler")
                whenAllowed(c, denied: { p.call(handler, [.nilValue, $0]) }) { p.start(from: from, handler) }
                return .void
            }
            t.method("stopUpdates", "") { c in try me(c).stopUpdates(); return .void }
            t.method("startEventUpdates", "handler:closure") { c in
                let p = try me(c), handler = c.function("handler")
                whenAllowed(c, denied: { p.call(handler, [.nilValue, $0]) }) { p.startEvents(handler) }
                return .void
            }
            t.method("stopEventUpdates", "") { c in try me(c).stopEvents(); return .void }
        }
        r.type("CMPedometerData", .motion, support: .full) { t in
            @MainActor func d(_ c: KCall) -> KPedometerData? { c.object(KPedometerData.self) }
            t.property("startDate") { c in d(c).map { .native(.date($0.start)) } ?? .nilValue }
            t.property("endDate") { c in d(c).map { .native(.date($0.end)) } ?? .nilValue }
            t.property("numberOfSteps") { c in number(d(c)?.steps ?? 0) }
            t.property("distance") { c in number(d(c)?.distance) }
            t.property("floorsAscended") { c in number(d(c)?.floorsUp) }
            t.property("floorsDescended") { c in number(d(c)?.floorsDown) }
            t.property("currentPace") { c in number(d(c)?.pace) }
            t.property("currentCadence") { c in number(d(c)?.cadence) }
            t.property("averageActivePace") { c in number(d(c)?.averagePace) }
        }
        r.type("CMPedometerEvent", .motion, support: .full) { t in
            t.property("date") { c in
                guard case .tuple(let p, _) = c.receiver else { return .nilValue }
                return p[0]
            }
            t.property("type") { c in
                guard case .tuple(let p, _) = c.receiver else { return .nilValue }
                return p[1]
            }
        }
    }

    // MARK: CMAltimeter

    static func altimeter(_ r: KRegistry) {
        r.type("CMAltimeter", .motion, support: .full,
               notes: "Relative altitude and pressure (kPa), and absolute altitude; asks for Motion & Fitness first.") { t in
            t.initializer("") { c in
                let a = KAltimeter(fake: fake(c), interp: c.interp)
                c.context.onTearDown { [weak a] in a?.stopAll() }
                return .native(.object("CMAltimeter", KRef(a)))
            }
            t.staticMethod("isRelativeAltitudeAvailable", "") { c in
                if let f = fake(c) { return .bool(f.hasAltimeter) }
                #if os(iOS) || os(watchOS)
                return .bool(CMAltimeter.isRelativeAltitudeAvailable())
                #else
                return .bool(false)
                #endif
            }
            t.staticMethod("isAbsoluteAltitudeAvailable", "") { c in
                if let f = fake(c) { return .bool(f.hasAltimeter) }
                #if os(iOS) || os(watchOS)
                return .bool(CMAltimeter.isAbsoluteAltitudeAvailable())
                #else
                return .bool(false)
                #endif
            }
            t.staticMethod("authorizationStatus", "") { c in authorization(c) }
            @MainActor func me(_ c: KCall) throws -> KAltimeter {
                guard let a = c.object(KAltimeter.self) else { throw c.fail("needs a CMAltimeter") }
                return a
            }
            for absolute in [false, true] {
                let kind = absolute ? "Absolute" : "Relative"
                t.method("start\(kind)AltitudeUpdates", "to:any withHandler:closure") { c in
                    let a = try me(c), handler = c.function("withHandler")
                    whenAllowed(c, denied: { a.call(handler, [.nilValue, $0]) }) { a.start(absolute: absolute, handler) }
                    return .void
                }
                t.method("stop\(kind)AltitudeUpdates", "") { c in try me(c).stop(absolute: absolute); return .void }
            }
        }
        r.type("CMAltitudeData", .motion, support: .full) { t in
            t.property("relativeAltitude") { c in number(c.object(KAltitudeData.self)?.relative ?? 0) }
            t.property("pressure") { c in number(c.object(KAltitudeData.self)?.pressure ?? 0) }
            t.property("timestamp") { c in .double(c.object(KAltitudeData.self)?.timestamp ?? 0) }
        }
        r.type("CMAbsoluteAltitudeData", .motion, support: .full) { t in
            t.property("altitude") { c in .double(c.object(KAltitudeData.self)?.altitude ?? 0) }
            t.property("accuracy") { c in .double(c.object(KAltitudeData.self)?.accuracy ?? 0) }
            t.property("precision") { c in .double(c.object(KAltitudeData.self)?.precision ?? 0) }
            t.property("timestamp") { c in .double(c.object(KAltitudeData.self)?.timestamp ?? 0) }
        }
    }

    // MARK: CMMotionActivityManager

    static func activity(_ r: KRegistry) {
        r.type("CMMotionActivityManager", .motion, support: .full,
               notes: "Walking, running, cycling, driving or still; asks for Motion & Fitness first.") { t in
            t.initializer("") { c in
                let a = KActivityManager(fake: fake(c), interp: c.interp)
                c.context.onTearDown { [weak a] in a?.stop() }
                return .native(.object("CMMotionActivityManager", KRef(a)))
            }
            t.staticMethod("isActivityAvailable", "") { c in
                if let f = fake(c) { return .bool(f.hasActivity) }
                #if os(iOS) || os(watchOS)
                return .bool(CMMotionActivityManager.isActivityAvailable())
                #else
                return .bool(false)
                #endif
            }
            t.staticMethod("authorizationStatus", "") { c in authorization(c) }
            @MainActor func me(_ c: KCall) throws -> KActivityManager {
                guard let a = c.object(KActivityManager.self) else { throw c.fail("needs a CMMotionActivityManager") }
                return a
            }
            t.method("startActivityUpdates", "to:any withHandler:closure") { c in
                let a = try me(c), handler = c.function("withHandler")
                // The device gives a refused app no updates: its handler has no error.
                whenAllowed(c, denied: { _ in }) { a.start(handler) }
                return .void
            }
            t.method("stopActivityUpdates", "") { c in try me(c).stop(); return .void }
            t.method("queryActivityStarting", "from:Date to:Date to:any withHandler:closure") { c in
                // Two parameters are labeled `to`: the second date, then the queue.
                let dates = c.args.compactMap { v -> Date? in if case .native(.date(let d)) = v { return d }; return nil }
                guard dates.count >= 2 else { throw c.fail("needs two dates") }
                let from = dates[0], to = dates[1]
                let a = try me(c), handler = c.function("withHandler")
                whenAllowed(c, denied: { a.call(handler, [.nilValue, $0]) }) { a.query(from: from, to: to, handler) }
                return .void
            }
        }
        r.type("CMMotionActivity", .motion, support: .full) { t in
            @MainActor func a(_ c: KCall) -> KMotionActivity? { c.object(KMotionActivity.self) }
            for kind in KilnFakeMotion.Activity.allCases {
                t.property(kind.rawValue) { c in .bool(a(c)?.kind == kind) }
            }
            t.property("confidence") { c in .native(.implicit(a(c)?.confidence ?? "low", [])) }
            t.property("startDate") { c in a(c).map { .native(.date($0.start)) } ?? .nilValue }
            t.property("timestamp") { c in .double(MotionBridges.uptime) }
        }
    }

    // MARK: CMHeadphoneMotionManager

    static func headphones(_ r: KRegistry) {
        r.delegateProtocol("CMHeadphoneMotionManagerDelegate", .motion,
                           requirements: ["headphoneMotionManagerDidConnect(_:)?", "headphoneMotionManagerDidDisconnect(_:)?"])
        r.type("CMHeadphoneMotionManager", .motion, support: .full,
               notes: "AirPods' head motion as `CMDeviceMotion`; asks for Motion & Fitness first.") { t in
            t.initializer("") { c in
                let h = KHeadphones(fake: fake(c), interp: c.interp)
                c.context.onTearDown { [weak h] in h?.stopAll() }
                return .native(.object("CMHeadphoneMotionManager", KRef(h)))
            }
            t.staticMethod("authorizationStatus", "") { c in authorization(c) }
            @MainActor func me(_ c: KCall) throws -> KHeadphones {
                guard let h = c.object(KHeadphones.self) else { throw c.fail("needs a CMHeadphoneMotionManager") }
                return h
            }
            t.property("delegate", { c in try me(c).delegate ?? .nilValue }, set: { c in
                let v = c.args.first ?? .nilValue
                if !v.isNil, !KDelegates.adopts(v, "CMHeadphoneMotionManagerDelegate", c.interp) {
                    throw c.fail("the delegate should be a class that adopts CMHeadphoneMotionManagerDelegate")
                }
                try me(c).delegate = v.isNil ? nil : v
            })
            t.property("isDeviceMotionAvailable") { c in .bool(try me(c).available) }
            t.property("isDeviceMotionActive") { c in .bool(try me(c).motionActive) }
            t.property("isConnectionStatusActive") { c in .bool(try me(c).statusActive) }
            t.property("deviceMotion") { c in try me(c).read() }
            t.method("startDeviceMotionUpdates", "") { c in
                let h = try me(c)
                whenAllowed(c, denied: { _ in }) { h.startMotion(nil) }
                return .void
            }
            t.method("startDeviceMotionUpdates", "to:any withHandler:closure") { c in
                let h = try me(c), handler = c.function("withHandler")
                whenAllowed(c, denied: { h.call(handler, [.nilValue, $0]) }) { h.startMotion(handler) }
                return .void
            }
            t.method("stopDeviceMotionUpdates", "") { c in try me(c).stopMotion(); return .void }
            t.method("startConnectionStatusUpdates", "") { c in
                let h = try me(c)
                whenAllowed(c, denied: { _ in }) { h.startStatus() }
                return .void
            }
            t.method("stopConnectionStatusUpdates", "") { c in try me(c).stopStatus(); return .void }
        }
    }
}

// MARK: - Natives

/// Something that runs a handler from the device, or from a fake on a timer.
@MainActor
class KMotionFeed {
    let fake: KilnFakeMotion?
    weak var interp: KInterpreter?
    var timers: [String: Timer] = [:]

    init(fake: KilnFakeMotion?, interp: KInterpreter) {
        self.fake = fake
        self.interp = interp
    }

    var headless: Bool { interp?.headless ?? true }

    func call(_ handler: KFunction?, _ args: [KV]) {
        guard let handler, let interp else { return }
        interp.perform(handler, args)
    }

    /// Runs `tick` now if it's a check, else every `seconds` (and once soon).
    func every(_ key: String, _ seconds: TimeInterval, _ tick: @escaping @MainActor () -> Void) {
        timers[key]?.invalidate()
        if headless { tick(); return }
        timers[key] = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        DispatchQueue.main.async { MainActor.assumeIsolated { if self.timers[key] != nil { tick() } } }
    }

    /// Runs `body` on the next turn of the run loop (now, in a check), as the
    /// device answers a query later.
    func soon(_ body: @escaping @MainActor () -> Void) {
        if headless { body(); return }
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }

    func cancel(_ key: String) {
        timers[key]?.invalidate()
        timers[key] = nil
    }

    func cancelAll() {
        for t in timers.values { t.invalidate() }
        timers = [:]
    }

    /// A device callback, on any queue, hops to the main actor.
    nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread { MainActor.assumeIsolated(body) } else { DispatchQueue.main.async { MainActor.assumeIsolated(body) } }
    }
}

@MainActor
final class KPedometer: KMotionFeed {
    #if os(iOS) || os(watchOS)
    private lazy var device = CMPedometer()
    #endif
    private var liveHandler: KFunction?

    func query(from: Date, to: Date, _ handler: KFunction?) {
        if let fake {
            guard fake.hasPedometer else { return soon { self.call(handler, [.nilValue, KMotionErrors.error(KMotionErrors.notAvailable)]) } }
            let data = KPedometerData.fake(fake, from: from, to: min(to, Date()), liveStart: nil)
            return soon { self.call(handler, [data.kv, .nilValue]) }
        }
        #if os(iOS) || os(watchOS)
        device.queryPedometerData(from: from, to: to) { [weak self] data, error in
            let box = KUnsafeSendable((data, error))
            KMotionFeed.onMain { self?.deliver(box.value.0, box.value.1, handler) }
        }
        #endif
    }

    func start(from: Date, _ handler: KFunction?) {
        stopUpdates()
        liveHandler = handler
        if let fake {
            guard fake.hasPedometer else { return soon { self.call(handler, [.nilValue, KMotionErrors.error(KMotionErrors.notAvailable)]) } }
            let live = Date()
            every("updates", 1) { [weak self] in
                guard let self, self.liveHandler != nil else { return }
                self.call(handler, [KPedometerData.fake(fake, from: from, to: Date(), liveStart: live).kv, .nilValue])
            }
            return
        }
        #if os(iOS) || os(watchOS)
        device.startUpdates(from: from) { [weak self] data, error in
            let box = KUnsafeSendable((data, error))
            KMotionFeed.onMain { guard self?.liveHandler != nil else { return }; self?.deliver(box.value.0, box.value.1, handler) }
        }
        #endif
    }

    #if os(iOS) || os(watchOS)
    private func deliver(_ data: CMPedometerData?, _ error: Error?, _ handler: KFunction?) {
        call(handler, [data.map { KPedometerData.device($0).kv } ?? .nilValue,
                       error.map { .native(.object("Error", KRef($0 as NSError))) } ?? .nilValue])
    }
    #endif

    func stopUpdates() {
        liveHandler = nil
        cancel("updates")
        #if os(iOS) || os(watchOS)
        if fake == nil { device.stopUpdates() }
        #endif
    }

    private var eventsOn = false

    func startEvents(_ handler: KFunction?) {
        eventsOn = true
        if fake != nil {
            soon { [weak self] in
                guard self?.eventsOn == true else { return }
                self?.call(handler, [.tuple([.native(.date(Date())), .native(.implicit("resume", []))], ["date", "type"]), .nilValue])
            }
            return
        }
        #if os(iOS)
        device.startEventUpdates { [weak self] event, error in
            let box = KUnsafeSendable((event, error))
            KMotionFeed.onMain {
                guard let self, self.eventsOn else { return }
                let (event, error) = box.value
                let value: KV = event.map { .tuple([.native(.date($0.date)), .native(.implicit($0.type == .pause ? "pause" : "resume", []))],
                                                  ["date", "type"]) } ?? .nilValue
                self.call(handler, [value, error.map { .native(.object("Error", KRef($0 as NSError))) } ?? .nilValue])
            }
        }
        #endif
    }

    func stopEvents() {
        eventsOn = false
        #if os(iOS)
        if fake == nil { device.stopEventUpdates() }
        #endif
    }

    func stopAll() {
        stopUpdates()
        stopEvents()
        cancelAll()
    }
}

@MainActor
final class KAltimeter: KMotionFeed {
    #if os(iOS) || os(watchOS)
    private lazy var device = CMAltimeter()
    #endif
    private var on: Set<Bool> = []

    func start(absolute: Bool, _ handler: KFunction?) {
        stop(absolute: absolute)
        on.insert(absolute)
        let key = absolute ? "absolute" : "relative"
        if let fake {
            guard fake.hasAltimeter else { return }
            let start = Date()
            every(key, 1) { [weak self] in
                guard let self, self.on.contains(absolute) else { return }
                let t = Date().timeIntervalSince(start)
                let climb = fake.climbPerSecond * t
                let data = absolute
                    ? KAltitudeData(type: "CMAbsoluteAltitudeData", altitude: fake.altitude + climb, accuracy: 5, precision: 0.1,
                                    timestamp: MotionBridges.uptime)
                    : KAltitudeData(type: "CMAltitudeData", relative: climb, pressure: fake.pressure - 0.012 * climb,
                                    timestamp: MotionBridges.uptime)
                self.call(handler, [data.kv, .nilValue])
            }
            return
        }
        #if os(iOS) || os(watchOS)
        if absolute {
            device.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, error in
                let box = KUnsafeSendable((data, error))
                KMotionFeed.onMain {
                    guard let self, self.on.contains(true) else { return }
                    let v: KV = box.value.0.map { KAltitudeData(type: "CMAbsoluteAltitudeData", altitude: $0.altitude, accuracy: $0.accuracy,
                                                                precision: $0.precision, timestamp: $0.timestamp).kv } ?? .nilValue
                    self.call(handler, [v, box.value.1.map { .native(.object("Error", KRef($0 as NSError))) } ?? .nilValue])
                }
            }
        } else {
            device.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                let box = KUnsafeSendable((data, error))
                KMotionFeed.onMain {
                    guard let self, self.on.contains(false) else { return }
                    let v: KV = box.value.0.map { KAltitudeData(type: "CMAltitudeData", relative: $0.relativeAltitude.doubleValue,
                                                                pressure: $0.pressure.doubleValue, timestamp: $0.timestamp).kv } ?? .nilValue
                    self.call(handler, [v, box.value.1.map { .native(.object("Error", KRef($0 as NSError))) } ?? .nilValue])
                }
            }
        }
        #endif
    }

    func stop(absolute: Bool) {
        on.remove(absolute)
        cancel(absolute ? "absolute" : "relative")
        #if os(iOS) || os(watchOS)
        if fake == nil {
            if absolute { device.stopAbsoluteAltitudeUpdates() } else { device.stopRelativeAltitudeUpdates() }
        }
        #endif
    }

    func stopAll() {
        stop(absolute: true)
        stop(absolute: false)
    }
}

@MainActor
final class KActivityManager: KMotionFeed {
    #if os(iOS) || os(watchOS)
    private lazy var device = CMMotionActivityManager()
    #endif
    private var on = false

    func start(_ handler: KFunction?) {
        on = true
        if let fake {
            guard fake.hasActivity else { return }
            // The coprocessor reports a change, not a stream: once now, again if the fake's activity changes.
            var last: KilnFakeMotion.Activity?
            every("activity", 1) { [weak self] in
                guard let self, self.on, fake.activity != last else { return }
                last = fake.activity
                self.call(handler, [KMotionActivity(kind: fake.activity, confidence: "high", start: Date()).kv])
            }
            return
        }
        #if os(iOS) || os(watchOS)
        device.startActivityUpdates(to: .main) { [weak self] activity in
            let box = KUnsafeSendable(activity)
            KMotionFeed.onMain {
                guard let self, self.on else { return }
                self.call(handler, [box.value.map { KMotionActivity.device($0).kv } ?? .nilValue])
            }
        }
        #endif
    }

    func stop() {
        on = false
        cancelAll()
        #if os(iOS) || os(watchOS)
        if fake == nil { device.stopActivityUpdates() }
        #endif
    }

    func query(from: Date, to: Date, _ handler: KFunction?) {
        if let fake {
            guard fake.hasActivity else { return soon { self.call(handler, [.nilValue, KMotionErrors.error(KMotionErrors.notAvailable)]) } }
            // The past: still, then whatever the fake is doing for the last stretch.
            let mid = Date(timeInterval: max(0, to.timeIntervalSince(from)) * 0.75, since: from)
            let list: [KV] = [KMotionActivity(kind: .stationary, confidence: "high", start: from).kv,
                              KMotionActivity(kind: fake.activity, confidence: "high", start: mid).kv]
            return soon { self.call(handler, [.array(list), .nilValue]) }
        }
        #if os(iOS) || os(watchOS)
        device.queryActivityStarting(from: from, to: to, to: .main) { [weak self] list, error in
            let box = KUnsafeSendable((list, error))
            KMotionFeed.onMain {
                let value: KV = box.value.0.map { .array($0.map { KMotionActivity.device($0).kv }) } ?? .nilValue
                self?.call(handler, [value, box.value.1.map { .native(.object("Error", KRef($0 as NSError))) } ?? .nilValue])
            }
        }
        #endif
    }
}

@MainActor
final class KHeadphones: KMotionFeed {
    var delegate: KV?
    private(set) var motionActive = false
    private(set) var statusActive = false
    private var started: TimeInterval = 0
    private var connected = false
    #if os(iOS) || os(watchOS) || os(macOS)
    private var deviceManager: AnyObject?
    #endif

    var available: Bool {
        if let fake { return fake.headphonesConnected }
        #if os(iOS) || os(watchOS) || os(macOS)
        if #available(macOS 14.0, *) { return headphoneDevice.isDeviceMotionAvailable }
        #endif
        return false
    }

    var selfKV: KV { .native(.object("CMHeadphoneMotionManager", KRef(self))) }

    /// The fake's headphones connect when something first listens.
    private func connectFake() {
        guard let fake, fake.headphonesConnected, !connected else { return }
        connected = true
        soon { [weak self] in
            guard let self, let interp = self.interp else { return }
            KDelegates.send("headphoneMotionManagerDidConnect(_:)", to: self.delegate, [self.selfKV], interp)
        }
    }

    func startMotion(_ handler: KFunction?) {
        stopMotion()
        motionActive = true
        started = MotionBridges.uptime
        if let fake {
            connectFake()
            guard fake.headphonesConnected, let handler else { return }
            // Headphones report about 25 times a second.
            every("motion", 1.0 / 25) { [weak self] in
                guard let self, self.motionActive else { return }
                self.call(handler, [self.fakeSample(fake).kv, .nilValue])
            }
            return
        }
        #if os(iOS) || os(watchOS) || os(macOS)
        if #available(macOS 14.0, *) {
            let manager = headphoneDevice
            guard let handler else { manager.startDeviceMotionUpdates(); return }
            manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
                let box = KUnsafeSendable((motion, error))
                KMotionFeed.onMain {
                    guard let self, self.motionActive else { return }
                    #if os(iOS) || os(watchOS)
                    let v: KV = box.value.0.map { KDeviceMotion.device($0).kv } ?? .nilValue
                    #else
                    let v: KV = .nilValue
                    #endif
                    self.call(handler, [v, box.value.1.map { .native(.object("Error", KRef($0 as NSError))) } ?? .nilValue])
                }
            }
        }
        #endif
    }

    private func fakeSample(_ fake: KilnFakeMotion) -> KDeviceMotion {
        let now = MotionBridges.uptime
        return KDeviceMotion.fake(fake.headReading(now - started), frame: "xArbitraryZVertical", at: now, sensorLocation: "headphoneLeft")
    }

    func read() -> KV {
        guard motionActive else { return .nilValue }
        if let fake { return fake.headphonesConnected ? fakeSample(fake).kv : .nilValue }
        #if os(iOS) || os(watchOS)
        return headphoneDevice.deviceMotion.map { KDeviceMotion.device($0).kv } ?? .nilValue
        #else
        return .nilValue
        #endif
    }

    func stopMotion() {
        motionActive = false
        cancel("motion")
        #if os(iOS) || os(watchOS) || os(macOS)
        if fake == nil, #available(macOS 14.0, *), deviceManager != nil { headphoneDevice.stopDeviceMotionUpdates() }
        #endif
    }

    func startStatus() {
        statusActive = true
        if fake != nil { connectFake(); return }
        #if os(iOS) || os(watchOS) || os(macOS)
        if #available(iOS 17.0, macOS 14.0, *) { headphoneDevice.startConnectionStatusUpdates() }
        #endif
    }

    func stopStatus() {
        statusActive = false
        #if os(iOS) || os(watchOS) || os(macOS)
        if fake == nil, #available(iOS 17.0, macOS 14.0, *), deviceManager != nil { headphoneDevice.stopConnectionStatusUpdates() }
        #endif
    }

    func stopAll() {
        stopMotion()
        stopStatus()
        cancelAll()
        delegate = nil
    }

    #if os(iOS) || os(watchOS) || os(macOS)
    /// The device's manager, made when first used, with Kiln as its delegate.
    @available(macOS 14.0, *)
    private var headphoneDevice: CMHeadphoneMotionManager {
        if let m = deviceManager as? CMHeadphoneMotionManager { return m }
        let m = CMHeadphoneMotionManager()
        let forward = KHeadphoneDelegate(self)
        m.delegate = forward
        KDelegates.retain(forward, by: m)
        deviceManager = m
        return m
    }

    fileprivate func deviceConnected(_ yes: Bool) {
        guard let interp else { return }
        KDelegates.send(yes ? "headphoneMotionManagerDidConnect(_:)" : "headphoneMotionManagerDidDisconnect(_:)",
                        to: delegate, [selfKV], interp)
    }
    #endif
}

#if os(iOS) || os(watchOS) || os(macOS)
/// The device's headphone manager's delegate: tells the app's.
@available(macOS 14.0, *)
private final class KHeadphoneDelegate: NSObject, CMHeadphoneMotionManagerDelegate {
    weak var owner: KHeadphones?
    init(_ owner: KHeadphones) { self.owner = owner }
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        KMotionFeed.onMain { [weak self] in self?.owner?.deviceConnected(true) }
    }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        KMotionFeed.onMain { [weak self] in self?.owner?.deviceConnected(false) }
    }
}
#endif
