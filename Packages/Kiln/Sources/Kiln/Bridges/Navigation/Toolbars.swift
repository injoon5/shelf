//
//  Toolbars.swift
//  Bridges: toolbars, their items and placements, and the bars' modifiers
//
//  `.toolbar { … }` is SwiftUI's own: each `ToolbarItem`, `ToolbarItemGroup`,
//  `ToolbarSpacer` (iOS 26), `DefaultToolbarItem`, `ToolbarTitleMenu` and
//  `ToolbarOverflowMenu` (iOS 27) is one entry of a `ForEach` of toolbar
//  content, in the app's order, with the `ToolbarContent` modifiers written on
//  it (`visibilityPriority`, `sharedBackgroundVisibility`…).
//

import SwiftUI

/// One entry of a toolbar, as the app described it.
struct KToolbarEntry: Identifiable {
    enum Kind { case item, group, spacer(fixed: Bool), defaultItem(String), titleMenu, overflowMenu }
    let id: Int
    var kind: Kind
    var placement: String
    var views: [AnyView] = []
    var priority: String?
    var sharedBackground: Visibility?
    var zoomID: KV?
    var marginsRemoved = false
    var axisBehavior: String?
}

struct KToolbarContent: ToolbarContent {
    let entries: [KToolbarEntry]
    /// Items by position, not a `ForEach`: SwiftUI doesn't redraw an item of a
    /// toolbar `ForEach` whose id it has seen, so `.disabled(title.isEmpty)` on a
    /// toolbar button would never update. 24 items is more than any bar shows.
    var body: some ToolbarContent {
        KToolbarSlots(entries: entries, from: 0)
        KToolbarSlots(entries: entries, from: 6)
        KToolbarSlots(entries: entries, from: 12)
        KToolbarSlots(entries: entries, from: 18)
    }
}

struct KToolbarSlots: ToolbarContent {
    let entries: [KToolbarEntry]
    let from: Int
    var body: some ToolbarContent {
        if entries.count > from { KToolbarEntryContent(entry: entries[from]) }
        if entries.count > from + 1 { KToolbarEntryContent(entry: entries[from + 1]) }
        if entries.count > from + 2 { KToolbarEntryContent(entry: entries[from + 2]) }
        if entries.count > from + 3 { KToolbarEntryContent(entry: entries[from + 3]) }
        if entries.count > from + 4 { KToolbarEntryContent(entry: entries[from + 4]) }
        if entries.count > from + 5 { KToolbarEntryContent(entry: entries[from + 5]) }
    }
}

struct KToolbarEntryContent: ToolbarContent {
    let entry: KToolbarEntry
    @Environment(\.kilnZoomNamespace) private var namespace

    var body: some ToolbarContent {
        if #available(iOS 27.0, macOS 27.0, *) {
            decorated
                .visibilityPriority(entry.priority == "high" ? .high : (entry.priority == "low" ? .low : .automatic))
                .contentMarginsRemoved(entry.marginsRemoved)
        } else {
            decorated
        }
    }

    @ToolbarContentBuilder var decorated: some ToolbarContent {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            if let id = entry.zoomID, let namespace {
                kind.sharedBackgroundVisibility(entry.sharedBackground ?? .automatic).matchedTransitionSource(id: id, in: namespace)
            } else {
                kind.sharedBackgroundVisibility(entry.sharedBackground ?? .automatic)
            }
        } else {
            kind
        }
        #else
        kind
        #endif
    }

    @ToolbarContentBuilder var kind: some ToolbarContent {
        switch entry.kind {
        case .spacer(let fixed):
            if #available(iOS 26.0, macOS 26.0, *) {
                ToolbarSpacer(fixed ? .fixed : .flexible, placement: KToolbarPlacement.placement(entry.placement))
            } else {
                ToolbarItem(placement: KToolbarPlacement.placement(entry.placement)) { Spacer() }
            }
        case .defaultItem(let k):
            if #available(iOS 26.0, macOS 26.0, *) {
                DefaultToolbarItem(kind: k == "search" ? .search : (k == "sidebarToggle" ? .sidebarToggle : .title), placement: KToolbarPlacement.placement(entry.placement))
            } else {
                ToolbarItem(placement: .automatic) { EmptyView() }
            }
        case .titleMenu:
            ToolbarTitleMenu { group }
        case .overflowMenu:
            #if os(iOS)
            if #available(iOS 27.0, *) {
                ToolbarOverflowMenu { group }
            } else {
                ToolbarItem(placement: .primaryAction) { Menu { group } label: { Image(systemName: "ellipsis") } }
            }
            #else
            ToolbarItem(placement: .primaryAction) { Menu { group } label: { Image(systemName: "ellipsis") } }
            #endif
        case .group:
            ToolbarItemGroup(placement: KToolbarPlacement.placement(entry.placement)) { group }
        case .item:
            ToolbarItem(placement: KToolbarPlacement.placement(entry.placement)) { group }
        }
    }

    @ViewBuilder var group: some View {
        ForEach(Array(entry.views.enumerated()), id: \.offset) { _, v in v }
    }
}

