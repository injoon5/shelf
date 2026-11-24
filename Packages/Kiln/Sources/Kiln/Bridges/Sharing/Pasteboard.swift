//
//  Pasteboard.swift
//  Bridges: UIPasteboard.general (PLAN.md §3.2)
//
//      UIPasteboard.general.string = code
//      if UIPasteboard.general.hasStrings { text = UIPasteboard.general.string ?? "" }
//
//  On the phone it's the system pasteboard, so reading what another app
//  copied shows iOS's "Allow Paste" prompt, as it would for a compiled app
//  (`hasStrings`, `hasURLs` and `hasImages` never do). A check, a stub
//  context, or a test reads and writes a pasteboard of its own
//  (`KilnPasteboard.memory`), unless the host provides one.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// The pasteboard an app's `UIPasteboard.general` is. Hosts and tests can
/// `context.provide(KilnPasteboard.memory())` to keep a run off the system's.
public final class KilnPasteboard {
    public enum Item: Equatable {
        case string(String)
        case url(URL)
        case image(Data)
    }

    /// nil: the system pasteboard.
    var items: [Item]?
    public private(set) var changeCount = 0

    init(system: Bool) { items = system ? nil : [] }

    /// A pasteboard of its own, empty.
    public static func memory() -> KilnPasteboard { KilnPasteboard(system: false) }

    /// What a test reads back.
    public var strings: [String] { read { if case .string(let s) = $0 { return s }; return nil } }

    @MainActor static func forRun(_ c: KCall) -> KilnPasteboard {
        if let p = c.context.provided(KilnPasteboard.self) { return p }
        if c.context.isStub {
            let p = KilnPasteboard.memory()
            c.context.provide(p)
            return p
        }
        #if os(iOS)
        return system
        #else
        let p = KilnPasteboard.memory()
        c.context.provide(p)
        return p
        #endif
    }

    @MainActor static let system = KilnPasteboard(system: true)

    func read<T>(_ pick: (Item) -> T?) -> [T] {
        if let items { return items.compactMap(pick) }
        #if os(iOS)
        let pb = UIPasteboard.general
        var out: [Item] = []
        if T.self == String.self { out = (pb.strings ?? []).map { .string($0) } }
        else if T.self == URL.self { out = (pb.urls ?? []).map { .url($0) } }
        else { out = (pb.images ?? []).compactMap { $0.pngData() }.map { .image($0) } }
        return out.compactMap(pick)
        #else
        return []
        #endif
    }

    func write(_ new: [Item]) {
        changeCount += 1
        if items != nil { items = new; return }
        #if os(iOS)
        let pb = UIPasteboard.general
        pb.items = new.map { item -> [String: Any] in
            switch item {
            case .string(let s): return [UTType.utf8PlainText.identifier: s]
            case .url(let u): return [UTType.url.identifier: u]
            case .image(let d): return [UTType.png.identifier: d]
            }
        }
        #endif
    }

    /// Whether it has strings, URLs or images, without reading them (so without a prompt).
    func has(_ kind: String) -> Bool {
        if let items {
            return items.contains { item in
                switch (item, kind) {
                case (.string, "strings"), (.url, "urls"), (.image, "images"): return true
                default: return false
                }
            }
        }
        #if os(iOS)
        let pb = UIPasteboard.general
        switch kind {
        case "strings": return pb.hasStrings
        case "urls": return pb.hasURLs
        default: return pb.hasImages
        }
        #else
        return false
        #endif
    }

    var count: Int {
        if let items { return items.count }
        #if os(iOS)
        return UIPasteboard.general.numberOfItems
        #else
        return 0
        #endif
    }

    var systemChangeCount: Int {
        #if os(iOS)
        if items == nil { return UIPasteboard.general.changeCount }
        #endif
        return changeCount
    }
}

extension SharingBridges {
    static func pasteboard(_ r: KRegistry) {
        r.type("UIPasteboard", .sharing, support: .full,
               notes: "`UIPasteboard.general`: `string`, `strings`, `url`, `urls`, `image`, `images` (read and set), `hasStrings`, `hasURLs`, `hasImages`, `numberOfItems`, `changeCount`. Reading another app's copy shows iOS's Allow Paste prompt; `PasteButton` never does.") { t in
            t.staticProperty("general") { c in .native(.object("UIPasteboard", KRef(KilnPasteboard.forRun(c)))) }
            @MainActor func pb(_ c: KCall) -> KilnPasteboard { c.object(KilnPasteboard.self) ?? KilnPasteboard.forRun(c) }
            @MainActor func strings(_ c: KCall) -> [String] { pb(c).read { if case .string(let s) = $0 { return s }; return nil } }
            @MainActor func urls(_ c: KCall) -> [URL] { pb(c).read { if case .url(let u) = $0 { return u }; return nil } }
            @MainActor func images(_ c: KCall) -> [KV] {
                pb(c).read { if case .image(let d) = $0 { return d }; return nil }.compactMap { KShare.imageValue($0, uiImage: true) }
            }
            @MainActor func imageData(_ v: KV) -> Data? {
                #if canImport(UIKit)
                if case .native(.object("UIImage", let ref)) = v { return (ref.value as? UIImage)?.pngData() }
                #endif
                return nil
            }
            @MainActor func values(_ c: KCall) -> [KV] { c.args.first.flatMap { $0.isNil ? [] : ((try? c.interp.sequence($0)) ?? [$0]) } ?? [] }

            t.property("string", { c in strings(c).first.map { .string($0) } ?? .nilValue }, set: { c in
                pb(c).write(c.args.first?.asString.map { [.string($0)] } ?? [])
            })
            t.property("strings", { c in .array(strings(c).map { .string($0) }) }, set: { c in
                pb(c).write(values(c).map { .string($0.asString ?? c.interp.describe($0)) })
            })
            t.property("url", { c in urls(c).first.map { .native(.url($0)) } ?? .nilValue }, set: { c in
                pb(c).write(c.url(0).map { [.url($0)] } ?? [])
            })
            t.property("urls", { c in .array(urls(c).map { .native(.url($0)) }) }, set: { c in
                pb(c).write(values(c).compactMap { v in if case .native(.url(let u)) = v { return .url(u) }; return nil })
            })
            t.property("image", { c in images(c).first ?? .nilValue }, set: { c in
                pb(c).write(c.args.first.flatMap(imageData).map { [.image($0)] } ?? [])
            })
            t.property("images", { c in .array(images(c)) }, set: { c in
                pb(c).write(values(c).compactMap(imageData).map { .image($0) })
            })
            t.property("hasStrings") { c in .bool(pb(c).has("strings")) }
            t.property("hasURLs") { c in .bool(pb(c).has("urls")) }
            t.property("hasImages") { c in .bool(pb(c).has("images")) }
            t.property("numberOfItems") { c in .int(pb(c).count) }
            t.property("changeCount") { c in .int(pb(c).systemChangeCount) }
        }
    }
}
