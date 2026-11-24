//
//  Geocoding.swift
//  Bridges: turning places into addresses and back (PLAN.md §4.6)
//
//  MapKit's types that draw nothing (MapKit's views are won't-do):
//
//      if let request = MKReverseGeocodingRequest(location: location) {
//          let items = try await request.mapItems
//          city = items.first?.addressRepresentations?.cityWithContext ?? ""
//      }
//      let found = try await MKGeocodingRequest(addressString: "1 Infinite Loop")?.mapItems
//
//  `MKMapItem` (name, location, address, address representations, time
//  zone, `openInMaps()` through the host's URL policy), and `CLGeocoder`
//  with `CLPlacemark` for older code, with handlers or `await`.
//
//  The device asks Apple's servers; a fake (`KilnFakeLocation.places`)
//  answers checks and tests.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(MapKit)
import MapKit
#endif

/// A place as geocoding returns it: `MKMapItem` and `CLPlacemark` read from this.
@MainActor
final class KPlace {
    var name: String?
    var location: KV = .nilValue
    var coordinate: (Double, Double)?
    var fullAddress: String?
    var shortAddress: String?
    var subThoroughfare: String?, thoroughfare: String?
    var subLocality: String?, locality: String?
    var subAdministrativeArea: String?, administrativeArea: String?
    var postalCode: String?, country: String?, isoCountryCode: String?
    var timeZone: TimeZone?
    var phoneNumber: String?
    var url: URL?
    var areasOfInterest: [String]?
    var inlandWater: String?, ocean: String?
    /// The device's own, for what only it can answer (`fullAddress(includingRegion:singleLine:)`).
    var device: AnyObject?

    var mapItem: KV { .native(.object("MKMapItem", KRef(self))) }
    var placemark: KV { .native(.object("CLPlacemark", KRef(self))) }

    static func fake(_ p: KilnFakeLocation.Place) -> KPlace {
        let k = KPlace()
        k.name = p.name
        k.coordinate = (p.latitude, p.longitude)
        #if canImport(CoreLocation)
        k.location = LocationBridges.location(CLLocation(latitude: p.latitude, longitude: p.longitude))
        #endif
        k.fullAddress = p.fullAddress
        k.shortAddress = p.shortAddress
        k.subThoroughfare = p.subThoroughfare
        k.thoroughfare = p.thoroughfare
        k.subLocality = p.subLocality
        k.locality = p.locality
        k.administrativeArea = p.administrativeArea
        k.postalCode = p.postalCode
        k.country = p.country
        k.isoCountryCode = p.isoCountryCode
        k.timeZone = p.timeZone.flatMap(TimeZone.init(identifier:))
        return k
    }

    /// "Cupertino, CA" for an American place, "Paris, France" elsewhere.
    var cityWithContext: String? {
        guard let city = locality else { return nil }
        if isoCountryCode == "US", let state = administrativeArea { return "\(city), \(state)" }
        return country.map { "\(city), \($0)" } ?? city
    }

