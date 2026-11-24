//
//  Sharing.swift
//  Bridges: share links, paste, copy and text selection (PLAN.md §3.2)
//
//  `ShareLink` is SwiftUI's own, for one item or an array of them: a
//  `String`, a `URL`, an `Image`, `Data`, or the app's own `Transferable`
//  (Transferable.swift), with `subject:`, `message:`, a `SharePreview` or a
//  closure that makes one per item, and a title or a label.
//
//  `PasteButton(payloadType:)` is SwiftUI's too: iOS shows it as the system's
//  paste control, so pasting from it never asks. `UIPasteboard.general` is
//  in Pasteboard.swift.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

@objc(KilnBridges_Sharing)
final class SharingBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        transferable(r)
        pasteboard(r)
        r.view("ShareLink", .sharing,
               notes: "A `String`, `URL`, `Image`, `Data` or your `Transferable`, or `items:` an array of one of them; `preview:` a `SharePreview` or a closure per item.") { v in
            for items in ["item:any", "items:any"] {
                // A preview closure as the first trailing closure, then `label:`:
                // `ShareLink(items: notes) { note in SharePreview(…) } label: { … }`.
                v.forms(["\(items) subject:any? message:any? preview:closure label:content",
                         "\(items) subject:any? message:any? preview:any?", "_:title \(items) subject:any? message:any? preview:any?",
                         "\(items) subject:any? message:any? preview:any? label:content"]) { c in shareLink(c) }
            }
        }
        r.view("PasteButton", .sharing,
               notes: "`PasteButton(payloadType: String.self) { strings in … }`: `String`, `URL`, `Data`, `Image` or your `Transferable` type.") { v in
            v.form("payloadType:any onPaste:closure") { c in pasteButton(c) }
            v.probe { _, args, interp in
                guard case .function(let f)? = args.lastFunction else { return [] }
                return [KProbeCall(fn: f, args: [KShare.samples(args["payloadType"], interp)], use: .action)]
            }
        }
        textSelection(r)
        editCommands(r)
    }

    // MARK: ShareLink

    @MainActor static func shareLink(_ c: KCall) -> AnyView {
        let title = ControlsBridges.stringTitle(c)
        let subject = c["subject"].flatMap { KShare.text($0, c) }
        let message = c["message"].flatMap { KShare.text($0, c) }
        let values: [KV] = c["item"].map { [$0] } ?? (c["items"].map { (try? c.interp.sequence($0)) ?? [] } ?? [])
        let label: AnyView? = c.has("label") ? c.content("label") : nil
        let links = KShare.Links(title: title, subject: subject, message: message, label: label)

        // One `SharePreview`, or a closure that makes one for each item.
        let previewArg = c["preview"]
        var previews: [KSharePreview?]
        if case .function(let f)? = previewArg {
            previews = values.map { v in KHaptics.ask(c.interp, f, [v]).flatMap { KCall.objectValue($0) as? KSharePreview } }
        } else {
            let one = KCall.objectValue(previewArg) as? KSharePreview
            previews = values.map { _ in one }
        }
        let hasPreview = previews.contains { $0 != nil }
        let fallback = title ?? "Share"

        switch KShare.kind(values, c.interp) {
        case .strings(let s):
            return hasPreview ? links.previewed(s, previews, c, fallback) : links.plain(s)
        case .urls(let u):
            return hasPreview ? links.previewed(u, previews, c, fallback) : links.plain(u)
        case .data(let d):
            return links.previewed(d, previews, c, fallback)
        case .images(let i):
            return links.previewed(i, previews, c, fallback)
        case .app(let a):
            return links.previewed(a, previews, c, fallback)
        case .none(let why):
            c.interp.report(c.fail(why))
            return AnyView(Label(fallback, systemImage: "square.and.arrow.up"))
        }
    }

    // MARK: PasteButton

    @MainActor static func pasteButton(_ c: KCall) -> AnyView {
        guard let f = c.function("onPaste") ?? c.function(0) else { return AnyView(EmptyView()) }
        let interp = c.interp
        let line = c.line
        @MainActor func deliver(_ values: [KV]) {
            guard !values.isEmpty else { return }
            interp.perform(f, [.array(values)])
        }
        switch KShare.payloadName(c["payloadType"]) {
        case "String", "Substring":
            return AnyView(PasteButton(payloadType: String.self) { items in Task { @MainActor in deliver(items.map { .string($0) }) } })
        case "URL":
            return AnyView(PasteButton(payloadType: URL.self) { items in Task { @MainActor in deliver(items.map { .native(.url($0)) }) } })
        case "Data":
            return AnyView(PasteButton(payloadType: Data.self) { items in Task { @MainActor in deliver(items.map { KBuiltins.data($0) }) } })
        case "Image", "UIImage":
            let asUIImage = KShare.payloadName(c["payloadType"]) == "UIImage"
            return AnyView(PasteButton(payloadType: KPastedImage.self) { items in
                Task { @MainActor in deliver(items.compactMap { KShare.imageValue($0.data, uiImage: asUIImage) }) }
            })
        default:
            guard case .type(.user(let t))? = c["payloadType"], t.conforms("Transferable") else {
                interp.report(c.fail("payloadType needs String.self, URL.self, Data.self, Image.self or your Transferable type"))
                return AnyView(EmptyView())
            }
            return AnyView(PasteButton(payloadType: KImportItem.self) { items in
                Task { @MainActor in
                    var out: [KV] = []
                    for item in items {
                        do {
                            if let v = try await KTransferables.importValue(t, data: item.data, contentType: item.type, interp) { out.append(v) }
                        } catch {
                            interp.report(KERuntimeError(message: "PasteButton: \(t.name) couldn't be made from what was pasted: \(error)", line: line))
                        }
                    }
                    deliver(out)
                }
            })
        }
    }

    // MARK: Text selection

    static func textSelection(_ r: KRegistry) {
        r.modifier("textSelection", .sharing, notes: "`.enabled` lets a person select and copy the text; `.disabled` turns it off again.") { m in
            m.form("_:TextSelectability") { c, view in
                if c.symbol(0) == "disabled" { view.textSelection(.disabled) } else { view.textSelection(.enabled) }
            }
        }
        r.type("TextSelectability", .sharing, support: .full) { t in
            t.internal()
            t.staticProperties(["enabled": .native(.implicit("enabled", [])), "disabled": .native(.implicit("disabled", []))])
        }
        r.modifier("textSelectionAffinity", .sharing, introduced: "18.0") { m in
            m.form("_:TextSelectionAffinity", introduced: "18.0") { c, view in
                if #available(iOS 18, macOS 15, *) {
                    view.textSelectionAffinity(KTextSelection.affinity(c.symbol(0)))
                } else {
                    view
                }
            }
        }
        r.type("TextSelectionAffinity", .sharing, support: .full, introduced: "18.0") { t in
            t.internal()
            for n in ["automatic", "upstream", "downstream"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.type("TextSelection", .sharing, support: .full, introduced: "18.0",
               notes: "`TextField(text:selection:)` and `TextEditor(text:selection:)` keep it; `.indices` is `.selection(range)` in character offsets, so `text[range]` reads it.") { t in
            t.initializer("range:any") { c in
                guard case .range(let lo, let hi, let closed)? = c["range"], let l = lo.asInt, let h = hi.asInt else { throw c.fail("needs a range") }
                return KTextSelection(ranges: [l..<(closed ? h + 1 : h)]).kv
            }
            t.initializer("insertionPoint:any") { c in
                guard let i = c["insertionPoint"]?.asInt else { throw c.fail("needs an index") }
                return KTextSelection(ranges: [i..<i]).kv
            }
            t.initializer("ranges:any") { c in
                let ranges = ((try? c.interp.sequence(c["ranges"] ?? .void)) ?? []).compactMap { v -> Range<Int>? in
                    guard case .range(let lo, let hi, let closed) = v, let l = lo.asInt, let h = hi.asInt else { return nil }
                    return l..<(closed ? h + 1 : h)
                }
                return KTextSelection(ranges: ranges).kv
            }
            @MainActor func sel(_ c: KCall) -> KTextSelection? {
                if case .native(.boxed(let b)) = c.receiver { return b.get(KTextSelection.self) }
                return nil
            }
            t.property("indices") { c in
                guard let s = sel(c) else { return .nilValue }
                if s.ranges.count == 1 { return .native(.implicit("selection", [.range(.int(s.ranges[0].lowerBound), .int(s.ranges[0].upperBound), closed: false)])) }
                return .native(.implicit("multiSelection", [.array(s.ranges.map { .range(.int($0.lowerBound), .int($0.upperBound), closed: false) })]))
            }
            t.property("isInsertion") { c in .bool(sel(c)?.isInsertion ?? true) }
            t.property("affinity") { c in .native(.implicit(sel(c)?.affinity ?? "automatic", [])) }
        }
    }

    // MARK: Copy, cut and paste commands (iOS 27)

    static func editCommands(_ r: KRegistry) {
        let note = "The Edit menu's and the keyboard's Copy, Cut and Paste for the focused view: `String`, `URL`, `Data` or your `Transferable`."
        r.modifier("copyable", .sharing, introduced: "27.0", notes: note) { m in
            m.form("_:any", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 13, *) {
                    let interp = c.interp
                    let items = c[0] ?? .array([])
                    view.copyable(KShare.transferItems(items, interp))
                } else {
                    view
                }
            }
        }
        r.modifier("cuttable", .sharing, introduced: "27.0", notes: note) { m in
            m.form("for:any? action:closure", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 13, *), let f = c.function("action") {
                    let interp = c.interp
                    view.cuttable(for: KShareItem.self) { KShare.transferItems(KHaptics.ask(interp, f, []) ?? .array([]), interp) }
                } else {
                    view
                }
            }
        }
        r.modifier("pasteDestination", .sharing, introduced: "27.0", notes: note) { m in
            m.form("for:any? action:closure validator:closure?", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 13, *), let f = c.function("action") {
                    let interp = c.interp
                    let type = c["for"]
                    let validator = c.function("validator")
                    view.pasteDestination(for: KImportItem.self, action: { items in
                        Task { @MainActor in
                            var values = await KShare.imported(items, as: type, interp)
                            if let validator, let kept = KHaptics.ask(interp, validator, [.array(values)]) { values = (try? interp.sequence(kept)) ?? values }
                            if !values.isEmpty { interp.perform(f, [.array(values)]) }
                        }
                    })
                } else {
                    view
                }
            }
            m.probe { _, args, interp in
                args.args.compactMap { v -> KProbeCall? in
                    guard case .function(let f) = v else { return nil }
                    return KProbeCall(fn: f, args: [KShare.samples(args["for"], interp)], use: .action)
                }
            }
        }
    }
}

