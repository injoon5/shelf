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
//  §1.5 proves the mechanism with `.photoLibrary` (no permission is needed:
//  the picker runs out of process). Round 3 (§4.3) adds `.camera` behind the
//  capability gate, and the rest of the controller.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

@objc(KilnBridges_Camera)
final class CameraBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        imagePicker(r)
    }

    static let infoKeys = ["originalImage", "editedImage", "imageURL", "mediaType", "mediaURL", "cropRect", "mediaMetadata", "livePhoto", "phAsset"]

    static func imagePicker(_ r: KRegistry) {
        r.type("UIImagePickerController", .camera, support: .partial,
               notes: "`.photoLibrary` only, in a representable, `delegate = context.coordinator`.") { t in
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
                return .bool(UIImagePickerController.isSourceTypeAvailable(sourceType(c.symbol(0))))
                #else
                return .bool(false)
                #endif
            }
            t.property("sourceType", { c in
                #if os(iOS)
                switch c.object(UIImagePickerController.self)?.sourceType {
                case .camera?: return .native(.implicit("camera", []))
                case .savedPhotosAlbum?: return .native(.implicit("savedPhotosAlbum", []))
                default: return .native(.implicit("photoLibrary", []))
                }
                #else
                return .nilValue
                #endif
            }, set: { c in
                #if os(iOS)
                guard let picker = c.object(UIImagePickerController.self) else { return }
                let source = sourceType(c.symbol(0))
                guard UIImagePickerController.isSourceTypeAvailable(source) else {
                    throw c.fail("this device has no \(c.symbol(0) ?? "source"); check UIImagePickerController.isSourceTypeAvailable first")
                }
                if source == .camera { throw c.fail("the camera comes with Round 3; use .photoLibrary") }
                picker.sourceType = source
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
        for name in ["UIImagePickerController.SourceType", "UIImagePickerController.InfoKey"] {
            r.type(name, .camera) { t in t.anyStatic { _, member in .native(.implicit(member, [])) } }
        }
        #if os(iOS)
        r.representableController(UIImagePickerController.self, "UIImagePickerController")
        #endif

        r.delegateProtocol("UIImagePickerControllerDelegate", .camera,
                           requirements: ["imagePickerController(_:didFinishPickingMediaWithInfo:)?", "imagePickerControllerDidCancel(_:)?"],
                           notes: "`info[.originalImage] as? UIImage`.") { spec in
            spec.arguments("imagePickerController(_:didFinishPickingMediaWithInfo:)") { args, _ in
                [KNativeValues.kv(from: args.first), infoDictionary(args.count > 1 ? args[1] : nil)]
            }
        }
    }

    /// `[UIImagePickerController.InfoKey: Any]` as the app reads it: `info[.originalImage]`.
    @MainActor static func infoDictionary(_ v: Any?) -> KV {
        guard let d = v as? [AnyHashable: Any] else { return .dict([:]) }
        var out: [KV: KV] = [:]
        for (k, value) in d {
            let raw = (k.base as? String) ?? "\(k.base)"
            var name = raw.hasPrefix("UIImagePickerController") ? String(raw.dropFirst("UIImagePickerController".count)) : raw
            name = name == "PHAsset" ? "phAsset" : name.prefix(1).lowercased() + name.dropFirst()
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
