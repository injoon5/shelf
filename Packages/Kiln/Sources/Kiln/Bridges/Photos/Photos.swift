//
//  Photos.swift
//  Bridges: the photo picker, and saving to the library (PLAN.md §4.2)
//
//      @State private var item: PhotosPickerItem?
//      @State private var image: Image?
//      PhotosPicker("Choose", selection: $item, matching: .images)
//          .onChange(of: item) {
//              Task {
//                  if let data = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: data) {
//                      image = Image(uiImage: ui)
//                  }
//              }
//          }
//
//  - `PhotosPicker` and `.photosPicker` are PhotosUI's own: the picker runs
//    out of process and needs no permission, so it isn't gated. One item or
//    many (`maxSelectionCount:`, `selectionBehavior:`), `matching:` every
//    `PHPickerFilter`, the inline and compact styles, and the picker's
//    other modifiers.
//  - `PhotosPickerItem.loadTransferable(type:)` loads `Data`, an `Image`, a
//    `UIImage`, or the app's own `Transferable` (a `FileRepresentation` gets
//    a file in the app's temporary folder; a movie never passes through memory).
//  - Saving: `UIImageWriteToSavedPhotosAlbum`, `UISaveVideoAtPathToSavedPhotosAlbum`
//    and `PHPhotoLibrary.shared().performChanges` with
//    `PHAssetChangeRequest.creationRequestForAsset…`, each behind the
//    capability gate (`.photoLibraryAdd`). An app that's been turned off gets
//    what iOS gives a refused app: the save's error, `.denied`.
//  - A check shows no picker and saves nothing: `loadTransferable` answers a
//    small image, and saves are recorded (`KPhotoSaves`).
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(Photos)
import Photos
#endif
#if canImport(UIKit)
import UIKit
#endif

