//
//  LocationManager.swift
//  Bridges: `CLLocationManager` and its delegate (PLAN.md §1.5, §4.6)
//
//      final class Locator: NSObject, CLLocationManagerDelegate {
//          let manager = CLLocationManager()
//          override init() { super.init(); manager.delegate = self }
//          func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
//              if manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
//          }
//          func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { … }
//          func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { … }
//      }
//
//  The app's manager is Kiln's (`KLocationManager`), which answers
//  authorization from the capability gate, not from the device: the device's
//  answer is the host's, and the app gets the host's answer for the app.
//  Locations come from the device's own `CLLocationManager` (whose delegate
//  is Kiln's) or from the run's fake, and reach the app's delegate through
//  `KDelegates.send`, as the forwarding proxy would deliver them.
//
//  - `requestWhenInUseAuthorization()` asks the gate; `requestAlwaysAuthorization()`
//    asks for the same, since a Shelf app runs only while it's open.
//  - `startUpdatingLocation()` and `requestLocation()` ask too if nobody
//    has; a refused app's delegate gets `didFailWithError` with `CLError.denied`.
//  - Background updates and monitoring are errors that say why.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

extension LocationBridges {
    static func manager(_ r: KRegistry) {
        r.delegateProtocol("CLLocationManagerDelegate", .location,
                           requirements: ["locationManager(_:didUpdateLocations:)?", "locationManager(_:didFailWithError:)?",
                                          "locationManagerDidChangeAuthorization(_:)?", "locationManager(_:didChangeAuthorization:)?",
                                          "locationManager(_:didUpdateHeading:)?", "locationManagerShouldDisplayHeadingCalibration(_:)?"],
                           notes: "`manager.delegate = self` from an `NSObject` subclass; called on the main actor.")
        symbols(r, "CLAuthorizationStatus", ["notDetermined", "restricted", "denied", "authorizedAlways", "authorizedWhenInUse", "authorized"])
        symbols(r, "CLAccuracyAuthorization", ["fullAccuracy", "reducedAccuracy"])
        symbols(r, "CLActivityType", ["other", "automotiveNavigation", "fitness", "otherNavigation", "airborne"])
        symbols(r, "CLDeviceOrientation", ["unknown", "portrait", "portraitUpsideDown", "landscapeLeft", "landscapeRight", "faceUp", "faceDown"])

        r.type("CLLocationManager", .location, support: .full,
               notes: "While the app is open: authorization (asks first), `startUpdatingLocation`, `requestLocation`, heading. No background updates or monitoring.") { t in
            t.initializer("") { c in
                let m = KLocationManager(c.interp)
                c.context.onTearDown { [weak m] in m?.stopAll() }
                return m.kv
            }
            @MainActor func me(_ c: KCall) throws -> KLocationManager {
                guard let m = c.object(KLocationManager.self) else { throw c.fail("needs a CLLocationManager") }
                return m
            }
            t.staticMethod("locationServicesEnabled", "") { c in .bool(KLocationManager.servicesEnabled(c.interp)) }
            t.staticMethod("headingAvailable", "") { c in .bool(KLocationManager.headingAvailable(c.interp)) }
            t.staticMethod("authorizationStatus", "") { c in .native(.implicit(KLocationManager.authorization(c.interp, device: nil), [])) }
            t.staticMethod("significantLocationChangeMonitoringAvailable", "") { _ in .bool(false) }
            t.staticMethod("isMonitoringAvailable", "for:any") { _ in .bool(false) }
            t.staticMethod("isRangingAvailable", "") { _ in .bool(false) }

            t.property("delegate", { c in try me(c).delegate ?? .nilValue }, set: { c in
                let v = c.args.first ?? .nilValue
                if !v.isNil, !KDelegates.adopts(v, "CLLocationManagerDelegate", c.interp) {
                    throw c.fail("the delegate should be a class that adopts CLLocationManagerDelegate")
                }
                try me(c).setDelegate(v.isNil ? nil : v)
            })
            t.property("authorizationStatus") { c in .native(.implicit(try me(c).authorization, [])) }
            t.property("accuracyAuthorization") { c in .native(.implicit(try me(c).accuracy, [])) }
            t.property("location") { c in try me(c).lastLocation }
            t.property("heading") { c in try me(c).lastHeading?.kv ?? .nilValue }
            t.property("desiredAccuracy", { c in .double(try me(c).desiredAccuracy) }, set: { c in
                try me(c).desiredAccuracy = c.args.first?.asDouble ?? -1
            })
            t.property("distanceFilter", { c in .double(try me(c).distanceFilter) }, set: { c in
                try me(c).distanceFilter = c.args.first?.asDouble ?? -1
            })
            t.property("headingFilter", { c in .double(try me(c).headingFilter) }, set: { c in
                try me(c).headingFilter = c.args.first?.asDouble ?? 1
            })
            t.property("activityType", { c in .native(.implicit(try me(c).activityType, [])) }, set: { c in
                try me(c).activityType = c.symbol(0) ?? "other"
            })
            t.property("headingOrientation", { c in .native(.implicit(try me(c).headingOrientation, [])) }, set: { c in
                try me(c).headingOrientation = c.symbol(0) ?? "portrait"
            })
            t.property("pausesLocationUpdatesAutomatically", { c in .bool(try me(c).pauses) }, set: { c in
                try me(c).pauses = c.interp.truthy(c.args.first ?? .bool(true))
            })
            t.property("showsBackgroundLocationIndicator", { _ in .bool(false) }, set: { _ in })
            t.property("allowsBackgroundLocationUpdates", { _ in .bool(false) }, set: { c in
                if c.interp.truthy(c.args.first ?? .bool(false)) {
                    throw c.fail("background location isn't available: a Shelf app runs only while it's open")
                }
            })
            t.method("requestWhenInUseAuthorization", "") { c in try me(c).requestAuthorization(); return .void }
            t.method("requestAlwaysAuthorization", "") { c in try me(c).requestAuthorization(); return .void }
            t.method("requestTemporaryFullAccuracyAuthorization", "withPurposeKey:string completion:closure?") { c in
                // Shelf has no purpose strings to show: the accuracy the person chose for Shelf stands.
                let m = try me(c), done = c.function("completion")
                m.soon { m.interp?.perform(done, [m.accuracy == "fullAccuracy" ? .nilValue : KLocationErrors.error("denied")]) }
                return .void
            }
            t.method("startUpdatingLocation", "") { c in try me(c).startUpdating(); return .void }
            t.method("stopUpdatingLocation", "") { c in try me(c).stopUpdating(); return .void }
            t.method("requestLocation", "") { c in try me(c).requestLocation(); return .void }
            t.method("startUpdatingHeading", "") { c in try me(c).startHeading(); return .void }
            t.method("stopUpdatingHeading", "") { c in try me(c).stopHeading(); return .void }
            t.method("dismissHeadingCalibrationDisplay", "") { _ in .void }
            for name in ["startMonitoringSignificantLocationChanges", "startMonitoringVisits", "allowDeferredLocationUpdates"] {
                t.method(name, nil) { c in
                    throw c.fail("background location and monitoring aren't available: a Shelf app runs only while it's open")
                }
            }
            t.method("startMonitoring", "for:any") { c in
                throw c.fail("region monitoring isn't available: a Shelf app runs only while it's open")
            }
            for name in ["stopMonitoringSignificantLocationChanges", "stopMonitoringVisits"] { t.method(name, "") { _ in .void } }
        }
        #if canImport(CoreLocation)
        r.nativeClass(CLLocationManager.self, "CLLocationManager")
        #if !os(tvOS)
        r.nativeClass(CLHeading.self, "CLHeading")
        #endif
        #endif
    }

