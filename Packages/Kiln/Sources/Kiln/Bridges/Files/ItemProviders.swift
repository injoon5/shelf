//
//  ItemProviders.swift
//  Bridges: `NSItemProvider`, for the older drag and drop API (PLAN.md §4.1)
//
//      .onDrop(of: [.text], isTargeted: $over) { providers in
//          providers.first?.loadObject(ofClass: String.self) { text, _ in
//              DispatchQueue.main.async { dropped = text ?? "" }
//          }
//          return true
//      }
//
//  The provider is Foundation's own. What it loads reaches the app's
//  completion handler on the main thread (Kiln's code runs only there),
//  converted to the app's values: a `String`, a `URL`, `Data`, a `UIImage`.
//  A file it hands over (`loadFileRepresentation`) is copied into the app's
//  temporary folder first, since the system deletes its copy when the
//  handler returns.
//

import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

extension FilesBridges {
    static func itemProviders(_ r: KRegistry) {
        r.type("NSItemProvider", .files, support: .full,
               notes: "`NSItemProvider(object:)` for a `String`, `URL` or `UIImage`; `loadObject(ofClass:)`, `loadDataRepresentation(for:)`, `loadFileRepresentation(for:)`, `loadTransferable(type:)`; the handler runs on the main thread.") { t in
            @MainActor func provider(_ c: KCall) -> NSItemProvider? { c.object(NSItemProvider.self) }
            @MainActor func wrap(_ p: NSItemProvider) -> KV { .native(.object("NSItemProvider", KRef(p))) }
            t.initializer("") { _ in wrap(NSItemProvider()) }
            t.initializer("object:any") { c in
                guard let object = writing(c["object"] ?? .nilValue) else { throw c.fail("makes a provider for a String, URL or UIImage") }
                return wrap(NSItemProvider(object: object))
            }
            t.initializer("item:any typeIdentifier:string?") { c in
                let item: NSSecureCoding? = {
                    switch c["item"] {
                    case .string(let s)?: return s as NSString
                    case .native(.url(let u))?: return u as NSURL
                    case let v?: return KBuiltins.dataValue(v).map { $0 as NSData }
                    default: return nil
                    }
                }()
                return wrap(NSItemProvider(item: item, typeIdentifier: c.string("typeIdentifier")))
            }
            t.initializer("contentsOf:URL") { c in
                let url = try FoundationBridges.file(c, "contentsOf")
                return NSItemProvider(contentsOf: url).map(wrap) ?? .nilValue
            }
            t.property("suggestedName", { c in provider(c)?.suggestedName.map(KV.string) ?? .nilValue },
                       set: { c in provider(c)?.suggestedName = c.string(0) })
            t.property("registeredTypeIdentifiers") { c in .array((provider(c)?.registeredTypeIdentifiers ?? []).map(KV.string)) }
            t.property("registeredContentTypes") { c in .array((provider(c)?.registeredContentTypes ?? []).map(utType)) }
            t.method("hasItemConformingToTypeIdentifier", "_:string") { c in .bool(provider(c)?.hasItemConformingToTypeIdentifier(c.string(0) ?? "") ?? false) }
            t.method("hasRepresentationConforming", "toTypeIdentifier:string fileOptions:any?") { c in
                .bool(provider(c)?.hasRepresentationConforming(toTypeIdentifier: c.string("toTypeIdentifier") ?? "", fileOptions: []) ?? false)
            }
            t.method("canLoadObject", "ofClass:any") { c in
                guard let p = provider(c) else { return .bool(false) }
                switch KShare.payloadName(c["ofClass"]) {
                case "String", "NSString": return .bool(p.canLoadObject(ofClass: NSString.self))
                case "URL", "NSURL": return .bool(p.canLoadObject(ofClass: NSURL.self))
                #if canImport(UIKit)
                case "UIImage": return .bool(p.canLoadObject(ofClass: UIImage.self))
                #endif
                default: return .bool(false)
                }
            }
            t.method("registerObject", "_:any visibility:any") { c in
                if let o = writing(c[0] ?? .nilValue) { provider(c)?.registerObject(o, visibility: .all) }
                return .void
            }

            t.method("loadObject", "ofClass:any completionHandler:closure") { c in
                guard let p = provider(c), let f = c.function("completionHandler") else { return .nilValue }
                let interp = c.interp
                @MainActor func deliver(_ v: KV, _ error: Error?) {
                    interp.perform(f, [v, error.map { KBuiltins.errorValue($0.localizedDescription) } ?? .nilValue])
                }
                if interp.headless {
                    deliver(c["ofClass"].map { KShare.payloadName($0) == "URL" ? .native(.url(URL(string: "https://example.com")!)) : .string("Dropped") } ?? .nilValue, nil)
                    return .nilValue
                }
                switch KShare.payloadName(c["ofClass"]) {
                case "URL", "NSURL":
                    _ = p.loadObject(ofClass: URL.self) { u, e in Task { @MainActor in deliver(u.map { .native(.url($0)) } ?? .nilValue, e) } }
                #if canImport(UIKit)
                case "UIImage":
                    _ = p.loadObject(ofClass: UIImage.self) { o, e in
                        let image = KUnsafeSendable(o as? UIImage)
                        Task { @MainActor in deliver(image.value.map(DrawingBridges.uiImage) ?? .nilValue, e) }
                    }
                #endif
                default:
                    _ = p.loadObject(ofClass: String.self) { s, e in Task { @MainActor in deliver(s.map(KV.string) ?? .nilValue, e) } }
                }
                return .nilValue
            }
            for (label, kind) in [("forTypeIdentifier", "string"), ("for", "UTType")] {
                t.method("loadDataRepresentation", "\(label):\(kind) completionHandler:closure") { c in
                    guard let p = provider(c), let f = c.function("completionHandler") else { return .nilValue }
                    let interp = c.interp
                    let id = label == "for" ? (utType(c["for"])?.identifier ?? "public.data") : (c.string(.label(label)) ?? "public.data")
                    if interp.headless { interp.perform(f, [KBuiltins.data(Data("Dropped".utf8)), .nilValue]); return .nilValue }
                    _ = p.loadDataRepresentation(forTypeIdentifier: id) { d, e in
                        Task { @MainActor in interp.perform(f, [d.map { KBuiltins.data($0) } ?? .nilValue, e.map { KBuiltins.errorValue($0.localizedDescription) } ?? .nilValue]) }
                    }
                    return .nilValue
                }
                t.method("loadFileRepresentation", "\(label):\(kind) completionHandler:closure") { c in
                    guard let p = provider(c), let f = c.function("completionHandler") else { return .nilValue }
                    let interp = c.interp, context = c.context
                    let id = label == "for" ? (utType(c["for"])?.identifier ?? "public.data") : (c.string(.label(label)) ?? "public.data")
                    if interp.headless { interp.perform(f, [.native(.url(sampleFile(interp))), .nilValue]); return .nilValue }
                    _ = p.loadFileRepresentation(forTypeIdentifier: id) { url, e in
                        // The system's copy goes when this returns: keep one first.
                        var kept: URL?
                        if let url {
                            let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-drops/\(UUID().uuidString)", directoryHint: .isDirectory)
                            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                            let copy = folder.appending(path: url.lastPathComponent)
                            if (try? FileManager.default.copyItem(at: url, to: copy)) != nil { kept = copy }
                        }
                        let k = kept
                        Task { @MainActor in
                            let mine = k.flatMap { KDropItem.keep($0, context) }
                            interp.perform(f, [mine.map { .native(.url($0)) } ?? .nilValue, e.map { KBuiltins.errorValue($0.localizedDescription) } ?? .nilValue])
                        }
                    }
                    return .nilValue
                }
            }
            t.method("loadItem", "forTypeIdentifier:string options:any? completionHandler:closure") { c in
                guard let p = provider(c), let f = c.function("completionHandler") else { return .void }
                let interp = c.interp
                if interp.headless { interp.perform(f, [.string("Dropped"), .nilValue]); return .void }
                p.loadItem(forTypeIdentifier: c.string("forTypeIdentifier") ?? "public.data", options: nil) { item, e in
                    let value = KUnsafeSendable(item)
                    Task { @MainActor in interp.perform(f, [KNativeValues.kv(from: value.value), e.map { KBuiltins.errorValue($0.localizedDescription) } ?? .nilValue]) }
                }
                return .void
            }
            t.method("loadTransferable", "type:any completionHandler:closure") { c in
                guard let p = provider(c), let f = c.function("completionHandler") else { return .nilValue }
                let interp = c.interp, context = c.context
                let type = c["type"]
                if interp.headless {
                    let sample = (try? interp.sequence(FilesBridges.samples(type, interp)))?.first ?? .nilValue
                    interp.perform(f, [FilesBridges.success(sample, interp)])
                    return .nilValue
                }
                _ = p.loadTransferable(type: KDropItem.self) { result in
                    let r = KUnsafeSendable(result)
                    Task { @MainActor in
                        switch r.value {
                        case .success(let item):
                            let v = await KDropItem.values([item], as: type, interp, context).first ?? .nilValue
                            interp.perform(f, [FilesBridges.success(v, interp)])
                        case .failure(let e):
                            interp.perform(f, [FilesBridges.failure(e, interp)])
                        }
                    }
                }
                return .nilValue
            }
        }
        r.nativeClass(NSItemProvider.self, "NSItemProvider")
    }

    /// A value `NSItemProvider(object:)` can carry.
    @MainActor static func writing(_ v: KV) -> NSItemProviderWriting? {
        switch v {
        case .string(let s): return s as NSString
        case .native(.url(let u)): return u as NSURL
        #if canImport(UIKit)
        case .native(.object("UIImage", let ref)): return ref.value as? UIImage
        #endif
        default: return nil
        }
    }
}
