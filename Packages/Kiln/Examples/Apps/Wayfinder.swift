import SwiftUI
import CoreLocation
import CoreMotion

// Round 3B (§4.5, §4.6): Core Location's values and Core Motion's
// availability, the parts native and Kiln answer the same on a simulator.
// Where the device is comes from fakes in Kiln's tests, not here.

struct Landmark: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}

enum Geo {
    static let landmarks = [
        Landmark(id: "Apple Park", coordinate: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)),
        Landmark(id: "Infinite Loop", coordinate: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312)),
        Landmark(id: "Ferry Building", coordinate: CLLocationCoordinate2D(latitude: 37.7955, longitude: -122.3937)),
        Landmark(id: "Golden Gate Bridge", coordinate: CLLocationCoordinate2D(latitude: 37.8199, longitude: -122.4783)),
        Landmark(id: "Half Dome", coordinate: CLLocationCoordinate2D(latitude: 37.7459, longitude: -119.5332)),
    ]

    /// Degrees clockwise from north, from one coordinate to another.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees < 0 ? degrees + 360 : degrees
    }

    static func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int((degrees + 22.5) / 45) % 8]
    }
}

struct ContentView: View {
    @State private var originName = "Apple Park"
    @State private var walked = 0
    @State private var typed = "37.5, -122.2"

    var origin: CLLocationCoordinate2D {
        var c = Geo.landmarks.first { $0.id == originName }?.coordinate ?? Geo.landmarks[0].coordinate
        c.latitude += Double(walked) * 1000 / 111_320
        return c
    }

    var others: [(Landmark, CLLocationDistance)] {
        let here = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return Geo.landmarks.filter { $0.id != originName }
            .map { ($0, here.distance(from: $0.location)) }
            .sorted { $0.1 < $1.1 }
    }

    var typedCoordinate: CLLocationCoordinate2D? {
        let parts = typed.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return nil }
        let c = CLLocationCoordinate2D(latitude: parts[0], longitude: parts[1])
        return CLLocationCoordinate2DIsValid(c) ? c : nil
    }

    var authorization: String {
        switch CLLocationManager().authorizationStatus {
        case .notDetermined: return "Not asked"
        case .authorizedWhenInUse, .authorizedAlways: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("From") {
                    Picker("Origin", selection: $originName) {
                        ForEach(Geo.landmarks.prefix(3)) { Text($0.id).tag($0.id) }
                    }
                    .pickerStyle(.segmented)
                    LabeledContent("Coordinate", value: String(format: "%.4f, %.4f", origin.latitude, origin.longitude))
                    Button("Walk 1 km north") { walked += 1 }
                }
                Section("Nearest first") {
                    ForEach(others, id: \.0.id) { landmark, distance in
                        let degrees = Geo.bearing(from: origin, to: landmark.coordinate)
                        LabeledContent(landmark.id) {
                            Text(String(format: "%.1f km %@ %.0f°", distance / 1000, Geo.compassPoint(degrees), degrees))
                                .monospacedDigit()
                        }
                    }
                }
                Section("A coordinate") {
                    TextField("Latitude, longitude", text: $typed)
                    if let c = typedCoordinate {
                        let km = CLLocation(latitude: c.latitude, longitude: c.longitude)
                            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude)) / 1000
                        Text(String(format: "Valid: %.1f km away", km))
                    } else {
                        Text("Not a coordinate")
                    }
                }
                Section("This device") {
                    LabeledContent("Device motion", value: CMMotionManager().isDeviceMotionAvailable ? "Yes" : "No")
                    LabeledContent("Step counting", value: CMPedometer.isStepCountingAvailable() ? "Yes" : "No")
                    LabeledContent("Heading", value: CLLocationManager.headingAvailable() ? "Yes" : "No")
                    LabeledContent("Location", value: authorization)
                    LabeledContent("Best accuracy", value: "\(kCLLocationAccuracyBest)")
                }
            }
            .navigationTitle("Wayfinder")
        }
    }
}
