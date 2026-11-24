//
//  DragDrop.swift
//  Bridges: drag and drop (PLAN.md §4.1)
//
//  SwiftUI's own modifiers, with the app's values as SwiftUI's `Transferable`s:
//
//  - `.draggable(item)` (with a `preview:`) drags a `String`, `URL`, `Data`,
//    `Image`/`UIImage` or the app's `Transferable` (`KDragPayload`).
//  - `.dropDestination(for: T.self)` receives the same kinds (`KDropItem`),
//    in each of its forms: `{ items, location in … }` with `isTargeted:`,
//    iOS 26's `{ items, session in … }` with `isEnabled:`, and on a `ForEach`
//    `{ items, index in … }`. A dropped file is copied into the app's
//    temporary folder first, so the app's URL is its own.
//  - The older `NSItemProvider` API: `.onDrag`, `.itemProvider`, `.onDrop(of:…)`
//    with a closure or the app's `DropDelegate` (through `KDropDelegate`).
//  - iOS 27's drag containers: `.dragContainer(for:in:)` with
//    `.draggable(containerItemID:)` (or `draggable(_:item:)`),
//    `.dragContainerSelection`, `.dragConfiguration`, `.dropConfiguration`
//    and the session callbacks, whose ids are the app's own values (`KDragID`).
//  - `.springLoadingBehavior` and its environment value.
//
//  A check drops one sample item of the payload type and calls the session
//  callbacks once with an ended session.
//

import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

extension FilesBridges {
    static func dragAndDrop(_ r: KRegistry) {
        dragging(r)
        dropping(r)
        itemProviders(r)
        containers(r)
        springLoading(r)
    }

    // MARK: Payloads

    /// The payload type's name: `String.self` → "String".
    static func payloadName(_ v: KV?) -> String? { KShare.payloadName(v) }