    /// An enum-like type whose cases are symbols.
    static func symbols(_ r: KRegistry, _ name: String, _ cases: [String]) {
        r.type(name, .location, support: .full) { t in
            t.staticProperties(Dictionary(uniqueKeysWithValues: cases.map { ($0, KV.native(.implicit($0, []))) }))
        }
    }
}

/// The app's `CLLocationManager`.
@MainActor
final class KLocationManager: NSObject {
    weak var interp: KInterpreter?
    let fake: KilnFakeLocation?
    private(set) var delegate: KV?
    var desiredAccuracy = -1.0
    var distanceFilter = -1.0
    var headingFilter = 1.0
    var activityType = "other"
    var headingOrientation = "portrait"
    var pauses = true
    private var updating = false
    private var wantsOne = false
    private var headingOn = false
    private var started: Date?
    private var headingStarted: Date?
    private var lastDelivered: (lat: Double, lon: Double)?
    private var lastFixLocation: KV = .nilValue
    private(set) var lastHeading: KHeading?
    private var timers: [String: Timer] = [:]
    /// The device's answer, last heard (an ungated run reports it).
    private var deviceStatus: String?
    #if canImport(CoreLocation)
    private var device: CLLocationManager?
    #endif

    init(_ interp: KInterpreter) {
        self.interp = interp
        self.fake = LocationBridges.fake(interp)
        super.init()
    }

