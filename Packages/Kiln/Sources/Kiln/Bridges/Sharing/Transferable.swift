//
//  Transferable.swift
//  Bridges: the app's own `Transferable` types (PLAN.md §1.5, §3.2)
//
//      struct Note: Codable, Transferable {
//          var text: String
//          static var transferRepresentation: some TransferRepresentation {
//              CodableRepresentation(contentType: .json)
//              ProxyRepresentation(exporting: \.text)
//          }
//      }
//
//  The app's `transferRepresentation` runs through `TransferRepresentationBuilder`
//  into a list of representations (`KTransferRep`). `KTransferItem` is the
//  native `Transferable` standing for the app's value: it offers, in order, a
//  URL and a string (from `ProxyRepresentation`s), then data in each content
//  type the representations export (Codable as JSON, `DataRepresentation`s).
//  Importing goes the other way (`KTransferables.importValue`), for
//  `PasteButton` and `.pasteDestination` (Sharing.swift) and Round 3's drop and
//  file importer.
//

import SwiftUI
import UniformTypeIdentifiers

/// One representation the app declared.
final class KTransferRep {
    enum Kind {
        case codable(UTType)
        case data(exported: UTType?, imported: UTType?, export: KFunction?, importing: KFunction?)
        /// `ProxyRepresentation`: `exporting` is a closure or a key path.
        case proxy(exporting: KV?, importing: KFunction?)
        case file(exported: UTType?, imported: UTType?)
    }
    let kind: Kind
    var suggestedFileName: String?
    var condition: KFunction?
    init(_ kind: Kind) { self.kind = kind }
}

extension SharingBridges {
    static func transferable(_ r: KRegistry) {
        r.protocolBridge("Transferable", .sharing, requirements: ["static transferRepresentation"], support: .partial,
                         notes: "For `ShareLink`, `PasteButton` and paste: `CodableRepresentation`, `DataRepresentation`, `ProxyRepresentation`.") { app in
            KTransferItem(app)
        }
        r.resultBuilder("TransferRepresentationBuilder", .sharing) { b in
            b.method("buildBlock") { parts, _, _ in .array(parts.flatMap { $0.asArray ?? [$0] }) }
            b.method("buildPartialBlock") { parts, _, _ in .array(parts.flatMap { $0.asArray ?? [$0] }) }
            b.method("buildExpression") { args, _, _ in args.first ?? .void }
            b.method("buildOptional") { args, _, _ in args.first.flatMap { $0.isNil ? nil : $0 } ?? .array([]) }
            b.method("buildEither") { args, _, _ in args.first ?? .array([]) }
            b.method("buildArray") { args, _, _ in .array((args.first?.asArray ?? []).flatMap { $0.asArray ?? [$0] }) }
            b.method("buildLimitedAvailability") { args, _, _ in args.first ?? .array([]) }
        }

        @MainActor func rep(_ k: KTransferRep.Kind) -> KV { .native(.object("TransferRepresentation", KRef(KTransferRep(k)))) }
        r.type("CodableRepresentation", .sharing) { t in
            t.initializer("contentType:UTType") { c in rep(.codable(FilesBridges.utType(c.args[0]) ?? .json)) }
            t.initializer("for:any contentType:UTType") { c in rep(.codable(FilesBridges.utType(c.args[1]) ?? .json)) }
        }
        r.type("DataRepresentation", .sharing) { t in
            t.initializer("contentType:UTType exporting:closure importing:closure") { c in
                rep(.data(exported: FilesBridges.utType(c.args[0]), imported: FilesBridges.utType(c.args[0]), export: c.function("exporting"), importing: c.function("importing")))
            }
            t.initializer("exportedContentType:UTType exporting:closure") { c in
                rep(.data(exported: FilesBridges.utType(c.args[0]), imported: nil, export: c.function("exporting"), importing: nil))
            }
            t.initializer("importedContentType:UTType importing:closure") { c in
                rep(.data(exported: nil, imported: FilesBridges.utType(c.args[0]), export: nil, importing: c.function("importing")))
            }
        }
        r.type("ProxyRepresentation", .sharing) { t in
            // `exporting:` is a function (a key path works as one), so `ProxyRepresentation { $0.text }` exports.
            t.initializer("exporting:closure importing:closure?") { c in rep(.proxy(exporting: c.args[0], importing: c.function("importing"))) }
            t.initializer("importing:closure") { c in rep(.proxy(exporting: nil, importing: c.function("importing"))) }
        }
        r.type("FileRepresentation", .sharing, support: .stub, notes: "Accepted; files are Round 3's (§4.1).") { t in
            for sig in ["contentType:UTType exporting:closure importing:closure", "exportedContentType:UTType exporting:closure",
                        "importedContentType:UTType importing:closure"] {
                t.initializer(sig) { c in rep(.file(exported: FilesBridges.utType(c.args[0]), imported: FilesBridges.utType(c.args[0]))) }
            }
        }
        r.type("TransferRepresentation", .sharing) { t in
            @MainActor func receiver(_ c: KCall) -> KTransferRep? { KCall.objectValue(c.receiver) as? KTransferRep }
            t.method("suggestedFileName", "_:string") { c in receiver(c)?.suggestedFileName = c.string(0); return c.receiver }
            t.method("exportingCondition", "_:closure") { c in receiver(c)?.condition = c.function(0); return c.receiver }
            t.method("visibility", "_:any") { c in c.receiver }
        }
        r.type("SharePreview", .sharing, support: .full) { t in
            for sig in ["_:title", "_:title image:any", "_:title icon:any", "_:title image:any icon:any"] {
                t.initializer(sig) { c in .native(.object("SharePreview", KRef(KSharePreview(title: c.title(0), image: c["image"], icon: c["icon"])))) }
            }
        }
    }
}

