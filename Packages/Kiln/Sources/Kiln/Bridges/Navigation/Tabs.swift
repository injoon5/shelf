//
//  Tabs.swift
//  Bridges: TabView with Tab, Tab(role: .search) and TabSection, the tab
//  modifiers, and the tab bar's
//
//  A `TabView` of `Tab`s is SwiftUI's own, built from a `ForEach` of tab
//  content: each `Tab` keeps its value, role, badge and the other `TabContent`
//  modifiers written on it, and its content is evaluated only when SwiftUI
//  shows it. A `TabView` of views with `.tabItem` is the older form.
//

import SwiftUI

/// A `Tab` or a `TabSection`, as the app described it.
struct KTab: Identifiable {
    let id: Int
    var value: KV = .nilValue
    var title = ""
    var systemImage: String?
    var image: String?
    var role: String?
    var content: AnyView = AnyView(EmptyView())
    var label: AnyView?
    var badge: Text?
    var hidden = false
    var disabled = false
    var accessibilityLabel: Text?
    var accessibilityHint: Text?
    var accessibilityValue: Text?
    var accessibilityIdentifier: String?
    var inputLabels: [Text] = []
    var customizationID: String?
    var visibility: Visibility = .automatic
    var placement = "automatic"
    var help: Text?
    var contextMenu: AnyView?
    var swipe: (leading: Bool, full: Bool, content: AnyView)?
    var popover: (shown: Binding<Bool>, content: AnyView)?
    // A section.
    var isSection = false
    var children: [KTab] = []
    var header: AnyView?
    var sectionActions: AnyView?
    var expansion: String?
}

@available(iOS 18.0, macOS 15.0, *)
struct KTabsContent: TabContent {
    let tabs: [KTab]
    var body: some TabContent<KV> {
        ForEach(tabs) { tab in KTabEntry(tab: tab) }
    }
}

@available(iOS 18.0, macOS 15.0, *)
struct KTabEntry: TabContent {
    let tab: KTab
    var body: some TabContent<KV> {
        if tab.isSection {
            KTabSectionContent(tab: tab)
        } else {
            KTabLeaf(tab: tab)
        }
    }
}

@available(iOS 18.0, macOS 15.0, *)
struct KTabSectionContent: TabContent {
    let tab: KTab
    var body: some TabContent<KV> {
        if let actions = tab.sectionActions {
            section.sectionActions { actions }
        } else {
            section
        }
    }

    @TabContentBuilder<KV> var section: some TabContent<KV> {
        TabSection {
            ForEach(tab.children) { child in KTabLeaf(tab: child) }
        } header: {
            if let header = tab.header { header } else { Text(tab.title) }
        }
        .customizationID(tab.customizationID ?? "kiln.section.\(tab.id)")
    }
}

@available(iOS 18.0, macOS 15.0, *)
struct KTabLeaf: TabContent {
    let tab: KTab
    var body: some TabContent<KV> {
        if let menu = tab.contextMenu {
            decorated.contextMenu { menu }
        } else {
            decorated
        }
    }

    @TabContentBuilder<KV> var decorated: some TabContent<KV> {
        base
            .badge(tab.badge)
            .hidden(tab.hidden)
            .accessibilityLabel(tab.accessibilityLabel ?? Text(""), isEnabled: tab.accessibilityLabel != nil)
            .accessibilityHint(tab.accessibilityHint ?? Text(""), isEnabled: tab.accessibilityHint != nil)
            .accessibilityValue(tab.accessibilityValue ?? Text(""), isEnabled: tab.accessibilityValue != nil)
            .accessibilityIdentifier(tab.accessibilityIdentifier ?? "", isEnabled: tab.accessibilityIdentifier != nil)
            .accessibilityInputLabels(tab.inputLabels, isEnabled: !tab.inputLabels.isEmpty)
            .customizationID(tab.customizationID ?? "kiln.tab.\(tab.id)")
            .defaultVisibility(tab.visibility, for: .tabBar)
            .tabPlacement(placement)
    }

    var placement: TabPlacement {
        #if os(iOS)
        if tab.placement == "sidebarOnly" { return .sidebarOnly }
        #endif
        return tab.placement == "pinned" ? .pinned : .automatic
    }

    @TabContentBuilder<KV> var base: some TabContent<KV> {
        if let label = tab.label {
            Tab(value: tab.value, role: role) { content } label: { label }
        } else if let image = tab.image {
            Tab(tab.title, image: image, value: tab.value, role: role) { content }
        } else if tab.role == "search", tab.systemImage == nil, tab.title.isEmpty {
            Tab(value: tab.value, role: .search) { content }
        } else {
            Tab(tab.title, systemImage: tab.systemImage ?? "circle", value: tab.value, role: role) { content }
        }
    }

