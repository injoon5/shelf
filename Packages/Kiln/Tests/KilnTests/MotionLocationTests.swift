//
//  MotionLocationTests.swift
//  KilnTests
//
//  PLAN.md §4.5 and §4.6 (Round 3B): Core Motion and Core Location through
//  the run's fakes (`KilnFakeMotion`, `KilnFakeLocation`) and its capability
//  gate: both forms of `CMMotionManager`, the clamped interval, the gated
//  Motion & Fitness sensors and the answer a refused app gets, live updates,
//  `CLLocationManager` with its delegate, geocoding, and teardown.
//

import XCTest
import SwiftUI
@testable import Kiln

@MainActor
final class MotionLocationTests: XCTestCase {
    private var contexts: [KilnContext] = []

    override func tearDown() async throws {
        await MainActor.run {
            for c in contexts { c.tearDown() }
            contexts = []
        }
    }

    /// A real run (not a check), with fakes and a gate of fixed answers.
    private func context(motion: KilnFakeMotion? = nil, location: KilnFakeLocation? = nil,
                         gate: (any KilnCapabilityGate)? = nil) -> KilnContext {
        let gate = gate ?? KilnStubCapabilities()
        let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-sensors-\(UUID().uuidString)")
        let c = KilnContext(slug: "sensors", name: "Sensors", defaults: KilnMemoryDefaults(), files: KilnFiles(root: folder), capabilities: gate)
        if let motion { c.provide(motion) }
        if let location { c.provide(location) }
        contexts.append(c)
        return c
    }

    /// Runs the app's `async` `main()` and returns what it returned.
    private func run(_ source: String, _ context: KilnContext, file: StaticString = #filePath, line: UInt = #line) async throws -> String? {
        let c = try KilnEngine.compile("import SwiftUI\nimport CoreMotion\nimport CoreLocation\nimport MapKit\n" + source
                                       + "\nstruct ContentView: View { var body: some View { Text(\"x\") } }",
                                       headless: false, context: context)
        let main = try XCTUnwrap(c.interp.functions["main"]?.first, file: file, line: line)
        let t = c.interp.startTask(KFunction(.user(main, c.interp.globalEnv, nil)), [], parent: nil, reportsErrors: true)
        let result = await t.completion()
        XCTAssertEqual(c.interp.errors, [], file: file, line: line)
        if case .value(let v) = result { return v.asString }
        if case .error(let e) = result { return "threw \(e)" }
        return nil
    }

    /// Waits in the app until `cond` holds, a tenth of a second at a time.
    static let waitFor = """
    func waitFor(_ cond: () -> Bool) async {
        var n = 0
        while !cond() && n < 50 { try? await Task.sleep(for: .milliseconds(20)); n += 1 }
    }
    """

    static let tilted = KilnFakeMotion(reading: { _ in
        KilnFakeMotion.Reading(roll: 0.5, pitch: 0.25, yaw: 0.1, rotationRate: SIMD3(0.1, 0.2, 0.3), userAcceleration: SIMD3(0, 0.05, 0))
    })

    // MARK: CMMotionManager

    func testDeviceMotionHandlerGetsTheFakeAtAClampedInterval() async throws {
        let out = try await run("""
        \(Self.waitFor)
        func main() async -> String {
            let motion = CMMotionManager()
            motion.deviceMotionUpdateInterval = 0.001
            var rolls: [Double] = []
            var gravityZ = 0.0
            motion.startDeviceMotionUpdates(to: .main) { data, error in
                guard let data, error == nil else { return }
                rolls.append(data.attitude.roll)
                gravityZ = data.gravity.z
            }
            await waitFor { rolls.count >= 3 }
            let active = motion.isDeviceMotionActive
            motion.stopDeviceMotionUpdates()
            let interval = (motion.deviceMotionUpdateInterval * 600).rounded() / 10
            return "\\(rolls.count >= 3) \\((rolls[0] * 100).rounded() / 100) \\(gravityZ < -0.8) \\(interval) \\(active) \\(motion.isDeviceMotionActive)"
        }
        """, context(motion: Self.tilted))
        XCTAssertEqual(out, "true 0.5 true 1.0 true false")
    }

