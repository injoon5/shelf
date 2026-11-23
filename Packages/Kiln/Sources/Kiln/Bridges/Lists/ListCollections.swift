//
//  ListCollections.swift
//  Bridges: list selection, outlines, edit actions, iOS 27 reordering, and
//  the row and section modifiers
//
//  `List(selection: $picked)` keeps one value or a `Set`; rows are known by
//  their `.tag` or their `ForEach` id, as in SwiftUI. `List(tree, children:
//  \.children)` and `OutlineGroup` disclose nested rows. `ForEach($items,
//  editActions: .all)` deletes and moves in the array itself. On iOS 27,
//  `ForEach(items).reorderable()` in a `.reorderContainer(for:)` hands the
//  app a `ReorderDifference` to apply.
//

import SwiftUI

/// A row of an outline: its value, id and children (nil: a leaf).
struct KOutlineNode: Identifiable {
    let id: KV
    let value: KV
    let children: [KOutlineNode]?
}

extension ListsBridges {
    static func collections(_ r: KRegistry) {
        for name in ["Prominence", "BadgeProminence", "ListSectionSpacing", "EditActions", "ListItemTint"] {
            r.type(name, .lists) { t in
                t.internal()
                t.anyStatic { _, member in .native(.implicit(member, [])) }
            }
        }
        outlines(r)
        reordering(r)
        listModifiers(r)
        listEnvironment(r)
        for (name, notes) in [("EditableCollectionContent", "What `ForEach($items, editActions:)` makes."),
                              ("OutlineSubgroupChildren", "The children an `OutlineGroup` shows under a row.")] {
            r.view(name, .lists, notes: notes) { v in v.bridge.constructible = false }
        }
    }

    // MARK: List

    @MainActor static func list(_ c: KCall) -> AnyView {
        let r = c.r
        let rows: AnyView
        if c["children"] != nil {
            let nodes = outlineNodes(c)
            let fn = c["rowContent"] ?? c.last
            rows = AnyView(OutlineGroup(nodes, children: \.children) { node in r.renderContent(fn, [node.value]) })
        } else if c["editActions"] != nil {
            rows = editableRows(c)
        } else if let data = c.first, c.a.firstIsUnlabeled, !r.isFunction(data) {
            let items = r.forEachRows(c.a)
            rows = AnyView(ForEach(items) { row in r.renderList(row.views) })
        } else {
            rows = c.content(c["content"] != nil ? "content" : nil)
        }
        guard let b = c.kbinding("selection") else { return AnyView(List { rows }) }
        // A `Set` binding is many rows; anything else (an optional) is one.
        if case .set = b.get() {
            let many = Binding<Set<KV>>(get: { if case .set(let s) = b.get() { return s }; return [] }, set: { b.set(.set($0)) })
            return AnyView(List(selection: many) { rows })
        }
        let one = Binding<KV?>(get: { let v = b.get(); return v.isNil ? nil : v }, set: { b.set($0 ?? .nilValue) })
        return AnyView(List(selection: one) { rows })
    }

    @MainActor static func verticalEdges(_ v: KV?) -> VerticalEdge.Set {
        switch v {
        case .native(.implicit("top", _))?: return .top
        case .native(.implicit("bottom", _))?: return .bottom
        default: return .all
        }
    }