final class KSharePreview {
    let title: String
    let image: KV?
    let icon: KV?
    init(title: String, image: KV?, icon: KV? = nil) {
        self.title = title
        self.image = image
        self.icon = icon
    }
}

@MainActor
enum KTransferables {
    /// The representations the app's type declares, in order.
    static func representations(_ t: KType, _ interp: KInterpreter) throws -> [KTransferRep] {
        guard let decl = t.staticDecls["transferRepresentation"] else { return [] }
        let env = KEnv(parent: interp.globalEnv, selfContext: KSelfContext(type: t, location: .box(KBox(.type(.user(t)))), isStatic: true))
        var v: KV
        if let getter = decl.getter {
            // Swift applies `@TransferRepresentationBuilder` from the requirement.
            guard let b = interp.builder([KEAttribute(name: "TransferRepresentationBuilder", args: [])]) else { return [] }
            v = try interp.entry { try interp.runBuilt(b, getter, env, line: decl.line) }
        } else if let initial = decl.initial {
            v = try interp.entry { try interp.eval(initial, env) }
        } else {
            return []
        }
        if case .native(.object("TransferRepresentation", _)) = v { v = .array([v]) }
        return (v.asArray ?? []).compactMap { KCall.objectValue($0) as? KTransferRep }
    }

    /// What `exporting:` makes of the item: a key path's value or the closure's.
    static func apply(_ exporting: KV, to item: KV, _ interp: KInterpreter) async throws -> KV {
        switch exporting {
        case .native(.keyPath(let comps)):
            var v = item
            for name in comps { v = try interp.member(v, name, line: 0) }
            return v
        case .function(let f):
            return try await interp.callAwaiting(f, [item])
        default:
            return .nilValue
        }
    }

    static func applySync(_ exporting: KV, to item: KV, _ interp: KInterpreter) -> KV? {
        switch exporting {
        case .native(.keyPath(let comps)):
            var v = item
            for name in comps { guard let next = try? interp.member(v, name, line: 0) else { return nil }; v = next }
            return v
        case .function(let f):
            guard let v = try? interp.entry({ try interp.call(f, [item], [nil]) }), v.asSuspension == nil else { return nil }
            return v
        default:
            return nil
        }
    }

    static func allowed(_ rep: KTransferRep, _ item: KV, _ interp: KInterpreter) -> Bool {
        guard let cond = rep.condition else { return true }
        return (try? interp.entry { interp.truthy(try interp.call(cond, [item], [nil])) }) ?? false
    }