    /// What a check drops: one value of the payload type.
    @MainActor static func samples(_ type: KV?, _ interp: KInterpreter) -> KV {
        switch payloadName(type) {
        case "UIImage":
            #if canImport(UIKit)
            return .array([DrawingBridges.uiImage(UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in })])
            #else
            return .array([])
            #endif
        default:
            return KShare.samples(type, interp)
        }
    }

    // MARK: .draggable

    static func dragging(_ r: KRegistry) {
        r.modifier("draggable", .files,
                   notes: "A `String`, `URL`, `Data`, `Image` or your `Transferable`, with `preview:`; in iOS 27's drag containers, `draggable(containerItemID:)` or `draggable(Item.self, item:)`.") { m in
            m.form("_:any") { c, view in draggable(c, view) }
            m.form("_:any preview:content") { c, view in draggable(c, view) }
            // iOS 27: an item of a drag container (`.dragContainer`).
            m.form("containerItemID:any containerNamespace:any?", introduced: "27.0") { c, view in containerDraggable(c, view) }
            m.form("_:any? item:any containerNamespace:any?", introduced: "27.0") { c, view in containerDraggable(c, view) }
            m.form("_:any? id:any item:any containerNamespace:any?", introduced: "27.0") { c, view in containerDraggable(c, view) }
            m.form("_:any? containerNamespace:any? _:closure", introduced: "27.0") { c, view in containerDraggable(c, view) }
            m.form("_:any? id:any containerNamespace:any? _:closure", introduced: "27.0") { c, view in containerDraggable(c, view) }
            m.form("_:any", receiver: "TabContent", introduced: "18.1") { _, view in view }
        }
        r.modifier("onDrag", .files, notes: "Returns an `NSItemProvider`; `.draggable` is simpler.") { m in
            m.form("_:closure") { c, view in onDrag(c, view) }
            m.form("_:closure preview:content") { c, view in onDrag(c, view) }
        }
        r.modifier("itemProvider", .files) { m in
            m.form("_:closure?") { c, view in
                guard let f = c.function(0) else { return AnyView(view.itemProvider(nil)) }
                let interp = c.interp
                return AnyView(view.itemProvider { KHaptics.ask(interp, f, []).flatMap { KCall.objectValue($0) as? NSItemProvider } })
            }
        }
    }

    @MainActor static func draggable(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let payload = KDragPayload.make(c[0] ?? .nilValue, c) else {
            c.interp.report(c.fail("drags a String, URL, Data, an Image or your Transferable type, not \((c[0] ?? .nilValue).typeName)"))
            return view
        }
        if c.has("preview") {
            let preview = c.content("preview")
            return AnyView(view.draggable(payload) { preview })
        }
        return AnyView(view.draggable(payload))
    }

    @MainActor static func onDrag(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let f = c.function(0) else { return view }
        let interp = c.interp
        let provide: () -> NSItemProvider = {
            KHaptics.ask(interp, f, []).flatMap { KCall.objectValue($0) as? NSItemProvider } ?? NSItemProvider()
        }
        if c.has("preview") {
            let preview = c.content("preview")
            return AnyView(view.onDrag(provide) { preview })
        }
        return AnyView(view.onDrag(provide))
    }

    // MARK: .dropDestination, .onDrop

    static func dropping(_ r: KRegistry) {
        r.modifier("dropDestination", .files,
                   notes: "`for: String.self` (or `URL`, `Data`, `Image`, your `Transferable`): `{ items, location in … return true }` with `isTargeted:`, iOS 26's `{ items, session in … }`, or on a `ForEach` `{ items, index in … }`. A dropped file arrives copied into the app's temporary folder.") { m in
            m.formOnBase("for:any? action:closure isTargeted:closure?") { c in dropDestination(c) }
            m.formOnBase("for:any? isEnabled:bool? action:closure", introduced: "26.0") { c in dropDestination(c) }
            m.form("for:any? action:closure", receiver: "TabContent", introduced: "18.0") { _, view in view }
            m.probe { base, args, interp in
                var calls: [KProbeCall] = []
                let items = samples(args["for"], interp)
                if case .function(let f)? = args["action"] {
                    let n = KRenderer(interp: interp).closureParamCount(.function(f))
                    let second: KV = base?.primitiveName == "ForEach" ? .int(0)
                        : (args["isEnabled"] != nil || takesSession(f) ? KDragSessions.endedDrop() : .native(.point(0, 0)))
                    calls.append(KProbeCall(fn: f, args: n >= 2 ? [items, second] : [items], use: .action))
                }
                if case .function(let f)? = args["isTargeted"] { calls.append(KProbeCall(fn: f, args: [.bool(true)], use: .action)) }
                return calls
            }
        }
        r.modifier("onDrop", .files, notes: "`NSItemProvider`s, read with `loadObject(ofClass:)` or `loadDataRepresentation(for:)`; or your `DropDelegate`. `.dropDestination` is simpler.") { m in
            m.form("of:any isTargeted:binding? perform:closure") { c, view in onDrop(c, view) }
            m.form("of:any delegate:any") { c, view in onDrop(c, view) }
            m.probe { _, args, interp in
                guard case .function(let f)? = args["perform"] else { return [] }
                let n = KRenderer(interp: interp).closureParamCount(.function(f))
                let providers = KV.array([.native(.object("NSItemProvider", KRef(NSItemProvider(object: "Dropped" as NSString))))])
                return [KProbeCall(fn: f, args: n >= 2 ? [providers, .native(.point(0, 0))] : [providers], use: .action)]
            }
        }
        r.protocolBridge("DropDelegate", .files,
                         requirements: ["performDrop(info:)", "validateDrop(info:)?", "dropEntered(info:)?", "dropUpdated(info:)?", "dropExited(info:)?"],
                         support: .full, notes: "For `.onDrop(of:delegate:)`: `info.location`, `info.hasItemsConforming(to:)`, `info.itemProviders(for:)`.") { app in
            KDropDelegate(app: app)
        }
        r.type("DropInfo", .files, support: .full) { t in
            @MainActor func info(_ c: KCall) -> DropInfo? { (KCall.objectValue(c.receiver) as? KDropInfoBox)?.info }
            t.property("location") { c in info(c).map { .native(.point($0.location.x, $0.location.y)) } ?? .native(.point(0, 0)) }
            t.method("hasItemsConforming", "to:any") { c in .bool(info(c)?.hasItemsConforming(to: utTypes(c["to"], c.interp)) ?? false) }
            t.method("itemProviders", "for:any") { c in
                .array((info(c)?.itemProviders(for: utTypes(c["for"], c.interp)) ?? []).map { .native(.object("NSItemProvider", KRef($0))) })
            }
        }
        r.type("DropProposal", .files, support: .full) { t in
            t.initializer("operation:DropOperation") { c in .native(.implicit("proposal", [c["operation"] ?? .nilValue])) }
            t.initializer("withinApplication:DropOperation outsideApplication:DropOperation") { c in
                .native(.implicit("proposal", [c["withinApplication"] ?? .nilValue, c["outsideApplication"] ?? .nilValue]))
            }
        }
        r.type("DropOperation", .files, support: .full) { t in
            t.internal()
            for n in ["copy", "move", "cancel", "forbidden"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
    }

    @MainActor static func dropDestination(_ c: KCall) -> AnyView {
        let view = c.view
        guard let f = c.function("action") else { return view }
        let interp = c.interp, context = c.context
        let type = c["for"]
        // On a ForEach: `{ items, index in }` inserts at the index.
        if let base = c.base, base.primitiveName == "ForEach", !c.has("isTargeted"), !c.has("isEnabled") {
            return forEachDrop(c, base, f, type)
        }
        if c.has("isEnabled") || takesSession(f) {
            if #available(iOS 26, macOS 26, *) {
                let enabled = c.bool("isEnabled", default: true)
                return AnyView(view.dropDestination(for: KDropItem.self, isEnabled: enabled) { items, session in
                    let s = KDragSessions.drop(session)
                    Task { @MainActor in
                        let values = await KDropItem.values(items, as: type, interp, context)
                        interp.perform(f, [.array(values), s])
                    }
                })
            }
            return view
        }
        let targeted = c.function("isTargeted")
        return AnyView(view.dropDestination(for: KDropItem.self, action: { items, location in
            Task { @MainActor in
                let values = await KDropItem.values(items, as: type, interp, context)
                guard !values.isEmpty else { return }
                interp.perform(f, [.array(values), .native(.point(location.x, location.y))])
            }
            return true
        }, isTargeted: { on in if let targeted { interp.perform(targeted, [.bool(on)]) } }))
    }

    /// iOS 26's `{ items, session in }`: its second parameter is named or typed as a session.
    static func takesSession(_ f: KFunction) -> Bool {
        guard case .closure(let closure, _) = f.kind, closure.hasExplicitParams, closure.params.count == 2 else { return false }
        let p = closure.params[1]
        return p.name.lowercased().contains("session") || (p.type.map { "\($0)".contains("DropSession") } ?? false)
    }

    /// `ForEach(…) { … }.dropDestination(for:) { items, index in }`, keeping
    /// an `onDelete` and `onMove` from the same chain.
    @MainActor static func forEachDrop(_ c: KCall, _ base: KView, _ f: KFunction, _ type: KV?) -> AnyView {
        var deleteFn: KFunction?, moveFn: KFunction?
        var node = base
        while case .modified(let inner, let mm) = node.kind {
            if mm.name == "onDelete", case .function(let df)? = mm.first { deleteFn = df }
            if mm.name == "onMove", case .function(let mf)? = mm.first { moveFn = mf }
            node = inner
        }
        guard case .primitive(_, let args, let labels, _) = node.kind else { return c.view }
        let r = c.r, interp = c.interp, context = c.context
        let rows = r.forEachRows(KArgs(args: args, labels: labels))
        return AnyView(ForEach(rows) { row in r.renderList(row.views) }
            .onDelete(perform: deleteFn.map { df in { offsets in interp.perform(df, [.native(.indexSet(offsets))]) } })
            .onMove(perform: moveFn.map { mf in { from, to in interp.perform(mf, [.native(.indexSet(from)), .int(to)]) } })
            .dropDestination(for: KDropItem.self) { items, index in
                Task { @MainActor in
                    let values = await KDropItem.values(items, as: type, interp, context)
                    if !values.isEmpty { interp.perform(f, [.array(values), .int(index)]) }
                }
            })
    }

    @MainActor static func onDrop(_ c: KCall, _ view: AnyView) -> AnyView {
        let interp = c.interp
        let types = utTypes(c["of"], interp).nonEmpty ?? ((try? interp.sequence(c["of"] ?? .array([]))) ?? []).compactMap { $0.asString.flatMap { UTType($0) } }
        if let delegate = c["delegate"] {
            guard let proxy = interp.proxy(for: delegate, as: "DropDelegate") as? KDropDelegate else {
                interp.report(c.fail("the delegate should be your type that adopts DropDelegate"))
                return view
            }
            return AnyView(view.onDrop(of: types, delegate: proxy))
        }
        guard let f = c.function("perform") else { return view }
        let targeted = c.kbinding("isTargeted").map { c.r.boolBinding($0) }
        let wantsLocation = c.r.closureParamCount(.function(f)) >= 2
        @MainActor func call(_ providers: [NSItemProvider], _ location: CGPoint?) -> Bool {
            var args: [KV] = [.array(providers.map { .native(.object("NSItemProvider", KRef($0))) })]
            if let location { args.append(.native(.point(location.x, location.y))) }
            return KHaptics.ask(interp, f, args).map { interp.truthy($0) } ?? false
        }
        if wantsLocation {
            return AnyView(view.onDrop(of: types, isTargeted: targeted) { providers, location in call(providers, location) })
        }
        return AnyView(view.onDrop(of: types, isTargeted: targeted) { providers in call(providers, nil) })
    }

    // MARK: Spring loading

    static func springLoading(_ r: KRegistry) {
        r.modifier("springLoadingBehavior", .files) { m in
            m.form("_:SpringLoadingBehavior") { c, view in view.springLoadingBehavior(springBehavior(c.symbol(0))) }
            m.form("_:SpringLoadingBehavior", receiver: "TabContent", introduced: "18.0") { _, view in view }
        }
        r.type("SpringLoadingBehavior", .files, support: .full) { t in
            t.internal()
            for n in ["automatic", "enabled", "disabled"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.environmentValue("springLoadingBehavior", .files, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in
            let b = env.springLoadingBehavior
            return .native(.implicit(b == .enabled ? "enabled" : (b == .disabled ? "disabled" : "automatic"), []))
        }, write: nil)
    }

    static func springBehavior(_ name: String?) -> SpringLoadingBehavior {
        switch name {
        case "enabled": return .enabled
        case "disabled": return .disabled
        default: return .automatic
        }
    }
}

extension Array {
    var nonEmpty: Self? { isEmpty ? nil : self }
}

// MARK: - What a drag carries

/// The app's value as SwiftUI drags it.
struct KDragPayload: Transferable, @unchecked Sendable {
    enum Value {
        case string(String), url(URL), data(Data), image(Data), app(KTransferItem)
    }
    let value: Value

    var string: String? { if case .string(let s) = value { return s }; return nil }
    var url: URL? { if case .url(let u) = value { return u }; return nil }
    var data: Data? { if case .data(let d) = value { return d }; return nil }
    var image: Data? { if case .image(let d) = value { return d }; return nil }
    var app: KTransferItem? { if case .app(let a) = value { return a }; return nil }

    @MainActor static func make(_ v: KV, _ c: KCall) -> KDragPayload? {
        make(v, c.interp)
    }

    @MainActor static func make(_ v: KV, _ interp: KInterpreter) -> KDragPayload? {
        switch v {
        case .string(let s): return KDragPayload(value: .string(s))
        case .native(.url(let u)): return KDragPayload(value: .url(u))
        case .native(.object("Data", _)): return KBuiltins.dataValue(v).map { KDragPayload(value: .data($0)) }
        case .int, .double, .bool: return KDragPayload(value: .string(interp.describe(v)))
        default:
            #if canImport(UIKit)
            if case .native(.object("UIImage", let ref)) = v, let png = (ref.value as? UIImage)?.pngData() { return KDragPayload(value: .image(png)) }
            if let image = KShare.image(v, interp) {
                let renderer = ImageRenderer(content: image)
                if let png = renderer.uiImage?.pngData() { return KDragPayload(value: .image(png)) }
            }
            #endif
            if let item = interp.proxy(for: v, as: "Transferable") as? KTransferItem { return KDragPayload(value: .app(item)) }
            return nil
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: { (p: KDragPayload) -> KTransferItem in p.app! }).exportingCondition { $0.app != nil }
        ProxyRepresentation(exporting: { (p: KDragPayload) -> URL in p.url ?? URL(string: "about:blank")! }).exportingCondition { $0.url != nil }
        ProxyRepresentation(exporting: { (p: KDragPayload) -> String in p.string ?? "" }).exportingCondition { $0.string != nil }
        DataRepresentation(exportedContentType: .png) { $0.image ?? Data() }.exportingCondition { $0.image != nil }
        DataRepresentation(exportedContentType: .data) { $0.data ?? Data() }.exportingCondition { $0.data != nil }
    }
}

/// What a drop brings, before it's made the payload type's value.
struct KDropItem: Transferable, @unchecked Sendable {
    enum Value {
        case string(String), url(URL), data(Data, UTType), file(URL, UTType)
    }
    let value: Value

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .json) { KDropItem(value: .data($0, .json)) }
        ProxyRepresentation(importing: { (s: String) in KDropItem(value: .string(s)) })
        ProxyRepresentation(importing: { (u: URL) in KDropItem(value: .url(u)) })
        DataRepresentation(importedContentType: .image) { KDropItem(value: .data($0, .image)) }
        FileRepresentation(importedContentType: .item) { received in
            // The file is the system's until this returns: copy it out.
            let folder = FileManager.default.temporaryDirectory.appending(path: "kiln-drops/\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appending(path: received.file.lastPathComponent)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return KDropItem(value: .file(copy, UTType(filenameExtension: copy.pathExtension) ?? .data))
        }
        DataRepresentation(importedContentType: .data) { KDropItem(value: .data($0, .data)) }
    }

    /// The bytes it carries.
    var data: Data? {
        switch value {
        case .string(let s): return Data(s.utf8)
        case .url(let u): return u.isFileURL ? try? Data(contentsOf: u) : Data(u.absoluteString.utf8)
        case .data(let d, _): return d
        case .file(let u, _): return try? Data(contentsOf: u)
        }
    }

    var type: UTType {
        switch value {
        case .string: return .utf8PlainText
        case .url(let u): return u.isFileURL ? (UTType(filenameExtension: u.pathExtension) ?? .fileURL) : .url
        case .data(_, let t), .file(_, let t): return t
        }
    }

    /// Dropped items as values of the payload type (`String.self`, the app's type…).
    @MainActor static func values(_ items: [KDropItem], as type: KV?, _ interp: KInterpreter, _ context: KilnContext) async -> [KV] {
        var out: [KV] = []
        for item in items {
            switch FilesBridges.payloadName(type) {
            case "String", "Substring", nil:
                switch item.value {
                case .string(let s): out.append(.string(s))
                case .url(let u): out.append(.string(u.absoluteString))
                case .data(let d, let t) where t.conforms(to: .text) || t == .json: out.append(.string(String(decoding: d, as: UTF8.self)))
                default: break
                }
            case "URL":
                switch item.value {
                case .url(let u):
                    if u.isFileURL { KFileGrants.of(context).grant(u) }
                    out.append(.native(.url(u)))
                case .string(let s): if let u = URL(string: s), u.scheme != nil { out.append(.native(.url(u))) }
                case .file(let u, _): if let mine = keep(u, context) { out.append(.native(.url(mine))) }
                default: break
                }
            case "Data":
                if let d = item.data { out.append(KBuiltins.data(d)) }
            case "Image", "UIImage":
                if let d = item.data, let v = KShare.imageValue(d, uiImage: FilesBridges.payloadName(type) == "UIImage") { out.append(v) }
            default:
                guard case .type(.user(let t))? = type, let d = item.data else { continue }
                if let v = try? await KTransferables.importValue(t, data: d, contentType: item.type, interp) { out.append(v) }
            }
        }
        return out
    }

    /// A dropped file, moved into the app's temporary folder.
    @MainActor static func keep(_ file: URL, _ context: KilnContext) -> URL? {
        let dest = context.files.temporary.appending(path: file.lastPathComponent)
        try? FileManager.default.removeItem(at: dest)
        do { try FileManager.default.moveItem(at: file, to: dest) } catch { return nil }
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        return dest
    }
}