@MainActor
enum KToolbarPlacement {
    static let names = ["automatic", "principal", "navigation", "primaryAction", "secondaryAction", "status", "confirmationAction",
                        "cancellationAction", "destructiveAction", "keyboard", "topBarLeading", "topBarTrailing", "bottomBar",
                        "navigationBarLeading", "navigationBarTrailing", "title", "subtitle", "largeTitle", "largeSubtitle", "topBarPinnedTrailing"]

    nonisolated static func placement(_ name: String) -> ToolbarItemPlacement {
        switch name {
        case "principal": return .principal
        case "navigation": return .navigation
        case "primaryAction": return .primaryAction
        case "secondaryAction": return .secondaryAction
        case "status": return .status
        case "confirmationAction": return .confirmationAction
        case "cancellationAction": return .cancellationAction
        case "destructiveAction": return .destructiveAction
        #if os(iOS)
        case "keyboard": return .keyboard
        case "topBarLeading", "navigationBarLeading": return .topBarLeading
        case "topBarTrailing", "navigationBarTrailing": return .topBarTrailing
        case "bottomBar": return .bottomBar
        case "title":
            if #available(iOS 26.0, *) { return .title }
            return .principal
        case "subtitle":
            if #available(iOS 26.0, *) { return .subtitle }
            return .principal
        case "largeTitle":
            if #available(iOS 26.0, *) { return .largeTitle }
            return .principal
        case "largeSubtitle":
            if #available(iOS 26.0, *) { return .largeSubtitle }
            return .principal
        case "topBarPinnedTrailing":
            if #available(iOS 27.0, *) { return .topBarPinnedTrailing }
            return .topBarTrailing
        #endif
        default: return .automatic
        }
    }

    static func name(_ v: KV?) -> String {
        guard case .native(.implicit(let n, _))? = v else { return "automatic" }
        return n
    }
}

extension NavigationBridges {
    static func toolbars(_ r: KRegistry) {
        toolbarItems(r)
        toolbarContentModifiers(r)
        toolbarModifiers(r)
    }

    static func toolbarItems(_ r: KRegistry) {
        r.view("ToolbarItem", .navigation, notes: "In `.toolbar { }`, by placement.") { v in
            v.manifestKind = "content"
            v.forms(["placement:ToolbarItemPlacement? content:content", "id:string placement:ToolbarItemPlacement? content:content"]) { c in c.r.renderContent(c.a.lastFunction) }
        }
        r.view("ToolbarItemGroup", .navigation, notes: "In `.toolbar { }`: several items at one placement.") { v in
            v.manifestKind = "content"
            v.forms(["placement:ToolbarItemPlacement? content:content", "placement:ToolbarItemPlacement? content:content label:content"]) { c in c.r.renderContent(c["content"] ?? c.a.firstFunction) }
        }
        r.view("ToolbarSpacer", .navigation, introduced: "26.0", notes: "Separates toolbar items: `.flexible` (the default) or `.fixed`.") { v in
            v.manifestKind = "content"
            v.form("_:any? placement:ToolbarItemPlacement?") { _ in EmptyView() }
        }
        r.view("DefaultToolbarItem", .navigation, introduced: "26.0", notes: "Moves the system's `.search`, `.sidebarToggle` or `.title` item.") { v in
            v.manifestKind = "content"
            v.form("kind:any placement:ToolbarItemPlacement?") { _ in EmptyView() }
        }
        r.view("ToolbarTitleMenu", .navigation, notes: "A menu on the navigation title.") { v in
            v.manifestKind = "content"
            v.forms(["", "content:content"]) { _ in EmptyView() }
        }
        r.view("ToolbarOverflowMenu", .navigation, introduced: "27.0", notes: "Items for the toolbar's overflow (…) menu.") { v in
            v.manifestKind = "content"
            v.form("content:content") { _ in EmptyView() }
        }
        r.type("ToolbarItemPlacement", .navigation) { t in
            t.membersInManifest = true
            for p in KToolbarPlacement.names { t.staticProperty(p) { _ in .native(.implicit(p, [])) } }
        }
    }