    /// The item as data of `type`, by the first representation that exports it.
    static func data(_ item: KV, as type: UTType, _ interp: KInterpreter) async throws -> Data? {
        guard let t = item.userType else { return nil }
        for rep in try representations(t, interp) where allowed(rep, item, interp) {
            switch rep.kind {
            case .codable(let ct) where ct.conforms(to: type) || type.conforms(to: ct):
                let json = try KBuiltins.encode(item, KEncoderBox(), interp, 0)
                return try JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed, .sortedKeys])
            case .data(let exported?, _, let export?, _) where exported.conforms(to: type) || type.conforms(to: exported):
                return KBuiltins.dataValue(try await interp.callAwaiting(export, [item]))
            case .proxy(let exporting?, _):
                let v = try await apply(exporting, to: item, interp)
                if let s = v.asString, type.conforms(to: .plainText) || type == .data { return Data(s.utf8) }
                if v.userType?.conforms("Transferable") == true, let d = try await data(v, as: type, interp) { return d }
            default:
                continue
            }
        }
        return nil
    }

    /// The content types the item exports, in the app's order.
    static func exportedTypes(_ item: KV, _ interp: KInterpreter) -> [UTType] {
        guard let t = item.userType, let reps = try? representations(t, interp) else { return [] }
        var out: [UTType] = []
        for rep in reps where allowed(rep, item, interp) {
            switch rep.kind {
            case .codable(let ct): out.append(ct)
            case .data(let exported?, _, _, _): out.append(exported)
            case .proxy(let exporting?, _):
                guard let v = applySync(exporting, to: item, interp) else { continue }
                if v.asString != nil { out.append(.utf8PlainText) }
                if case .native(.url) = v { out.append(.url) }
                if v.userType != nil { out += exportedTypes(v, interp) }
            default: continue
            }
        }
        return out
    }

    /// A value of the app's type `t` from `data`, by the first representation
    /// that imports `contentType`: what paste, drop and the file importer use.
    static func importValue(_ t: KType, data: Data, contentType: UTType, _ interp: KInterpreter) async throws -> KV? {
        for rep in try representations(t, interp) {
            switch rep.kind {
            case .codable(let ct) where contentType.conforms(to: ct):
                let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                return try KBuiltins.decode(json, as: .named(t.name, []), KDecoderBox(), interp, 0)
            case .data(_, let imported?, _, let importing?) where contentType.conforms(to: imported):
                return try await interp.callAwaiting(importing, [KBuiltins.data(data)])
            case .proxy(_, let importing?) where contentType.conforms(to: .plainText):
                return try await interp.callAwaiting(importing, [.string(String(decoding: data, as: UTF8.self))])
            default:
                continue
            }
        }
        return nil
    }
}

/// The app's `Transferable` value as SwiftUI shares it. A URL and a string
/// it exports through `ProxyRepresentation` are worked out when it's made;
/// data is made when the receiver asks, by the app's code on the main actor.
struct KTransferItem: Transferable, @unchecked Sendable {
    let item: KV
    let interp: KInterpreter
    let types: [UTType]
    let string: String?
    let url: URL?

    @MainActor init(_ app: KAppValue) {
        item = app.value
        interp = app.interp
        types = KTransferables.exportedTypes(app.value, app.interp)
        var string: String?, url: URL?
        if let reps = try? KTransferables.representations(app.type, app.interp) {
            for rep in reps where KTransferables.allowed(rep, app.value, app.interp) {
                guard case .proxy(let exporting?, _) = rep.kind, let v = KTransferables.applySync(exporting, to: app.value, app.interp) else { continue }
                if string == nil, let s = v.asString { string = s }
                if url == nil, case .native(.url(let u)) = v { url = u }
            }
        }
        self.string = string
        self.url = url
    }

    func exports(_ type: UTType) -> Bool { types.contains { $0.conforms(to: type) } }

    func data(_ type: UTType) async throws -> Data {
        let item = KUnsafeSendable(self.item), interp = KUnsafeSendable(self.interp)
        let d = try await Task { @MainActor in try await KTransferables.data(item.value, as: type, interp.value) }.value
        guard let d else { throw CocoaError(.fileWriteUnknown) }
        return d
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (i: KTransferItem) -> URL in i.url ?? URL(string: "about:blank")! }).exportingCondition { $0.url != nil }
        ProxyRepresentation(exporting: { (i: KTransferItem) -> String in i.string ?? "" }).exportingCondition { $0.string != nil && $0.url == nil }
        DataRepresentation(exportedContentType: .json) { try await $0.data(.json) }.exportingCondition { $0.exports(.json) }
        DataRepresentation(exportedContentType: .commaSeparatedText) { try await $0.data(.commaSeparatedText) }.exportingCondition { $0.exports(.commaSeparatedText) }
        DataRepresentation(exportedContentType: .png) { try await $0.data(.png) }.exportingCondition { $0.exports(.png) }
        DataRepresentation(exportedContentType: .jpeg) { try await $0.data(.jpeg) }.exportingCondition { $0.exports(.jpeg) }
        DataRepresentation(exportedContentType: .pdf) { try await $0.data(.pdf) }.exportingCondition { $0.exports(.pdf) }
        DataRepresentation(exportedContentType: .plainText) { try await $0.data(.plainText) }.exportingCondition { $0.string == nil && $0.exports(.plainText) }
        DataRepresentation(exportedContentType: .data) { try await $0.data(.data) }
            .exportingCondition { i in !i.types.isEmpty && !i.types.contains { [.json, .commaSeparatedText, .png, .jpeg, .pdf, .plainText].contains($0) } }
    }
}

extension KType {
    func conforms(_ p: String) -> Bool { conformances.contains(p) }
}