    @MainActor static func swipeActionsNotified(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 27.0, *), case .function(let f)? = c["onPresentationChanged"] {
            let content = c.content("content"), interp = c.interp
            return AnyView(view.swipeActions(edge: c.symbol("edge") == "leading" ? .leading : .trailing, allowsFullSwipe: c.bool("allowsFullSwipe", default: true),
                                             content: { content }, onPresentationChanged: { shown in interp.perform(f, [.bool(shown)]) }))
        }
        #endif
        let content = c.content("content")
        return AnyView(view.swipeActions(edge: c.symbol("edge") == "leading" ? .leading : .trailing, allowsFullSwipe: c.bool("allowsFullSwipe", default: true)) { content })
    }

    // MARK: Edit actions

    /// `ForEach($items, editActions: .all) { $item in … }` and `List($items, editActions:)`.
    @MainActor static func editableRows(_ c: KCall) -> AnyView {
        let r = c.r, interp = c.interp
        let rows = r.forEachRows(c.a)
        let names: Set<String> = {
            var out: Set<String> = []
            func add(_ v: KV) {
                switch v {
                case .native(.implicit(let n, _)): out.insert(n)
                case .array(let items): items.forEach(add)
                case .set(let items): items.forEach(add)
                default: break
                }
            }
            if let e = c["editActions"] { add(e) }
            return out
        }()
        guard let b = c.kbinding(0) else { return AnyView(ForEach(rows) { row in r.renderList(row.views) }) }
        let canDelete = names.contains("all") || names.contains("delete"), canMove = names.contains("all") || names.contains("move")
        let delete: ((IndexSet) -> Void)? = canDelete ? { offsets in
            guard case .array(var items) = b.get() else { return }
            for i in offsets.sorted(by: >) where i < items.count { items.remove(at: i) }
            b.set(.array(items))
        } : nil
        let move: ((IndexSet, Int) -> Void)? = canMove ? { from, to in
            guard case .array(var items) = b.get() else { return }
            items.move(fromOffsets: from, toOffset: to)
            b.set(.array(items))
        } : nil
        _ = interp
        return AnyView(ForEach(rows) { row in r.renderList(row.views) }.onDelete(perform: delete).onMove(perform: move))
    }

    // MARK: Outlines

    static func outlines(_ r: KRegistry) {
        r.view("OutlineGroup", .lists, notes: "Over a tree: `OutlineGroup(items, children: \\.children) { item in … }`, with `id:` or `Identifiable` items.") { v in
            v.forms(["_:any children:any content:content", "_:any id:any children:any content:content"]) { c in
                let nodes = outlineNodes(c)
                let fn = c.last
                OutlineGroup(nodes, children: \.children) { node in c.r.renderContent(fn, [node.value]) }
            }
        }
    }

    @MainActor static func outlineNodes(_ c: KCall) -> [KOutlineNode] {
        let interp = c.interp, r = c.r
        guard case .native(.keyPath(let comps))? = c["children"] else { return [] }
        var budget = 2000
        func nodes(_ v: KV, depth: Int) -> [KOutlineNode] {
            let items = (try? interp.sequence(v)) ?? []
            return items.enumerated().compactMap { i, item -> KOutlineNode? in
                budget -= 1
                guard budget > 0 else { return nil }
                var kids: KV = item
                for comp in comps where comp != "self" { kids = (try? interp.member(kids, comp, line: c.line)) ?? .nilValue }
                let children: [KOutlineNode]? = (kids.isNil || depth > 32) ? nil : nodes(kids, depth: depth + 1)
                return KOutlineNode(id: r.rowID(item, c["id"]) ?? .string("\(depth).\(i)"), value: item, children: children)
            }
        }
        let data: KV = { if case .binding(let b)? = c.first { return b.get() }; return c.first ?? .array([]) }()
        return nodes(data, depth: 0)
    }

    // MARK: Reordering (iOS 27)

    static func reordering(_ r: KRegistry) {
        r.modifier("reorderable", .lists, introduced: "27.0", notes: "On a `ForEach` inside a `.reorderContainer(for:)`: its rows can be dragged into a new order.") { m in
            m.formOnBase("", receiver: "DynamicViewContent") { c in reorderable(c, collection: nil) }
            m.formOnBase("collectionID:any", receiver: "DynamicViewContent") { c in reorderable(c, collection: c["collectionID"]) }
        }
        r.modifier("reorderContainer", .lists, introduced: "27.0",
                   notes: "`move` gets a `ReorderDifference`: `sources` (the ids moved) and `destination.position`, `.before(id)` or `.end` (and `destination.collectionID`).") { m in
            m.forms(["for:any isEnabled:bool? move:closure", "for:any in:any isEnabled:bool? move:closure",
                     "for:any itemID:any isEnabled:bool? move:closure", "for:any itemID:any in:any isEnabled:bool? move:closure"]) { c, view in
                reorderContainer(c, view)
            }
            m.probe { _, _ in [.tuple([.array([]), .tuple([.native(.implicit("end", [])), .nilValue], ["position", "collectionID"])], ["sources", "destination"])] }
        }
        r.modifier("swipeActionsContainer", .lists, introduced: "27.0", notes: "Lets `.swipeActions` work on the views of a `ScrollView`'s stack.") { m in
            m.form("") { _, view in
                #if os(iOS)
                if #available(iOS 27.0, *) { AnyView(view.swipeActionsContainer()) } else { view }
                #else
                view
                #endif
            }
        }
    }

    @MainActor static func reorderable(_ c: KCall, collection: KV?) -> AnyView {
        #if os(iOS)
        guard #available(iOS 27.0, *), let base = c.base, case .primitive("ForEach", let args, let labels, _)? = c.r.rootPrimitive(base) else { return c.view }
        let r = c.r
        let rows = r.forEachRows(KArgs(args: args, labels: labels))
        if let collection { return AnyView(ForEach(rows) { row in r.renderList(row.views) }.reorderable(collectionID: collection)) }
        return AnyView(ForEach(rows) { row in r.renderList(row.views) }.reorderable())
        #else
        return c.view
        #endif
    }

    @MainActor static func reorderContainer(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        guard #available(iOS 27.0, *), case .function(let f)? = c["move"] ?? c.last else { return view }
        let interp = c.interp, enabled = c.bool("isEnabled", default: true)
        func position(_ p: ReorderDifference<KV, some Hashable>.Destination.Position) -> KV {
            switch p {
            case .before(let id): return .native(.implicit("before", [id]))
            case .end: return .native(.implicit("end", []))
            @unknown default: return .native(.implicit("end", []))
            }
        }
        if c["in"] != nil {
            return AnyView(view.reorderContainer(for: KRenderer.Row.self, in: KV.self, isEnabled: enabled) { diff in
                interp.perform(f, [.tuple([.array(diff.sources), .tuple([position(diff.destination.position), diff.destination.collectionID], ["position", "collectionID"])],
                                          ["sources", "destination"])])
            })
        }
        return AnyView(view.reorderContainer(for: KRenderer.Row.self, isEnabled: enabled) { diff in
            interp.perform(f, [.tuple([.array(diff.sources), .tuple([position(diff.destination.position), .nilValue], ["position", "collectionID"])],
                                      ["sources", "destination"])])
        })
        #else
        return view
        #endif
    }

    // MARK: Row and section modifiers

    static func listModifiers(_ r: KRegistry) {
        for name in ["deleteDisabled", "moveDisabled"] {
            r.modifier(name, .lists, notes: "On a row of a `ForEach` with `onDelete`/`onMove` or `editActions`.") { m in
                m.form("_:bool") { c, view in
                    if name == "deleteDisabled" { view.deleteDisabled(c.bool(0, default: true)) } else { view.moveDisabled(c.bool(0, default: true)) }
                }
            }
        }
        r.modifier("selectionDisabled", .lists) { m in m.form("_:bool?") { c, view in view.selectionDisabled(c.bool(0, default: true)) } }
        r.modifier("badgeProminence", .lists) { m in
            m.form("_:BadgeProminence") { c, view in
                view.badgeProminence(c.pick(0, ["increased": BadgeProminence.increased, "decreased": .decreased]) ?? .standard)
            }
        }
        r.modifier("listItemTint", .lists) { m in
            m.form("_:any?") { c, view in
                if let color = c.color(0) { view.listItemTint(color) }
                else if c.symbol(0) == "monochrome" { view.listItemTint(.monochrome) }
                else { view.listItemTint(nil as Color?) }
            }
        }
        r.modifier("listRowSeparatorTint", .lists) { m in
            m.form("_:Color? edges:any?") { c, view in view.listRowSeparatorTint(c.color(0), edges: verticalEdges(c["edges"])) }
        }
        r.modifier("listSectionSeparatorTint", .lists) { m in
            m.form("_:Color? edges:any?") { c, view in view.listSectionSeparatorTint(c.color(0), edges: verticalEdges(c["edges"])) }
        }
        r.modifier("listRowSpacing", .lists) { m in m.form("_:number?") { c, view in iOSListModifier("listRowSpacing", c, view) } }
        r.modifier("listSectionSpacing", .lists) { m in m.form("_:any") { c, view in iOSListModifier("listSectionSpacing", c, view) } }
        r.modifier("listSectionMargins", .lists, introduced: "26.0") { m in
            m.form("_:Edge.Set? _:number?") { c, view in iOSListModifier("listSectionMargins", c, view) }
        }
        r.modifier("listSectionIndexVisibility", .lists, introduced: "26.0", notes: "Shows the index of `sectionIndexLabel`s down the side of a `List`.") { m in
            m.form("_:Visibility") { c, view in
                #if os(iOS)
                if #available(iOS 26.0, *) { AnyView(view.listSectionIndexVisibility(KControlValues.visibility(c[0]))) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("sectionIndexLabel", .lists, introduced: "26.0", notes: "On a `Section`: its letter in the list's index.") { m in
            m.form("_:title?") { c, view in
                if #available(iOS 26.0, macOS 26.0, *) { AnyView(view.sectionIndexLabel(c.string(0))) } else { view }
            }
        }
        r.modifier("findNavigator", .lists, notes: "Find (and replace) in a `TextEditor`.") { m in
            m.form("isPresented:binding") { c, view in
                #if os(iOS)
                if let b = c.kbinding("isPresented") { AnyView(view.findNavigator(isPresented: c.r.boolBinding(b))) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("findDisabled", .lists) { m in
            m.form("_:bool?") { c, view in
                #if os(iOS)
                view.findDisabled(c.bool(0, default: true))
                #else
                view
                #endif
            }
        }
        r.modifier("replaceDisabled", .lists) { m in
            m.form("_:bool?") { c, view in
                #if os(iOS)
                view.replaceDisabled(c.bool(0, default: true))
                #else
                view
                #endif
            }
        }
    }

    /// The list modifiers only iOS has.
    @MainActor static func iOSListModifier(_ name: String, _ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        switch name {
        case "listRowSpacing": return AnyView(view.listRowSpacing(c.cg(0)))
        case "listSectionSpacing":
            if let n = c.cg(0) { return AnyView(view.listSectionSpacing(n)) }
            if c.symbol(0) == "compact" { return AnyView(view.listSectionSpacing(.compact)) }
            if case .native(.implicit("custom", let a))? = c[0], let n = a.first?.cg { return AnyView(view.listSectionSpacing(.custom(n))) }
            return AnyView(view.listSectionSpacing(.default))
        case "listSectionMargins":
            guard #available(iOS 26.0, *) else { return view }
            if c.args.count >= 2 { return AnyView(view.listSectionMargins(c.edges(0), c.cg(1))) }
            return AnyView(view.listSectionMargins(.all, c.cg(0)))
        default: return view
        }
        #else
        return view
        #endif
    }

    // MARK: Environment values

    static func listEnvironment(_ r: KRegistry) {
        r.liveEnvironment("defaultMinListRowHeight", .lists, read: { env, _ in .double(Double(env.defaultMinListRowHeight)) },
                          write: { view, v, _ in AnyView(view.environment(\.defaultMinListRowHeight, v.cg ?? 44)) })
        r.liveEnvironment("defaultMinListHeaderHeight", .lists, read: { env, _ in env.defaultMinListHeaderHeight.map { .double(Double($0)) } ?? .nilValue },
                          write: { view, v, _ in AnyView(view.environment(\.defaultMinListHeaderHeight, v.cg)) })
        r.liveEnvironment("headerProminence", .lists, read: { env, _ in .native(.implicit(env.headerProminence == .increased ? "increased" : "standard", [])) },
                          write: { view, v, _ in
                              if case .native(.implicit("increased", _)) = v { return AnyView(view.environment(\.headerProminence, .increased)) }
                              return AnyView(view.environment(\.headerProminence, .standard))
                          })
        r.liveEnvironment("isScrollEnabled", .lists, read: { env, _ in .bool(env.isScrollEnabled) },
                          write: { view, v, _ in AnyView(view.environment(\.isScrollEnabled, v.asBool ?? true)) })
    }
}
