import AVFoundation
import CoreLocation
import CoreMotion
import Photos

/// What iOS has decided about Shelf itself, for one capability.
enum SystemPermissionStatus: Sendable, Equatable {
    /// iOS hasn't asked yet: its prompt comes after Shelf's own.
    case notDetermined
    case allowed
    /// Turned off for Shelf in iOS Settings.
    case denied
    /// Not Shelf's to ask for: Screen Time, or a device profile.
    case restricted

    /// Whether no app can have it, whatever the ledger says.
    var isRefused: Bool { self == .denied || self == .restricted }
}

/// iOS's answers for Shelf, and its prompts. `PermissionGate` reads it
/// through this, so tests can be allowed, denied or not asked yet without
/// any real prompt.
@MainActor
protocol SystemPermissions: AnyObject {
    func status(_ capability: Capability) -> SystemPermissionStatus
    /// Shows iOS's prompt, if iOS hasn't asked yet, and returns what it says
    /// now. Only called when `status` is `.notDetermined`.
    func request(_ capability: Capability) async -> SystemPermissionStatus
}

/// The real thing: each framework's own status and prompt. The usage strings
/// the prompts show are in `project.yml` (`NS…UsageDescription`).
@MainActor
final class DeviceSystemPermissions: NSObject, SystemPermissions {
    /// One manager, made on the main thread, so its delegate is called there.
    private lazy var locationManager: CLLocationManager = {
        let manager = CLLocationManager()
        manager.delegate = self
        return manager
    }()
    private var locationWaiters: [CheckedContinuation<SystemPermissionStatus, Never>] = []

    func status(_ capability: Capability) -> SystemPermissionStatus {
        switch capability {
        case .camera:
            Self.cameraStatus(AVCaptureDevice.authorizationStatus(for: .video))
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: .allowed
            case .denied: .denied
            default: .notDetermined
            }
        case .motion:
            Self.motionStatus()
        case .location:
            // `.denied` also covers Location Services switched off for the whole phone.
            switch locationManager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: .allowed
            case .denied: .denied
            case .restricted: .restricted
            default: .notDetermined
            }
        case .photoLibraryAdd:
            switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited: .allowed
            case .denied: .denied
            case .restricted: .restricted
            default: .notDetermined
            }
        }
    }

    func request(_ capability: Capability) async -> SystemPermissionStatus {
        guard status(capability) == .notDetermined else { return status(capability) }
        switch capability {
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        case .motion:
            await askForMotion()
        case .location:
            return await askForLocation()
        case .photoLibraryAdd:
            _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return status(capability)
    }

    private static func motionStatus() -> SystemPermissionStatus {
        #if targetEnvironment(simulator)
        // No motion coprocessor, so iOS never asks; apps read Kiln's fake (RunContext.provideSensors).
        if !CMMotionActivityManager.isActivityAvailable() { return .allowed }
        #endif
        return switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: .allowed
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    private static func cameraStatus(_ status: AVAuthorizationStatus) -> SystemPermissionStatus {
        switch status {
        case .authorized: .allowed
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    /// Motion & Fitness has no request call: the first query asks. A phone
    /// with no motion coprocessor (or the simulator) can't, and the status
    /// stays not determined, which the gate takes as no.
    private func askForMotion() async {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let manager = CMMotionActivityManager()
        let now = Date.now
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            manager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { _, _ in
                done.resume()
            }
        }
        // Held until the answer, or the query is dropped with it.
        withExtendedLifetime(manager) {}
    }

    /// Asks, then waits for the delegate to hear the answer.
    private func askForLocation() async -> SystemPermissionStatus {
        await withCheckedContinuation { waiter in
            locationWaiters.append(waiter)
            if locationWaiters.count == 1 { locationManager.requestWhenInUseAuthorization() }
        }
    }
}

extension DeviceSystemPermissions: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            // Also called once when the manager is made, still undecided.
            let status = status(.location)
            guard status != .notDetermined else { return }
            let waiters = locationWaiters
            locationWaiters = []
            for waiter in waiters { waiter.resume(returning: status) }
        }
    }
}

/// iOS's answers, fixed: for tests, the stub gate Kiln's `validate` runs
/// with, and previews. `request` turns `.notDetermined` into
/// `answerWhenAsked`, as a person tapping a button in iOS's prompt would.
@MainActor
final class FixedSystemPermissions: SystemPermissions {
    var statuses: [Capability: SystemPermissionStatus]
    var answerWhenAsked: SystemPermissionStatus
    /// Every prompt iOS would have shown, in order.
    private(set) var asked: [Capability] = []

    init(_ statuses: [Capability: SystemPermissionStatus] = [:], answerWhenAsked: SystemPermissionStatus = .allowed) {
        self.statuses = statuses
        self.answerWhenAsked = answerWhenAsked
    }

    /// iOS has already said yes to everything.
    static func allowingEverything() -> FixedSystemPermissions {
        FixedSystemPermissions(Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, .allowed) }))
    }

    func status(_ capability: Capability) -> SystemPermissionStatus {
        statuses[capability] ?? .notDetermined
    }

    func request(_ capability: Capability) async -> SystemPermissionStatus {
        guard status(capability) == .notDetermined else { return status(capability) }
        asked.append(capability)
        statuses[capability] = answerWhenAsked
        return answerWhenAsked
    }
}