    var kv: KV { .native(.object("CLLocationManager", KRef(self))) }
    private var headless: Bool { interp?.headless ?? true }

    func soon(_ body: @escaping @MainActor () -> Void) {
        if headless { body(); return }
        DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
    }

    private func send(_ requirement: String, _ args: [KV]) {
        guard let interp else { return }
        KDelegates.send(requirement, to: delegate, [kv] + args, interp)
    }

    // MARK: Authorization

    static func servicesEnabled(_ interp: KInterpreter) -> Bool {
        if let fake = LocationBridges.fake(interp) { return fake.servicesEnabled }
        #if canImport(CoreLocation)
        return CLLocationManager.locationServicesEnabled()
        #else
        return false
        #endif
    }

    static func headingAvailable(_ interp: KInterpreter) -> Bool {
        if let fake = LocationBridges.fake(interp) { return fake.hasHeading }
        #if os(iOS) || os(watchOS)
        return CLLocationManager.headingAvailable()
        #else
        return false
        #endif
    }

    /// `CLAuthorizationStatus`'s case: the gate's answer for the app; with no
    /// host gate and the device, the device's.
    static func authorization(_ interp: KInterpreter, device: String?) -> String {
        let caps = interp.context.capabilities
        let fake = LocationBridges.fake(interp)
        if let fake, !fake.servicesEnabled { return "denied" }
        #if canImport(CoreLocation)
        if caps.isUngated, fake == nil {
            if let device { return device }
            return name(CLLocationManager().authorizationStatus)
        }
        #endif
        switch caps.status(.location) {
        case .allowed: return "authorizedWhenInUse"
        case .denied: return "denied"
        case .notAsked: return "notDetermined"
        }
    }

    var authorization: String {
        guard let interp else { return "notDetermined" }
        return Self.authorization(interp, device: deviceStatus)
    }

    var isAuthorized: Bool { authorization.hasPrefix("authorized") }

    var accuracy: String {
        if let fake { return fake.approximate ? "reducedAccuracy" : "fullAccuracy" }
        #if canImport(CoreLocation)
        if let device { return device.accuracyAuthorization == .reducedAccuracy ? "reducedAccuracy" : "fullAccuracy" }
        #endif
        return "fullAccuracy"
    }

