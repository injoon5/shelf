// Name: Where Am I
// Icon: location.circle.fill
// Tint: blue
// Covers: Location

import SwiftUI
import CoreLocation
import MapKit

/// The older form: a manager and its delegate, for a compass.
final class Compass: NSObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    var heading: Double = -1
    var status = "Not asked"
    var onChange: () -> Void = {}

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() { manager.stopUpdatingHeading() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            status = manager.accuracyAuthorization == .reducedAccuracy ? "Approximate" : "Precise"
        case .denied, .restricted: status = "Off"
        default: status = "Not asked"
        }
        onChange()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        onChange()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let error = error as? CLError, error.code == .denied { status = "Off" }
        onChange()
    }
}

struct Landmark: Identifiable {
    let id: String
    let location: CLLocation
}

struct ContentView: View {
    @State private var here: CLLocation?
    @State private var place = ""
    @State private var denied = false
    @State private var limited = false
    @State private var heading = -1.0
    @State private var status = "Not asked"
    @State private var search = ""
    @State private var found: [String] = []
    @State private var compass = Compass()

    let landmarks = [
        Landmark(id: "Ferry Building", location: CLLocation(latitude: 37.7955, longitude: -122.3937)),
        Landmark(id: "Golden Gate Bridge", location: CLLocation(latitude: 37.8199, longitude: -122.4783)),
        Landmark(id: "Infinite Loop", location: CLLocation(latitude: 37.3318, longitude: -122.0312)),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Here") {
                    if denied {
                        ContentUnavailableView("Location is off", systemImage: "location.slash",
                                               description: Text("Turn it on in Settings › Permissions."))
                    } else if let here {
                        LabeledContent("Latitude", value: String(format: "%.4f", here.coordinate.latitude))
                        LabeledContent("Longitude", value: String(format: "%.4f", here.coordinate.longitude))
                        LabeledContent("Altitude", value: String(format: "%.0f m", here.altitude))
                        LabeledContent("Accuracy", value: limited ? "Approximate" : String(format: "± %.0f m", here.horizontalAccuracy))
                        if !place.isEmpty { LabeledContent("Place", value: place) }
                    } else {
                        ProgressView("Finding you…")
                    }
                    LabeledContent("Heading", value: heading < 0 ? "—" : "\(Int(heading))°")
                    LabeledContent("Permission", value: status)
                }
                if let here {
                    Section("Distances") {
                        ForEach(landmarks) { landmark in
                            LabeledContent(landmark.id, value: Measurement(value: here.distance(from: landmark.location), unit: UnitLength.meters)
                                .formatted(.measurement(width: .abbreviated, usage: .road)))
                        }
                    }
                }
                Section("Find an address") {
                    TextField("Address or place", text: $search)
                        .onSubmit { Task { await find() } }
                    ForEach(found, id: \.self) { Text($0) }
                }
                Section {
                    LocationButton(.currentLocation) { Task { await locateOnce() } }
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle("Where Am I")
            .task { await follow() }
            .onAppear {
                compass.onChange = {
                    heading = compass.heading
                    status = compass.status
                }
                compass.start()
            }
            .onDisappear { compass.stop() }
        }
    }

    /// The Swift form: a session and live updates, while the app is open.
    func follow() async {
        let session = CLServiceSession(authorization: .whenInUse)
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                denied = update.authorizationDenied || update.authorizationDeniedGlobally
                limited = update.accuracyLimited
                guard let location = update.location else { continue }
                let moved = here.map { $0.distance(from: location) > 50 } ?? true
                here = location
                if moved { await name(location) }
            }
        } catch {
            denied = true
        }
        session.invalidate()
    }

    func locateOnce() async {
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let location = update.location else { continue }
                here = location
                await name(location)
                break
            }
        } catch {}
    }

    func name(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location) else { return }
        if let item = try? await request.mapItems.first {
            place = item.addressRepresentations?.cityWithContext ?? item.name ?? ""
        }
    }

    func find() async {
        guard let request = MKGeocodingRequest(addressString: search) else { found = []; return }
        do {
            let items = try await request.mapItems
            found = items.map { item in
                let distance = here.map { " · " + String(format: "%.1f km", $0.distance(from: item.location) / 1000) } ?? ""
                return (item.name ?? item.address?.shortAddress ?? "Somewhere") + distance
            }
        } catch {
            found = ["Nothing found"]
        }
    }
}