// MARK: - DropDelegate

final class KDropInfoBox {
    let info: DropInfo
    init(_ info: DropInfo) { self.info = info }
}

/// The app's `DropDelegate`, as SwiftUI calls it.
struct KDropDelegate: DropDelegate {
    let app: KAppValue

    private func info(_ i: DropInfo) -> KV { .native(.object("DropInfo", KRef(KDropInfoBox(i)))) }

    private func call(_ name: String, _ i: DropInfo) -> KV? {
        guard app.implements(name, labels: ["info"]) else { return nil }
        var a = app
        return a.callReporting(name, [info(i)], labels: ["info"], fallback: .nilValue)
    }

    func performDrop(info: DropInfo) -> Bool { call("performDrop", info).map { app.interp.truthy($0) } ?? false }
    func validateDrop(info: DropInfo) -> Bool { call("validateDrop", info).map { app.interp.truthy($0) } ?? true }
    func dropEntered(info: DropInfo) { _ = call("dropEntered", info) }
    func dropExited(info: DropInfo) { _ = call("dropExited", info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let v = call("dropUpdated", info), case .native(.implicit("proposal", let ops)) = v else { return nil }
        let within = KDragSessions.operation(ops.first)
        if ops.count > 1, #available(iOS 26, macOS 26, *) {
            return DropProposal(withinApplication: within, outsideApplication: KDragSessions.operation(ops[1]))
        }
        return DropProposal(operation: within)
    }
}