    #if canImport(CoreLocation)
    static func name(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .authorizedWhenInUse: return "authorizedWhenInUse"
        case .authorizedAlways: return "authorizedAlways"
        case .denied: return "denied"
        case .restricted: return "restricted"
        default: return "notDetermined"
        }
    }
    #endif

    /// Tells the delegate what authorization is now, both ways iOS does.
    private func authorizationChanged() {
        send("locationManagerDidChangeAuthorization(_:)", [])
        send("locationManager(_:didChangeAuthorization:)", [.native(.implicit(authorization, []))])
    }

    func setDelegate(_ v: KV?) {
        delegate = v
        // iOS tells a new delegate where authorization stands.
        if v != nil { soon { [weak self] in self?.authorizationChanged() } }
    }

    /// Asks the gate (or, with no host gate, the device), then tells the delegate.
    func requestAuthorization() {
        guard let interp else { return }
        if authorization != "notDetermined" { return }
        #if canImport(CoreLocation)
        if interp.context.capabilities.isUngated, fake == nil {
            deviceManager().requestWhenInUseAuthorization()
            return
        }
        #endif
        interp.context.capabilities.answer(.location, headless: headless) { [weak self] _ in self?.authorizationChanged() }
    }

    /// Calls `then` once the app may read the location; a refused app's
    /// delegate hears `CLError.denied`.
    private func whenAllowed(_ then: @escaping @MainActor () -> Void) {
        guard let interp else { return }
        if let fake, !fake.servicesEnabled { fail("denied"); return }
        #if canImport(CoreLocation)
        if interp.context.capabilities.isUngated, fake == nil {
            // The device asks, and fails the request itself if refused.
            then()
            return
        }
        #endif
        let wasAsked = authorization != "notDetermined"
        interp.context.capabilities.answer(.location, headless: headless) { [weak self] allowed in
            guard let self else { return }
            if !wasAsked { self.authorizationChanged() }
            if allowed { then() } else { self.fail("denied") }
        }
    }

    private func fail(_ code: String) {
        soon { [weak self] in self?.send("locationManager(_:didFailWithError:)", [KLocationErrors.error(code)]) }
    }

    // MARK: Locations

    var lastLocation: KV {
        guard isAuthorized else { return .nilValue }
        if case .nilValue = lastFixLocation, let fake {
            return KLocationManager.location(fake, at: 0)
        }
        return lastFixLocation
    }

    static func location(_ fake: KilnFakeLocation, at t: TimeInterval) -> KV {
        #if canImport(CoreLocation)
        let f = fake.seen(t)
        return LocationBridges.location(CLLocation(coordinate: CLLocationCoordinate2D(latitude: f.latitude, longitude: f.longitude),
                                                   altitude: f.altitude, horizontalAccuracy: f.horizontalAccuracy,
                                                   verticalAccuracy: f.verticalAccuracy, course: f.course, speed: f.speed, timestamp: Date()))
        #else
        return .nilValue
        #endif
    }

    func startUpdating() {
        updating = true
        if started == nil { started = Date() }
        whenAllowed { [weak self] in
            guard let self, self.updating else { return }
            if let fake = self.fake {
                self.deliverFake(fake)
                if !self.headless {
                    self.timers["location"]?.invalidate()
                    self.timers["location"] = Timer.scheduledTimer(withTimeInterval: fake.interval, repeats: true) { [weak self] _ in
                        MainActor.assumeIsolated { if let self, self.updating { self.deliverFake(fake) } }
                    }
                }
                return
            }
            #if canImport(CoreLocation)
            let d = self.deviceManager()
            d.desiredAccuracy = self.desiredAccuracy
            d.distanceFilter = self.distanceFilter
            d.startUpdatingLocation()
            #endif
        }
    }

    func stopUpdating() {
        updating = false
        timers["location"]?.invalidate()
        timers["location"] = nil
        #if canImport(CoreLocation)
        if !wantsOne { device?.stopUpdatingLocation() }
        #endif
    }

    func requestLocation() {
        wantsOne = true
        whenAllowed { [weak self] in
            guard let self, self.wantsOne else { return }
            if let fake = self.fake {
                self.soon { [weak self] in
                    guard let self, self.wantsOne else { return }
                    self.wantsOne = false
                    self.deliverFake(fake, force: true)
                }
                return
            }
            #if canImport(CoreLocation)
            let d = self.deviceManager()
            d.desiredAccuracy = self.desiredAccuracy
            d.requestLocation()
            #endif
        }
    }

    private func deliverFake(_ fake: KilnFakeLocation, force: Bool = false) {
        let t = Date().timeIntervalSince(started ?? Date())
        let f = fake.seen(t)
        if !force, distanceFilter > 0, let last = lastDelivered {
            let dLat = (f.latitude - last.lat) * 111_320, dLon = (f.longitude - last.lon) * 111_320 * cos(f.latitude * .pi / 180)
            if (dLat * dLat + dLon * dLon).squareRoot() < distanceFilter { return }
        }
        lastDelivered = (f.latitude, f.longitude)
        let location = Self.location(fake, at: t)
        lastFixLocation = location
        send("locationManager(_:didUpdateLocations:)", [.array([location])])
    }

    // MARK: Heading

    func startHeading() {
        headingOn = true
        headingStarted = Date()
        if let fake {
            guard fake.hasHeading else { return }
            deliverHeading(fake)
            if !headless {
                timers["heading"]?.invalidate()
                timers["heading"] = Timer.scheduledTimer(withTimeInterval: 1.0 / 10, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { if let self, self.headingOn { self.deliverHeading(fake) } }
                }
            }
            return
        }
        #if os(iOS) || os(watchOS)
        let d = deviceManager()
        d.headingFilter = headingFilter
        d.startUpdatingHeading()
        #endif
    }

    func stopHeading() {
        headingOn = false
        timers["heading"]?.invalidate()
        timers["heading"] = nil
        #if os(iOS) || os(watchOS)
        device?.stopUpdatingHeading()
        #endif
    }

    private func deliverHeading(_ fake: KilnFakeLocation) {
        let t = Date().timeIntervalSince(headingStarted ?? Date())
        var magnetic = fake.heading(t).truncatingRemainder(dividingBy: 360)
        if magnetic < 0 { magnetic += 360 }
        if headingFilter > 0, let last = lastHeading, abs(last.magnetic - magnetic) < headingFilter, !headless { return }
        var trueHeading = -1.0
        if isAuthorized {
            trueHeading = (magnetic + fake.declination).truncatingRemainder(dividingBy: 360)
        }
        let rad = magnetic * .pi / 180
        let h = KHeading(magnetic: magnetic, trueHeading: trueHeading, accuracy: 5, x: 22 * cos(rad), y: -22 * sin(rad), z: -40,
                         timestamp: Date())
        lastHeading = h
        send("locationManager(_:didUpdateHeading:)", [h.kv])
    }

    func stopAll() {
        updating = false
        wantsOne = false
        headingOn = false
        for t in timers.values { t.invalidate() }
        timers = [:]
        #if canImport(CoreLocation)
        device?.stopUpdatingLocation()
        #if os(iOS) || os(watchOS)
        device?.stopUpdatingHeading()
        #endif
        device?.delegate = nil
        device = nil
        #endif
        delegate = nil
    }

    // MARK: The device

    #if canImport(CoreLocation)
    private func deviceManager() -> CLLocationManager {
        if let device { return device }
        let d = CLLocationManager()
        d.delegate = self
        device = d
        return d
    }
    #endif
}

