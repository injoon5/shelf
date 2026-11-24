//
//  Camera.swift
//  Bridges: `UIImagePickerController` and its delegate (PLAN.md §1.5, §4.3)
//
//  The form models write for a photo or the camera:
//
//      struct ImagePicker: UIViewControllerRepresentable {
//          @Binding var image: UIImage?
//          func makeUIViewController(context: Context) -> UIImagePickerController {
//              let picker = UIImagePickerController()
//              picker.sourceType = .photoLibrary
//              picker.delegate = context.coordinator
//              return picker
//          }
//          func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}
//          func makeCoordinator() -> Coordinator { Coordinator(self) }
//          class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate { … }
//      }
//
//  `.photoLibrary` needs no permission (the picker runs out of process).
//  `.camera` goes through the capability gate (CameraGate.swift): Shelf's
//  sheet, then iOS's prompt, and an app that's refused sees what iOS shows a
//  refused app, a screen saying the camera is off, with Cancel. Where
//  there's no camera (the simulator, a check), a `KilnFakeCamera` the host
//  provides stands in. Custom `AVCaptureSession` cameras are won't-do.
//
//  `AVCaptureDevice.authorizationStatus(for:)` and `requestAccess(for:)`
//  answer from the gate (`.video` is the camera, `.audio` the microphone).
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