    func testPullingDeviceMotionAndTheRawSensors() async throws {
        let out = try await run("""
        func main() async -> String {
            let motion = CMMotionManager()
            guard motion.isDeviceMotionAvailable, motion.isAccelerometerAvailable else { return "unavailable" }
            let before = motion.deviceMotion == nil
            motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical)
            motion.startAccelerometerUpdates()
            motion.startGyroUpdates()
            guard let m = motion.deviceMotion, let a = motion.accelerometerData, let g = motion.gyroData else { return "nil" }
            let pitch = (m.attitude.pitch * 100).rounded() / 100
            let heading = m.heading >= 0 && m.heading < 360
            let rate = g.rotationRate
            let reference = motion.attitudeReferenceFrame == .xMagneticNorthZVertical
            motion.stopAccelerometerUpdates()
            return "\\(before) \\(pitch) \\(heading) \\(a.acceleration.z < 0) \\(rate.y) \\(reference) \\(motion.accelerometerData == nil)"
        }
        """, context(motion: Self.tilted))
        XCTAssertEqual(out, "true 0.25 true true 0.2 true true")
    }

    func testAttitudeRelativeToAReference() async throws {
        let out = try await run("""
        func main() async -> String {
            let motion = CMMotionManager()
            motion.startDeviceMotionUpdates()
            guard let a = motion.deviceMotion?.attitude, let b = motion.deviceMotion?.attitude else { return "nil" }
            let q = a.quaternion
            let norm = ((q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w) * 1000).rounded() / 1000
            b.multiply(byInverseOf: a)
            return "\\(norm) \\(abs(b.roll) < 0.0001) \\(abs(b.pitch) < 0.0001) \\(abs(b.yaw) < 0.0001)"
        }
        """, context(motion: Self.tilted))
        XCTAssertEqual(out, "1.0 true true true")
    }

    func testEulerAnglesRoundTrip() {
        let m = KRotationMatrix.euler(roll: 0.3, pitch: -0.4, yaw: 1.2)
        let e = m.euler
        XCTAssertEqual(e.roll, 0.3, accuracy: 1e-9)
        XCTAssertEqual(e.pitch, -0.4, accuracy: 1e-9)
        XCTAssertEqual(e.yaw, 1.2, accuracy: 1e-9)
        // Flat and face up: gravity points out of the back.
        XCTAssertEqual(KRotationMatrix.euler(roll: 0, pitch: 0, yaw: 0).gravity, SIMD3(0, 0, -1))
        // Standing up (pitch 90°): gravity runs down the device's y axis.
        let up = KRotationMatrix.euler(roll: 0, pitch: .pi / 2, yaw: 0).gravity
        XCTAssertEqual(up.y, -1, accuracy: 1e-9)
    }

    func testTheSimulatorHasNoSensorsWithoutAFake() async throws {
        let fake = KilnFakeMotion.still()
        fake.hasSensors = false
        let out = try await run("""
        func main() async -> String {
            let motion = CMMotionManager()
            var calls = 0
            motion.startAccelerometerUpdates(to: OperationQueue.main) { _, _ in calls += 1 }
            try? await Task.sleep(for: .milliseconds(100))
            return "\\(motion.isAccelerometerAvailable) \\(calls)"
        }
        """, context(motion: fake))
        XCTAssertEqual(out, "false 0")
    }

    // MARK: Motion & Fitness, through the gate

    func testPedometerAllowedCountsSteps() async throws {
        let out = try await run("""
        \(Self.waitFor)
        func main() async -> String {
            guard CMPedometer.isStepCountingAvailable() else { return "unavailable" }
            let pedometer = CMPedometer()
            var past = -1
            var live = -1
            var distance = 0.0
            pedometer.queryPedometerData(from: Date().addingTimeInterval(-3600), to: Date()) { data, error in
                past = data?.numberOfSteps.intValue ?? -2
            }
            pedometer.startUpdates(from: Date()) { data, error in
                guard let data else { return }
                live = data.numberOfSteps.intValue
                distance = data.distance?.doubleValue ?? 0
            }
            await waitFor { past >= 0 && live >= 0 }
            pedometer.stopUpdates()
            return "\\(past) \\(live >= 0) \\(distance >= 0) \\(CMPedometer.authorizationStatus() == .authorized)"
        }
        """, context(motion: .walking()))
        XCTAssertEqual(out, "450 true true true")
    }