    func fullAddress(includingRegion: Bool, singleLine: Bool) -> String? {
        #if canImport(MapKit)
        if #available(iOS 26.0, macOS 26.0, *), let reps = (device as? MKMapItem)?.addressRepresentations {
            return reps.fullAddress(includingRegion: includingRegion, singleLine: singleLine)
        }
        #endif
        let street = [subThoroughfare, thoroughfare].compactMap { $0 }.joined(separator: " ")
        let state = [administrativeArea, postalCode].compactMap { $0 }.joined(separator: " ")
        let parts = [street, locality ?? "", state] + (includingRegion ? [country ?? ""] : [])
        return parts.filter { !$0.isEmpty }.joined(separator: singleLine ? ", " : "\n")
    }

    #if canImport(MapKit)
    @available(iOS 26.0, macOS 26.0, *)
    static func device(_ item: MKMapItem) -> KPlace {
        let k = KPlace()
        k.device = item
        k.name = item.name
        k.location = LocationBridges.location(item.location)
        k.coordinate = (item.location.coordinate.latitude, item.location.coordinate.longitude)
        k.fullAddress = item.address?.fullAddress
        k.shortAddress = item.address?.shortAddress
        k.locality = item.addressRepresentations?.cityName
        k.country = item.addressRepresentations?.regionName
        k.isoCountryCode = item.addressRepresentations?.region?.identifier
        k.timeZone = item.timeZone
        k.phoneNumber = item.phoneNumber
        k.url = item.url
        KGeocoderShim.fill(k, from: item)
        return k
    }
    #endif

    #if canImport(CoreLocation)
    static func device(_ p: CLPlacemark) -> KPlace {
        let k = KPlace()
        k.name = p.name
        k.location = p.location.map { LocationBridges.location($0) } ?? .nilValue
        k.coordinate = p.location.map { ($0.coordinate.latitude, $0.coordinate.longitude) }
        k.subThoroughfare = p.subThoroughfare
        k.thoroughfare = p.thoroughfare
        k.subLocality = p.subLocality
        k.locality = p.locality
        k.subAdministrativeArea = p.subAdministrativeArea
        k.administrativeArea = p.administrativeArea
        k.postalCode = p.postalCode
        k.country = p.country
        k.isoCountryCode = p.isoCountryCode
        k.timeZone = p.timeZone
        k.areasOfInterest = p.areasOfInterest
        k.inlandWater = p.inlandWater
        k.ocean = p.ocean
        let fake = KilnFakeLocation.Place(name: p.name ?? "", latitude: 0, longitude: 0, subThoroughfare: p.subThoroughfare,
                                          thoroughfare: p.thoroughfare, subLocality: p.subLocality, locality: p.locality,
                                          administrativeArea: p.administrativeArea, postalCode: p.postalCode, country: p.country)
        k.fullAddress = fake.fullAddress
        k.shortAddress = fake.shortAddress
        return k
    }
    #endif
}

/// What a geocoding request or a `CLGeocoder` does: find places.
@MainActor
enum KGeocoding {
    /// Places for a location: the fake's nearest, or the device's answer.
    /// Throws `MKError.placemarkNotFound` (or `CLError.geocodeFoundNoResult`).
    static func reverse(_ interp: KInterpreter, latitude: Double, longitude: Double, mapKit: Bool) async throws -> [KPlace] {
        if let fake = LocationBridges.fake(interp) {
            guard let p = fake.nearest(latitude: latitude, longitude: longitude) else { throw notFound(mapKit) }
            let place = KPlace.fake(p)
            #if canImport(CoreLocation)
            place.location = LocationBridges.location(CLLocation(latitude: latitude, longitude: longitude))
            #endif
            return [place]
        }
        #if canImport(MapKit)
        #if canImport(CoreLocation)
        let location = CLLocation(latitude: latitude, longitude: longitude)
        if mapKit, #available(iOS 26.0, macOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { throw notFound(mapKit) }
            do { return try await request.mapItems.map(KPlace.device) } catch { throw KEThrown(value: KLocationErrors.wrap(error)) }
        }
        do { return try await KGeocoderShim.reverse(location).map(KPlace.device) } catch { throw KEThrown(value: KLocationErrors.wrap(error)) }
        #endif
        #endif
    }

    /// Places for an address.
    static func forward(_ interp: KInterpreter, _ address: String, mapKit: Bool) async throws -> [KPlace] {
        if let fake = LocationBridges.fake(interp) {
            let found = fake.matching(address)
            guard !found.isEmpty else { throw notFound(mapKit) }
            return found.map(KPlace.fake)
        }
        #if canImport(MapKit)
        if mapKit, #available(iOS 26.0, macOS 26.0, *) {
            guard let request = MKGeocodingRequest(addressString: address) else { throw notFound(mapKit) }
            do { return try await request.mapItems.map(KPlace.device) } catch { throw KEThrown(value: KLocationErrors.wrap(error)) }
        }
        do { return try await KGeocoderShim.forward(address).map(KPlace.device) } catch { throw KEThrown(value: KLocationErrors.wrap(error)) }
        #else
        throw notFound(mapKit)
        #endif
    }

    static func notFound(_ mapKit: Bool) -> KEThrown {
        KEThrown(value: mapKit ? KLocationErrors.mapError("placemarkNotFound") : KLocationErrors.error("geocodeFoundNoResult"))
    }

    /// The thrown error as the app's value.
    static func errorValue(_ e: Error) -> KV {
        if let t = e as? KEThrown { return t.value }
        return KLocationErrors.wrap(e)
    }
}

