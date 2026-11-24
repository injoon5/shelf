//
//  Saving.swift
//  Bridges: saving to the photo library, behind the capability gate (PLAN.md §4.2)
//
//  Every way models save asks the gate for `.photoLibraryAdd` first (Shelf's
//  sheet, then iOS's prompt), and an app that's refused gets iOS's answers:
//  `PHAuthorizationStatus.denied`, `performChanges` throwing
//  `PHPhotosError.accessUserDenied`, and a completion selector's error.
//  A check saves nothing and records what would have been (`KPhotoSaves`).
//

import SwiftUI
#if canImport(Photos)
import Photos
#endif
#if canImport(UIKit)
import UIKit
#endif

/// `PHPhotoLibrary.shared()`.
final class KPhotoLibrary {
    @MainActor static let shared = KPhotoLibrary()
}

/// What a check (or a test) saw saved, and the changes `performChanges`'s
/// block asks for while it runs.
@MainActor
enum KPhotoSaves {
    enum Item: Equatable {
        case image(width: Int, height: Int)
        case video(String)
        case file(String)
    }
    /// Everything saved by stub runs, for tests. Real saves aren't listed.
    static var saved: [Item] = []
    /// The requests a `performChanges` block is making, while it runs.
    static var pending: [Item]?
    static var pendingImages: [AnyObject] = []
    static var pendingFiles: [(URL, Bool)] = []

    static var deniedError: Error {
        #if canImport(Photos)
        return PHPhotosError(.accessUserDenied)
        #else
        return CocoaError(.userCancelled)
        #endif
    }
}

extension PhotosBridges {
    static func status(_ s: KilnPermissionStatus) -> KV {
        switch s {
        case .allowed: return .native(.implicit("authorized", []))
        case .denied: return .native(.implicit("denied", []))
        case .notAsked: return .native(.implicit("notDetermined", []))
        }
    }

    /// `PHPhotoLibrary`'s static and instance members.
    static func saving(_ t: KTypeBuilder) {
        for sig in ["for:any", ""] {
            t.staticMethod("authorizationStatus", sig) { c in status(c.context.capabilities.status(.photoLibraryAdd)) }
        }
        // `await PHPhotoLibrary.requestAuthorization(for: .addOnly)`.
        t.staticMethod("requestAuthorization", "for:any", async: true) { c in
            let context = c.context
            return .suspension(KSuspension.async(headless: { status(context.capabilities.gate.answerWithoutAsking(.photoLibraryAdd) ? .allowed : .denied) }) {
                status(await context.capabilities.ask(.photoLibraryAdd) ? .allowed : .denied)
            })
        }
        for sig in ["for:any handler:closure", "_:closure"] {
            t.staticMethod("requestAuthorization", sig) { c in
                guard let f = c.function("handler") ?? c.function(0) else { return .void }
                let context = c.context, interp = c.interp
                if interp.headless || context.isStub {
                    interp.perform(f, [status(context.capabilities.gate.answerWithoutAsking(.photoLibraryAdd) ? .allowed : .denied)])
                    return .void
                }
                Task { @MainActor in
                    let allowed = await context.capabilities.ask(.photoLibraryAdd)
                    interp.perform(f, [status(allowed ? .allowed : .denied)])
                }
                return .void
            }
        }
        t.method("performChanges", "_:closure", async: true) { c in
            guard let f = c.function(0) else { return .void }
            let interp = c.interp, context = c.context
            let changes = try collect(f, interp)
            return .suspension(KSuspension.async(headless: { record(changes); return .void }) {
                if context.isStub { record(changes); return .void }
                guard await context.capabilities.ask(.photoLibraryAdd) else { throw thrown(KPhotoSaves.deniedError) }
                do { try await perform(changes) } catch { throw thrown(error) }
                return .void
            })
        }
        t.method("performChanges", "_:closure completionHandler:closure?") { c in
            guard let f = c.function(0) else { return .void }
            let interp = c.interp, context = c.context
            let done = c.function("completionHandler")
            let changes = try collect(f, interp)
            @MainActor func finish(_ error: Error?) {
                interp.perform(done, [.bool(error == nil), error.map { KBuiltins.errorValue(($0 as NSError).localizedDescription) } ?? .nilValue])
            }
            if interp.headless || context.isStub { record(changes); finish(nil); return .void }
            Task { @MainActor in
                guard await context.capabilities.ask(.photoLibraryAdd) else { finish(KPhotoSaves.deniedError); return }
                do { try await perform(changes); finish(nil) } catch { finish(error) }
            }
            return .void
        }
    }

    /// An error the app's `catch` gets, worded as Foundation words it.
    @MainActor static func thrown(_ error: Error) -> KEThrown {
        KEThrown(value: KBuiltins.errorValue((error as NSError).localizedDescription))
    }

    /// The requests a `performChanges` block makes, gathered as it runs.
    struct Changes {
        var images: [AnyObject] = []
        var files: [(URL, Bool)] = []
        var items: [KPhotoSaves.Item] = []
    }

    @MainActor static func collect(_ f: KFunction, _ interp: KInterpreter) throws -> Changes {
        KPhotoSaves.pending = []
        KPhotoSaves.pendingImages = []
        KPhotoSaves.pendingFiles = []
        defer { KPhotoSaves.pending = nil }
        _ = try interp.entry { try interp.call(f, [], []) }
        return Changes(images: KPhotoSaves.pendingImages, files: KPhotoSaves.pendingFiles, items: KPhotoSaves.pending ?? [])
    }

    @MainActor static func record(_ changes: Changes) { KPhotoSaves.saved += changes.items }