    func testARefusedAppGetsCoreMotionsNotAuthorizedError() async throws {
        let gate = KilnStubCapabilities([.motion: .denied])
        let out = try await run("""
        \(Self.waitFor)
        func main() async -> String {
            let pedometer = CMPedometer()
            var answer = ""
            pedometer.startUpdates(from: Date()) { data, error in
                if let error = error as NSError? { answer = "\\(error.domain) \\(error.code)" } else { answer = "data" }
            }
            var altitude = ""
            CMAltimeter().startRelativeAltitudeUpdates(to: .main) { data, error in altitude = error == nil ? "data" : "error" }
            await waitFor { !answer.isEmpty && !altitude.isEmpty }
            let status = CMPedometer.authorizationStatus()
            return "\\(answer) \\(altitude) \\(status == .denied) \\(CMMotionActivityManager.authorizationStatus() == .denied)"
        }
        """, context(motion: .walking(), gate: gate))
        XCTAssertEqual(out, "CMErrorDomain 105 error true true")
        // Refused already: answered without asking.
        XCTAssertEqual(gate.requested, [])
    }

    func testNotAskedAsksTheGateOnce() async throws {
        let gate = KilnStubCapabilities([:], answerWhenAsked: true)
        let out = try await run("""
        \(Self.waitFor)
        func main() async -> String {
            let before = CMPedometer.authorizationStatus() == .notDetermined
            var steps = -1
            CMPedometer().queryPedometerData(from: Date().addingTimeInterval(-7200), to: Date()) { data, _ in
                steps = data?.numberOfSteps.intValue ?? -2
            }
            await waitFor { steps != -1 }
            return "\\(before) \\(steps)"
        }
        """, context(motion: .walking(), gate: gate))
        XCTAssertEqual(out, "true 900")
        XCTAssertEqual(gate.requested, [.motion])
    }

    func testAltimeterActivityAndHeadphones() async throws {
        final class Box { var connected = 0 }
        let out = try await run("""
        \(Self.waitFor)
        final class Listener: NSObject, CMHeadphoneMotionManagerDelegate {
            var connected = 0
            func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) { connected += 1 }
        }
        func main() async -> String {
            let altimeter = CMAltimeter()
            var pressure = 0.0
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, _ in pressure = data?.pressure.doubleValue ?? 0 }
            var absolute = 0.0
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { data, _ in absolute = data?.altitude ?? 0 }
            var walking = false
            let activity = CMMotionActivityManager()
            activity.startActivityUpdates(to: .main) { a in walking = a?.walking ?? false }
            var history = 0
            activity.queryActivityStarting(from: Date().addingTimeInterval(-3600), to: Date(), to: .main) { list, _ in history = list?.count ?? 0 }
            let head = CMHeadphoneMotionManager()
            let listener = Listener()
            head.delegate = listener
            var nods = 0
            var location = ""
            head.startDeviceMotionUpdates(to: .main) { motion, _ in
                nods += 1
                if motion?.sensorLocation == .headphoneLeft { location = "left" }
            }
            await waitFor { pressure > 0 && absolute > 0 && walking && history > 0 && nods > 1 && listener.connected > 0 }
            altimeter.stopRelativeAltitudeUpdates()
            head.stopDeviceMotionUpdates()
            return "\\(pressure > 100) \\(absolute > 30) \\(walking) \\(history) \\(nods > 1) \\(location) \\(listener.connected) \\(head.isDeviceMotionActive)"
        }
        """, context(motion: .walking()))
        _ = Box()
        XCTAssertEqual(out, "true true true 2 true left 1 false")
    }

    func testTeardownStopsEveryUpdate() async throws {
        let ctx = context(motion: .walking())
        let c = try KilnEngine.compile("""
        import CoreMotion
        var calls = 0
        let motion = CMMotionManager()
        let pedometer = CMPedometer()
        func start() {
            motion.startDeviceMotionUpdates(to: .main) { _, _ in calls += 1 }
            pedometer.startUpdates(from: Date()) { _, _ in calls += 1 }
        }
        struct ContentView: View { var body: some View { Text("x").onAppear { start() } } }
        """, headless: false, context: ctx)
        try c.interp.call(XCTUnwrap(c.interp.functions["start"]?.first).asFunction(c.interp), [], [])
        try await Task.sleep(for: .milliseconds(150))
        let before = c.interp.globalEnv.lookup("calls")?.value.asInt ?? 0
        XCTAssertGreaterThan(before, 0)
        ctx.tearDown()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(c.interp.globalEnv.lookup("calls")?.value.asInt, before)
    }