/// A `TextSelection`: character offsets into the bound text.
struct KTextSelection: Hashable, KDescribable {
    var ranges: [Range<Int>]
    var affinity = "automatic"
    var isInsertion: Bool { ranges.allSatisfy(\.isEmpty) }
    var kv: KV { .native(.boxed(KBoxed("TextSelection", self))) }
    func describe(_ interp: KInterpreter) -> String {
        "TextSelection(" + ranges.map { "\($0.lowerBound)..<\($0.upperBound)" }.joined(separator: ", ") + ")"
    }

    @available(iOS 18, macOS 15, *)
    static func affinity(_ s: String?) -> TextSelectionAffinity {
        switch s {
        case "upstream": return .upstream
        case "downstream": return .downstream
        default: return .automatic
        }
    }

    /// SwiftUI's selection in `text`, as offsets.
    @available(iOS 18, macOS 15, *)
    init(_ s: TextSelection, in text: String) {
        func offset(_ i: String.Index) -> Int { text.distance(from: text.startIndex, to: min(max(i, text.startIndex), text.endIndex)) }
        switch s.indices {
        case .selection(let r): ranges = [offset(r.lowerBound)..<offset(r.upperBound)]
        case .multiSelection(let set): ranges = set.ranges.map { offset($0.lowerBound)..<offset($0.upperBound) }
        @unknown default: ranges = []
        }
        switch s.affinity {
        case .upstream: affinity = "upstream"
        case .downstream: affinity = "downstream"
        default: affinity = "automatic"
        }
    }