    static func toolbarContentModifiers(_ r: KRegistry) {
        // Read off the item by `toolbar`.
        for (name, sig) in [("visibilityPriority", "_:any"), ("sharedBackgroundVisibility", "_:Visibility"), ("contentMarginsRemoved", "_:bool?"),
                            ("axisBehavior", "_:any"), ("defaultCustomization", "_:Visibility? options:any?")] {
            r.modifier(name, .navigation, introduced: ["visibilityPriority": "27.0", "sharedBackgroundVisibility": "26.0", "contentMarginsRemoved": "27.0",
                                                       "axisBehavior": "27.1"][name]) { m in
                m.form(sig, receiver: "ToolbarContent") { _, view in view }
            }
        }
    }

    static func toolbarModifiers(_ r: KRegistry) {
        r.modifier("toolbar", .navigation, notes: "Items by placement, in order, with `ToolbarSpacer`s; `.toolbar(.hidden, for:)` hides a bar.") { m in
            m.form("content:content") { c, view in toolbar(c, view) }
            m.form("id:string content:content") { c, view in toolbar(c, view) }
            m.form("_:Visibility for:any...") { c, view in toolbarVisibility(c, view) }
            m.form("removing:any?") { c, view in
                if c.symbol("removing") == "sidebarToggle" { AnyView(view.toolbar(removing: .sidebarToggle)) } else { view }
            }
        }
        r.modifier("toolbarVisibility", .navigation, introduced: "18.0") { m in
            m.form("_:Visibility for:any...") { c, view in toolbarVisibility(c, view) }
        }
        r.modifier("toolbarBackground", .navigation) { m in
            m.form("_:any for:any...") { c, view in toolbarBackground(c, view) }
        }
        r.modifier("toolbarBackgroundVisibility", .navigation, introduced: "18.0") { m in
            m.form("_:Visibility for:any...") { c, view in toolbarBackgroundVisibility(c, view) }
        }
        r.modifier("toolbarColorScheme", .navigation) { m in
            m.form("_:ColorScheme? for:any...") { c, view in toolbarColorScheme(c, view) }
        }
        r.modifier("toolbarRole", .navigation) { m in
            m.form("_:ToolbarRole") { c, view in
                switch c.symbol(0) {
                #if os(iOS)
                case "navigationStack": view.toolbarRole(.navigationStack)
                case "browser": view.toolbarRole(.browser)
                #endif
                case "editor": view.toolbarRole(.editor)
                default: view.toolbarRole(.automatic)
                }
            }
        }
        r.modifier("toolbarTitleDisplayMode", .navigation) { m in
            m.form("_:ToolbarTitleDisplayMode") { c, view in
                switch c.symbol(0) {
                case "inline": AnyView(view.toolbarTitleDisplayMode(.inline))
                #if os(iOS)
                case "large": AnyView(view.toolbarTitleDisplayMode(.large))
                case "inlineLarge": AnyView(view.toolbarTitleDisplayMode(.inlineLarge))
                #endif
                default: AnyView(view.toolbarTitleDisplayMode(.automatic))
                }
            }
        }
        r.modifier("toolbarTitleMenu", .navigation) { m in
            m.form("content:content") { c, view in
                let content = c.content("content")
                view.toolbarTitleMenu { content }
            }
        }
        r.modifier("toolbarOverflowMenu", .navigation, introduced: "27.0") { m in
            m.form("content:content") { c, view in iOS27Toolbar("toolbarOverflowMenu", c, view) }
        }
        for name in ["toolbarMinimizationBehavior", "toolbarMinimizationRestoration", "toolbarMinimizationSafeAreaAdjustment"] {
            r.modifier(name, .navigation, introduced: "27.0", notes: name == "toolbarMinimizationBehavior" ? "`.onScrollDown`, `.onScrollUp` or `.never`, for the bars named." : nil) { m in
                m.form("_:any for:any...") { c, view in iOS27Toolbar(name, c, view) }
            }
        }
        for name in ["toolbarVerticalBehavior", "toolbarVerticalCompressionBehavior"] {
            r.modifier(name, .navigation, introduced: "27.1") { m in
                m.form("_:any") { c, view in iOS27Toolbar(name, c, view) }
            }
        }
        r.modifier("contentToolbar", .navigation, introduced: "18.4", notes: "visionOS and macOS place these; on iPhone it shows nothing.") { m in
            m.form("for:any content:content") { _, view in view }
        }
        r.modifier("safeAreaBar", .navigation, introduced: "26.0", notes: "A bar that scroll edge effects blur under, like `.safeAreaInset`.") { m in
            m.form("edge:any alignment:any? spacing:number? content:content") { c, view in safeAreaBar(c, view) }
        }
        r.liveEnvironment("toolbarLabelStyle", .navigation, read: { env, _ in
            if #available(iOS 18.0, macOS 15.0, *), env.toolbarLabelStyle != nil { return .native(.implicit("automatic", [])) }
            return .nilValue
        })
        r.liveEnvironment("toolbarVerticalEdge", .navigation, notes: "iOS 27.1.", read: { env, _ in
            #if os(iOS)
            if #available(iOS 27.1, *), let e = env.toolbarVerticalEdge { return .native(.implicit(e == .leading ? "leading" : "trailing", [])) }
            #endif
            return .nilValue
        })
    }