    var role: TabRole? {
        switch tab.role {
        case "search": return .search
        case "prominent":
            #if os(iOS)
            if #available(iOS 27.0, *) { return .prominent }
            #endif
            return nil
        default: return nil
        }
    }

    /// The tab's view, with what's written on the tab that SwiftUI applies to views.
    var content: AnyView {
        var v = tab.content
        if let help = tab.help { v = AnyView(v.help(help)) }
        if let s = tab.swipe { v = AnyView(v.swipeActions(edge: s.leading ? .leading : .trailing, allowsFullSwipe: s.full) { s.content }) }
        if let p = tab.popover { v = AnyView(v.popover(isPresented: p.shown) { p.content }) }
        if tab.disabled { v = AnyView(v.disabled(true)) }
        return v
    }
}

/// A `TabView` with no `selection:` keeps its own.
@available(iOS 18.0, macOS 15.0, *)
struct KTabHost: View {
    let tabs: [KTab]
    @State private var selection: KV?
    var body: some View {
        TabView(selection: Binding<KV>(get: { selection ?? KTabHost.first(tabs) }, set: { selection = $0 })) { KTabsContent(tabs: tabs) }
    }

    static func first(_ tabs: [KTab]) -> KV {
        for t in tabs {
            if t.isSection, let c = t.children.first { return c.value }
            if !t.isSection { return t.value }
        }
        return .int(0)
    }
}

extension NavigationBridges {
    static func tabs(_ r: KRegistry) {
        r.view("TabView", .navigation, notes: "`Tab`s (with `value:`, `role: .search`) and `TabSection`s, or views with `.tabItem`; `selection:` is the tab's value.") { v in
            v.form("selection:binding? content:content") { c in tabView(c) }
        }
        r.view("Tab", .navigation, notes: "A title with `systemImage:` or `image:`, `value:` for `TabView(selection:)`, and `role: .search`.") { v in
            v.manifestKind = "content"
            v.forms(["_:title systemImage:string content:content", "_:title systemImage:string value:any role:any? content:content",
                     "_:title systemImage:string role:any content:content",
                     "_:title image:string value:any? role:any? content:content",
                     "role:any content:content", "role:any content:content label:content",
                     "value:any role:any? content:content", "value:any? role:any? content:content label:content", "content:content label:content",
                     "content:content"]) { c in
                c.r.renderContent(c["content"] ?? c.a.firstFunction)
            }
        }
        r.view("TabSection", .navigation, introduced: "18.0", notes: "Groups tabs in the iPad sidebar; on iPhone its tabs are in the tab bar.") { v in
            v.manifestKind = "content"
            v.forms(["_:title content:content", "content:content", "content:content header:content"]) { c in c.r.renderContent(c["content"] ?? c.a.firstFunction) }
        }
        r.view("AnyTabContent", .navigation, introduced: "18.0") { v in
            v.manifestKind = "content"
            v.form("_:any") { c in c.r.renderList(KBuiltins.asViews(c[0] ?? .void, c.interp)) }
        }
        r.modifier("tabItem", .navigation) { m in
            m.form("_:content") { c, view in
                let content = c.content(0)
                view.tabItem { content }
            }
        }
        r.modifier("badge", .navigation, notes: "A count or text, on a list row or a tab.") { m in
            m.form("_:title") { c, view in
                if let n = c.int(0) { AnyView(view.badge(n)) }
                else if case .string(let s)? = c[0] { AnyView(view.badge(s)) }
                else { view }
            }
            m.form("_:title", receiver: "TabContent") { _, view in view }
        }
        tabContentModifiers(r)
        tabViewModifiers(r)
    }

    // MARK: TabContent modifiers (read by the TabView)

    static func tabContentModifiers(_ r: KRegistry) {
        // Each is read off the `Tab` by `tabView`; as a view modifier none of these does anything.
        let forms: [(String, [String])] = [
            ("customizationID", ["_:string"]),
            ("customizationBehavior", ["_:any for:any..."]),
            ("defaultVisibility", ["_:Visibility for:any..."]),
            ("tabPlacement", ["_:any"]),
            ("defaultSectionExpansion", ["_:any"]),
            ("sectionActions", ["content:content"]),
        ]
        for (name, sigs) in forms {
            r.modifier(name, .navigation, introduced: name == "defaultSectionExpansion" ? "27.0" : "18.0") { m in
                for s in sigs { m.form(s, receiver: "TabContent") { _, view in view } }
                if name == "sectionActions" {
                    m.form("content:content") { c, view in sectionActions(c, view) }
                }
                if name == "customizationBehavior" {
                    m.form("_:any", receiver: "ToolbarContent") { _, view in view }
                }
            }
        }
    }