extension LocationBridges {
    static func geocoding(_ r: KRegistry) {
        for kind in ["MKReverseGeocodingRequest", "MKGeocodingRequest"] {
            let reverse = kind == "MKReverseGeocodingRequest"
            r.type(kind, .location, support: .full, introduced: "26.0",
                   notes: reverse ? "`MKReverseGeocodingRequest(location:)` (nil for an invalid location), then `try await request.mapItems`."
                                  : "`MKGeocodingRequest(addressString:)` (nil for an empty string), then `try await request.mapItems`.") { t in
                t.initializer(reverse ? "location:CLLocation" : "addressString:string") { c in
                    let req = KGeocodeRequest(reverse: reverse, interp: c.interp)
                    if reverse {
                        #if canImport(CoreLocation)
                        guard let l = c.object(at: "location", CLLocation.self), CLLocationCoordinate2DIsValid(l.coordinate) else { return .nilValue }
                        req.location = l
                        #endif
                    } else {
                        guard let s = c.string("addressString"), !s.trimmingCharacters(in: .whitespaces).isEmpty else { return .nilValue }
                        req.address = s
                    }
                    c.context.onTearDown { [weak req] in req?.cancel() }
                    return .native(.object(kind, KRef(req)))
                }
                @MainActor func me(_ c: KCall) throws -> KGeocodeRequest {
                    guard let r = c.object(KGeocodeRequest.self) else { throw c.fail("needs a \(kind)") }
                    return r
                }
                t.property("mapItems", async: true) { c in
                    let req = try me(c)
                    return .suspension(KSuspension.callback { ctx, resume in
                        req.run { result in resume(result.map { .array($0.map(\.mapItem)) }) }
                        return { req.cancel() }
                    })
                }
                t.method("getMapItems", "completionHandler:closure") { c in
                    let req = try me(c), done = c.function("completionHandler"), interp = c.interp
                    req.run { result in
                        switch result {
                        case .success(let items): interp.perform(done, [.array(items.map(\.mapItem)), .nilValue])
                        case .failure(let e): interp.perform(done, [.nilValue, KGeocoding.errorValue(e)])
                        }
                    }
                    return .void
                }
                t.method("cancel", "") { c in try me(c).cancel(); return .void }
                t.property("isCancelled") { c in .bool(try me(c).cancelled) }
                t.property("isLoading") { c in .bool(try me(c).loading) }
                t.property("preferredLocale", { _ in .nilValue }, set: { _ in })
                if reverse {
                    #if canImport(CoreLocation)
                    t.property("location") { c in try me(c).location.map { LocationBridges.location($0) } ?? .nilValue }
                    #endif
                } else {
                    t.property("addressString") { c in .string(try me(c).address ?? "") }
                }
            }
        }

        r.type("MKMapItem", .location, support: .full,
               notes: "From geocoding: `name`, `location`, `address?.fullAddress`, `addressRepresentations?.cityWithContext`, `timeZone`; `openInMaps()` opens Maps. No map views.") { t in
            @MainActor func me(_ c: KCall) throws -> KPlace {
                guard let p = c.object(KPlace.self) else { throw c.fail("needs an MKMapItem") }
                return p
            }
            #if canImport(CoreLocation)
            t.initializer("location:CLLocation address:MKAddress?") { c in
                let p = KPlace()
                if let l = c.object(at: "location", CLLocation.self) {
                    p.location = LocationBridges.location(l)
                    p.coordinate = (l.coordinate.latitude, l.coordinate.longitude)
                }
                if case .tuple(let parts, _)? = c["address"] {
                    p.fullAddress = parts.first?.asString
                    p.shortAddress = parts.count > 1 ? parts[1].asString : nil
                }
                return p.mapItem
            }
            #endif
            t.property("name", { c in try me(c).name.map(KV.string) ?? .nilValue }, set: { c in try me(c).name = c.args.first?.asString })
            t.property("location") { c in try me(c).location }
            t.property("address") { c in
                let p = try me(c)
                guard let full = p.fullAddress else { return .nilValue }
                return .tuple([.string(full), p.shortAddress.map(KV.string) ?? .nilValue], ["fullAddress", "shortAddress"])
            }
            t.property("addressRepresentations") { c in .native(.object("MKAddressRepresentations", KRef(try me(c)))) }
            t.property("placemark") { c in try me(c).placemark }
            t.property("timeZone") { c in try me(c).timeZone.map { KDates.timeZoneValue($0) } ?? .nilValue }
            t.property("phoneNumber", { c in try me(c).phoneNumber.map(KV.string) ?? .nilValue }, set: { c in try me(c).phoneNumber = c.args.first?.asString })
            t.property("url", { c in try me(c).url.map { .native(.url($0)) } ?? .nilValue }, set: { c in try me(c).url = c.url(0) })
            t.property("isCurrentLocation") { _ in .bool(false) }
            t.property("pointOfInterestCategory") { _ in .nilValue }
            t.method("openInMaps", "launchOptions:any?") { c in .bool(openInMaps(c, try me(c))) }
            t.method("openInMaps", "launchOptions:any? completionHandler:closure") { c in
                let ok = openInMaps(c, try me(c))
                c.interp.perform(c.function("completionHandler"), [.bool(ok)])
                return .void
            }
        }
        r.type("MKAddress", .location, support: .full, introduced: "26.0") { t in
            t.initializer("fullAddress:string shortAddress:string?") { c in
                guard let full = c.string("fullAddress"), !full.isEmpty else { return .nilValue }
                return .tuple([.string(full), c.string("shortAddress").map(KV.string) ?? .nilValue], ["fullAddress", "shortAddress"])
            }
            for (i, name) in ["fullAddress", "shortAddress"].enumerated() {
                t.property(name) { c in
                    guard case .tuple(let p, _) = c.receiver, i < p.count else { return .nilValue }
                    return p[i]
                }
            }
        }
        r.type("MKAddressRepresentations", .location, support: .full, introduced: "26.0") { t in
            @MainActor func me(_ c: KCall) -> KPlace? { c.object(KPlace.self) }
            t.method("fullAddress", "includingRegion:bool singleLine:bool") { c in
                me(c)?.fullAddress(includingRegion: c.bool("includingRegion", default: true), singleLine: c.bool("singleLine", default: false))
                    .map(KV.string) ?? .nilValue
            }
            t.property("cityName") { c in me(c)?.locality.map(KV.string) ?? .nilValue }
            t.property("cityWithContext") { c in me(c)?.cityWithContext.map(KV.string) ?? .nilValue }
            t.method("cityWithContext", "_:any") { c in me(c)?.cityWithContext.map(KV.string) ?? .nilValue }
            t.property("regionName") { c in me(c)?.country.map(KV.string) ?? .nilValue }
            t.property("regionCode") { c in me(c)?.isoCountryCode.map(KV.string) ?? .nilValue }
        }
        r.type("MKError", .location, support: .full) { t in
            t.property("code") { c in KLocationErrors.code(c.receiver) }
            t.properties(["localizedDescription", "description"]) { c, _ in .string(c.object(NSError.self)?.localizedDescription ?? "") }
            for (name, _) in KLocationErrors.mapCodes { t.staticProperty(name) { _ in .native(.implicit(name, [])) } }
        }

        r.type("CLGeocoder", .location, support: .full,
               notes: "For older code; prefer `MKReverseGeocodingRequest`. With a handler or `await`.") { t in
            t.initializer("") { c in
                let g = KGeocodeRequest(reverse: true, interp: c.interp)
                c.context.onTearDown { [weak g] in g?.cancel() }
                return .native(.object("CLGeocoder", KRef(g)))
            }
            @MainActor func me(_ c: KCall) throws -> KGeocodeRequest {
                guard let g = c.object(KGeocodeRequest.self) else { throw c.fail("needs a CLGeocoder") }
                return g
            }
            @MainActor func start(_ c: KCall, reverse: Bool) throws -> KGeocodeRequest {
                let g = try me(c)
                g.cancel()
                g.reset(reverse: reverse)
                if reverse {
                    #if canImport(CoreLocation)
                    guard let l = c.object(at: 0, CLLocation.self) else { throw c.fail("needs a CLLocation") }
                    g.location = l
                    #endif
                } else {
                    g.address = c.string(0) ?? ""
                }
                return g
            }
            @MainActor func handler(_ c: KCall, _ g: KGeocodeRequest, _ label: String) {
                let done = c.function(.label(label)), interp = c.interp
                g.run(mapKit: false) { result in
                    switch result {
                    case .success(let places): interp.perform(done, [.array(places.map(\.placemark)), .nilValue])
                    case .failure(let e): interp.perform(done, [.nilValue, KGeocoding.errorValue(e)])
                    }
                }
            }
            @MainActor func awaited(_ g: KGeocodeRequest) -> KV {
                .suspension(KSuspension.callback { _, resume in
                    g.run(mapKit: false) { result in resume(result.map { .array($0.map(\.placemark)) }) }
                    return { g.cancel() }
                })
            }
            t.method("reverseGeocodeLocation", "_:CLLocation completionHandler:closure") { c in
                handler(c, try start(c, reverse: true), "completionHandler"); return .void
            }
            t.method("reverseGeocodeLocation", "_:CLLocation preferredLocale:any? completionHandler:closure") { c in
                handler(c, try start(c, reverse: true), "completionHandler"); return .void
            }
            t.method("reverseGeocodeLocation", "_:CLLocation", async: true) { c in awaited(try start(c, reverse: true)) }
            t.method("reverseGeocodeLocation", "_:CLLocation preferredLocale:any?", async: true) { c in awaited(try start(c, reverse: true)) }
            t.method("geocodeAddressString", "_:string completionHandler:closure") { c in
                handler(c, try start(c, reverse: false), "completionHandler"); return .void
            }
            t.method("geocodeAddressString", "_:string", async: true) { c in awaited(try start(c, reverse: false)) }
            t.method("cancelGeocode", "") { c in try me(c).cancel(); return .void }
            t.property("isGeocoding") { c in .bool(try me(c).loading) }
        }
        r.type("CLPlacemark", .location, support: .full,
               notes: "`name`, `locality`, `administrativeArea`, `country`, `postalCode`, `thoroughfare`, `location`, `timeZone`.") { t in
            @MainActor func me(_ c: KCall) -> KPlace? { c.object(KPlace.self) }
            let strings: [(String, @MainActor (KPlace) -> String?)] = [
                ("name", { $0.name }), ("thoroughfare", { $0.thoroughfare }), ("subThoroughfare", { $0.subThoroughfare }),
                ("locality", { $0.locality }), ("subLocality", { $0.subLocality }), ("administrativeArea", { $0.administrativeArea }),
                ("subAdministrativeArea", { $0.subAdministrativeArea }), ("postalCode", { $0.postalCode }), ("country", { $0.country }),
                ("isoCountryCode", { $0.isoCountryCode }), ("inlandWater", { $0.inlandWater }), ("ocean", { $0.ocean }),
            ]
            for (name, read) in strings {
                t.property(name) { c in me(c).flatMap(read).map(KV.string) ?? .nilValue }
            }
            t.property("location") { c in me(c)?.location ?? .nilValue }
            t.property("timeZone") { c in me(c)?.timeZone.map { KDates.timeZoneValue($0) } ?? .nilValue }
            t.property("areasOfInterest") { c in me(c)?.areasOfInterest.map { .array($0.map(KV.string)) } ?? .nilValue }
        }
    }