    @MainActor static func perform(_ changes: Changes) async throws {
        #if canImport(Photos) && canImport(UIKit)
        let images = changes.images.compactMap { $0 as? UIImage }
        let files = changes.files
        try await PHPhotoLibrary.shared().performChanges {
            for image in images { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            for (url, isVideo) in files {
                if isVideo { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
            }
        }
        #endif
    }

    static func saving(_ r: KRegistry) {
        r.type("PHAssetChangeRequest", .photos, support: .partial, notes: "Inside `PHPhotoLibrary.shared().performChanges { … }`: adding photos and videos.") { t in
            t.staticMethod("creationRequestForAsset", "from:any") { c in
                #if canImport(UIKit)
                guard let image = KCall.objectValue(c["from"]) as? UIImage else { throw c.fail("needs a UIImage") }
                try inBlock(c)
                KPhotoSaves.pendingImages.append(image)
                KPhotoSaves.pending?.append(.image(width: Int(image.size.width), height: Int(image.size.height)))
                #endif
                return .native(.object("PHAssetChangeRequest", KRef(NSObject())))
            }
            for (name, video) in [("creationRequestForAssetFromImage", false), ("creationRequestForAssetFromVideo", true)] {
                t.staticMethod(name, "atFileURL:URL") { c in
                    let url = try FoundationBridges.file(c, "atFileURL")
                    try inBlock(c)
                    KPhotoSaves.pendingFiles.append((url, video))
                    KPhotoSaves.pending?.append(video ? .video(url.lastPathComponent) : .file(url.lastPathComponent))
                    return .native(.object("PHAssetChangeRequest", KRef(NSObject())))
                }
            }
            t.property("placeholderForCreatedAsset") { _ in .nilValue }
        }
        r.type("PHAuthorizationStatus", .photos, support: .full) { t in
            t.internal()
            for n in ["notDetermined", "restricted", "denied", "authorized", "limited"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.type("PHAccessLevel", .photos, support: .full) { t in
            t.internal()
            for n in ["addOnly", "readWrite"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }

        // UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil), or with the app's
        // object and `#selector(image(_:didFinishSavingWithError:contextInfo:))`.
        r.function("UIImageWriteToSavedPhotosAlbum", .photos, "_:any _:any _:any _:any", owner: "UIKit",
                   notes: "Asks first (Shelf's sheet, then iOS's). With a target, its `image(_:didFinishSavingWithError:contextInfo:)` hears how it went.") { c in
            #if canImport(UIKit)
            guard let image = KCall.objectValue(c[0]) as? UIImage else { throw c.fail("needs a UIImage") }
            save(c, target: c[1], selectorArgs: [c[0] ?? .nilValue], item: .image(width: Int(image.size.width), height: Int(image.size.height))) {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                    KImageSaver.save(image) { error in if let error { done.resume(throwing: error) } else { done.resume() } }
                }
            }
            #endif
            return .void
        }
        r.function("UISaveVideoAtPathToSavedPhotosAlbum", .photos, "_:string _:any _:any _:any", owner: "UIKit") { c in
            #if canImport(UIKit)
            let url = try FoundationBridges.file(c, 0)
            save(c, target: c[1], selectorArgs: [.string(c.string(0) ?? "")], item: .video(url.lastPathComponent)) {
                try await PHPhotoLibrary.shared().performChanges { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
            }
            #endif
            return .void
        }
        r.function("UIVideoAtPathIsCompatibleWithSavedPhotosAlbum", .photos, "_:string", owner: "UIKit") { _ in .bool(true) }
    }

    @MainActor static func inBlock(_ c: KCall) throws {
        if KPhotoSaves.pending == nil { throw c.fail("call it inside PHPhotoLibrary.shared().performChanges { … }") }
    }

    /// Asks, saves, and tells the app's target (`image(_:didFinishSavingWithError:contextInfo:)`
    /// or `video(_:didFinishSavingWithError:contextInfo:)`) how it went.
    @MainActor static func save(_ c: KCall, target: KV?, selectorArgs: [KV], item: KPhotoSaves.Item, _ write: @escaping @MainActor () async throws -> Void) {
        let context = c.context, interp = c.interp
        let method = { if case .video = item { return "video" }; return "image" }()
        @MainActor func tell(_ error: Error?) {
            guard let target, !target.isNil, var app = KAppValue(target, interp),
                  app.implements(method, labels: [nil, "didFinishSavingWithError", "contextInfo"]) else { return }
            let e = error.map { KBuiltins.errorValue(($0 as NSError).localizedDescription) } ?? .nilValue
            _ = app.callReporting(method, selectorArgs + [e, .nilValue], labels: [nil, "didFinishSavingWithError", "contextInfo"], fallback: .nilValue)
        }
        if interp.headless || context.isStub {
            if context.capabilities.gate.answerWithoutAsking(.photoLibraryAdd) { KPhotoSaves.saved.append(item); tell(nil) } else { tell(KPhotoSaves.deniedError) }
            return
        }
        Task { @MainActor in
            guard await context.capabilities.ask(.photoLibraryAdd) else { tell(KPhotoSaves.deniedError); return }
            do { try await write(); tell(nil) } catch { tell(error) }
        }
    }
}

#if canImport(UIKit)
/// The target `UIImageWriteToSavedPhotosAlbum` calls back.
final class KImageSaver: NSObject {
    private let done: (Error?) -> Void
    private static var saving: Set<KImageSaver> = []

    private init(_ done: @escaping (Error?) -> Void) { self.done = done }

    @MainActor static func save(_ image: UIImage, _ done: @escaping (Error?) -> Void) {
        let saver = KImageSaver(done)
        saving.insert(saver)
        UIImageWriteToSavedPhotosAlbum(image, saver, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        done(error)
        MainActor.assumeIsolated { _ = Self.saving.remove(self) }
    }
}
#endif
