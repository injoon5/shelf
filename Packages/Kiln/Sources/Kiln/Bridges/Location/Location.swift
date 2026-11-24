//
//  Location.swift
//  Bridges: Core Location (PLAN.md §4.6)
//
//  The forms models write, while the app is open:
//
//  - `for try await update in CLLocationUpdate.liveUpdates()`, with
//    `CLServiceSession(authorization: .whenInUse)` (LiveUpdates.swift);
//  - `CLLocationManager` with a delegate, `requestWhenInUseAuthorization()`,
//    `startUpdatingLocation()`, `requestLocation()` and heading
//    (LocationManager.swift);
//  - `CLLocation` (distance, course, altitude), `CLLocationCoordinate2D` and
//    `CLHeading` (here);
//  - geocoding with MapKit's `MKReverseGeocodingRequest` and
//    `MKGeocodingRequest`, and `CLGeocoder` for older code (Geocoding.swift);
//  - `LocationButton` (LiveUpdates.swift).
//
//  Every way of reading where the device is goes through the run's
//  capability gate (`.location`) first, so an app the host hasn't allowed
//  gets what Core Location gives an app that isn't: `.denied`, a delegate's
//  `didFailWithError` with `CLError.denied`, an update whose
//  `authorizationDenied` is true. The system's approximate location is
//  passed through as it is (`accuracyAuthorization`, `accuracyLimited`).
//
//  Not here (PLAN.md's won't-do): background location, region and visit
//  monitoring, `CLMonitor`, `CLBackgroundActivitySession`. A Shelf app runs
//  only while it's open, and everything stops with its screen.
//
//  The device, or the run's fake (`KilnFakeLocation`): a host or a test
//  provides one; a check reads `KilnFakeLocation.applePark()`.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