    init(ranges: [Range<Int>]) { self.ranges = ranges }

    /// The app's selection as SwiftUI's, in `text`.
    @available(iOS 18, macOS 15, *)
    func swiftUI(in text: String) -> TextSelection {
        func index(_ o: Int) -> String.Index { text.index(text.startIndex, offsetBy: min(max(o, 0), text.count)) }
        if ranges.count > 1 {
            return TextSelection(ranges: RangeSet(ranges.map { index($0.lowerBound)..<index($0.upperBound) }))
        }
        let r = ranges.first ?? 0..<0
        return r.isEmpty ? TextSelection(insertionPoint: index(r.lowerBound)) : TextSelection(range: index(r.lowerBound)..<index(r.upperBound))
    }

    /// A `selection:` binding over the app's `TextSelection?`, read against the text binding.
    @available(iOS 18, macOS 15, *)
    @MainActor static func binding(_ sel: KBinding, text: @escaping () -> String) -> Binding<TextSelection?> {
        Binding(get: {
            guard case .native(.boxed(let b)) = sel.get(), let s = b.get(KTextSelection.self) else { return nil }
            return s.swiftUI(in: text())
        }, set: { new in
            sel.set(new.map { KTextSelection($0, in: text()).kv } ?? .nilValue)
        })
    }
}