@objc(KilnBridges_Photos)
final class PhotosBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        picker(r)
        pickerModifiers(r)
        items(r)
        saving(r)
    }

    #if canImport(PhotosUI)
    static func item(_ i: PhotosPickerItem) -> KV { .native(.boxed(KBoxed("PhotosPickerItem", i))) }

    @MainActor static func item(_ v: KV?) -> PhotosPickerItem? {
        if case .native(.boxed(let b))? = v { return b.get(PhotosPickerItem.self) }
        return nil
    }

    /// `.images`, `.any(of: [.images, .videos])`, `.not(.livePhotos)`.
    @MainActor static func filter(_ v: KV?) -> PHPickerFilter? {
        switch v {
        case .native(.boxed(let b))?: return b.get(PHPickerFilter.self)
        case .native(.implicit(let n, let args))?: return filter(n, args)
        default: return nil
        }
    }

    @MainActor static func filter(_ name: String, _ args: [KV]) -> PHPickerFilter? {
        switch name {
        case "images": return .images
        case "videos": return .videos
        case "livePhotos": return .livePhotos
        case "depthEffectPhotos": return .depthEffectPhotos
        case "bursts": return .bursts
        case "panoramas": return .panoramas
        case "screenshots": return .screenshots
        case "screenRecordings": return .screenRecordings
        case "slomoVideos": return .slomoVideos
        case "timelapseVideos": return .timelapseVideos
        case "cinematicVideos": return .cinematicVideos
        case "spatialMedia": if #available(iOS 18, macOS 15, *) { return .spatialMedia } else { return .images }
        case "any": return .any(of: (args.first?.asArray ?? []).compactMap { filter($0) })
        case "all": return .all(of: (args.first?.asArray ?? []).compactMap { filter($0) })
        case "not": return args.first.flatMap { filter($0) }.map { .not($0) }
        case "playbackStyle":
            #if os(iOS)
            if case .native(.implicit(let s, _))? = args.first { return .playbackStyle(playbackStyle(s)) }
            #endif
            return .images
        default: return nil
        }
    }

    #if os(iOS)
    static func playbackStyle(_ s: String) -> PHAsset.PlaybackStyle {
        switch s {
        case "image": return .image
        case "imageAnimated": return .imageAnimated
        case "livePhoto": return .livePhoto
        case "video": return .video
        case "videoLooping": return .videoLooping
        default: return .unsupported
        }
    }
    #endif

    static func encoding(_ name: String?) -> PhotosPickerItem.EncodingDisambiguationPolicy {
        switch name {
        case "current": return .current
        case "compatible": return .compatible
        default: return .automatic
        }
    }

    static func selectionBehavior(_ name: String?) -> PhotosPickerSelectionBehavior {
        switch name {
        case "ordered": return .ordered
        case "continuous": return .continuous
        case "continuousAndOrdered": return .continuousAndOrdered
        default: return .default
        }
    }
    #endif

    // MARK: PhotosPicker

    static let pickerNotes = "One item (`PhotosPickerItem?`) or several (`[PhotosPickerItem]`, `maxSelectionCount:`), `matching: .images` (or `.videos`, `.any(of:)`, `.not(_:)`…); load with `try await item.loadTransferable(type: Data.self)`. Needs no permission."

    static func picker(_ r: KRegistry) {
        r.view("PhotosPicker", .photos, notes: pickerNotes) { v in
            var forms: [String] = []
            for title in ["", "_:title "] {
                for library in ["", " photoLibrary:any"] {
                    for label in [title.isEmpty ? " label:content" : ""] {
                        forms.append(title + "selection:binding matching:PHPickerFilter? preferredItemEncoding:any?" + library + label)
                        forms.append(title + "selection:binding maxSelectionCount:number? selectionBehavior:any? matching:PHPickerFilter? preferredItemEncoding:any?" + library + label)
                    }
                }
            }
            v.forms(forms) { c in photosPicker(c) }
        }
        r.modifier("photosPicker", .photos, notes: "Shows the picker while `isPresented` is true.") { m in
            for library in ["", " photoLibrary:any"] {
                m.form("isPresented:binding selection:binding matching:PHPickerFilter? preferredItemEncoding:any?" + library) { c, view in photosPickerModifier(c, view) }
                m.form("isPresented:binding selection:binding maxSelectionCount:number? selectionBehavior:any? matching:PHPickerFilter? preferredItemEncoding:any?" + library) { c, view in
                    photosPickerModifier(c, view)
                }
            }
        }
    }

    @MainActor static func photosPicker(_ c: KCall) -> AnyView {
        #if canImport(PhotosUI)
        guard let b = c.kbinding("selection") else { return AnyView(EmptyView()) }
        let filter = filter(c["matching"])
        let enc = encoding(c.symbol("preferredItemEncoding"))
        let label: AnyView = c.has("label") ? c.content("label") : AnyView(Text(c.title(0)))
        let library = c.has("photoLibrary")
        if isMany(b.get(), c) {
            let many = manyBinding(b)
            let max = c.int("maxSelectionCount")
            let behavior = selectionBehavior(c.symbol("selectionBehavior"))
            switch (label, library) {
            case (let l, false): return AnyView(PhotosPicker(selection: many, maxSelectionCount: max, selectionBehavior: behavior, matching: filter, preferredItemEncoding: enc) { l })
            case (let l, true): return AnyView(PhotosPicker(selection: many, maxSelectionCount: max, selectionBehavior: behavior, matching: filter, preferredItemEncoding: enc, photoLibrary: .shared()) { l })
            }
        }
        let one = oneBinding(b)
        switch (label, library) {
        case (let l, false): return AnyView(PhotosPicker(selection: one, matching: filter, preferredItemEncoding: enc) { l })
        case (let l, true): return AnyView(PhotosPicker(selection: one, matching: filter, preferredItemEncoding: enc, photoLibrary: .shared()) { l })
        }
        #else
        return AnyView(EmptyView())
        #endif
    }

    @MainActor static func photosPickerModifier(_ c: KCall, _ view: AnyView) -> AnyView {
        #if canImport(PhotosUI)
        guard let shown = c.kbinding("isPresented").map({ c.r.boolBinding($0) }), let b = c.kbinding("selection") else { return view }
        let filter = filter(c["matching"])
        let enc = encoding(c.symbol("preferredItemEncoding"))
        let library = c.has("photoLibrary")
        if isMany(b.get(), c) {
            let max = c.int("maxSelectionCount")
            let behavior = selectionBehavior(c.symbol("selectionBehavior"))
            if library {
                return AnyView(view.photosPicker(isPresented: shown, selection: manyBinding(b), maxSelectionCount: max, selectionBehavior: behavior,
                                                 matching: filter, preferredItemEncoding: enc, photoLibrary: .shared()))
            }
            return AnyView(view.photosPicker(isPresented: shown, selection: manyBinding(b), maxSelectionCount: max, selectionBehavior: behavior,
                                             matching: filter, preferredItemEncoding: enc))
        }
        if library {
            return AnyView(view.photosPicker(isPresented: shown, selection: oneBinding(b), matching: filter, preferredItemEncoding: enc, photoLibrary: .shared()))
        }
        return AnyView(view.photosPicker(isPresented: shown, selection: oneBinding(b), matching: filter, preferredItemEncoding: enc))
        #else
        return view
        #endif
    }

    /// An array selection: what the binding holds, or `maxSelectionCount:`.
    @MainActor static func isMany(_ v: KV, _ c: KCall) -> Bool {
        if case .array = v { return true }
        return c.has("maxSelectionCount") || c.has("selectionBehavior")
    }

    #if canImport(PhotosUI)
    @MainActor static func oneBinding(_ b: KBinding) -> Binding<PhotosPickerItem?> {
        Binding(get: { item(b.get()) }, set: { b.set($0.map(item) ?? .nilValue) })
    }

    @MainActor static func manyBinding(_ b: KBinding) -> Binding<[PhotosPickerItem]> {
        Binding(get: { (b.get().asArray ?? []).compactMap { item($0) } }, set: { b.set(.array($0.map(item))) })
    }
    #endif

    // MARK: The picker's modifiers

    static func pickerModifiers(_ r: KRegistry) {
        r.modifier("photosPickerStyle", .photos, notes: "`.inline` puts the picker in the app's layout; `.compact` is one row.") { m in
            m.form("_:PhotosPickerStyle") { c, view in
                #if canImport(PhotosUI)
                switch c.symbol(0) {
                case "inline": view.photosPickerStyle(.inline)
                case "compact": view.photosPickerStyle(.compact)
                default: view.photosPickerStyle(.presentation)
                }
                #else
                view
                #endif
            }
        }
        r.type("PhotosPickerStyle", .photos, support: .full) { t in
            t.internal()
            for n in ["presentation", "inline", "compact"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.modifier("photosPickerAccessoryVisibility", .photos) { m in
            m.form("_:Visibility edges:Edge.Set?") { c, view in
                #if canImport(PhotosUI)
                view.photosPickerAccessoryVisibility(KControlValues.visibility(c[0]), edges: c.has("edges") ? c.edges("edges") : .all)
                #else
                view
                #endif
            }
        }
        r.modifier("photosPickerDisabledCapabilities", .photos) { m in
            m.form("_:PHPickerCapabilities") { c, view in
                #if canImport(PhotosUI)
                view.photosPickerDisabledCapabilities(capabilities(c[0], c.interp))
                #else
                view
                #endif
            }
        }
        r.type("PHPickerCapabilities", .photos, support: .full) { t in
            t.internal()
            for n in ["search", "stagingArea", "collectionNavigation", "selectionActions", "sensitivityAnalysisIntervention"] {
                t.staticProperty(n) { _ in .native(.implicit(n, [])) }
            }
        }
        r.modifier("photosPickerMetadataOptions", .photos, introduced: "27.0", notes: "`.removeLocation`, `.removeCaptions`: what the picked items leave out.") { m in
            m.form("_:PHPickerMetadataOptions", introduced: "27.0") { c, view in
                #if canImport(PhotosUI) && os(iOS)
                if #available(iOS 27, *) {
                    var options: PHPickerMetadataOptions = []
                    for n in names(c[0], c.interp) {
                        if n == "removeLocation" { options.insert(.removeLocation) }
                        if n == "removeCaptions" { options.insert(.removeCaptions) }
                    }
                    return AnyView(view.photosPickerMetadataOptions(options))
                }
                #endif
                return view
            }
        }
        r.type("PHPickerMetadataOptions", .photos, support: .full, introduced: "27.0") { t in
            t.internal()
            for n in ["removeLocation", "removeCaptions"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.modifier("photosPickerSearchText", .photos, introduced: "27.0", notes: "Starts the picker's search with this text.") { m in
            m.form("_:any", introduced: "27.0") { c, view in
                #if canImport(PhotosUI) && os(iOS)
                if #available(iOS 27, *) {
                    if case .native(.object("PHPickerSearchText", let ref))? = c[0], let s = ref.value as? KSearchText {
                        return AnyView(view.photosPickerSearchText(PHPickerSearchText(s.text)))
                    }
                    return AnyView(view.photosPickerSearchText(c.string(0)))
                }
                #endif
                return view
            }
        }
        r.modifier("photosReferenceImageViewer", .photos, support: .partial, introduced: "27.0",
                   notes: "The `fileURL:` form, for an image in the app's folder; the `asset:`, `pickerItem:` and `pickerResult:` forms read the photo library, which apps on Shelf can't.") { m in
            m.form("fileURL:binding onProcessingCompletion:closure?", introduced: "27.0") { c, view in
                #if canImport(PhotosUI) && os(iOS)
                if #available(iOS 27, *), let b = c.kbinding("fileURL") {
                    let interp = c.interp
                    let done = c.function("onProcessingCompletion")
                    let url = FilesBridges.previewBinding(b, c)
                    return AnyView(view.photosReferenceImageViewer(fileURL: url, onProcessingCompletion: done.map { f in { result in
                        switch result {
                        case .success(let u): interp.perform(f, [FilesBridges.success(.native(.url(u)), interp)])
                        case .failure(let e): interp.perform(f, [FilesBridges.failure(e, interp)])
                        }
                    } }))
                }
                #endif
                return view
            }
        }
        r.type("PHPickerSearchText", .photos, support: .full, introduced: "27.0") { t in
            t.initializer("_:string") { c in .native(.object("PHPickerSearchText", KRef(KSearchText(text: c.string(0) ?? "")))) }
        }
        r.type("PHPickerFilter", .photos, support: .full,
               notes: "`.images`, `.videos`, `.livePhotos`, `.screenshots` and the other kinds; `.any(of:)`, `.all(of:)`, `.not(_:)`.") { t in
            for n in ["images", "videos", "livePhotos", "depthEffectPhotos", "bursts", "panoramas", "screenshots", "screenRecordings",
                      "slomoVideos", "timelapseVideos", "cinematicVideos", "spatialMedia"] {
                t.staticProperty(n) { _ in .native(.implicit(n, [])) }
            }
            for (n, sig) in [("any", "of:any"), ("all", "of:any"), ("not", "_:PHPickerFilter"), ("playbackStyle", "_:any")] {
                t.staticMethod(n, sig) { c in .native(.implicit(n, [c[0] ?? c["of"] ?? .nilValue])) }
            }
        }
        r.type("PHAsset.PlaybackStyle", .photos, support: .full) { t in
            t.internal()
            for n in ["unsupported", "image", "imageAnimated", "livePhoto", "video", "videoLooping"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.type("PhotosPickerSelectionBehavior", .photos, support: .full) { t in
            t.internal()
            for n in ["default", "ordered", "continuous", "continuousAndOrdered"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.type("PhotosPickerItem.EncodingDisambiguationPolicy", .photos, support: .full) { t in
            t.internal()
            for n in ["automatic", "current", "compatible"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
    }

    @MainActor static func names(_ v: KV?, _ interp: KInterpreter) -> [String] {
        if case .native(.implicit(let n, _))? = v { return [n] }
        return ((try? interp.sequence(v ?? .array([]))) ?? []).compactMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil }
    }

    #if canImport(PhotosUI)
    @MainActor static func capabilities(_ v: KV?, _ interp: KInterpreter) -> PHPickerCapabilities {
        var out: PHPickerCapabilities = []
        for n in names(v, interp) {
            switch n {
            case "search": out.insert(.search)
            case "stagingArea": out.insert(.stagingArea)
            case "collectionNavigation": out.insert(.collectionNavigation)
            case "selectionActions": out.insert(.selectionActions)
            case "sensitivityAnalysisIntervention": out.insert(.sensitivityAnalysisIntervention)
            default: break
            }
        }
        return out
    }
    #endif
}

final class KSearchText {
    let text: String
    init(text: String) { self.text = text }
}