    /// Opens Maps at the item, through the host's URL policy.
    @MainActor static func openInMaps(_ c: KCall, _ p: KPlace) -> Bool {
        guard let (lat, lon) = p.coordinate else { return false }
        var components = URLComponents(string: "maps://")!
        components.queryItems = [URLQueryItem(name: "ll", value: "\(lat),\(lon)")] + (p.name.map { [URLQueryItem(name: "q", value: $0)] } ?? [])
        guard let url = components.url, !c.interp.headless, !c.context.isStub else { return !c.interp.headless }
        return c.context.openURL?(url) ?? false
    }
}

/// One geocoding request (`MKReverseGeocodingRequest`, `MKGeocodingRequest`)
/// or a `CLGeocoder`: one search at a time.
@MainActor
final class KGeocodeRequest {
    weak var interp: KInterpreter?
    private(set) var reverse: Bool
    #if canImport(CoreLocation)
    var location: CLLocation?
    #endif
    var address: String?
    private(set) var loading = false
    private(set) var cancelled = false
    private var work: Task<Void, Never>?
    private var finish: ((Result<[KPlace], Error>) -> Void)?

    init(reverse: Bool, interp: KInterpreter) {
        self.reverse = reverse
        self.interp = interp
    }

    func reset(reverse: Bool) {
        self.reverse = reverse
        cancelled = false
    }