/// One item to share or copy, whatever its kind (the edit commands take one type).
struct KShareItem: Transferable, @unchecked Sendable {
    enum Value { case string(String), url(URL), data(Data), app(KTransferItem) }
    let value: Value
    var string: String? { if case .string(let s) = value { return s }; return nil }
    var url: URL? { if case .url(let u) = value { return u }; return nil }
    var app: KTransferItem? { if case .app(let a) = value { return a }; return nil }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (i: KShareItem) -> String in i.string ?? "" }).exportingCondition { $0.string != nil }
        ProxyRepresentation(exporting: { (i: KShareItem) -> URL in i.url ?? URL(string: "about:blank")! }).exportingCondition { $0.url != nil }
        ProxyRepresentation(exporting: { (i: KShareItem) -> KTransferItem in i.app! }).exportingCondition { $0.app != nil }
        DataRepresentation(exportedContentType: .data) { i in
            if case .data(let d) = i.value { return d }
            return Data()
        }.exportingCondition { if case .data = $0.value { return true }; return false }
    }
}

/// What a paste or a drop brings: its bytes and its content type, made into
/// the app's value by `KTransferables.importValue`.
struct KImportItem: Transferable, @unchecked Sendable {
    let data: Data
    let type: UTType

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .json) { KImportItem(data: $0, type: .json) }
        ProxyRepresentation(importing: { (u: URL) in KImportItem(data: Data(u.absoluteString.utf8), type: .url) })
        ProxyRepresentation(importing: { (s: String) in KImportItem(data: Data(s.utf8), type: .utf8PlainText) })
        DataRepresentation(importedContentType: .png) { KImportItem(data: $0, type: .png) }
        DataRepresentation(importedContentType: .jpeg) { KImportItem(data: $0, type: .jpeg) }
        DataRepresentation(importedContentType: .data) { KImportItem(data: $0, type: .data) }
    }
}

/// A pasted image, by its bytes.
struct KPastedImage: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { KPastedImage(data: $0) }
    }
}

@MainActor
enum KShare {
    enum Kind {
        case strings([String]), urls([URL]), data([Data]), images([Image]), app([KTransferItem])
        case none(String)
    }