#if canImport(CoreLocation)
extension KLocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let box = KUnsafeSendable(locations)
        KMotionFeed.onMain { [weak self] in
            guard let self, self.updating || self.wantsOne, let last = box.value.last else { return }
            self.wantsOne = false
            if !self.updating { self.device?.stopUpdatingLocation() }
            self.lastFixLocation = LocationBridges.location(last)
            self.send("locationManager(_:didUpdateLocations:)", [.array(box.value.map { LocationBridges.location($0) })])
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let box = KUnsafeSendable(error)
        KMotionFeed.onMain { [weak self] in
            guard let self, self.updating || self.wantsOne else { return }
            self.wantsOne = false
            self.send("locationManager(_:didFailWithError:)", [KLocationErrors.wrap(box.value)])
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        KMotionFeed.onMain { [weak self] in
            // Only a run with no host gate hears the device's answer; a gated
            // one hears the gate's, when the gate answers.
            guard let self, let interp = self.interp, interp.context.capabilities.isUngated, self.fake == nil else { return }
            let name = KLocationManager.name(status)
            guard name != self.deviceStatus else { return }
            self.deviceStatus = name
            self.authorizationChanged()
        }
    }

    #if os(iOS) || os(watchOS)
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let box = KUnsafeSendable(newHeading)
        KMotionFeed.onMain { [weak self] in
            guard let self, self.headingOn else { return }
            let h = KHeading.device(box.value)
            self.lastHeading = h
            self.send("locationManager(_:didUpdateHeading:)", [h.kv])
        }
    }

    nonisolated func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        KDelegates.onMain { [weak self] in
            guard let self, let interp = self.interp else { return false }
            return KDelegates.send("locationManagerShouldDisplayHeadingCalibration(_:)", to: self.delegate, [self.kv], interp)
                .map { interp.truthy($0) } ?? false
        }
    }
    #endif
}
#endif
