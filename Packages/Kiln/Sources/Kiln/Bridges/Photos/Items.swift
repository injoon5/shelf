//
//  Items.swift
//  Bridges: `PhotosPickerItem` and loading what was picked (PLAN.md §4.2)
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

/// A picked movie or other file, handed over as a file the system deletes
/// when the handler returns: copied out first.
struct KPickedFile: Transferable, @unchecked Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .item) { received in
            let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-picked/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return KPickedFile(url: copy)
        }
    }
}

extension PhotosBridges {
    static func items(_ r: KRegistry) {
        r.type("PhotosPickerItem", .photos, support: .full,
               notes: "`try await item.loadTransferable(type: Data.self)` (or `Image.self`, or your `Transferable`, such as a movie with `FileRepresentation`); `itemIdentifier`, `supportedContentTypes`.") { t in
            #if canImport(PhotosUI)
            @MainActor func me(_ c: KCall) -> PhotosPickerItem? { item(c.receiver) }
            t.initializer("itemIdentifier:string") { c in item(PhotosPickerItem(itemIdentifier: c.string("itemIdentifier") ?? "")) }
            t.property("itemIdentifier") { c in me(c)?.itemIdentifier.map(KV.string) ?? .nilValue }
            t.property("supportedContentTypes") { c in .array((me(c)?.supportedContentTypes ?? []).map(FilesBridges.utType)) }
            t.method("loadTransferable", "type:any", async: true) { c in
                let type = c["type"], interp = c.interp, context = c.context
                guard let picked = me(c) else { throw c.fail("needs a PhotosPickerItem") }
                return .suspension(KSuspension.async(headless: { sample(type, interp) }) {
                    try await load(picked, as: type, interp, context)
                })
            }
            t.method("loadTransferable", "type:any completionHandler:closure") { c in
                let type = c["type"], interp = c.interp, context = c.context
                guard let picked = me(c), let f = c.function("completionHandler") else { return .nilValue }
                if interp.headless || context.isStub {
                    interp.perform(f, [FilesBridges.success(sample(type, interp), interp)])
                    return .nilValue
                }
                Task { @MainActor in
                    do {
                        let v = try await load(picked, as: type, interp, context)
                        interp.perform(f, [FilesBridges.success(v, interp)])
                    } catch {
                        interp.perform(f, [FilesBridges.failure(error, interp)])
                    }
                }
                return .nilValue
            }
            #endif
        }
        r.type("PHPhotoLibrary", .photos, support: .partial,
               notes: "`PHPhotoLibrary.shared()` for `photoLibrary:` and saving with `performChanges`; an app can add to the library, not read it.") { t in
            t.staticMethod("shared", "") { _ in .native(.object("PHPhotoLibrary", KRef(KPhotoLibrary.shared))) }
            saving(t)
        }
    }

    /// What a check's `loadTransferable` answers: a small image as the type.
    @MainActor static func sample(_ type: KV?, _ interp: KInterpreter) -> KV {
        // A 2 × 2 teal PNG.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGMw2HAAiBggFAArTgaBXvj7BQAAAABJRU5ErkJggg==") ?? Data()
        switch KShare.payloadName(type) {
        case "Data": return KBuiltins.data(png)
        case "Image", "UIImage": return KShare.imageValue(png, uiImage: KShare.payloadName(type) == "UIImage") ?? .nilValue
        default: return .nilValue
        }
    }

    #if canImport(PhotosUI)
    /// A picked item as the type the app asked for, or nil when it can't be.
    @MainActor static func load(_ picked: PhotosPickerItem, as type: KV?, _ interp: KInterpreter, _ context: KilnContext) async throws -> KV {
        let contentType = picked.supportedContentTypes.first ?? .data
        switch KShare.payloadName(type) {
        case "Data":
            return try await picked.loadTransferable(type: Data.self).map(KBuiltins.data) ?? .nilValue
        case "Image", "UIImage":
            guard let data = try await picked.loadTransferable(type: Data.self) else { return .nilValue }
            return KShare.imageValue(data, uiImage: KShare.payloadName(type) == "UIImage") ?? .nilValue
        case "URL":
            // A picked item has no URL of its own, as in compiled code.
            return .nilValue
        default:
            guard case .type(.user(let t))? = type, t.conforms("Transferable") else {
                throw interp.fail("loadTransferable(type:) takes Data.self, Image.self or your Transferable type")
            }
            if KTransferables.importsFile(t, contentType, interp) {
                guard let file = try await picked.loadTransferable(type: KPickedFile.self) else { return .nilValue }
                guard let mine = KDropItem.keep(file.url, context) else { return .nilValue }
                return try await KTransferables.importFile(t, file: mine, contentType: contentType, interp) ?? .nilValue
            }
            guard let data = try await picked.loadTransferable(type: Data.self) else { return .nilValue }
            return try await KTransferables.importValue(t, data: data, contentType: contentType, interp) ?? .nilValue
        }
    }
    #endif
}
