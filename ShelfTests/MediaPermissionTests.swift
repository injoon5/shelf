import AVFoundation
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Kiln
@testable import Shelf

/// Round 3A on the simulator (plan §4.0–§4.4): Kiln's camera, photos and
/// microphone bridges reach Shelf's permission gate through the run's
/// context, a switched-off app gets the answers iOS gives a refused app,
/// and the audio session records only while a recorder does.
@MainActor
@Suite(.serialized)
struct MediaPermissionTests {
    /// A run of `app` through Shelf's own gate, as `RunContext.installed` makes one,
    /// with Kiln's fake camera (the simulator has none).
    static func context(_ h: GateHarness, _ app: AppMeta) -> (KilnContext, URL) {
        let folder = FileManager.default.temporaryDirectory.appending(path: "media-\(UUID().uuidString)", directoryHint: .isDirectory)
        let context = KilnContext(slug: app.slug, name: app.name, defaults: KilnMemoryDefaults(), files: KilnFiles(root: folder),
                                  capabilities: PermissionsGate(h.gate.forApp(app)))
        RunContext.provideFakes(context)
        return (context, folder)
    }

    static let snapshot = #"""
        import SwiftUI
        import UIKit

        struct Camera: UIViewControllerRepresentable {
            @Binding var taken: String
            func makeUIViewController(context: Context) -> UIImagePickerController {
                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.delegate = context.coordinator
                return picker
            }
            func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
            func makeCoordinator() -> Coordinator { Coordinator(self) }
            class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
                let parent: Camera
                init(_ parent: Camera) { self.parent = parent }
                func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                    if let image = info[.originalImage] as? UIImage {
                        parent.taken = "\(Int(image.size.width))x\(Int(image.size.height))"
                        print("photo", parent.taken)
                    }
                }
                func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                    print("cancelled")
                }
            }
        }

        struct ContentView: View {
            @State private var taken = "none"
            var body: some View {
                VStack {
                    Text(taken)
                    Camera(taken: $taken)
                }
            }
        }
        """#

    static func gateController(in window: UIWindow) async -> KCameraGateController? {
        var found: KCameraGateController?
        for _ in 0..<100 where found == nil {
            try? await Task.sleep(for: .milliseconds(20))
            found = FeatureFixtureTests.find(KCameraGateController.self, in: window.rootViewController)
        }
        return found
    }

    /// The first time, Shelf asks; allowed, the (fake) camera shows, and its
    /// shutter hands the app's coordinator a photo.
    @Test func theCameraAsksThenTakesAPhoto() async throws {
        let h = GateHarness(choices: [.allow])
        defer { h.cleanUp() }
        let (context, folder) = Self.context(h, habits)
        defer { try? FileManager.default.removeItem(at: folder) }
        let compiled = try KilnEngine.compile(Self.snapshot, context: context)
        defer { compiled.interp.tearDown(); context.tearDown() }
        let window = try FeatureFixtureTests.show(compiled)
        defer { window.isHidden = true }

        let gate = try #require(await Self.gateController(in: window), "the camera wasn't shown behind the gate")
        #expect(gate.picker.sourceType == .photoLibrary, "the simulator's picker never gets .camera")
        let camera = try #require(context.provided(KilnFakeCamera.self))
        for _ in 0..<150 where camera.showing.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!camera.showing.isEmpty)
        #expect(h.asker.asks.map(\.capability) == [.camera])
        #expect(h.gate.ledger.answer(.camera, for: habits.slug) == .allowed)

        camera.showing.first?.shoot()
        #expect(compiled.interp.console.contains("photo 1200x900"), "\(compiled.interp.console) \(compiled.interp.errors)")
        #expect(compiled.interp.errors.isEmpty, "\(compiled.interp.errors)")
    }

    /// Switched off in Settings › Permissions: no sheet, no camera; the app
    /// sees iOS's camera-off screen, whose Cancel reaches its delegate.
    @Test func aSwitchedOffCameraShowsTheOffScreen() async throws {
        let h = GateHarness()
        defer { h.cleanUp() }
        h.gate.setAllowed(false, .camera, for: habits.slug, name: habits.name)
        let (context, folder) = Self.context(h, habits)
        defer { try? FileManager.default.removeItem(at: folder) }
        let compiled = try KilnEngine.compile(Self.snapshot, context: context)
        defer { compiled.interp.tearDown(); context.tearDown() }
        let window = try FeatureFixtureTests.show(compiled)
        defer { window.isHidden = true }

        let gate = try #require(await Self.gateController(in: window))
        for _ in 0..<150 where !(gate.children.first is UIHostingController<KCameraOffView>) { try await Task.sleep(for: .milliseconds(20)) }
        #expect(context.provided(KilnFakeCamera.self)?.showing.isEmpty ?? false)
        #expect(h.asker.asks.isEmpty)
        let off = try #require(gate.children.first as? UIHostingController<KCameraOffView>)
        off.rootView.cancel()
        #expect(compiled.interp.console.contains("cancelled"), "\(compiled.interp.console)")
    }

    static let everyCheck = #"""
        import SwiftUI
        import AVFoundation
        import Photos

        func report() async {
            print("camera", AVCaptureDevice.authorizationStatus(for: .video) == .denied)
            print("camera asked", await AVCaptureDevice.requestAccess(for: .video))
            print("microphone", AVAudioApplication.shared.recordPermission == .denied)
            print("microphone asked", await AVAudioApplication.requestRecordPermission())
            print("photos", PHPhotoLibrary.authorizationStatus(for: .addOnly) == .denied)
            print("photos asked", await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .denied)
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: UIImage(systemName: "star")!)
                }
                print("saved")
            } catch {
                print("save refused")
            }
            let recorder = try? AVAudioRecorder(url: URL.documentsDirectory.appending(path: "r.m4a"), settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC)])
            print("record", recorder?.record() ?? true)
        }

        struct ContentView: View {
            var body: some View { Text("x").task { await report() } }
        }
        """#

    /// What a switched-off app gets from each API is iOS's "denied", and
    /// nobody is asked.
    @Test func aSwitchedOffAppGetsDeniedEverywhere() async throws {
        let h = GateHarness(system: Dictionary(uniqueKeysWithValues: Capability.allCases.map { ($0, .allowed) }))
        defer { h.cleanUp() }
        for capability in [Capability.camera, .microphone, .photoLibraryAdd] {
            h.gate.setAllowed(false, capability, for: habits.slug, name: habits.name)
        }
        let (context, folder) = Self.context(h, habits)
        defer { try? FileManager.default.removeItem(at: folder) }
        let compiled = try KilnEngine.compile(Self.everyCheck, context: context)
        defer { compiled.interp.tearDown(); context.tearDown() }
        let window = try FeatureFixtureTests.show(compiled)
        defer { window.isHidden = true }
        let expected = ["camera true", "camera asked false", "microphone true", "microphone asked false", "photos true",
                        "photos asked true", "save refused", "record false"]
        for _ in 0..<150 where compiled.interp.console.split(separator: "\n").count < expected.count {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(compiled.interp.console.split(separator: "\n").map(String.init) == expected, "\(compiled.interp.console) \(compiled.interp.errors)")
        #expect(h.asker.asks.isEmpty)
        #expect(h.system.asked.isEmpty)
    }

    /// Recording holds the session as `.playAndRecord`; when the last
    /// recorder stops, it plays again (or goes, if nothing plays).
    @Test func theAudioSessionRecordsOnlyWhileARecorderDoes() throws {
        let session = AVAudioSession.sharedInstance()
        AppAudio.begin()
        #expect(session.category == .playback)
        AppAudio.beginRecording()
        #expect(session.category == .playAndRecord)
        #expect(session.categoryOptions.contains(.mixWithOthers))
        AppAudio.endRecording()
        #expect(session.category == .playback)
        AppAudio.end()
        #expect(AppAudio.playing == 0 && AppAudio.recording == 0)
    }
}