    /// Searches, and calls `done` once on the main actor (at once in a check).
    func run(mapKit: Bool = true, _ done: @escaping @MainActor (Result<[KPlace], Error>) -> Void) {
        guard let interp else { return }
        if cancelled { done(.failure(KEThrown(value: mapKit ? KLocationErrors.mapError("unknown") : KLocationErrors.error("geocodeCanceled")))); return }
        let reverse = self.reverse
        #if canImport(CoreLocation)
        let coordinate = location?.coordinate
        #endif
        let address = self.address ?? ""
        // A check answers from the fake, now.
        if interp.headless || interp.context.isStub || interp.context.provided(KilnFakeLocation.self) != nil {
            let result: Result<[KPlace], Error>
            if let fake = LocationBridges.fake(interp) {
                #if canImport(CoreLocation)
                if reverse {
                    let place = fake.nearest(latitude: coordinate?.latitude ?? 0, longitude: coordinate?.longitude ?? 0).map(KPlace.fake)
                    if let place, let l = location { place.location = LocationBridges.location(l) }
                    result = place.map { .success([$0]) } ?? .failure(KGeocoding.notFound(mapKit))
                } else {
                    let found = fake.matching(address).map(KPlace.fake)
                    result = found.isEmpty ? .failure(KGeocoding.notFound(mapKit)) : .success(found)
                }
                #else
                result = .failure(KGeocoding.notFound(mapKit))
                #endif
            } else {
                result = .failure(KGeocoding.notFound(mapKit))
            }
            if interp.headless { done(result); return }
            loading = true
            DispatchQueue.main.async { MainActor.assumeIsolated {
                self.loading = false
                done(self.cancelled ? .failure(KEThrown(value: KLocationErrors.error("geocodeCanceled"))) : result)
            } }
            return
        }
        loading = true
        finish = done
        work = Task { @MainActor [weak self] in
            let result: Result<[KPlace], Error>
            do {
                #if canImport(CoreLocation)
                if reverse {
                    result = .success(try await KGeocoding.reverse(interp, latitude: coordinate?.latitude ?? 0,
                                                                   longitude: coordinate?.longitude ?? 0, mapKit: mapKit))
                } else {
                    result = .success(try await KGeocoding.forward(interp, address, mapKit: mapKit))
                }
                #else
                result = .success(try await KGeocoding.forward(interp, address, mapKit: mapKit))
                #endif
            } catch {
                result = .failure(error)
            }
            guard let self, let finish = self.finish else { return }
            self.finish = nil
            self.loading = false
            finish(result)
        }
    }

