//
//  Containers.swift
//  Bridges: iOS 26 and 27's drag sessions and drag containers (PLAN.md §4.1)
//
//      LazyVGrid { ForEach(photos) { p in Thumb(p).draggable(containerItemID: p.id) } }
//          .dragContainer(for: Photo.self) { ids in photos.filter { ids.contains($0.id) } }
//          .dragContainerSelection(selected)
//          .onDragSessionUpdated { session in if case .ended(.move) = session.phase { … } }
//
//  An item's id is the app's own value (`KDragID`), and its payload the
//  app's `Transferable` (`KDragPayload`). Sessions reach the app as values
//  with `phase` (`.initial`, `.active`, `.ended(.move)`…), `location`,
//  `draggedItemIndex` and `draggedItemIDs(for:)`.
//

import SwiftUI
import UniformTypeIdentifiers

/// The app's value as an item id SwiftUI keeps.
struct KDragID: Hashable, @unchecked Sendable {
    let value: KV
}

/// One item of a drag container: its id and what it drags.
struct KContainerItem: Transferable, Identifiable, @unchecked Sendable {
    let id: KDragID
    let payload: KDragPayload

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.payload)
    }
}

/// A drag or drop session, as the app reads it.
final class KSessionBox {
    var phase: KV = .native(.implicit("initial", []))
    var location = CGPoint.zero
    var draggedItemIndex = 0
    var draggedIDs: [KV] = []
    var itemsCount = 0
    var size = CGSize.zero
    var id = UUID()
}

@MainActor
enum KDragSessions {
    static func operationName(_ op: DropOperation) -> String {
        switch op {
        case .copy: return "copy"
        case .move: return "move"
        case .forbidden: return "forbidden"
        default: return "cancel"
        }
    }

    static func operation(_ v: KV?) -> DropOperation {
        guard case .native(.implicit(let n, _))? = v else { return .copy }
        switch n {
        case "move": return .move
        case "cancel": return .cancel
        case "forbidden": return .forbidden
        default: return .copy
        }
    }

    static func phase(_ name: String, _ op: DropOperation? = nil) -> KV {
        .native(.implicit(name, op.map { [.native(.implicit(operationName($0), []))] } ?? []))
    }

    static func box(_ b: KSessionBox, _ type: String) -> KV { .native(.object(type, KRef(b))) }

    /// What a check passes: a drop that ended with a copy.
    static func endedDrop() -> KV {
        let b = KSessionBox()
        b.phase = phase("ended", .copy)
        b.itemsCount = 1
        return box(b, "DropSession")
    }

    static func endedDrag() -> KV {
        let b = KSessionBox()
        b.phase = phase("ended", .move)
        return box(b, "DragSession")
    }

    static func ids(_ ids: [KDragID]) -> [KV] { ids.map(\.value) }

    @available(iOS 26, macOS 26, *)
    static func drop(_ s: DropSession) -> KV {
        let b = KSessionBox()
        switch s.phase {
        case .entering: b.phase = phase("entering")
        case .active: b.phase = phase("active")
        case .exiting: b.phase = phase("exiting")
        case .ended(let op): b.phase = phase("ended", op)
        case .dataTransferCompleted: b.phase = phase("dataTransferCompleted")
        @unknown default: b.phase = phase("active")
        }
        b.location = s.location
        b.itemsCount = s.itemsCount
        b.size = s.size
        b.draggedIDs = ids(s.localSession?.draggedItemIDs(for: KDragID.self) ?? [])
        return box(b, "DropSession")
    }

    @available(iOS 26, macOS 26, *)
    static func drag(_ s: DragSession) -> KV {
        let b = KSessionBox()
        switch s.phase {
        case .initial: b.phase = phase("initial")
        case .active: b.phase = phase("active")
        case .ended(let op): b.phase = phase("ended", op)
        case .dataTransferCompleted: b.phase = phase("dataTransferCompleted")
        default:
            #if os(iOS)
            if case .ending(let op) = s.phase { b.phase = phase("ending", op) } else { b.phase = phase("active") }
            #else
            b.phase = phase("active")
            #endif
        }
        b.location = s.location
        b.draggedItemIndex = s.draggedItemIndex
        b.draggedIDs = ids(s.draggedItemIDs(for: KDragID.self))
        return box(b, "DragSession")
    }
}