    @MainActor static func bars(_ c: KCall, from i: Int = 1) -> [ToolbarPlacement] {
        var out: [ToolbarPlacement] = []
        for v in c.args.dropFirst(i) {
            let items: [KV] = { if case .array(let a) = v { return a }; return [v] }()
            for item in items {
                guard case .native(.implicit(let n, _)) = item else { continue }
                switch n {
                #if os(iOS)
                case "navigationBar": out.append(.navigationBar)
                case "tabBar": out.append(.tabBar)
                case "bottomBar": out.append(.bottomBar)
                #endif
                default: out.append(.automatic)
                }
            }
        }
        return out.isEmpty ? [.automatic] : out
    }

    @MainActor static func toolbarVisibility(_ c: KCall, _ view: AnyView) -> AnyView {
        var v = view
        for bar in bars(c) { v = AnyView(v.toolbar(KControlValues.visibility(c[0]), for: bar)) }
        return v
    }

    @MainActor static func toolbarBackground(_ c: KCall, _ view: AnyView) -> AnyView {
        var v = view
        for bar in bars(c) {
            if case .native(.implicit(let n, _))? = c[0], ["visible", "hidden", "automatic"].contains(n) {
                v = AnyView(v.toolbarBackground(KControlValues.visibility(c[0]), for: bar))
            } else if let style = c.shapeStyle(0) {
                v = AnyView(v.toolbarBackground(style, for: bar))
            }
        }
        return v
    }

    @MainActor static func toolbarBackgroundVisibility(_ c: KCall, _ view: AnyView) -> AnyView {
        guard #available(iOS 18.0, macOS 15.0, *) else { return view }
        var v = view
        for bar in bars(c) { v = AnyView(v.toolbarBackgroundVisibility(KControlValues.visibility(c[0]), for: bar)) }
        return v
    }

    @MainActor static func toolbarColorScheme(_ c: KCall, _ view: AnyView) -> AnyView {
        let scheme: ColorScheme? = c.symbol(0) == "dark" ? .dark : (c.symbol(0) == "light" ? .light : nil)
        var v = view
        for bar in bars(c) { v = AnyView(v.toolbarColorScheme(scheme, for: bar)) }
        return v
    }