    func cancel() {
        cancelled = true
        work?.cancel()
        work = nil
        loading = false
        if let finish {
            self.finish = nil
            finish(.failure(KEThrown(value: KLocationErrors.error("geocodeCanceled"))))
        }
    }
}

#if canImport(CoreLocation) && canImport(MapKit)
/// `CLGeocoder`, and `MKMapItem.placemark`, are deprecated in iOS 26 but
/// still what older apps write: called through a protocol, so the
/// deprecation stays in this one place.
private protocol KGeocoderCalls {
    func reverse(_ location: CLLocation) async throws -> [CLPlacemark]
    func forward(_ address: String) async throws -> [CLPlacemark]
    @MainActor func fill(_ place: KPlace, from item: MKMapItem)
}

private struct KDeprecatedGeocoder: KGeocoderCalls {
    @available(iOS, deprecated: 26.0)
    @available(macOS, deprecated: 26.0)
    func reverse(_ location: CLLocation) async throws -> [CLPlacemark] {
        try await CLGeocoder().reverseGeocodeLocation(location)
    }

    @available(iOS, deprecated: 26.0)
    @available(macOS, deprecated: 26.0)
    func forward(_ address: String) async throws -> [CLPlacemark] {
        try await CLGeocoder().geocodeAddressString(address)
    }

    @available(iOS, deprecated: 26.0)
    @available(macOS, deprecated: 26.0)
    @MainActor func fill(_ place: KPlace, from item: MKMapItem) {
        let p = item.placemark
        place.subThoroughfare = p.subThoroughfare
        place.thoroughfare = p.thoroughfare
        place.subLocality = p.subLocality
        place.locality = p.locality ?? place.locality
        place.subAdministrativeArea = p.subAdministrativeArea
        place.administrativeArea = p.administrativeArea
        place.postalCode = p.postalCode
        place.country = p.country ?? place.country
        place.isoCountryCode = p.isoCountryCode ?? place.isoCountryCode
        place.areasOfInterest = p.areasOfInterest
    }
}

enum KGeocoderShim {
    private static let calls: any KGeocoderCalls = KDeprecatedGeocoder()
    static func reverse(_ location: CLLocation) async throws -> [CLPlacemark] { try await calls.reverse(location) }
    static func forward(_ address: String) async throws -> [CLPlacemark] { try await calls.forward(address) }
    @MainActor static func fill(_ place: KPlace, from item: MKMapItem) { calls.fill(place, from: item) }
}
#endif