    @MainActor static func sectionActions(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            let content = c.content("content")
            return AnyView(view.sectionActions { content })
        }
        #endif
        return view
    }

    // MARK: TabView

    @MainActor static func tabView(_ c: KCall) -> AnyView {
        let r = c.r
        let children = r.content(c.a.lastFunction).flatMap(\.flattened)
        let usesTabs = children.contains { ["Tab", "TabSection", "AnyTabContent"].contains(r.rootPrimitiveName($0) ?? "") || r.rootPrimitiveName($0) == "ForEach" }
        if usesTabs, #available(iOS 18.0, macOS 15.0, *) {
            var next = 0
            let tabs = children.flatMap { tabs(from: $0, r, &next) }
            if let sel = c.kbinding("selection") {
                return AnyView(TabView(selection: Binding<KV>(get: { sel.get() }, set: { sel.set($0) })) { KTabsContent(tabs: tabs) })
            }
            return AnyView(KTabHost(tabs: tabs))
        }
        let items = ForEach(Array(children.enumerated()), id: \.offset) { i, child in tabContent(r, child, index: i) }
        if let sel = c.kbinding("selection") {
            return AnyView(TabView(selection: Binding<KV>(get: { sel.get() }, set: { sel.set($0) })) { items })
        }
        return AnyView(TabView { items })
    }

    /// The `Tab`s a child of the `TabView` describes (a `ForEach` of tabs is several).
    @MainActor static func tabs(from v: KView, _ r: KRenderer, _ next: inout Int) -> [KTab] {
        guard case .primitive(let name, let args, let labels, _)? = r.rootPrimitive(v) else { return [] }
        let a = KArgs(args: args, labels: labels)
        switch name {
        case "ForEach":
            var out: [KTab] = []
            for row in r.forEachRows(a) { for view in row.views.flatMap(\.flattened) { out += tabs(from: view, r, &next) } }
            return out
        case "AnyTabContent":
            return KBuiltins.asViews(a.first ?? .void, r.interp).flatMap { tabs(from: $0, r, &next) }
        case "TabSection":
            var t = KTab(id: next)
            next += 1
            t.isSection = true
            t.title = r.string(a.first.flatMap { if case .string = $0 { return $0 }; return nil }) ?? ""
            if let h = a["header"] { t.header = r.renderContent(h) }
            let body = a["content"] ?? a.firstFunction
            t.children = r.content(body).flatMap(\.flattened).flatMap { tabs(from: $0, r, &next) }
            if let m = v.modifier("sectionActions"), let f = m.args.last { t.sectionActions = r.renderContent(f) }
            if let m = v.modifier("customizationID") { t.customizationID = m.first.flatMap { r.string($0) } }
            if let m = v.modifier("defaultSectionExpansion"), case .native(.implicit(let n, _))? = m.first { t.expansion = n }
            return [t]
        case "Tab":
            var t = KTab(id: next)
            next += 1
            if case .string? = a.first, (labels.first ?? nil) == nil { t.title = r.string(a.first) ?? "" }
            t.systemImage = a["systemImage"].flatMap { r.string($0) }
            t.image = a["image"].flatMap { r.string($0) }
            t.value = a["value"] ?? .int(1000 + t.id)
            if case .native(.implicit(let n, _))? = a["role"] { t.role = n }
            let fn = a["content"] ?? a.firstFunction
            t.content = AnyView(KLazyView { r.renderContent(fn) })
            if let l = a["label"] { t.label = r.renderContent(l) }
            readTabModifiers(v, into: &t, r)
            return [t]
        default:
            return []
        }
    }

    @MainActor static func readTabModifiers(_ v: KView, into t: inout KTab, _ r: KRenderer) {
        func text(_ m: KModifier?) -> Text? {
            guard let first = m?.first else { return nil }
            if case .view(let tv) = first { return r.text(tv) }
            if first.isNil { return nil }
            return r.string(first).map { Text($0) }
        }
        var node = v
        while case .modified(let base, let m) = node.kind {
            switch m.name {
            case "badge":
                if let n = m.first?.asInt { t.badge = n == 0 ? nil : Text("\(n)") } else { t.badge = text(m) }
            case "hidden": t.hidden = m.first.map { r.interp.truthy($0) } ?? true
            case "disabled": t.disabled = m.first.map { r.interp.truthy($0) } ?? true
            case "accessibilityLabel": t.accessibilityLabel = text(m)
            case "accessibilityHint": t.accessibilityHint = text(m)
            case "accessibilityValue": t.accessibilityValue = text(m)
            case "accessibilityIdentifier": t.accessibilityIdentifier = m.first.flatMap { r.string($0) }
            case "accessibilityInputLabels": t.inputLabels = (m.first?.asArray ?? []).compactMap { r.string($0) }.map { Text($0) }
            case "customizationID": t.customizationID = m.first.flatMap { r.string($0) }
            case "defaultVisibility": t.visibility = KControlValues.visibility(m.first)
            case "tabPlacement": if case .native(.implicit(let n, _))? = m.first { t.placement = n }
            case "help": t.help = text(m)
            case "contextMenu": if let f = m.args.first { t.contextMenu = r.renderContent(f) }
            case "swipeActions":
                if let f = m.args.last {
                    let edge = m.arg("edge").flatMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil }
                    t.swipe = (edge == "leading", m.arg("allowsFullSwipe").map { r.interp.truthy($0) } ?? true, r.renderContent(f))
                }
            case "popover":
                if let b = r.binding(m.arg("isPresented")), let f = m.args.last { t.popover = (r.boolBinding(b), AnyView(KLazyView { r.renderContent(f) })) }
            default: break
            }
            node = base
        }
    }

    @MainActor static func tabContent(_ r: KRenderer, _ child: KView, index: Int) -> AnyView {
        AnyView(r.render(child).tag(child.modifier("tag")?.first ?? .int(index)))
    }

    // MARK: The tab view's modifiers

    static func tabViewModifiers(_ r: KRegistry) {
        r.modifier("tabViewStyle", .navigation, notes: "`.page` (a swiping carousel, with `indexDisplayMode:`), `.sidebarAdaptable`, `.tabBarOnly`.") { m in
            m.styles("TabViewStyle", ["automatic", "page", "sidebarAdaptable", "tabBarOnly"])
            m.form("_:TabViewStyle") { c, view in tabViewStyle(c, view) }
        }
        r.modifier("indexViewStyle", .navigation) { m in
            m.styles("IndexViewStyle", ["page"])
            m.form("_:IndexViewStyle") { c, view in
                #if os(iOS)
                if case .native(.implicit("page", let args))? = c[0], case .native(.implicit(let mode, _))? = args.first {
                    AnyView(view.indexViewStyle(.page(backgroundDisplayMode: mode == "always" ? .always : (mode == "never" ? .never : (mode == "interactive" ? .interactive : .automatic)))))
                } else {
                    AnyView(view.indexViewStyle(.page))
                }
                #else
                view
                #endif
            }
        }
        r.modifier("tabBarMinimizeBehavior", .navigation, introduced: "26.0") { m in
            m.form("_:TabBarMinimizeBehavior") { c, view in
                #if os(iOS)
                if #available(iOS 26.0, *) {
                    AnyView(view.tabBarMinimizeBehavior(c.pick(0, ["onScrollDown": TabBarMinimizeBehavior.onScrollDown, "onScrollUp": .onScrollUp, "never": .never]) ?? .automatic))
                } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("tabViewBottomAccessory", .navigation, introduced: "26.0", notes: "A bar above the tab bar (a mini player); `isEnabled:` hides it.") { m in
            m.forms(["content:content", "isEnabled:bool content:content"]) { c, view in bottomAccessory(c, view) }
        }
        r.modifier("tabViewSearchActivation", .navigation, introduced: "26.0") { m in
            m.form("_:TabSearchActivation") { c, view in
                #if os(iOS)
                if #available(iOS 26.0, *) {
                    AnyView(view.tabViewSearchActivation(c.symbol(0) == "searchTabSelection" ? .searchTabSelection : .automatic))
                } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("tabViewCustomization", .navigation, introduced: "18.0", notes: "Bound to a `TabViewCustomization` in `@State`; the iPad sidebar's edits are kept while the app is open.") { m in
            m.form("_:binding?") { c, view in
                if #available(iOS 18.0, macOS 15.0, *), let b = c.kbinding(0) {
                    AnyView(view.tabViewCustomization(Binding<TabViewCustomization>(get: {
                        if case .native(.object(_, let ref)) = b.get(), let box = ref.value as? KTabCustomizationBox { return box.value }
                        return TabViewCustomization()
                    }, set: { b.set(.native(.object("TabViewCustomization", KRef(KTabCustomizationBox($0))))) })))
                } else { view }
            }
        }
        r.type("TabViewCustomization", .navigation, introduced: "18.0") { t in
            t.initializer("") { _ in
                if #available(iOS 18.0, macOS 15.0, *) { return .native(.object("TabViewCustomization", KRef(KTabCustomizationBox(TabViewCustomization())))) }
                return .nilValue
            }
        }
        for name in ["tabViewSidebarHeader", "tabViewSidebarFooter", "tabViewSidebarBottomBar"] {
            r.modifier(name, .navigation, introduced: "18.0", notes: "In the iPad sidebar of a `.sidebarAdaptable` `TabView`.") { m in
                m.form("content:content") { c, view in sidebarAccessory(name, c, view) }
            }
        }
        r.modifier("defaultAdaptableTabBarPlacement", .navigation, introduced: "18.0") { m in
            m.form("_:any?") { c, view in tabBarPlacement(c, view, adaptable: true) }
        }
        r.modifier("defaultTabBarPlacement", .navigation, introduced: "27.0") { m in
            m.form("_:any") { c, view in tabBarPlacement(c, view, adaptable: false) }
        }
        r.liveEnvironment("isTabBarShowingSections", .navigation, read: { env, _ in
            #if os(iOS)
            if #available(iOS 18.0, *) { return .bool(env.isTabBarShowingSections) }
            #endif
            return .bool(false)
        })
        r.liveEnvironment("tabViewBottomAccessoryPlacement", .navigation, notes: "`.inline` while the tab bar is minimized, else `.expanded`.", read: { env, _ in
            #if os(iOS)
            if #available(iOS 26.0, *), let p = env.tabViewBottomAccessoryPlacement {
                return .native(.implicit(p == .inline ? "inline" : "expanded", []))
            }
            #endif
            return .nilValue
        })
    }

    @MainActor static func tabViewStyle(_ c: KCall, _ view: AnyView) -> AnyView {
        switch c.symbol(0) {
        #if os(iOS)
        case "page":
            if case .native(.implicit(_, let args))? = c[0], case .native(.implicit(let mode, _))? = args.first {
                return AnyView(view.tabViewStyle(.page(indexDisplayMode: mode == "never" ? .never : (mode == "always" ? .always : .automatic))))
            }
            return AnyView(view.tabViewStyle(.page))
        #endif
        case "sidebarAdaptable":
            if #available(iOS 18.0, macOS 15.0, *) { return AnyView(view.tabViewStyle(.sidebarAdaptable)) }
            return view
        case "tabBarOnly":
            if #available(iOS 18.0, macOS 15.0, *) { return AnyView(view.tabViewStyle(.tabBarOnly)) }
            return view
        default: return view
        }
    }

    @MainActor static func bottomAccessory(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            let content = c.content("content")
            if c["isEnabled"] != nil, #available(iOS 26.1, *) {
                return AnyView(view.tabViewBottomAccessory(isEnabled: c.bool("isEnabled", default: true)) { content })
            }
            return AnyView(view.tabViewBottomAccessory { content })
        }
        #endif
        return view
    }

    @MainActor static func sidebarAccessory(_ name: String, _ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            let content = c.content("content")
            switch name {
            case "tabViewSidebarHeader": return AnyView(view.tabViewSidebarHeader { content })
            case "tabViewSidebarFooter": return AnyView(view.tabViewSidebarFooter { content })
            default: return AnyView(view.tabViewSidebarBottomBar { content })
            }
        }
        #endif
        return view
    }

    @MainActor static func tabBarPlacement(_ c: KCall, _ view: AnyView, adaptable: Bool) -> AnyView {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            let p: AdaptableTabBarPlacement = c.symbol(0) == "sidebar" ? .sidebar : (c.symbol(0) == "tabBar" ? .tabBar : .automatic)
            if adaptable { return AnyView(view.defaultAdaptableTabBarPlacement(p)) }
            if #available(iOS 27.0, *) { return AnyView(view.defaultTabBarPlacement(p)) }
        }
        #endif
        return view
    }
}

@available(iOS 18.0, macOS 15.0, *)
final class KTabCustomizationBox {
    let value: TabViewCustomization
    init(_ value: TabViewCustomization) { self.value = value }
}

extension KRenderer {
    func rootPrimitiveName(_ v: KView) -> String? {
        if case .primitive(let n, _, _, _)? = rootPrimitive(v) { return n }
        return nil
    }
}