    @MainActor static func iOS27Toolbar(_ name: String, _ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        guard #available(iOS 27.0, *) else { return view }
        switch name {
        case "toolbarOverflowMenu":
            let content = c.content("content")
            return AnyView(view.toolbarOverflowMenu { content })
        case "toolbarMinimizationBehavior":
            let b: ToolbarMinimizationBehavior = c.pick(0, ["onScrollDown": .onScrollDown, "onScrollUp": .onScrollUp, "never": .never]) ?? .automatic
            var v = view
            for bar in bars(c) { v = AnyView(v.toolbarMinimizationBehavior(b, for: bar)) }
            return v
        case "toolbarMinimizationRestoration":
            let b: ToolbarMinimizationRestoration = c.symbol(0) == "atScrollEdge" ? .atScrollEdge : .automatic
            var v = view
            for bar in bars(c) { v = AnyView(v.toolbarMinimizationRestoration(b, for: bar)) }
            return v
        case "toolbarMinimizationSafeAreaAdjustment":
            let b: ToolbarMinimizationSafeAreaAdjustment = c.pick(0, ["enabled": .enabled, "disabled": .disabled]) ?? .automatic
            var v = view
            for bar in bars(c) { v = AnyView(v.toolbarMinimizationSafeAreaAdjustment(b, for: bar)) }
            return v
        case "toolbarVerticalBehavior":
            guard #available(iOS 27.1, *) else { return view }
            return AnyView(view.toolbarVerticalBehavior(c.symbol(0) == "disabled" ? .disabled : .automatic))
        case "toolbarVerticalCompressionBehavior":
            guard #available(iOS 27.1, *) else { return view }
            let b: ToolbarVerticalCompressionBehavior = c.pick(0, ["prefersTabBar": .prefersTabBar, "prefersToolbarItems": .prefersToolbarItems]) ?? .automatic
            return AnyView(view.toolbarVerticalCompressionBehavior(b))
        default: return view
        }
        #else
        return view
        #endif
    }

    @MainActor static func safeAreaBar(_ c: KCall, _ view: AnyView) -> AnyView {
        guard #available(iOS 26.0, macOS 26.0, *) else { return view }
        let content = c.content("content")
        switch c.symbol("edge") {
        case "top": return AnyView(view.safeAreaBar(edge: .top, alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing")) { content })
        case "leading": return AnyView(view.safeAreaBar(edge: .leading, alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing")) { content })
        case "trailing": return AnyView(view.safeAreaBar(edge: .trailing, alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing")) { content })
        default: return AnyView(view.safeAreaBar(edge: .bottom, alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing")) { content })
        }
    }

    // MARK: The toolbar's items

    @MainActor static func toolbar(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let fn = c.last, c.r.isFunction(fn) else { return view }
        let r = c.r
        var entries: [KToolbarEntry] = []
        for item in r.content(fn).flatMap(\.flattened) { entries += toolbarEntries(item, r, next: entries.count) }
        return AnyView(view.toolbar { KToolbarContent(entries: entries) })
    }

    @MainActor static func toolbarEntries(_ item: KView, _ r: KRenderer, next: Int) -> [KToolbarEntry] {
        guard case .primitive(let n, let args, let labels, _)? = r.rootPrimitive(item) else {
            return [KToolbarEntry(id: next, kind: .item, placement: "automatic", views: [r.render(item)])]
        }
        let a = KArgs(args: args, labels: labels)
        var e = KToolbarEntry(id: next, kind: .item, placement: KToolbarPlacement.name(a["placement"]))
        switch n {
        case "ToolbarItem":
            e.views = [r.renderContent(a.lastFunction)]
        case "ToolbarItemGroup":
            e.kind = .group
            e.views = r.content(a["content"] ?? a.firstFunction).flatMap(\.flattened).map { r.render($0) }
        case "ToolbarSpacer":
            e.kind = .spacer(fixed: { if case .native(.implicit("fixed", _))? = a.first { return true }; return false }())
        case "DefaultToolbarItem":
            e.kind = .defaultItem(KToolbarPlacement.name(a["kind"]))
        case "ToolbarTitleMenu":
            e.kind = .titleMenu
            e.views = r.content(a.lastFunction).flatMap(\.flattened).map { r.render($0) }
        case "ToolbarOverflowMenu":
            e.kind = .overflowMenu
            e.views = r.content(a.lastFunction).flatMap(\.flattened).map { r.render($0) }
        case "ForEach":
            var out: [KToolbarEntry] = []
            for row in r.forEachRows(a) { for v in row.views.flatMap(\.flattened) { out += toolbarEntries(v, r, next: next + out.count) } }
            return out
        default:
            return [KToolbarEntry(id: next, kind: .item, placement: "automatic", views: [r.render(item)])]
        }
        var node = item
        while case .modified(let base, let m) = node.kind {
            switch m.name {
            case "visibilityPriority": e.priority = KToolbarPlacement.name(m.first)
            case "sharedBackgroundVisibility": e.sharedBackground = KControlValues.visibility(m.first)
            case "matchedTransitionSource": e.zoomID = m.arg("id")
            case "contentMarginsRemoved": e.marginsRemoved = m.first.map { r.interp.truthy($0) } ?? true
            case "axisBehavior": e.axisBehavior = KToolbarPlacement.name(m.first)
            default: break
            }
            node = base
        }
        return [e]
    }
}
