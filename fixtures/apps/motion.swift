// Name: Level & Steps
// Icon: gyroscope
// Tint: teal
// Covers: Motion

import SwiftUI
import CoreMotion

/// A bubble level from device motion, with the raw sensors behind it.
@Observable
final class Tilt {
    private let motion = CMMotionManager()
    var roll = 0.0
    var pitch = 0.0
    var gravity = CMAcceleration(x: 0, y: 0, z: -1)
    var heading = -1.0
    var updates = 0
    private var reference: CMAttitude?

    var available: Bool { motion.isDeviceMotionAvailable }

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1 / 60
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            let attitude = data.attitude
            if let reference = self.reference { attitude.multiply(byInverseOf: reference) }
            self.roll = attitude.roll
            self.pitch = attitude.pitch
            self.gravity = data.gravity
            self.heading = data.heading
            self.updates += 1
        }
        motion.startGyroUpdates()
    }

    /// Zero the level where the phone lies now.
    func calibrate() { reference = motion.deviceMotion?.attitude }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopGyroUpdates()
    }

    /// The gyro, read when asked (the `TimelineView` form).
    var spin: Double {
        guard let rate = motion.gyroData?.rotationRate else { return 0 }
        return (rate.x * rate.x + rate.y * rate.y + rate.z * rate.z).squareRoot()
    }
}

struct ContentView: View {
    @State private var tilt = Tilt()
    @State private var steps = 0
    @State private var stepsToday = 0
    @State private var distance = 0.0
    @State private var climbed = 0.0
    @State private var activity = "—"
    @State private var headphones = "Not connected"
    @State private var fitnessError: String?
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private let activityManager = CMMotionActivityManager()
    private let headphoneMotion = CMHeadphoneMotionManager()

    var body: some View {
        NavigationStack {
            List {
                Section("Level") {
                    if tilt.available {
                        BubbleLevel(roll: tilt.roll, pitch: tilt.pitch)
                            .frame(height: 180)
                            .frame(maxWidth: .infinity)
                        LabeledContent("Roll", value: degrees(tilt.roll))
                        LabeledContent("Pitch", value: degrees(tilt.pitch))
                        LabeledContent("Heading", value: tilt.heading < 0 ? "—" : "\(Int(tilt.heading))°")
                        LabeledContent("Gravity z", value: String(format: "%.2f g", tilt.gravity.z))
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            LabeledContent("Spin", value: String(format: "%.2f rad/s", tilt.spin))
                        }
                        Button("Calibrate") { tilt.calibrate() }
                    } else {
                        ContentUnavailableView("No motion sensors", systemImage: "gyroscope")
                    }
                }
                Section("Today") {
                    LabeledContent("Steps", value: "\(stepsToday + steps)")
                    LabeledContent("Distance", value: Measurement(value: distance, unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))
                    LabeledContent("Climbed", value: String(format: "%.1f m", climbed))
                    LabeledContent("Activity", value: activity)
                    LabeledContent("Headphones", value: headphones)
                    if let fitnessError {
                        Label(fitnessError, systemImage: "hand.raised")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Level & Steps")
            .onAppear(perform: start)
            .onDisappear(perform: stop)
        }
    }

    func start() {
        tilt.start()
        guard CMPedometer.isStepCountingAvailable() else { return }
        let midnight = Calendar.current.startOfDay(for: .now)
        pedometer.queryPedometerData(from: midnight, to: .now) { data, error in
            if let error {
                fitnessError = CMPedometer.authorizationStatus() == .denied ? "Motion & Fitness is off for this app" : error.localizedDescription
                return
            }
            stepsToday = data?.numberOfSteps.intValue ?? 0
        }
        pedometer.startUpdates(from: .now) { data, error in
            guard let data, error == nil else { return }
            DispatchQueue.main.async {
                steps = data.numberOfSteps.intValue
                distance = data.distance?.doubleValue ?? 0
            }
        }
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { data, _ in
                climbed = data?.relativeAltitude.doubleValue ?? climbed
            }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { a in
                guard let a else { return }
                activity = a.walking ? "Walking" : a.running ? "Running" : a.cycling ? "Cycling" : a.automotive ? "Driving" : a.stationary ? "Still" : "Unknown"
            }
        }
        if headphoneMotion.isDeviceMotionAvailable {
            headphoneMotion.startDeviceMotionUpdates(to: .main) { motion, _ in
                guard let motion else { return }
                headphones = "Nodding \(degrees(motion.attitude.pitch))"
            }
        }
    }

    func stop() {
        tilt.stop()
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        activityManager.stopActivityUpdates()
        headphoneMotion.stopDeviceMotionUpdates()
    }

    func degrees(_ radians: Double) -> String {
        "\(Int((radians * 180 / .pi).rounded()))°"
    }
}

struct BubbleLevel: View {
    let roll: Double
    let pitch: Double

    var body: some View {
        ZStack {
            Circle().stroke(.secondary, lineWidth: 2)
            Circle().stroke(.secondary.opacity(0.4), lineWidth: 1).frame(width: 40, height: 40)
            Circle()
                .fill(.teal.gradient)
                .frame(width: 32, height: 32)
                .offset(x: max(-70, min(70, roll * 140)), y: max(-70, min(70, -pitch * 140)))
                .animation(.interactiveSpring, value: roll)
        }
        .frame(width: 180, height: 180)
    }
}