@objc(KilnBridges_Location)
final class LocationBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        values(r)
        manager(r)
        liveUpdates(r)
        geocoding(r)
        button(r)
    }

    /// `Error.code` reads Core Location's and MapKit's codes as their enums
    /// (`error.code == .denied`); Foundation's `Error` registers after this family.
    override class func extend(into r: KRegistry) {
        r.extend("Error") { t in
            t.property("code") { c in KLocationErrors.code(c.receiver) }
            t.property("errorCode") { c in .int(c.object(NSError.self)?.code ?? 0) }
            t.property("domain") { c in .string(c.object(NSError.self)?.domain ?? "") }
        }
    }

    /// The fake this run reads, or nil for the device. A check without one
    /// gets Apple Park, the same one for the whole run.
    @MainActor static func fake(_ c: KCall) -> KilnFakeLocation? { fake(c.interp) }

    @MainActor static func fake(_ interp: KInterpreter) -> KilnFakeLocation? {
        if let f = interp.context.provided(KilnFakeLocation.self) { return f }
        guard interp.headless || interp.context.isStub else { return nil }
        let park = KilnFakeLocation.applePark()
        interp.context.provide(park)
        return park
    }

    // MARK: Values

    static func values(_ r: KRegistry) {
        for alias in ["CLLocationDegrees", "CLLocationDistance", "CLLocationSpeed", "CLLocationDirection", "CLLocationAccuracy",
                      "CLLocationSpeedAccuracy", "CLLocationDirectionAccuracy", "CLHeadingComponentValue"] {
            r.alias(alias, to: "Double")
        }
        let constants: [String: Double] = [
            "kCLLocationAccuracyBestForNavigation": -2, "kCLLocationAccuracyBest": -1, "kCLLocationAccuracyNearestTenMeters": 10,
            "kCLLocationAccuracyHundredMeters": 100, "kCLLocationAccuracyKilometer": 1000, "kCLLocationAccuracyThreeKilometers": 3000,
            "kCLLocationAccuracyReduced": 6_380_000, "kCLDistanceFilterNone": -1, "kCLHeadingFilterNone": -1,
            "CLLocationDistanceMax": Double.greatestFiniteMagnitude, "CLTimeIntervalMax": Double.greatestFiniteMagnitude,
        ]
        for (name, value) in constants { r.addConstant(name) { _ in .double(value) } }
        r.addConstant("kCLLocationCoordinate2DInvalid") { _ in KCoordinate(latitude: -180, longitude: -180).kv }

        r.type("CLLocationCoordinate2D", .location, support: .full,
               notes: "`latitude` and `longitude` in degrees; not `Equatable`, as in Swift.") { t in
            t.initializer("latitude:number longitude:number") { c in
                KCoordinate(latitude: c.double("latitude") ?? 0, longitude: c.double("longitude") ?? 0).kv
            }
            t.initializer("") { _ in KCoordinate(latitude: 0, longitude: 0).kv }
            for field in ["latitude", "longitude"] {
                t.property(field, { c in
                    guard let p = KCoordinate.of(c.receiver) else { return .double(0) }
                    return .double(field == "latitude" ? p.latitude : p.longitude)
                }, set: { c in
                    guard var p = KCoordinate.of(c.receiver), let v = c.args.first?.asDouble else { return }
                    if field == "latitude" { p.latitude = v } else { p.longitude = v }
                    c.mutated = p.kv
                })
            }
        }
        r.function("CLLocationCoordinate2DIsValid", .location, "_:CLLocationCoordinate2D", owner: "CoreLocation") { c in
            .bool(KCoordinate.of(c[0])?.isValid ?? false)
        }
        r.function("CLLocationCoordinate2DMake", .location, "_:number _:number", owner: "CoreLocation") { c in
            KCoordinate(latitude: c.double(0) ?? 0, longitude: c.double(1) ?? 0).kv
        }

        r.type("CLLocation", .location, support: .full,
               notes: "`coordinate`, `altitude`, `speed`, `course` (-1 when unknown), accuracies, `timestamp`, `distance(from:)`.") { t in
            #if canImport(CoreLocation)
            t.initializer("latitude:number longitude:number") { c in
                location(CLLocation(latitude: c.double("latitude") ?? 0, longitude: c.double("longitude") ?? 0))
            }
            t.initializer("coordinate:CLLocationCoordinate2D altitude:number horizontalAccuracy:number verticalAccuracy:number timestamp:Date") { c in
                location(CLLocation(coordinate: coordinate(c, "coordinate"), altitude: c.double("altitude") ?? 0,
                                    horizontalAccuracy: c.double("horizontalAccuracy") ?? 0, verticalAccuracy: c.double("verticalAccuracy") ?? 0,
                                    timestamp: c.date("timestamp") ?? Date()))
            }
            t.initializer("coordinate:CLLocationCoordinate2D altitude:number horizontalAccuracy:number verticalAccuracy:number course:number speed:number timestamp:Date") { c in
                location(CLLocation(coordinate: coordinate(c, "coordinate"), altitude: c.double("altitude") ?? 0,
                                    horizontalAccuracy: c.double("horizontalAccuracy") ?? 0, verticalAccuracy: c.double("verticalAccuracy") ?? 0,
                                    course: c.double("course") ?? -1, speed: c.double("speed") ?? -1, timestamp: c.date("timestamp") ?? Date()))
            }
            t.initializer("coordinate:CLLocationCoordinate2D altitude:number horizontalAccuracy:number verticalAccuracy:number course:number courseAccuracy:number speed:number speedAccuracy:number timestamp:Date") { c in
                location(CLLocation(coordinate: coordinate(c, "coordinate"), altitude: c.double("altitude") ?? 0,
                                    horizontalAccuracy: c.double("horizontalAccuracy") ?? 0, verticalAccuracy: c.double("verticalAccuracy") ?? 0,
                                    course: c.double("course") ?? -1, courseAccuracy: c.double("courseAccuracy") ?? -1,
                                    speed: c.double("speed") ?? -1, speedAccuracy: c.double("speedAccuracy") ?? -1,
                                    timestamp: c.date("timestamp") ?? Date()))
            }
            @MainActor func me(_ c: KCall) throws -> CLLocation {
                guard let l = c.object(CLLocation.self) else { throw c.fail("needs a CLLocation") }
                return l
            }
            t.property("coordinate") { c in KCoordinate(try me(c).coordinate).kv }
            t.property("altitude") { c in .double(try me(c).altitude) }
            t.property("ellipsoidalAltitude") { c in .double(try me(c).ellipsoidalAltitude) }
            t.property("horizontalAccuracy") { c in .double(try me(c).horizontalAccuracy) }
            t.property("verticalAccuracy") { c in .double(try me(c).verticalAccuracy) }
            t.property("course") { c in .double(try me(c).course) }
            t.property("courseAccuracy") { c in .double(try me(c).courseAccuracy) }
            t.property("speed") { c in .double(try me(c).speed) }
            t.property("speedAccuracy") { c in .double(try me(c).speedAccuracy) }
            t.property("timestamp") { c in .native(.date(try me(c).timestamp)) }
            t.property("floor") { c in try me(c).floor.map { .tuple([.int($0.level)], ["level"]) } ?? .nilValue }
            t.property("sourceInformation") { c in
                try me(c).sourceInformation.map { .tuple([.bool($0.isSimulatedBySoftware), .bool($0.isProducedByAccessory)],
                                                         ["isSimulatedBySoftware", "isProducedByAccessory"]) } ?? .nilValue
            }
            t.property("description") { c in .string(try me(c).description) }
            t.method("distance", "from:CLLocation") { c in
                guard let other = c.object(at: "from", CLLocation.self) else { throw c.fail("needs a CLLocation") }
                return .double(try me(c).distance(from: other))
            }
            #endif
        }
        r.type("CLFloor", .location, support: .full) { t in
            t.property("level") { c in
                guard case .tuple(let p, _) = c.receiver else { return .int(0) }
                return p[0]
            }
        }
        r.type("CLLocationSourceInformation", .location, support: .full) { t in
            for (i, name) in ["isSimulatedBySoftware", "isProducedByAccessory"].enumerated() {
                t.property(name) { c in
                    guard case .tuple(let p, _) = c.receiver else { return .bool(false) }
                    return p[i]
                }
            }
        }

        r.type("CLHeading", .location, support: .full,
               notes: "`magneticHeading`, `trueHeading` (-1 until location is allowed), `headingAccuracy`, and the raw `x`, `y`, `z`.") { t in
            @MainActor func h(_ c: KCall) -> KHeading? { c.object(KHeading.self) }
            t.property("magneticHeading") { c in .double(h(c)?.magnetic ?? 0) }
            t.property("trueHeading") { c in .double(h(c)?.trueHeading ?? -1) }
            t.property("headingAccuracy") { c in .double(h(c)?.accuracy ?? -1) }
            t.property("x") { c in .double(h(c)?.x ?? 0) }
            t.property("y") { c in .double(h(c)?.y ?? 0) }
            t.property("z") { c in .double(h(c)?.z ?? 0) }
            t.property("timestamp") { c in .native(.date(h(c)?.timestamp ?? Date())) }
        }

        r.type("CLError", .location, support: .full,
               notes: "`error as? CLError` then `.code`: `.denied`, `.locationUnknown`, `.network`, `.geocodeFoundNoResult`.") { t in
            t.property("code") { c in KLocationErrors.code(c.receiver) }
            t.property("errorCode") { c in .int(c.object(NSError.self)?.code ?? 0) }
            t.properties(["localizedDescription", "description"]) { c, _ in .string(c.object(NSError.self)?.localizedDescription ?? "") }
            for (name, _) in KLocationErrors.codes { t.staticProperty(name) { _ in .native(.implicit(name, [])) } }
            t.staticProperty("Code") { _ in .type(.builtin("CLError.Code")) }
        }
        r.type("CLError.Code", .location, support: .full) { t in
            t.staticProperties(Dictionary(uniqueKeysWithValues: KLocationErrors.codes.map { ($0.0, KV.native(.implicit($0.0, []))) }))
            t.property("rawValue") { c in
                if case .native(.implicit(let n, _)) = c.receiver { return .int(KLocationErrors.codes.first { $0.0 == n }?.1 ?? 0) }
                return .int(0)
            }
        }

        #if canImport(CoreLocation)
        r.nativeClass(CLLocation.self, "CLLocation")
        #endif
    }

    #if canImport(CoreLocation)
    @MainActor static func location(_ l: CLLocation) -> KV { .native(.object("CLLocation", KRef(l))) }

    @MainActor static func coordinate(_ c: KCall, _ label: String) -> CLLocationCoordinate2D {
        KCoordinate.of(c[.label(label)])?.cl ?? kCLLocationCoordinate2DInvalid
    }
    #endif
}