    // MARK: Location

    func testLiveUpdatesWalkTheFakesRoute() async throws {
        let out = try await run("""
        func main() async -> String {
            var seen: [CLLocation] = []
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    if let location = update.location { seen.append(location) }
                    if seen.count == 2 { break }
                }
            } catch { return "threw" }
            let center = CLLocation(latitude: 37.3349, longitude: -122.0090)
            let r = (seen[0].distance(from: center) / 10).rounded() * 10
            return "\\(seen.count) \\(r) \\(seen[0].speed) \\(seen[0].course >= 0)"
        }
        """, context(location: {
            let f = KilnFakeLocation.walkingTheRing()
            f.interval = 0.02
            return f
        }()))
        XCTAssertEqual(out, "2 230.0 1.4 true")
    }

    func testARefusedAppsLiveUpdatesSayDenied() async throws {
        let gate = KilnStubCapabilities([.location: .denied])
        let out = try await run("""
        func main() async -> String {
            let session = CLServiceSession(authorization: .whenInUse)
            var answer = ""
            for try await diagnostic in session.diagnostics {
                answer += diagnostic.authorizationDenied ? "session denied" : "session ok"
                break
            }
            for try await update in CLLocationUpdate.liveUpdates() {
                answer += update.authorizationDenied ? ", denied" : ", allowed"
                answer += update.location == nil ? ", no location" : ", a location"
                break
            }
            session.invalidate()
            return answer
        }
        """, context(location: .applePark(), gate: gate))
        XCTAssertEqual(out, "session denied, denied, no location")
    }

    func testApproximateLocationIsBlurredAndSaysSo() async throws {
        let fake = KilnFakeLocation.applePark()
        fake.approximate = true
        let out = try await run("""
        func main() async -> String {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let l = update.location else { continue }
                let reduced = CLLocationManager().accuracyAuthorization == .reducedAccuracy
                return "\\(update.accuracyLimited) \\(l.horizontalAccuracy) \\(reduced)"
            }
            return "none"
        }
        """, context(location: fake))
        XCTAssertEqual(out, "true 3000.0 true")
    }

    static let locator = """
    final class Locator: NSObject, CLLocationManagerDelegate {
        let manager = CLLocationManager()
        var log: [String] = []
        override init() {
            super.init()
            manager.delegate = self
        }
        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .notDetermined: log.append("notDetermined")
            case .authorizedWhenInUse, .authorizedAlways:
                log.append("allowed")
                manager.requestLocation()
            case .denied, .restricted:
                log.append("denied")
                manager.requestLocation()
            @unknown default: log.append("?")
            }
        }
        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let l = locations.last else { return }
            log.append("at \\((l.coordinate.latitude * 100).rounded() / 100)")
        }
        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            if let e = error as? CLError, e.code == .denied { log.append("CLError.denied") } else { log.append("failed") }
        }
    }
    """

    /// A person who taps Allow, and the host remembering it.
    final class Asking: KilnCapabilityGate {
        var answers: [KilnCapability: Bool] = [:]
        var asked: [KilnCapability] = []
        func request(_ capability: KilnCapability) async -> Bool {
            asked.append(capability)
            answers[capability] = true
            return true
        }
        func status(_ capability: KilnCapability) -> KilnPermissionStatus {
            answers[capability].map { $0 ? .allowed : .denied } ?? .notAsked
        }
        func cancelRequests() {}
    }

    func testDelegateAsksThenHearsALocation() async throws {
        let gate = Asking()
        let out = try await run("""
        \(Self.waitFor)
        \(Self.locator)
        func main() async -> String {
            let locator = Locator()
            await waitFor { locator.log.count >= 1 }
            locator.manager.requestWhenInUseAuthorization()
            await waitFor { locator.log.count >= 3 }
            return locator.log.joined(separator: ", ")
        }
        """, context(location: .applePark(), gate: gate))
        XCTAssertEqual(out, "notDetermined, allowed, at 37.33")
        XCTAssertEqual(gate.asked, [.location])
    }

