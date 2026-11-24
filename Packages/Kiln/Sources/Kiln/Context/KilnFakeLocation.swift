//
//  KilnFakeLocation.swift
//  Kiln's run context: a location source the host provides (PLAN.md §4.6)
//
//  Core Location's bridges ask the run's context first:
//
//      context.provide(KilnFakeLocation.applePark())    // the host, or a test
//
//  and read the fake instead of the device: where it is (as a function of
//  time, so it can walk a route), its heading, whether the person chose
//  approximate location, and the places geocoding finds. Without one, a
//  stub context (a check) gets `KilnFakeLocation.applePark()`, and a real
//  run asks the device (the simulator's is set with `xcrun simctl location`).
//

import Foundation

@MainActor
public final class KilnFakeLocation {
    /// Where the device is at one moment.
    public struct Fix: Sendable, Equatable {
        public var latitude: Double
        public var longitude: Double
        /// Meters above sea level.
        public var altitude: Double
        /// Meters per second; -1 when unknown.
        public var speed: Double
        /// Degrees from true north; -1 when unknown.
        public var course: Double
        public var horizontalAccuracy: Double
        public var verticalAccuracy: Double

        public init(latitude: Double, longitude: Double, altitude: Double = 0, speed: Double = -1, course: Double = -1,
                    horizontalAccuracy: Double = 5, verticalAccuracy: Double = 3) {
            self.latitude = latitude
            self.longitude = longitude
            self.altitude = altitude
            self.speed = speed
            self.course = course
            self.horizontalAccuracy = horizontalAccuracy
            self.verticalAccuracy = verticalAccuracy
        }
    }

    /// A place geocoding knows, with the parts of its address.
    public struct Place: Sendable, Equatable {
        public var name: String
        public var latitude: Double
        public var longitude: Double
        public var subThoroughfare: String?
        public var thoroughfare: String?
        public var subLocality: String?
        public var locality: String?
        public var administrativeArea: String?
        public var postalCode: String?
        public var country: String?
        public var isoCountryCode: String?
        public var timeZone: String?

        public init(name: String, latitude: Double, longitude: Double, subThoroughfare: String? = nil, thoroughfare: String? = nil,
                    subLocality: String? = nil, locality: String? = nil, administrativeArea: String? = nil, postalCode: String? = nil,
                    country: String? = nil, isoCountryCode: String? = nil, timeZone: String? = nil) {
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.subThoroughfare = subThoroughfare
            self.thoroughfare = thoroughfare
            self.subLocality = subLocality
            self.locality = locality
            self.administrativeArea = administrativeArea
            self.postalCode = postalCode
            self.country = country
            self.isoCountryCode = isoCountryCode
            self.timeZone = timeZone
        }