extension KCall {
    /// A native object argument of type `T`.
    func object<T>(at ref: KArgRef, _ type: T.Type) -> T? {
        if case .native(.object(_, let o))? = self[ref] { return o.value as? T }
        return nil
    }
}

/// `CLLocationCoordinate2D`: a value.
struct KCoordinate: Hashable, KDescribable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    var kv: KV { .native(.boxed(KBoxed("CLLocationCoordinate2D", self))) }

    var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }

    func describe(_ interp: KInterpreter) -> String { "CLLocationCoordinate2D(latitude: \(latitude), longitude: \(longitude))" }

    static func of(_ v: KV?) -> KCoordinate? {
        if case .native(.boxed(let b))? = v { return b.value as? KCoordinate }
        return nil
    }

    #if canImport(CoreLocation)
    init(_ c: CLLocationCoordinate2D) { self.init(latitude: c.latitude, longitude: c.longitude) }
    var cl: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    #endif
}

#if canImport(CoreLocation)
extension CLLocation: KDescribable {
    func describe(_ interp: KInterpreter) -> String { description }
}
#endif

/// `CLHeading`: the device's, or a fake's.
@MainActor
final class KHeading {
    let magnetic: Double, trueHeading: Double, accuracy: Double
    let x: Double, y: Double, z: Double
    let timestamp: Date