    func testDelegateOfARefusedAppHearsDenied() async throws {
        let gate = KilnStubCapabilities([.location: .denied])
        let out = try await run("""
        \(Self.waitFor)
        \(Self.locator)
        func main() async -> String {
            let locator = Locator()
            await waitFor { locator.log.count >= 2 }
            return locator.log.joined(separator: ", ") + " \\(locator.manager.location == nil)"
        }
        """, context(location: .applePark(), gate: gate))
        XCTAssertEqual(out, "denied, CLError.denied true")
    }

    func testUpdatingLocationAndHeading() async throws {
        let fake = KilnFakeLocation.walkingTheRing()
        fake.interval = 0.02
        let out = try await run("""
        \(Self.waitFor)
        final class Compass: NSObject, CLLocationManagerDelegate {
            var headings: [Double] = []
            var fixes = 0
            func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
                headings.append(newHeading.trueHeading)
            }
            func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { fixes += locations.count }
        }
        func main() async -> String {
            let manager = CLLocationManager()
            let compass = Compass()
            manager.delegate = compass
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
            guard CLLocationManager.headingAvailable() else { return "no heading" }
            manager.startUpdatingHeading()
            manager.startUpdatingLocation()
            await waitFor { compass.fixes >= 3 && !compass.headings.isEmpty }
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
            return "\\(compass.fixes >= 3) \\(compass.headings[0] >= 0) \\(manager.location != nil) \\(manager.heading != nil)"
        }
        """, context(location: fake))
        XCTAssertEqual(out, "true true true true")
    }

    func testBackgroundLocationIsAnErrorThatSaysWhy() throws {
        let result = Kiln.validate("""
        import SwiftUI
        import CoreLocation
        struct ContentView: View {
            let manager = CLLocationManager()
            var body: some View {
                Button("Go") { manager.allowsBackgroundLocationUpdates = true }
            }
        }
        """)
        XCTAssertTrue(result.errors.contains { $0.contains("background location isn't available") }, "\(result.errors)")
    }

    // MARK: Geocoding

    func testGeocodingAnswersFromTheFake() async throws {
        let out = try await run("""
        \(Self.waitFor)
        func main() async -> String {
            var out: [String] = []
            let here = CLLocation(latitude: 37.3348, longitude: -122.0089)
            if let request = MKReverseGeocodingRequest(location: here) {
                let items = try? await request.mapItems
                out.append(items?.first?.name ?? "none")
                out.append(items?.first?.addressRepresentations?.cityWithContext ?? "none")
                out.append(items?.first?.address?.shortAddress ?? "none")
            }
            if let found = try? await MKGeocodingRequest(addressString: "ferry building")?.mapItems {
                out.append(found.first?.addressRepresentations?.cityName ?? "none")
            }
            do {
                _ = try await MKGeocodingRequest(addressString: "Atlantis")?.mapItems
                out.append("found?")
            } catch {
                out.append((error as? MKError)?.code == .placemarkNotFound ? "not found" : "other error")
            }
            out.append(MKGeocodingRequest(addressString: "  ") == nil ? "nil for empty" : "made")
            // `await` over a chain: the async property inside it is waited on.
            if let request = MKReverseGeocodingRequest(location: here), let first = try? await request.mapItems.first {
                out.append(first.name ?? "no name")
            }
            let city = try? await MKReverseGeocodingRequest(location: here)?.mapItems.first?.addressRepresentations?.cityName
            out.append(city ?? "no city")
            let count = (try? await MKGeocodingRequest(addressString: "Atlantis")?.mapItems.count) ?? -1
            out.append(String(count))
            var placemark = ""
            CLGeocoder().reverseGeocodeLocation(here) { marks, error in
                placemark = marks?.first.map { "\\($0.locality ?? "") \\($0.postalCode ?? "")" } ?? "error"
            }
            await waitFor { !placemark.isEmpty }
            out.append(placemark)
            let marks = try? await CLGeocoder().geocodeAddressString("Infinite Loop, Cupertino")
            out.append(marks?.first?.thoroughfare ?? "none")
            return out.joined(separator: "; ")
        }
        """, context(location: .applePark()))
        XCTAssertEqual(out, "Apple Park; Cupertino, CA; 1 Apple Park Way, Cupertino; San Francisco; not found; nil for empty; Apple Park; Cupertino; -1; Cupertino 95014; Infinite Loop")
    }

