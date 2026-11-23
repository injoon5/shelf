//
//  Lists.swift
//  Bridges: List, Form, Section, ForEach and their rows
//

import SwiftUI

@objc(KilnBridges_Lists)
final class ListsBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        views(r)
        rows(r)
    }

    // MARK: Views

    static func views(_ r: KRegistry) {
        r.view("List", .lists, support: .partial, notes: "Rows, sections, `onDelete` and `onMove`; `selection:` isn't kept.") { v in
            v.forms(["selection:binding? content:content", "_:any id:any? selection:binding? content:content"]) { c in
                if let data = c.first, c.a.lastFunction != nil, c.a.firstIsUnlabeled, !c.r.isFunction(data) {
                    let rows = c.r.forEachRows(c.a)
                    List { ForEach(rows) { row in c.r.renderList(row.views) } }
                } else {
                    List { c.content() }
                }
            }
        }
        r.view("Form", .lists) { v in
            v.form("content:content") { c in Form { c.content() } }
        }
        r.view("ForEach", .lists, notes: "Over arrays, ranges and bindings (`ForEach($items) { $item in }`), by `id:` or `Identifiable`.") { v in
            v.forms(["_:any content:content", "_:any id:any content:content"]) { c in
                let rows = c.r.forEachRows(c.a)
                ForEach(rows) { row in c.r.renderList(row.views) }
            }
        }
        r.view("Section", .lists) { v in
            v.forms(["_:title content:content", "content:content header:content? footer:content?", "header:any footer:any? content:content",
                     "footer:any content:content"]) { c in section(c) }
        }
        r.view("GroupBox", .lists) { v in
            v.forms(["_:title content:content", "content:content label:content", "label:any content:content", "content:content"]) { c in
                if let t = ControlsBridges.stringTitle(c) {
                    GroupBox(t) { c.r.renderContent(c.a.lastFunction) }
                } else if c.a["label"] != nil {
                    GroupBox { c.r.renderContent(c.a.firstFunction) } label: { c.r.renderContent(c.a["label"]) }
                } else {
                    GroupBox { c.r.renderContent(c.a.lastFunction) }
                }
            }
        }
        r.view("DisclosureGroup", .lists, support: .partial) { v in
            v.forms(["_:title content:content", "_:title isExpanded:binding content:content"]) { c in
                if let b = c.kbinding("isExpanded") {
                    DisclosureGroup(c.title(0), isExpanded: c.r.boolBinding(b)) { c.r.renderContent(c.a.lastFunction) }
                } else {
                    DisclosureGroup(c.title(0)) { c.r.renderContent(c.a.lastFunction) }
                }
            }
            v.forms(["content:content label:content", "isExpanded:binding content:content label:content"]) { c in
                if let b = c.kbinding("isExpanded") {
                    DisclosureGroup(isExpanded: c.r.boolBinding(b)) { c.content("content") } label: { c.content("label") }
                } else {
                    DisclosureGroup { c.content("content") } label: { c.content("label") }
                }
            }
        }
    }

    @MainActor static func section(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        let body = r.renderContent(a.firstFunction ?? a.lastFunction)
        if let title = ControlsBridges.stringTitle(c) { return AnyView(Section(title) { body }) }
        let header = a["header"].map { v -> AnyView in r.isFunction(v) ? r.renderContent(v) : r.renderList(KBuiltins.asViews(v, c.interp)) }
        let footer = a["footer"].map { v -> AnyView in r.isFunction(v) ? r.renderContent(v) : r.renderList(KBuiltins.asViews(v, c.interp)) }
        switch (header, footer) {
        case (let h?, let f?): return AnyView(Section { body } header: { h } footer: { f })
        case (let h?, nil): return AnyView(Section { body } header: { h })
        case (nil, let f?): return AnyView(Section { body } footer: { f })
        default: return AnyView(Section { body })
        }
    }

    // MARK: Rows

    static func rows(_ r: KRegistry) {
        for name in ["onDelete", "onMove"] {
            r.modifier(name, .lists, notes: "On a `ForEach` in a `List`.") { m in
                m.formOnBase("perform:action?", receiver: "DynamicViewContent") { c in
                    if let base = c.base, base.primitiveName == "ForEach" { editableForEach(c, base, name) } else { c.view }
                }
            }
        }
        r.modifier("refreshable", .lists, notes: "The spinner stays until the closure, which may wait, is done.") { m in
            m.form("action:action") { c, view in
                if let fn = c.function("action") {
                    let interp = c.interp
                    view.refreshable { await interp.runViewTask(fn) }
                } else {
                    view
                }
            }
            m.closuresCanWait()
        }
        r.modifier("listStyle", .lists, support: .partial) { m in
            m.styles("ListStyle", ["plain", "inset", "sidebar", "insetGrouped", "grouped", "automatic"])
            m.form("_:ListStyle") { c, view in
                switch c.symbol(0) {
                case "plain": AnyView(view.listStyle(.plain))
                case "inset": AnyView(view.listStyle(.inset))
                case "sidebar": AnyView(view.listStyle(.sidebar))
                #if os(iOS)
                case "insetGrouped": AnyView(view.listStyle(.insetGrouped))
                case "grouped": AnyView(view.listStyle(.grouped))
                #endif
                default: view
                }
            }
        }
        r.modifier("listRowBackground", .lists) { m in
            m.form("_:Color?") { c, view in
                if let color = c.color(0) {
                    AnyView(view.listRowBackground(color))
                } else if case .view(let v)? = c[0] {
                    AnyView(view.listRowBackground(c.r.render(v)))
                } else {
                    view
                }
            }
        }
        r.modifier("listRowSeparator", .lists, support: .partial) { m in
            m.form("_:Visibility edges:any?") { c, view in
                if c.symbol(0) == "hidden" { view.listRowSeparator(.hidden) } else { view }
            }
        }
        r.modifier("listRowInsets", .lists, support: .partial, notes: "Always zero insets.") { m in
            m.form("_:any?") { _, view in view.listRowInsets(EdgeInsets()) }
        }
        r.modifier("listSectionSeparator", .lists, support: .stub) { m in m.stub(["_:Visibility edges:any?"]) }
        r.modifier("headerProminence", .lists, support: .stub) { m in m.stub(["_:Prominence"]) }
        r.modifier("scrollContentBackground", .lists) { m in
            m.form("_:Visibility") { c, view in
                if c.symbol(0) == "hidden" { view.scrollContentBackground(.hidden) } else { view }
            }
        }
        r.modifier("swipeActions", .lists, support: .partial, notes: "On `List` rows.") { m in
            m.form("edge:HorizontalEdge? allowsFullSwipe:bool? content:content") { c, view in
                let content = c.content("content")
                view.swipeActions(edge: c.symbol("edge") == "leading" ? .leading : .trailing,
                                  allowsFullSwipe: c.bool("allowsFullSwipe", default: true)) { content }
            }
        }
    }

    /// A `ForEach` with `onDelete` and `onMove`: both, from anywhere in its chain.
    @MainActor static func editableForEach(_ c: KCall, _ base: KView, _ name: String) -> AnyView {
        var deleteFn: KV? = name == "onDelete" ? c.first : nil, moveFn: KV? = name == "onMove" ? c.first : nil
        var node = base
        while case .modified(let inner, let mm) = node.kind {
            if mm.name == "onDelete" { deleteFn = deleteFn ?? mm.first }
            if mm.name == "onMove" { moveFn = moveFn ?? mm.first }
            node = inner
        }
        guard case .primitive(_, let args, let labels, _) = node.kind else { return c.view }
        let r = c.r
        let rows = r.forEachRows(KArgs(args: args, labels: labels))
        let interp = c.interp
        var each = AnyView(ForEach(rows) { row in r.renderList(row.views) })
        if case .function(let df)? = deleteFn {
            each = AnyView(ForEach(rows) { row in r.renderList(row.views) }
                .onDelete { offsets in interp.perform(df, [.native(.indexSet(offsets))]) })
        }
        if case .function(let mf)? = moveFn {
            each = AnyView(ForEach(rows) { row in r.renderList(row.views) }
                .onDelete(perform: deleteFn.flatMap { if case .function(let df) = $0 { return { offsets in interp.perform(df, [.native(.indexSet(offsets))]) } }; return nil })
                .onMove { from, to in interp.perform(mf, [.native(.indexSet(from)), .int(to)]) })
        }
        return each
    }
}
