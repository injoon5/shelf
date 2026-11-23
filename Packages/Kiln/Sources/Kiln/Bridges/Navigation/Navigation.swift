//
//  Navigation.swift
//  Bridges: navigation stacks, links, tabs, toolbars and search
//
//  Presentations (sheets, alerts, dialogs) are in Presentations.swift.
//

import SwiftUI

@objc(KilnBridges_Navigation)
final class NavigationBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        stacks(r)
        tabs(r)
        toolbars(r)
        presentations(r)
        delegates(r)
    }

    // MARK: Stacks and links

    static func stacks(_ r: KRegistry) {
        r.view("NavigationStack", .navigation, support: .partial, notes: "`path:` isn't kept; push with `NavigationLink(value:)` and `.navigationDestination(for:)`.") { v in
            v.form("path:binding? root:content") { c in NavigationStack { c.r.renderContent(c.a.lastFunction) } }
        }
        r.view("NavigationView", .navigation) { v in
            v.form("content:content") { c in NavigationStack { c.r.renderContent(c.a.lastFunction) } }
        }
        r.view("NavigationSplitView", .navigation, support: .partial, notes: "Shown as a stack of its sidebar.") { v in
            v.forms(["columnVisibility:binding? sidebar:content detail:content", "columnVisibility:binding? sidebar:content content:content detail:content"]) { c in
                NavigationStack { c.r.renderContent(c.a.firstFunction) }
            }
        }
        r.view("NavigationLink", .navigation) { v in
            v.forms(["_:title value:any?", "value:any? label:content", "_:title destination:content", "destination:content label:content"]) { c in
                navigationLink(c)
            }
        }
        r.modifier("navigationTitle", .navigation) { m in
            m.form("_:title") { c, view in
                if let s = c.string(0) { view.navigationTitle(s) } else { view }
            }
        }
        r.modifier("navigationBarTitleDisplayMode", .navigation) { m in
            m.form("_:NavigationBarItem.TitleDisplayMode") { c, view in
                #if os(iOS)
                if let n = c.symbol(0) { view.navigationBarTitleDisplayMode(n == "inline" ? .inline : (n == "large" ? .large : .automatic)) } else { view }
                #else
                view
                #endif
            }
        }
        for name in ["navigationBarHidden", "navigationBarBackButtonHidden"] {
            r.modifier(name, .navigation, support: name == "navigationBarHidden" ? .partial : .full,
                       notes: name == "navigationBarHidden" ? "Hides the back button only." : nil) { m in
                m.form("_:bool?") { c, view in view.navigationBarBackButtonHidden(c.bool(0, default: true)) }
            }
        }
        r.modifier("navigationDestination", .navigation, support: .partial, notes: "`for:` with any type the links push, and `isPresented:`.") { m in
            m.forms(["for:any destination:content", "isPresented:binding destination:content"]) { c, view in
                navigationDestination(c, view)
            }
        }
        r.modifier("searchable", .navigation, support: .partial, notes: "`text:` and `prompt:`.") { m in
            m.forms(["text:binding placement:any? prompt:title?", "text:binding isPresented:binding placement:any? prompt:title?"]) { c, view in
                if let b = c.kbinding("text") {
                    view.searchable(text: c.r.stringBinding(b), prompt: c.string("prompt") ?? "Search")
                } else {
                    view
                }
            }
        }
    }

    @MainActor static func navigationLink(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        let title = ControlsBridges.stringTitle(c)
        if let value = a["value"] {
            let label: AnyView = title.map { AnyView(Text($0)) } ?? r.renderContent(a.lastFunction)
            return AnyView(NavigationLink(value: KNavValue(value: value)) { label })
        }
        let dest = a["destination"] ?? (title != nil ? a.lastFunction : nil)
        let destination = KLazyView {
            if let dest, r.isFunction(dest) { return r.renderContent(dest) }
            return r.renderList(KBuiltins.asViews(dest ?? .void, c.interp))
        }
        if let title { return AnyView(NavigationLink(title) { destination }) }
        let labelFn = a["label"] ?? a.lastFunction
        return AnyView(NavigationLink { destination } label: { r.renderContent(labelFn) })
    }

    @MainActor static func navigationDestination(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let fn = c.last, c.r.isFunction(fn) else { return view }
        let r = c.r
        if let b = c.kbinding("isPresented") {
            return AnyView(view.navigationDestination(isPresented: r.boolBinding(b)) { KLazyView { r.renderContent(fn) } })
        }
        return AnyView(view.navigationDestination(for: KNavValue.self) { nav in KLazyView { r.renderContent(fn, [nav.value]) } })
    }

    // MARK: Tabs

    static func tabs(_ r: KRegistry) {
        r.view("TabView", .navigation, support: .partial, notes: "Tabs from `.tabItem` or `Tab`.") { v in
            v.form("selection:binding? content:content") { c in tabView(c) }
        }
        r.view("Tab", .navigation, support: .partial, notes: "With a title, `systemImage:` and `value:`; `role:` is ignored.") { v in
            v.manifestKind = "content"
            v.forms(["_:title systemImage:string content:content", "_:title systemImage:string value:any role:any? content:content",
                     "_:title image:string value:any? content:content", "value:any? role:any? content:content label:content"]) { c in
                c.r.renderContent(c.a.lastFunction)
            }
        }
        r.modifier("tabItem", .navigation) { m in
            m.form("_:content") { c, view in
                let content = c.content(0)
                view.tabItem { content }
            }
        }
        r.modifier("badge", .navigation) { m in
            m.form("_:title") { c, view in
                if let n = c.int(0) { AnyView(view.badge(n)) }
                else if case .string(let s)? = c[0] { AnyView(view.badge(s)) }
                else { view }
            }
        }
    }

    @MainActor static func tabView(_ c: KCall) -> AnyView {
        let r = c.r
        let children = r.content(c.a.lastFunction).flatMap(\.flattened)
        let tabs = ForEach(Array(children.enumerated()), id: \.offset) { i, child in tabContent(r, child, index: i) }
        if let sel = c.kbinding("selection") {
            return AnyView(TabView(selection: Binding<KV>(get: { sel.get() }, set: { sel.set($0) })) { tabs })
        }
        return AnyView(TabView { tabs })
    }

    @MainActor static func tabContent(_ r: KRenderer, _ child: KView, index: Int) -> AnyView {
        if case .primitive("Tab", let args, let labels, _) = child.kind {
            let a = KArgs(args: args, labels: labels)
            let title = r.string(a.first) ?? "Tab"
            let icon = a["systemImage"].flatMap { r.string($0) } ?? "circle"
            return AnyView(r.renderContent(a.lastFunction).tabItem { Label(title, systemImage: icon) }.tag(a["value"] ?? .int(index)))
        }
        return AnyView(r.render(child).tag(child.modifier("tag")?.first ?? .int(index)))
    }

    // MARK: Toolbars

    static let placements = ["automatic", "principal", "cancellationAction", "confirmationAction", "destructiveAction", "primaryAction",
                             "topBarLeading", "topBarTrailing", "bottomBar", "keyboard", "navigationBarLeading", "navigationBarTrailing"]

    static func toolbars(_ r: KRegistry) {
        for name in ["ToolbarItem", "ToolbarItemGroup"] {
            r.view(name, .navigation, notes: "In `.toolbar { }`, by placement.") { v in
                v.manifestKind = "content"
                v.forms(name == "ToolbarItem" ? ["placement:ToolbarItemPlacement? content:content", "id:string placement:ToolbarItemPlacement? content:content"]
                                              : ["placement:ToolbarItemPlacement? content:content"]) { c in
                    c.r.renderContent(c.a.lastFunction)
                }
            }
        }
        r.type("ToolbarItemPlacement", .navigation) { t in
            t.membersInManifest = true
            for p in placements { t.staticProperty(p) { _ in .native(.implicit(p, [])) } }
        }
        r.modifier("toolbar", .navigation, support: .partial, notes: "Items by placement; `.toolbar(.hidden)` isn't supported.") { m in
            m.form("content:content") { c, view in toolbar(c, view) }
            m.form("_:Visibility for:any?") { _, view in view }
        }
        r.modifier("toolbarBackground", .navigation, support: .stub) { m in m.stub(["_:any for:any?"]) }
        r.modifier("toolbarColorScheme", .navigation, support: .stub) { m in m.stub(["_:ColorScheme? for:any?"]) }
    }

    @MainActor static func toolbar(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let fn = c.last, c.r.isFunction(fn) else { return view }
        let r = c.r
        var groups: [String: [AnyView]] = [:]
        for item in r.content(fn).flatMap(\.flattened) {
            if case .primitive(let n, let args, let labels, _) = item.kind, n == "ToolbarItem" || n == "ToolbarItemGroup" {
                let a = KArgs(args: args, labels: labels)
                groups[placementKey(a["placement"]), default: []].append(r.renderContent(a.lastFunction))
            } else {
                groups["automatic", default: []].append(r.render(item))
            }
        }
        return AnyView(view.toolbar { KToolbar(groups: groups) })
    }

    static func placementKey(_ v: KV?) -> String {
        guard case .native(.implicit(let n, _))? = v else { return "automatic" }
        switch n {
        case "navigationBarTrailing": return "topBarTrailing"
        case "navigationBarLeading": return "topBarLeading"
        default: return n
        }
    }
}

/// Toolbar items grouped by placement (ToolbarContent needs a static shape).
struct KToolbar: ToolbarContent {
    let groups: [String: [AnyView]]

    func items(_ key: String) -> some View {
        ForEach(Array((groups[key] ?? []).enumerated()), id: \.offset) { _, v in v }
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) { items("automatic") }
        ToolbarItemGroup(placement: .principal) { items("principal") }
        ToolbarItemGroup(placement: .cancellationAction) { items("cancellationAction") }
        ToolbarItemGroup(placement: .confirmationAction) { items("confirmationAction") }
        ToolbarItemGroup(placement: .destructiveAction) { items("destructiveAction") }
        ToolbarItemGroup(placement: .primaryAction) { items("primaryAction") }
        #if os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) { items("topBarLeading") }
        ToolbarItemGroup(placement: .topBarTrailing) { items("topBarTrailing") }
        ToolbarItemGroup(placement: .bottomBar) { items("bottomBar") }
        #endif
    }
}