    // MARK: Checks

    static let checkedApps = [
        """
        import SwiftUI
        import CoreMotion
        @Observable final class Tilt {
            private let motion = CMMotionManager()
            var roll = 0.0
            func start() {
                guard motion.isDeviceMotionAvailable else { return }
                motion.deviceMotionUpdateInterval = 1 / 60
                motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                    guard let data else { return }
                    self?.roll = data.attitude.roll
                }
            }
            func stop() { motion.stopDeviceMotionUpdates() }
        }
        struct ContentView: View {
            @State private var tilt = Tilt()
            @State private var steps = 0
            private let pedometer = CMPedometer()
            var body: some View {
                VStack {
                    Text(tilt.roll, format: .number.precision(.fractionLength(2)))
                    Text("\\(steps) steps")
                    TimelineView(.animation) { _ in Text("x") }
                }
                .onAppear {
                    tilt.start()
                    pedometer.startUpdates(from: Calendar.current.startOfDay(for: .now)) { data, error in
                        guard let data, error == nil else { return }
                        DispatchQueue.main.async { steps = data.numberOfSteps.intValue }
                    }
                }
                .onDisappear { tilt.stop(); pedometer.stopUpdates() }
            }
        }
        """,
        """
        import SwiftUI
        import CoreLocation
        import MapKit
        struct ContentView: View {
            @State private var location: CLLocation?
            @State private var city = ""
            @State private var denied = false
            var body: some View {
                VStack {
                    if let location {
                        Text("\\(location.coordinate.latitude), \\(location.coordinate.longitude)")
                        Text(city)
                    }
                    if denied { Text("Location is off") }
                    LocationButton(.currentLocation) { }
                }
                .task {
                    let session = CLServiceSession(authorization: .whenInUse)
                    do {
                        for try await update in CLLocationUpdate.liveUpdates() {
                            denied = update.authorizationDenied
                            guard let l = update.location else { continue }
                            location = l
                            if let request = MKReverseGeocodingRequest(location: l),
                               let item = try await request.mapItems.first {
                                city = item.addressRepresentations?.cityWithContext ?? ""
                            }
                        }
                    } catch {}
                    _ = session
                }
            }
        }
        """,
    ]

    func testModelWrittenAppsCheckAndValidateClean() {
        for app in Self.checkedApps {
            XCTAssertEqual(Kiln.check(app).errors.map(\.description), [])
            XCTAssertEqual(Kiln.validate(app).errors, [])
        }
    }

    /// Shelf's two fixtures, checked, validated and shown with a check's fakes.
    func testShelfsFixturesRunOnTheFakes() throws {
        let apps = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../../../fixtures/apps").standardized
        for name in ["motion", "location"] {
            let source = try String(contentsOf: apps.appending(path: "\(name).swift"), encoding: .utf8)
            XCTAssertEqual(BridgeTest.problems(source), [], name)
        }
        let lab = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "../../Examples/Apps/Wayfinder.swift").standardized
        XCTAssertEqual(BridgeTest.problems(try String(contentsOf: lab, encoding: .utf8)), [], "Wayfinder")
    }

    func testValidateRunsAHandlerOnceWithAStillDevice() {
        let result = Kiln.validate("""
        import SwiftUI
        import CoreMotion
        struct ContentView: View {
            let motion = CMMotionManager()
            @State private var z = 0.0
            var body: some View {
                Text("\\(z)")
                    .onAppear {
                        motion.startAccelerometerUpdates(to: .main) { data, _ in
                            z = data!.acceleration.z
                            print("z \\(z)")
                        }
                    }
            }
        }
        """)
        XCTAssertEqual(result.errors, [])
    }
}

private extension KEFuncDecl {
    @MainActor func asFunction(_ interp: KInterpreter) -> KFunction { KFunction(.user(self, interp.globalEnv, nil)) }
}
