//
//  Location.swift
//  Bridges: Core Location's delegate (PLAN.md §1.5; §4.6 adds the rest)
//
//  An app class adopting `CLLocationManagerDelegate` gets a forwarding proxy
//  (Engine/KEDelegates.swift) like any delegate. Round 3's `CLLocationManager`
//  bridge sets it with `KDelegates.proxy(for:)` when the app writes
//  `manager.delegate = self`, behind the capability gate. The values the
//  delegate gets arrive as `CLLocation` and `CLHeading` objects (their
//  members are Round 3's) and errors as `Error`.
//

import Foundation
#if canImport(CoreLocation)
import CoreLocation
#endif

@objc(KilnBridges_Location)
final class LocationBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.delegateProtocol("CLLocationManagerDelegate", .location,
                           requirements: ["locationManager(_:didUpdateLocations:)?", "locationManager(_:didFailWithError:)?",
                                          "locationManagerDidChangeAuthorization(_:)?", "locationManager(_:didUpdateHeading:)?"],
                           support: .stub,
                           notes: "Declared, with its proxy, but nothing calls it yet: `CLLocationManager` is Round 3's (§4.6).")
        #if canImport(CoreLocation)
        r.nativeClass(CLLocationManager.self, "CLLocationManager")
        r.nativeClass(CLLocation.self, "CLLocation")
        #if !os(tvOS)
        r.nativeClass(CLHeading.self, "CLHeading")
        #endif
        #endif
    }
}