@objc(KilnBridges_Camera)
final class CameraBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        imagePicker(r)
        captureDevice(r)
        #if os(iOS)
        KRepresentables.hosts["UIImagePickerController"] = { vc, interp in KCameraGate.host(vc, interp) }
        #endif
    }

    static let infoKeys = ["originalImage", "editedImage", "imageURL", "mediaType", "mediaURL", "cropRect", "mediaMetadata", "livePhoto", "phAsset"]

    static func imagePicker(_ r: KRegistry) {
        r.type("UIImagePickerController", .camera, support: .full,
               notes: "In a `UIViewControllerRepresentable`, with `delegate = context.coordinator`: `.camera` (check `isSourceTypeAvailable(.camera)`) or `.photoLibrary`; `info[.originalImage] as? UIImage`.") { t in
            t.initializer("") { c in
                #if os(iOS)
                return .native(.object("UIImagePickerController", KRef(UIImagePickerController())))
                #else
                throw c.fail("needs iOS")
                #endif
            }
            t.staticProperty("InfoKey") { _ in .type(.builtin("UIImagePickerController.InfoKey")) }
            t.staticProperty("SourceType") { _ in .type(.builtin("UIImagePickerController.SourceType")) }
            t.staticMethod("isSourceTypeAvailable", "_:UIImagePickerController.SourceType") { c in
                #if os(iOS)
                if c.symbol(0) == "camera" { return .bool(KCameraGate.hasCamera(c.context)) }
                return .bool(UIImagePickerController.isSourceTypeAvailable(sourceType(c.symbol(0))))
                #else
                return .bool(false)
                #endif
            }
            t.staticMethod("isCameraDeviceAvailable", "_:any") { c in
                #if os(iOS)
                if KCameraGate.fake(c.context) != nil { return .bool(true) }
                return .bool(UIImagePickerController.isCameraDeviceAvailable(c.symbol(0) == "front" ? .front : .rear))
                #else
                return .bool(false)
                #endif
            }
            t.staticMethod("isFlashAvailable", "for:any") { c in
                #if os(iOS)
                return .bool(UIImagePickerController.isFlashAvailable(for: c.symbol("for") == "front" ? .front : .rear))
                #else
                return .bool(false)
                #endif
            }
            t.staticMethod("availableMediaTypes", "for:UIImagePickerController.SourceType") { c in
                #if os(iOS)
                if c.symbol("for") == "camera", KCameraGate.fake(c.context) != nil { return .array([.string("public.image")]) }
                return (UIImagePickerController.availableMediaTypes(for: sourceType(c.symbol("for"))) ?? []).isEmpty ? .nilValue
                    : .array((UIImagePickerController.availableMediaTypes(for: sourceType(c.symbol("for"))) ?? []).map(KV.string))
                #else
                return .nilValue
                #endif
            }
            t.property("sourceType", { c in
                #if os(iOS)
                guard let picker = c.object(UIImagePickerController.self) else { return .nilValue }
                if KCameraGate.wantsCamera(picker) { return .native(.implicit("camera", [])) }
                switch picker.sourceType {
                case .camera: return .native(.implicit("camera", []))
                case .savedPhotosAlbum: return .native(.implicit("savedPhotosAlbum", []))
                default: return .native(.implicit("photoLibrary", []))
                }
                #else
                return .nilValue
                #endif
            }, set: { c in
                #if os(iOS)
                guard let picker = c.object(UIImagePickerController.self) else { return }
                let name = c.symbol(0) ?? "photoLibrary"
                if name == "camera" {
                    guard KCameraGate.hasCamera(c.context) else {
                        throw c.fail("this device has no camera; check UIImagePickerController.isSourceTypeAvailable(.camera) first")
                    }
                    KCameraGate.setWantsCamera(picker, true)
                    // The real camera's source is set when the gate allows it; a fake camera shows instead of the picker.
                    if KCameraGate.fake(c.context) == nil, c.context.capabilities.status(.camera) == .allowed { picker.sourceType = .camera }
                    return
                }
                KCameraGate.setWantsCamera(picker, false)
                let source = sourceType(name)
                guard UIImagePickerController.isSourceTypeAvailable(source) else {
                    throw c.fail("this device has no \(name); check UIImagePickerController.isSourceTypeAvailable first")
                }
                picker.sourceType = source
                #endif
            })
            for (name, values) in [("cameraDevice", ["rear", "front"]), ("cameraCaptureMode", ["photo", "video"]), ("cameraFlashMode", ["auto", "off", "on"])] {
                t.property(name, { c in .native(.implicit(KCameraGate.setting(c.object(AnyObject.self), name) ?? values[0], [])) },
                           set: { c in KCameraGate.set(c.object(AnyObject.self), name, c.symbol(0) ?? values[0]) })
            }
            t.property("showsCameraControls", { c in .bool(KCameraGate.setting(c.object(AnyObject.self), "showsCameraControls") != "false") },
                       set: { c in KCameraGate.set(c.object(AnyObject.self), "showsCameraControls", c.interp.truthy(c.args[0]) ? "true" : "false") })
            t.property("videoMaximumDuration", { c in
                #if os(iOS)
                return .double(c.object(UIImagePickerController.self)?.videoMaximumDuration ?? 600)
                #else
                return .double(600)
                #endif
            }, set: { c in
                #if os(iOS)
                c.object(UIImagePickerController.self)?.videoMaximumDuration = c.double(0) ?? 600
                #endif
            })
            t.property("videoQuality", { _ in .native(.implicit("typeMedium", [])) }, set: { c in
                #if os(iOS)
                let q: UIImagePickerController.QualityType = ["typeHigh": .typeHigh, "typeLow": .typeLow, "type640x480": .type640x480][c.symbol(0) ?? ""] ?? .typeMedium
                c.object(UIImagePickerController.self)?.videoQuality = q
                #endif
            })
            t.property("allowsEditing", { c in
                #if os(iOS)
                return .bool(c.object(UIImagePickerController.self)?.allowsEditing ?? false)
                #else
                return .bool(false)
                #endif
            }, set: { c in
                #if os(iOS)
                c.object(UIImagePickerController.self)?.allowsEditing = c.interp.truthy(c.args[0])
                #endif
            })
            t.property("mediaTypes", { c in
                #if os(iOS)
                return .array((c.object(UIImagePickerController.self)?.mediaTypes ?? []).map(KV.string))
                #else
                return .array([])
                #endif
            }, set: { c in
                #if os(iOS)
                c.object(UIImagePickerController.self)?.mediaTypes = (c.args[0].asArray ?? []).compactMap(\.asString)
                #endif
            })
            t.property("delegate", { _ in .nilValue }, set: { c in
                #if os(iOS)
                guard let picker = c.object(UIImagePickerController.self) else { return }
                if c.args[0].isNil { picker.delegate = nil; KDelegates.retain(nil, by: picker); return }
                guard let proxy = KDelegates.proxy(for: c.args[0], c.interp) else {
                    throw c.fail("the delegate should be a class that adopts UIImagePickerControllerDelegate and UINavigationControllerDelegate")
                }
                picker.delegate = unsafeBitCast(proxy, to: (UIImagePickerControllerDelegate & UINavigationControllerDelegate).self)
                KDelegates.retain(proxy, by: picker)
                #endif
            })
            t.method("dismiss", "animated:bool completion:closure?") { c in
                #if os(iOS)
                let after = c.function("completion")
                let interp = c.interp
                c.object(UIImagePickerController.self)?.dismiss(animated: c.bool("animated", default: true)) {
                    if let after { interp.perform(after) }
                }
                #endif
                return .void
            }
        }
        for name in ["UIImagePickerController.SourceType", "UIImagePickerController.InfoKey", "UIImagePickerController.CameraDevice",
                     "UIImagePickerController.CameraCaptureMode", "UIImagePickerController.CameraFlashMode", "UIImagePickerController.QualityType"] {
            r.type(name, .camera) { t in t.anyStatic { _, member in .native(.implicit(member, [])) } }
        }
        #if os(iOS)
        r.representableController(UIImagePickerController.self, "UIImagePickerController")
        #endif

        r.delegateProtocol("UIImagePickerControllerDelegate", .camera,
                           requirements: ["imagePickerController(_:didFinishPickingMediaWithInfo:)?", "imagePickerControllerDidCancel(_:)?"],
                           notes: "`info[.originalImage] as? UIImage`.") { spec in
            spec.arguments("imagePickerController(_:didFinishPickingMediaWithInfo:)") { args, interp in
                [KNativeValues.kv(from: args.first), infoDictionary(args.count > 1 ? args[1] : nil, interp)]
            }
        }
    }

    /// `[UIImagePickerController.InfoKey: Any]` as the app reads it:
    /// `info[.originalImage]`. A movie's or image's file (`.mediaURL`,
    /// `.imageURL`) is the person's, handed to the app: it may read it.
    @MainActor static func infoDictionary(_ v: Any?, _ interp: KInterpreter? = nil) -> KV {
        guard let d = v as? [AnyHashable: Any] else { return .dict([:]) }
        var out: [KV: KV] = [:]
        for (k, value) in d {
            let raw = (k.base as? String) ?? "\(k.base)"
            var name = raw.hasPrefix("UIImagePickerController") ? String(raw.dropFirst("UIImagePickerController".count)) : raw
            name = name == "PHAsset" ? "phAsset" : name.prefix(1).lowercased() + name.dropFirst()
            if let url = value as? URL, url.isFileURL, let interp { KFileGrants.of(interp.context).grant(url) }
            out[.native(.implicit(name, []))] = KNativeValues.kv(from: value)
        }
        return .dict(out)
    }

    #if os(iOS)
    static func sourceType(_ name: String?) -> UIImagePickerController.SourceType {
        switch name {
        case "camera": return .camera
        case "savedPhotosAlbum": return .savedPhotosAlbum
        default: return .photoLibrary
        }
    }
    #endif
}