        /// "1 Apple Park Way, Cupertino, CA 95014, United States".
        public var fullAddress: String {
            let street = [subThoroughfare, thoroughfare].compactMap { $0 }.joined(separator: " ")
            let state = [administrativeArea, postalCode].compactMap { $0 }.joined(separator: " ")
            return [street, locality, state, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        }

        /// "1 Apple Park Way, Cupertino".
        public var shortAddress: String {
            let street = [subThoroughfare, thoroughfare].compactMap { $0 }.joined(separator: " ")
            return [street, locality].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    /// Where the device is, by seconds since updates started.
    public var fix: @MainActor (TimeInterval) -> Fix
    /// Magnetic heading in degrees, by seconds since heading updates started.
    public var heading: @MainActor (TimeInterval) -> Double
    /// True north minus magnetic north, degrees (about 13 at Cupertino).
    public var declination: Double = 13
    /// The person chose approximate location for the host: coordinates are
    /// a few kilometers off, `accuracyAuthorization` is `.reducedAccuracy`.
    public var approximate = false
    /// Location Services are on for the phone.
    public var servicesEnabled = true
    public var hasHeading = true
    /// Seconds between live updates.
    public var interval: TimeInterval = 1
    /// What geocoding finds: the nearest one for a location, the ones whose
    /// name or address has the text for an address.
    public var places: [Place]

    public init(fix: @escaping @MainActor (TimeInterval) -> Fix, heading: @escaping @MainActor (TimeInterval) -> Double = { _ in 0 },
                places: [Place] = KilnFakeLocation.cupertino) {
        self.fix = fix
        self.heading = heading
        self.places = places
    }

    /// Standing still at Apple Park: what a check gets.
    public static func applePark() -> KilnFakeLocation {
        KilnFakeLocation(fix: { _ in Fix(latitude: 37.3349, longitude: -122.0090, altitude: 48) }, heading: { _ in 45 })
    }

    /// Walking round Apple Park's ring at 1.4 m/s, a lap in about 18
    /// minutes, the heading following the path.
    public static func walkingTheRing() -> KilnFakeLocation {
        let center = (lat: 37.3349, lon: -122.0090), radius = 230.0, speed = 1.4
        let metersPerDegree = 111_320.0
        func angle(_ t: TimeInterval) -> Double { t * speed / radius }
        let fake = KilnFakeLocation(fix: { t in
            let a = angle(t)
            let lat = center.lat + radius * cos(a) / metersPerDegree
            let lon = center.lon + radius * sin(a) / (metersPerDegree * cos(center.lat * .pi / 180))
            // Counterclockwise from north: the course is perpendicular to the radius.
            let course = (90 + a * 180 / .pi).truncatingRemainder(dividingBy: 360)
            return Fix(latitude: lat, longitude: lon, altitude: 48, speed: speed, course: course, horizontalAccuracy: 8)
        }, heading: { t in (90 + angle(t) * 180 / .pi - 13).truncatingRemainder(dividingBy: 360) })
        return fake
    }

    /// Places around Cupertino and San Francisco.
    nonisolated public static let cupertino: [Place] = [
        Place(name: "Apple Park", latitude: 37.3349, longitude: -122.0090, subThoroughfare: "1", thoroughfare: "Apple Park Way",
              locality: "Cupertino", administrativeArea: "CA", postalCode: "95014", country: "United States", isoCountryCode: "US",
              timeZone: "America/Los_Angeles"),
        Place(name: "Infinite Loop", latitude: 37.3318, longitude: -122.0312, subThoroughfare: "1", thoroughfare: "Infinite Loop",
              locality: "Cupertino", administrativeArea: "CA", postalCode: "95014", country: "United States", isoCountryCode: "US",
              timeZone: "America/Los_Angeles"),
        Place(name: "Ferry Building", latitude: 37.7955, longitude: -122.3937, subThoroughfare: "1", thoroughfare: "Ferry Building",
              subLocality: "Embarcadero", locality: "San Francisco", administrativeArea: "CA", postalCode: "94111",
              country: "United States", isoCountryCode: "US", timeZone: "America/Los_Angeles"),
        Place(name: "Golden Gate Bridge", latitude: 37.8199, longitude: -122.4783, thoroughfare: "Golden Gate Bridge",
              locality: "San Francisco", administrativeArea: "CA", postalCode: "94129", country: "United States", isoCountryCode: "US",
              timeZone: "America/Los_Angeles"),
    ]

    /// The fix as the app sees it: blurred when the person chose approximate.
    func seen(_ t: TimeInterval) -> Fix {
        var f = fix(t)
        guard approximate else { return f }
        // About 3 km: what iOS's approximate location gives.
        f.latitude = (f.latitude / 0.03).rounded() * 0.03
        f.longitude = (f.longitude / 0.03).rounded() * 0.03
        f.horizontalAccuracy = 3000
        f.verticalAccuracy = -1
        f.altitude = 0
        f.speed = -1
        f.course = -1
        return f
    }

    /// The place nearest a coordinate, within 50 km.
    func nearest(latitude: Double, longitude: Double) -> Place? {
        func d(_ p: Place) -> Double {
            let dl = (p.latitude - latitude), dn = (p.longitude - longitude) * cos(latitude * .pi / 180)
            return (dl * dl + dn * dn).squareRoot() * 111_320
        }
        return places.min { d($0) < d($1) }.flatMap { d($0) < 50_000 ? $0 : nil }
    }

    /// Places whose name or address has `text` (case and accents ignored).
    func matching(_ text: String) -> [Place] {
        let words = text.lowercased().split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        return places.filter { p in
            let hay = (p.name + " " + p.fullAddress).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return words.allSatisfy { hay.contains($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) }
        }
    }
}