    /// The items, all of one kind, as SwiftUI shares them.
    static func kind(_ values: [KV], _ interp: KInterpreter) -> Kind {
        guard let first = values.first else { return .strings([]) }
        switch first {
        case .string:
            return .strings(values.map { $0.asString ?? interp.describe($0) })
        case .native(.url):
            return .urls(values.compactMap { if case .native(.url(let u)) = $0 { return u }; return nil })
        case .native(.object("Data", _)):
            return .data(values.compactMap { KBuiltins.dataValue($0) })
        default:
            if image(first, interp) != nil { return .images(values.compactMap { image($0, interp) }) }
            let items = values.compactMap { interp.proxy(for: $0, as: "Transferable") as? KTransferItem }
            if items.count == values.count { return .app(items) }
            if let t = values.first(where: { interp.proxy(for: $0, as: "Transferable") == nil })?.userType {
                return .none("'\(t.name)' isn't Transferable: add `: Transferable` and `static var transferRepresentation`")
            }
            return .none("shares a String, URL, Image, Data or your Transferable type, not \(first.typeName)")
        }
    }

    /// An `Image` value (`Image("x")`, `Image(systemName:)`, `Image(uiImage:)`) or a `UIImage`.
    static func image(_ v: KV, _ interp: KInterpreter) -> Image? {
        switch v {
        case .view(let view):
            switch view.kind {
            case .image(let img): return img
            case .primitive("Image", let args, let labels, _):
                let a = KArgs(args: args, labels: labels)
                if let img = DrawingBridges.uiImageArgument(a) { return img }
                if let s = a["systemName"]?.asString { return Image(systemName: s) }
                if let n = a.first?.asString { return Kiln.hostImageProvider?(n) ?? Image(n) }
                return nil
            case .modified(let base, _): return image(.view(base), interp)
            default: return nil
            }
        case .native(.object("UIImage", let ref)):
            #if canImport(UIKit)
            if let ui = ref.value as? UIImage { return Image(uiImage: ui) }
            #endif
            return nil
        default:
            return nil
        }
    }

    /// A pasted image as the app's value.
    static func imageValue(_ data: Data, uiImage: Bool) -> KV? {
        #if canImport(UIKit)
        guard let ui = UIImage(data: data) else { return nil }
        return uiImage ? DrawingBridges.uiImage(ui) : .view(.image(Image(uiImage: ui)))
        #else
        return nil
        #endif
    }

    static func text(_ v: KV, _ c: KCall) -> Text? {
        if case .view(let t) = v { return c.r.text(t) }
        return c.r.string(v).map { Text($0) }
    }

    /// `String.self` → "String"; the app's type → its name.
    static func payloadName(_ v: KV?) -> String? {
        if case .type(let t)? = v { return t.name }
        return nil
    }

    /// What a check pastes: one value of the payload type (a word, a URL,
    /// empty data, an image), or nothing for the app's own type.
    static func samples(_ type: KV?, _ interp: KInterpreter) -> KV {
        switch payloadName(type) {
        case "URL": return .array([.native(.url(URL(string: "https://example.com")!))])
        case "Data": return .array([KBuiltins.data(Data())])
        case "Image": return .array([.view(.image(Image(systemName: "photo")))])
        case "String", "Substring", nil: return .array([.string("Pasted")])
        default: return .array([])
        }
    }

    /// Items to copy or cut.
    static func transferItems(_ v: KV, _ interp: KInterpreter) -> [KShareItem] {
        let values = (try? interp.sequence(v)) ?? [v]
        return values.compactMap { item in
            switch item {
            case .string(let s): return KShareItem(value: .string(s))
            case .native(.url(let u)): return KShareItem(value: .url(u))
            case .native(.object("Data", _)): return KBuiltins.dataValue(item).map { KShareItem(value: .data($0)) }
            default:
                if let t = interp.proxy(for: item, as: "Transferable") as? KTransferItem { return KShareItem(value: .app(t)) }
                return KShareItem(value: .string(interp.describe(item)))
            }
        }
    }

