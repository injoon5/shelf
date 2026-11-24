//
//  CameraGate.swift
//  Bridges: the camera behind the capability gate (PLAN.md §4.3)
//
//  The app's representable returns its `UIImagePickerController`; when its
//  source is `.camera`, Kiln shows it inside `KCameraGateController`, which
//  asks the gate first (Shelf's sheet, then iOS's prompt). Allowed, the
//  picker (or the fake camera) appears; refused, the app gets what iOS shows
//  an app the camera is off for: a screen saying so, whose Cancel calls the
//  delegate's `imagePickerControllerDidCancel(_:)`.
//
//  Where there's no camera, the context's `KilnFakeCamera` stands in (a stub
//  context has one of its own): a viewfinder whose shutter hands the
//  delegate the fake's photo, as `info[.originalImage]`.
//
//  `AVCaptureDevice`'s permission checks are here too: the gate's answer,
//  mapped onto `AVAuthorizationStatus`.
//

import SwiftUI
import ObjectiveC
#if canImport(UIKit)
import UIKit
#endif

extension CameraBridges {
    static func captureDevice(_ r: KRegistry) {
        @MainActor func capability(_ c: KCall, _ label: KArgRef) -> KilnCapability? {
            switch c.symbol(label) {
            case "video": return .camera
            case "audio": return .microphone
            default: return nil
            }
        }
        @MainActor func status(_ s: KilnPermissionStatus) -> KV {
            .native(.implicit(s == .allowed ? "authorized" : (s == .denied ? "denied" : "notDetermined"), []))
        }
        r.type("AVCaptureDevice", .camera, support: .partial,
               notes: "Only its permission checks: `authorizationStatus(for: .video)` and `await requestAccess(for: .video)`. Take photos with `UIImagePickerController`; custom `AVCaptureSession` cameras aren't supported.") { t in
            t.staticMethod("authorizationStatus", "for:AVMediaType") { c in
                guard let cap = capability(c, "for") else { return status(.denied) }
                return status(c.context.capabilities.status(cap))
            }
            t.staticMethod("requestAccess", "for:AVMediaType", async: true) { c in
                guard let cap = capability(c, "for") else { return .bool(false) }
                return .suspension(c.context.capabilities.request(cap))
            }
            t.staticMethod("requestAccess", "for:AVMediaType completionHandler:closure") { c in
                guard let f = c.function("completionHandler") else { return .void }
                let interp = c.interp, context = c.context
                guard let cap = capability(c, "for") else { interp.perform(f, [.bool(false)]); return .void }
                if interp.headless || context.isStub {
                    interp.perform(f, [.bool(context.capabilities.gate.answerWithoutAsking(cap))])
                    return .void
                }
                Task { @MainActor in
                    let allowed = await context.capabilities.ask(cap)
                    interp.perform(f, [.bool(allowed)])
                }
                return .void
            }
        }
        r.type("AVMediaType", .camera, support: .full) { t in
            t.internal()
            for n in ["video", "audio"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.type("AVAuthorizationStatus", .camera, support: .full) { t in
            t.internal()
            for n in ["notDetermined", "restricted", "denied", "authorized"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
    }
}

@MainActor
enum KCameraGate {
    #if canImport(UIKit)
    /// A check's own fake camera.
    static let stubCamera = KilnFakeCamera()
    #endif

    /// The run's fake camera: the host's, or a check's.
    static func fake(_ context: KilnContext) -> KilnFakeCamera? {
        #if canImport(UIKit)
        if let fake = context.provided(KilnFakeCamera.self) { return fake }
        return context.isStub ? stubCamera : nil
        #else
        return nil
        #endif
    }

    /// `isSourceTypeAvailable(.camera)`: a real camera, or a fake one.
    static func hasCamera(_ context: KilnContext) -> Bool {
        #if os(iOS)
        return fake(context) != nil || UIImagePickerController.isSourceTypeAvailable(.camera)
        #else
        return fake(context) != nil
        #endif
    }

    private static var wantsKey = 0
    private static var settingsKey = 0

    /// The app set `.camera`: the picker's own source waits for the gate.
    static func wantsCamera(_ picker: AnyObject) -> Bool {
        (objc_getAssociatedObject(picker, &wantsKey) as? Bool) ?? false
    }

    static func setWantsCamera(_ picker: AnyObject, _ on: Bool) {
        objc_setAssociatedObject(picker, &wantsKey, on, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// The camera's settings the app made (`cameraDevice`, `cameraFlashMode`…),
    /// kept until the real camera's source can be set.
    static func setting(_ picker: AnyObject?, _ name: String) -> String? {
        guard let picker else { return nil }
        return (objc_getAssociatedObject(picker, &settingsKey) as? [String: String])?[name]
    }

    static func set(_ picker: AnyObject?, _ name: String, _ value: String) {
        guard let picker else { return }
        var all = (objc_getAssociatedObject(picker, &settingsKey) as? [String: String]) ?? [:]
        all[name] = value
        objc_setAssociatedObject(picker, &settingsKey, all, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        #if os(iOS)
        if let p = picker as? UIImagePickerController, p.sourceType == .camera { apply(p) }
        #endif
    }

    #if os(iOS)
    /// The app's camera settings, on a picker whose source is the camera.
    static func apply(_ picker: UIImagePickerController) {
        if let d = setting(picker, "cameraDevice") { picker.cameraDevice = d == "front" ? .front : .rear }
        if let m = setting(picker, "cameraCaptureMode") { picker.cameraCaptureMode = m == "video" ? .video : .photo }
        if let f = setting(picker, "cameraFlashMode") { picker.cameraFlashMode = f == "on" ? .on : (f == "off" ? .off : .auto) }
        if let s = setting(picker, "showsCameraControls") { picker.showsCameraControls = s != "false" }
    }

    /// What the representable shows for the app's picker.
    static func host(_ vc: UIViewController, _ interp: KInterpreter) -> UIViewController {
        guard let picker = vc as? UIImagePickerController, wantsCamera(picker) else { return vc }
        return KCameraGateController(picker: picker, context: interp.context)
    }
    #endif
}

#if os(iOS)
/// Asks for the camera, then shows the camera, or what iOS shows when it's off.
final class KCameraGateController: UIViewController, KHostingController {
    let picker: UIImagePickerController
    let context: KilnContext
    var hosted: UIViewController { picker }
    private var shown: UIViewController?

    init(picker: UIImagePickerController, context: KilnContext) {
        self.picker = picker
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let context = self.context
        if context.capabilities.status(.camera) == .allowed {
            showCamera()
            return
        }
        Task { @MainActor [weak self] in
            let allowed = await context.capabilities.ask(.camera)
            guard let self, !context.isTornDown else { return }
            if allowed { self.showCamera() } else { self.showRefused() }
        }
    }

    private func embed(_ child: UIViewController) {
        shown?.willMove(toParent: nil)
        shown?.view.removeFromSuperview()
        shown?.removeFromParent()
        addChild(child)
        child.view.frame = view.bounds
        child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(child.view)
        child.didMove(toParent: self)
        shown = child
    }

    private func showCamera() {
        if let fake = KCameraGate.fake(context) {
            embed(KFakeCameraController(picker: picker, camera: fake))
            return
        }
        picker.sourceType = .camera
        KCameraGate.apply(picker)
        embed(picker)
    }

    private func showRefused() {
        let name = context.name
        let picker = self.picker
        embed(UIHostingController(rootView: KCameraOffView(app: name) { [weak self] in
            KCameraGateController.cancel(picker, from: self)
        }))
    }

    /// The delegate's `imagePickerControllerDidCancel`, or, when it has none,
    /// what UIKit does then: the picker goes.
    static func cancel(_ picker: UIImagePickerController, from vc: UIViewController?) {
        if let delegate = picker.delegate, delegate.responds(to: #selector(UIImagePickerControllerDelegate.imagePickerControllerDidCancel(_:))) {
            delegate.imagePickerControllerDidCancel?(picker)
        } else {
            vc?.dismiss(animated: true)
        }
    }
}

/// What iOS shows in the camera when an app isn't allowed it.
struct KCameraOffView: View {
    let app: String
    let cancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "video.slash.fill").font(.system(size: 44)).foregroundStyle(.secondary)
                Text("Camera Is Off").font(.title2.bold())
                Text("\(app) isn’t allowed to use the camera. You can turn it on in Shelf’s Settings › Permissions.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary).padding(.horizontal, 32)
            }
            .foregroundStyle(.white)
            VStack {
                Spacer()
                Button("Cancel", action: cancel).font(.body.weight(.semibold)).foregroundStyle(.white).padding(.bottom, 24)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}

/// The fake camera's viewfinder: the photo it will take, a shutter and Cancel.
final class KFakeCameraController: UIViewController, KilnFakeCameraScreen {
    let picker: UIImagePickerController
    let camera: KilnFakeCamera

    init(picker: UIImagePickerController, camera: KilnFakeCamera) {
        self.picker = picker
        self.camera = camera
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: KFakeViewfinder(preview: camera.photo(), shoot: { [weak self] in self?.shoot() },
                                                                 cancel: { [weak self] in self?.cancel() }))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        view.accessibilityIdentifier = "KilnFakeCamera"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        camera.appeared(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        camera.disappeared(self)
    }

    func shoot() {
        let photo = camera.photo()
        var info: [UIImagePickerController.InfoKey: Any] = [.originalImage: photo, .mediaType: "public.image", .mediaMetadata: [String: Any]()]
        if picker.allowsEditing {
            info[.editedImage] = photo
            info[.cropRect] = NSValue(cgRect: CGRect(origin: .zero, size: photo.size))
        }
        if let delegate = picker.delegate,
           delegate.responds(to: #selector(UIImagePickerControllerDelegate.imagePickerController(_:didFinishPickingMediaWithInfo:))) {
            delegate.imagePickerController?(picker, didFinishPickingMediaWithInfo: info)
        } else {
            dismiss(animated: true)
        }
    }

    func cancel() { KCameraGateController.cancel(picker, from: self) }
}

struct KFakeViewfinder: View {
    let preview: UIImage
    let shoot: () -> Void
    let cancel: () -> Void
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image(uiImage: preview).resizable().scaledToFit().opacity(0.85)
            VStack {
                Text("Simulated camera").font(.caption.weight(.semibold)).padding(8).background(.ultraThinMaterial, in: Capsule()).padding(.top, 12)
                Spacer()
                ZStack {
                    Button(action: shoot) {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 74, height: 74)
                            .overlay(Circle().fill(.white).padding(8))
                    }
                    .accessibilityLabel("Take Photo")
                    HStack {
                        Button("Cancel", action: cancel).foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 28)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
#endif