    init(magnetic: Double, trueHeading: Double, accuracy: Double, x: Double, y: Double, z: Double, timestamp: Date) {
        self.magnetic = magnetic
        self.trueHeading = trueHeading
        self.accuracy = accuracy
        self.x = x
        self.y = y
        self.z = z
        self.timestamp = timestamp
    }

    var kv: KV { .native(.object("CLHeading", KRef(self))) }

    #if os(iOS) || os(watchOS) || os(macOS)
    static func device(_ h: CLHeading) -> KHeading {
        KHeading(magnetic: h.magneticHeading, trueHeading: h.trueHeading, accuracy: h.headingAccuracy, x: h.x, y: h.y, z: h.z, timestamp: h.timestamp)
    }
    #endif
}

/// Core Location's and MapKit's errors, as the device gives them.
enum KLocationErrors {
    /// `CLError.Code`'s cases and raw values.
    static let codes: [(String, Int)] = [
        ("locationUnknown", 0), ("denied", 1), ("network", 2), ("headingFailure", 3), ("regionMonitoringDenied", 4),
        ("regionMonitoringFailure", 5), ("regionMonitoringSetupDelayed", 6), ("regionMonitoringResponseDelayed", 7),
        ("geocodeFoundNoResult", 8), ("geocodeFoundPartialResult", 9), ("geocodeCanceled", 10), ("deferredFailed", 11),
        ("deferredNotUpdatingLocation", 12), ("deferredAccuracyTooLow", 13), ("deferredDistanceFiltered", 14),
        ("deferredCanceled", 15), ("rangingUnavailable", 16), ("rangingFailure", 17), ("promptDeclined", 18),
        ("historicalLocationError", 19),
    ]
    /// `MKError.Code`'s.
    static let mapCodes: [(String, Int)] = [
        ("unknown", 1), ("serverFailure", 2), ("loadingThrottled", 3), ("placemarkNotFound", 4), ("directionsNotFound", 5),
        ("decodingFailed", 6),
    ]

    static let domain = "kCLErrorDomain"
    static let mapDomain = "MKErrorDomain"

    /// A `CLError`, with the message the device gives.
    @MainActor static func error(_ name: String) -> KV {
        let code = codes.first { $0.0 == name }?.1 ?? 0
        let message = "The operation couldn’t be completed. (kCLErrorDomain error \(code).)"
        return .native(.object("CLError", KRef(NSError(domain: domain, code: code, userInfo: [NSLocalizedDescriptionKey: message]))))
    }

    /// An `MKError`.
    @MainActor static func mapError(_ name: String) -> KV {
        let code = mapCodes.first { $0.0 == name }?.1 ?? 1
        let message = "The operation couldn’t be completed. (MKErrorDomain error \(code).)"
        return .native(.object("MKError", KRef(NSError(domain: mapDomain, code: code, userInfo: [NSLocalizedDescriptionKey: message]))))
    }

    /// A device error as the app sees it.
    @MainActor static func wrap(_ e: Error) -> KV {
        let ns = e as NSError
        let type = ns.domain == domain ? "CLError" : ns.domain == mapDomain ? "MKError" : "Error"
        return .native(.object(type, KRef(ns)))
    }

    /// `error.code`: Core Location's and MapKit's as their enum's cases, others as a number.
    @MainActor static func code(_ v: KV) -> KV {
        guard case .native(.object(_, let ref)) = v, let e = ref.value as? NSError else { return .int(0) }
        if e.domain == domain, let name = codes.first(where: { $0.1 == e.code })?.0 { return .native(.implicit(name, [])) }
        if e.domain == mapDomain, let name = mapCodes.first(where: { $0.1 == e.code })?.0 { return .native(.implicit(name, [])) }
        return .int(e.code)
    }
}