extension FilesBridges {
    static func containers(_ r: KRegistry) {
        let note = "iOS 27's multi-item drag: `.dragContainer(for: Item.self) { ids in items }` on the container, `.draggable(containerItemID: item.id)` on each item."
        r.modifier("dragContainer", .files, introduced: "27.0", notes: note) { m in
            for sig in ["for:any? in:any? _:closure", "for:any? itemID:any in:any? _:closure"] {
                m.form(sig, introduced: "27.0") { c, view in dragContainer(c, view) }
            }
            m.probe { _, args, interp in
                guard let f = args.lastFunction.flatMap({ if case .function(let f) = $0 { return f }; return nil }) else { return [] }
                return [KProbeCall(fn: f, args: [.array([])], use: .action)]
            }
        }
        r.modifier("dragContainerSelection", .files, introduced: "27.0", notes: "The ids dragged together when one of them is.") { m in
            m.form("_:any containerNamespace:any?", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 26, *) {
                    let ids = ((try? c.interp.sequence(c[0] ?? .array([]))) ?? []).map(KDragID.init)
                    AnyView(view.dragContainerSelection(ids, containerNamespace: c.interp.namespace(c["containerNamespace"])?.id))
                } else {
                    view
                }
            }
        }
        r.modifier("dragConfiguration", .files, introduced: "27.0", notes: "`DragConfiguration(allowMove:)` or `(operationsWithinApp:operationsOutsideApp:)`.") { m in
            m.form("_:DragConfiguration", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 26, *), let config = KCall.objectValue(c[0]) as? KDragConfiguration {
                    AnyView(view.dragConfiguration(config.swiftUI))
                } else {
                    view
                }
            }
        }
        r.modifier("onDragSessionUpdated", .files, introduced: "27.0") { m in
            m.form("_:closure", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 26, *), let f = c.function(0) {
                    let interp = c.interp
                    AnyView(view.onDragSessionUpdated { s in interp.perform(f, [KDragSessions.drag(s)]) })
                } else {
                    view
                }
            }
            m.probe { _, args, _ in
                guard case .function(let f)? = args.args.first else { return [] }
                return [KProbeCall(fn: f, args: [KDragSessions.endedDrag()], use: .action)]
            }
        }
        r.modifier("onDropSessionUpdated", .files, introduced: "27.0") { m in
            m.form("_:closure", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 26, *), let f = c.function(0) {
                    let interp = c.interp
                    AnyView(view.onDropSessionUpdated { s in interp.perform(f, [KDragSessions.drop(s)]) })
                } else {
                    view
                }
            }
            m.probe { _, args, _ in
                guard case .function(let f)? = args.args.first else { return [] }
                return [KProbeCall(fn: f, args: [KDragSessions.endedDrop()], use: .action)]
            }
        }
        r.modifier("dropConfiguration", .files, introduced: "27.0", notes: "`{ session in DropConfiguration(operation: .move) }`.") { m in
            m.form("_:closure", introduced: "27.0") { c, view in
                if #available(iOS 27, macOS 26, *), let f = c.function(0) {
                    let interp = c.interp
                    AnyView(view.dropConfiguration { s in
                        let v = KHaptics.ask(interp, f, [KDragSessions.drop(s)])
                        return DropConfiguration(operation: (v.flatMap { KCall.objectValue($0) } as? KDropConfiguration)?.operation ?? .copy)
                    })
                } else {
                    view
                }
            }
            m.probe { _, args, _ in
                guard case .function(let f)? = args.args.first else { return [] }
                return [KProbeCall(fn: f, args: [KDragSessions.endedDrop()], use: .action)]
            }
        }

        r.type("DragConfiguration", .files, support: .full, introduced: "26.0") { t in
            t.initializer("allowMove:bool") { c in
                .native(.object("DragConfiguration", KRef(KDragConfiguration(withinMove: c.bool("allowMove", default: false), outsideCopy: true))))
            }
            t.initializer("operationsWithinApp:any? operationsOutsideApp:any?") { c in
                func flag(_ v: KV?, _ label: String, _ d: Bool) -> Bool {
                    guard case .native(.object(_, let ref))? = v, let o = ref.value as? KDragOperations else { return d }
                    return o.flags[label] ?? d
                }
                return .native(.object("DragConfiguration", KRef(KDragConfiguration(withinMove: flag(c["operationsWithinApp"], "allowMove", false),
                                                                                    outsideCopy: flag(c["operationsOutsideApp"], "allowCopy", true)))))
            }
        }
        for name in ["DragConfiguration.OperationsWithinApp", "DragConfiguration.OperationsOutsideApp"] {
            r.type(name, .files, support: .full, introduced: "26.0") { t in
                t.initializer(name.hasSuffix("WithinApp") ? "allowMove:bool?" : "allowCopy:bool?") { c in
                    var flags: [String: Bool] = [:]
                    for l in ["allowMove", "allowCopy"] where c.has(.label(l)) { flags[l] = c.bool(.label(l), default: false) }
                    return .native(.object(name, KRef(KDragOperations(flags))))
                }
            }
        }
        r.type("DropConfiguration", .files, support: .full, introduced: "26.0") { t in
            t.initializer("operation:DropOperation") { c in .native(.object("DropConfiguration", KRef(KDropConfiguration(operation: KDragSessions.operation(c["operation"]))))) }
            t.property("operation") { c in .native(.implicit(KDragSessions.operationName((KCall.objectValue(c.receiver) as? KDropConfiguration)?.operation ?? .copy), [])) }
        }
        for type in ["DragSession", "DropSession"] {
            r.type(type, .files, support: .full, introduced: "26.0") { t in
                @MainActor func s(_ c: KCall) -> KSessionBox? { KCall.objectValue(c.receiver) as? KSessionBox }
                t.property("phase") { c in s(c)?.phase ?? .nilValue }
                t.property("location") { c in s(c).map { .native(.point($0.location.x, $0.location.y)) } ?? .nilValue }
                t.property("id") { c in .string(s(c)?.id.uuidString ?? "") }
                if type == "DragSession" {
                    t.property("draggedItemIndex") { c in .int(s(c)?.draggedItemIndex ?? 0) }
                    t.method("draggedItemIDs", "for:any") { c in .array(s(c)?.draggedIDs ?? []) }
                } else {
                    t.property("itemsCount") { c in .int(s(c)?.itemsCount ?? 0) }
                    t.property("size") { c in s(c).map { .native(.size($0.size.width, $0.size.height)) } ?? .nilValue }
                    t.property("localSession") { c in s(c).map { $0.draggedIDs.isEmpty ? .nilValue : .native(.object("DropSession.LocalSession", KRef($0))) } ?? .nilValue }
                }
            }
        }
        r.type("DropSession.LocalSession", .files, support: .full, introduced: "26.0") { t in
            t.method("draggedItemIDs", "for:any") { c in .array((KCall.objectValue(c.receiver) as? KSessionBox)?.draggedIDs ?? []) }
        }
    }

    /// The app's item → its id: `item.id`, or the key path the app gave.
    @MainActor static func itemID(_ item: KV, _ keyPath: KV?, _ interp: KInterpreter) -> KV {
        if case .native(.keyPath(let comps))? = keyPath {
            var v = item
            for name in comps { v = (try? interp.member(v, name, line: 0)) ?? .nilValue }
            return v
        }
        return (try? interp.member(item, "id", line: 0)) ?? item
    }

    @MainActor static func dragContainer(_ c: KCall, _ view: AnyView) -> AnyView {
        guard #available(iOS 27, macOS 26, *), let f = c.a.lastFunction.flatMap({ if case .function(let f) = $0 { return f }; return nil }) else { return view }
        let interp = c.interp
        let keyPath = c["itemID"]
        let ns = interp.namespace(c["in"])?.id
        // Swift picks the one-id form when the closure takes a single id (`draggedItemID`).
        let single: Bool = {
            if case .closure(let closure, _) = f.kind, closure.hasExplicitParams, let p = closure.params.first {
                return !p.name.hasSuffix("s") && !(p.type.map { "\($0)".hasPrefix("[") } ?? false)
            }
            return false
        }()
        @MainActor func items(_ ids: [KDragID]) -> [KContainerItem] {
            let arg: KV = single ? (ids.first?.value ?? .nilValue) : .array(ids.map(\.value))
            let made = KHaptics.ask(interp, f, [arg]) ?? .array([])
            let values = (try? interp.sequence(made)) ?? [made]
            return values.compactMap { v in
                KDragPayload.make(v, interp).map { KContainerItem(id: KDragID(value: itemID(v, keyPath, interp)), payload: $0) }
            }
        }
        if single {
            return AnyView(view.dragContainer(for: KContainerItem.self, in: ns) { (id: KDragID) in items([id]) })
        }
        return AnyView(view.dragContainer(for: KContainerItem.self, in: ns) { (ids: [KDragID]) in items(ids) })
    }

    @MainActor static func containerDraggable(_ c: KCall, _ view: AnyView) -> AnyView {
        guard #available(iOS 27, macOS 26, *) else { return view }
        let interp = c.interp
        let ns = interp.namespace(c["containerNamespace"])?.id
        if let id = c["containerItemID"] {
            return AnyView(view.draggable(containerItemID: KDragID(value: id), containerNamespace: ns))
        }
        let keyPath = c["id"]
        @MainActor func item(_ v: KV) -> KContainerItem? {
            guard !v.isNil, let payload = KDragPayload.make(v, interp) else { return nil }
            return KContainerItem(id: KDragID(value: itemID(v, keyPath, interp)), payload: payload)
        }
        if let v = c["item"] {
            return AnyView(view.draggable(KContainerItem.self, item: item(v), containerNamespace: ns))
        }
        if let f = c.a.lastFunction.flatMap({ if case .function(let f) = $0 { return f }; return nil }) {
            return AnyView(view.draggable(KContainerItem.self, containerNamespace: ns) { KHaptics.ask(interp, f, []).flatMap(item) })
        }
        return view
    }
}

final class KDragConfiguration {
    let withinMove: Bool
    let outsideCopy: Bool
    init(withinMove: Bool, outsideCopy: Bool) {
        self.withinMove = withinMove
        self.outsideCopy = outsideCopy
    }

    @available(iOS 26, macOS 26, *)
    var swiftUI: DragConfiguration {
        #if os(iOS) || os(visionOS)
        DragConfiguration(operationsWithinApp: .init(allowMove: withinMove), operationsOutsideApp: .init(allowCopy: outsideCopy))
        #else
        DragConfiguration(operationsWithinApp: .init(allowCopy: true, allowMove: withinMove), operationsOutsideApp: .init(allowCopy: outsideCopy))
        #endif
    }
}

final class KDragOperations {
    let flags: [String: Bool]
    init(_ flags: [String: Bool]) { self.flags = flags }
}

final class KDropConfiguration {
    let operation: DropOperation
    init(operation: DropOperation) { self.operation = operation }
}