    /// Pasted items as the payload type's values.
    static func imported(_ items: [KImportItem], as type: KV?, _ interp: KInterpreter) async -> [KV] {
        var out: [KV] = []
        for item in items {
            switch payloadName(type) {
            case "String", nil:
                if item.type.conforms(to: .text) || item.type == .url { out.append(.string(String(decoding: item.data, as: UTF8.self))) }
            case "URL":
                if let u = URL(string: String(decoding: item.data, as: UTF8.self)), u.scheme != nil { out.append(.native(.url(u))) }
            case "Data":
                out.append(KBuiltins.data(item.data))
            default:
                if case .type(.user(let t))? = type, let v = try? await KTransferables.importValue(t, data: item.data, contentType: item.type, interp) {
                    out.append(v)
                }
            }
        }
        return out
    }

    /// One item with the index of its preview.
    struct Indexed<T: Transferable>: Transferable, @unchecked Sendable {
        let value: T
        let index: Int
        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation(exporting: \.value)
        }
    }

    /// ShareLink with its title or label, subject and message.
    struct Links {
        let title: String?
        let subject: Text?
        let message: Text?
        let label: AnyView?

        /// A `String` or a `URL`, which need no preview.
        @MainActor func plain(_ items: [String]) -> AnyView {
            if let label { return AnyView(ShareLink(items: items, subject: subject, message: message) { label }) }
            if let title { return AnyView(ShareLink(title, items: items, subject: subject, message: message)) }
            return AnyView(ShareLink(items: items, subject: subject, message: message))
        }
        @MainActor func plain(_ items: [URL]) -> AnyView {
            if let label { return AnyView(ShareLink(items: items, subject: subject, message: message) { label }) }
            if let title { return AnyView(ShareLink(title, items: items, subject: subject, message: message)) }
            return AnyView(ShareLink(items: items, subject: subject, message: message))
        }

        /// Anything, with each item's preview (the title when it has none).
        @MainActor func previewed<T: Transferable>(_ items: [T], _ previews: [KSharePreview?], _ c: KCall, _ fallback: String) -> AnyView {
            let indexed = items.enumerated().map { Indexed(value: $0.element, index: $0.offset) }
            let interp = c.interp
            func p(_ i: Int) -> KSharePreview? { i < previews.count ? previews[i] : previews.last ?? nil }
            let images = previews.map { $0?.image.flatMap { KShare.image($0, interp) } }
            let icons = previews.map { $0?.icon.flatMap { KShare.image($0, interp) } }
            func title(_ i: Int) -> String { p(i)?.title ?? fallback }
            func img(_ i: Int) -> Image { (i < images.count ? images[i] : nil) ?? images.compactMap { $0 }.first ?? Image(systemName: "doc") }
            func icon(_ i: Int) -> Image { (i < icons.count ? icons[i] : nil) ?? icons.compactMap { $0 }.first ?? Image(systemName: "doc") }
            let hasImage = images.contains { $0 != nil }, hasIcon = icons.contains { $0 != nil }
            if hasImage && hasIcon { return make(indexed) { SharePreview(title($0.index), image: img($0.index), icon: icon($0.index)) } }
            if hasImage { return make(indexed) { SharePreview(title($0.index), image: img($0.index)) } }
            if hasIcon { return make(indexed) { SharePreview(title($0.index), icon: icon($0.index)) } }
            return make(indexed) { SharePreview(title($0.index)) }
        }

        @MainActor func make<T: Transferable, I: Transferable, C: Transferable>(_ items: [Indexed<T>], _ preview: @escaping (Indexed<T>) -> SharePreview<I, C>) -> AnyView {
            if let label { return AnyView(ShareLink(items: items, subject: subject, message: message, preview: preview) { label }) }
            if let title { return AnyView(ShareLink(title, items: items, subject: subject, message: message, preview: preview)) }
            return AnyView(ShareLink(items: items, subject: subject, message: message, preview: preview))
        }
    }
}
