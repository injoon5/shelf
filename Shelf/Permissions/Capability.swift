import Foundation

/// What an app has to ask before it can use it (plan §4.0). iOS asks once for
/// Shelf; Shelf asks once for each app, and keeps the answer in its ledger.
///
/// Only what iOS itself asks about is here. The photo picker, the camera
/// picker's library source, files, and `CMMotionManager`'s raw sensors
/// (accelerometer, gyro, magnetometer, device motion) need no prompt on iOS,
/// so they need none in Shelf either.
///
/// The raw values are what the ledger stores: never rename one.
enum Capability: String, CaseIterable, Codable, Identifiable, Sendable {
    /// `UIImagePickerController` with `.camera` (§4.3).
    case camera
    /// `AVAudioRecorder` (§4.4).
    case microphone
    /// `CMPedometer`, `CMMotionActivityManager`, `CMAltimeter` and
    /// `CMHeadphoneMotionManager` (§4.5): what iOS files under Motion & Fitness.
    case motion
    /// Location while the app is open: `CLLocationUpdate`, `CLLocationManager`,
    /// heading (§4.6). Never in the background.
    case location
    /// Saving to the photo library, without seeing it (§4.2).
    case photoLibraryAdd

    var id: String { rawValue }

    /// Its name in Settings › Permissions.
    var title: String {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .motion: "Motion & Fitness"
        case .location: "Location"
        case .photoLibraryAdd: "Saving to Photos"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .motion: "figure.walk"
        case .location: "location.fill"
        case .photoLibraryAdd: "photo.badge.plus"
        }
    }

    /// The sheet's title: "Run Tracker wants to use your location".
    func ask(_ name: String) -> String {
        switch self {
        case .camera: "\(name) wants to use your camera"
        case .microphone: "\(name) wants to use your microphone"
        case .motion: "\(name) wants to use your motion and fitness data"
        case .location: "\(name) wants to use your location"
        case .photoLibraryAdd: "\(name) wants to save to your photos"
        }
    }

    /// What allowing it lets the app do, under the title.
    var purpose: String {
        switch self {
        case .camera: "It can take photos and videos while it’s open."
        case .microphone: "It can record sound while it’s open."
        case .motion: "It can read your steps, the floors you climb, and whether you’re walking, running or driving."
        case .location: "It can see where you are while it’s open, never in the background."
        case .photoLibraryAdd: "It can add photos and videos to your library. It can’t see the ones already there."
        }
    }

    /// What Settings › Permissions says when iOS has turned it off for Shelf.
    var systemDenied: String {
        switch self {
        case .camera: "Shelf isn’t allowed to use the camera, so no app here can."
        case .microphone: "Shelf isn’t allowed to use the microphone, so no app here can."
        case .motion: "Shelf isn’t allowed to use motion and fitness data, so no app here can."
        case .location: "Shelf isn’t allowed to use your location, so no app here can."
        case .photoLibraryAdd: "Shelf isn’t allowed to save to your photos, so no app here can."
        }
    }
}

/// What an app gets back when it checks (`PermissionGate.status`): the
/// ledger's answer for it, with iOS's own answer for Shelf on top. Kiln maps
/// it onto each API's own type: `.notAsked` is `.notDetermined`, `.allowed`
/// is `.authorized` (or `.authorizedWhenInUse`, `.granted`), `.denied` is
/// `.denied`.
enum PermissionStatus: String, Sendable, Equatable {
    /// Nobody has decided yet: asking would show a prompt.
    case notAsked
    case allowed
    /// Refused here, switched off in Settings › Permissions, or refused to
    /// Shelf by iOS.
    case denied
}
