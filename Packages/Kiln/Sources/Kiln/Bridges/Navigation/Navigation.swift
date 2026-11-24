//
//  Navigation.swift
//  Bridges: navigation stacks, split views, links, destinations, paths and
//  navigation transitions
//
//  Tabs are in Tabs.swift, toolbars in Toolbars.swift, search in Search.swift
//  and presentations (sheets, alerts, dialogs, inspectors) in
//  Presentations.swift.
//

import SwiftUI

@objc(KilnBridges_Navigation)
final class NavigationBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        stacks(r)
        transitions(r)
        tabs(r)
        toolbars(r)
        search(r)
        presentations(r)
        presentationModifiers(r)
        delegates(r)
    }

    // MARK: Stacks and links

    static func stacks(_ r: KRegistry) {
        r.view("NavigationStack", .navigation, notes: "Push with `NavigationLink(value:)` and `.navigationDestination(for:)`; `path:` is an array of values or a `NavigationPath`.") { v in
            v.forms(["root:content", "path:binding root:content"]) { c in navigationStack(c) }
        }
        r.view("NavigationView", .navigation) { v in
            v.form("content:content") { c in KZoomScope { NavigationStack { c.r.renderContent(c.a.lastFunction) } } }
        }
        r.view("NavigationSplitView", .navigation, notes: "Two or three columns on iPad; on iPhone it's a stack from the sidebar. `columnVisibility:` and `preferredCompactColumn:` are kept.") { v in
            v.forms(["columnVisibility:binding? preferredCompactColumn:binding? sidebar:content detail:content",
                     "columnVisibility:binding? preferredCompactColumn:binding? sidebar:content content:content detail:content"]) { c in splitView(c) }
        }
        r.view("NavigationLink", .navigation) { v in
            v.forms(["_:title value:any?", "value:any? label:content", "_:title destination:content", "destination:content label:content"]) { c in
                navigationLink(c)
            }
        }
        r.type("NavigationPath", .navigation, support: .full, notes: "`append`, `removeLast()`, `count`, `isEmpty`; `NavigationPath()` or from an array.") { t in
            t.initializer("") { _ in KNavPath.kv([]) }
            t.initializer("_:any") { c in KNavPath.kv((try? c.interp.sequence(c[0] ?? .array([]))) ?? []) }
            t.property("count") { c in .int(KNavPath.items(c.receiver).count) }
            t.property("isEmpty") { c in .bool(KNavPath.items(c.receiver).isEmpty) }
            t.method("append", "_:any") { c in
                c.mutated = KNavPath.kv(KNavPath.items(c.receiver) + [c[0] ?? .nilValue])
                return .void
            }
            t.method("removeLast", "_:number?") { c in
                let items = KNavPath.items(c.receiver)
                c.mutated = KNavPath.kv(Array(items.dropLast(min(items.count, c.int(0) ?? 1))))
                return .void
            }
        }
        r.modifier("navigationTitle", .navigation) { m in
            m.form("_:title") { c, view in
                if let s = c.string(0) { view.navigationTitle(s) } else { view }
            }
            m.form("_:binding", notes: "An editable title: rename it from the title menu.") { c, view in
                #if os(iOS)
                if let b = c.kbinding(0) { AnyView(view.navigationTitle(c.r.stringBinding(b))) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("navigationSubtitle", .navigation, introduced: "26.0") { m in
            m.form("_:title") { c, view in
                if #available(iOS 26.0, macOS 26.0, *), let s = c.string(0) { AnyView(view.navigationSubtitle(s)) } else { view }
            }
        }
        r.modifier("navigationBarTitle", .navigation, notes: "Old; `.navigationTitle` and `.navigationBarTitleDisplayMode`.") { m in
            m.forms(["_:title", "_:title displayMode:any"]) { c, view in
                navigationBarTitleDisplayMode(c.symbol("displayMode"), AnyView(view.navigationTitle(c.string(0) ?? "")))
            }
        }
        r.modifier("navigationBarTitleDisplayMode", .navigation) { m in
            m.form("_:NavigationBarItem.TitleDisplayMode") { c, view in navigationBarTitleDisplayMode(c.symbol(0), view) }
        }
        r.modifier("navigationBarItems", .navigation, notes: "Old; prefer `.toolbar`.") { m in
            m.forms(["leading:view", "trailing:view", "leading:view trailing:view"]) { c, view in
                let r = c.r
                let leading = c["leading"].map { r.renderList(KBuiltins.asViews($0, c.interp)) }
                let trailing = c["trailing"].map { r.renderList(KBuiltins.asViews($0, c.interp)) }
                view.toolbar {
                    if let leading { ToolbarItem(placement: .navigation) { leading } }
                    if let trailing { ToolbarItem(placement: .primaryAction) { trailing } }
                }
            }
        }
        r.modifier("navigationBarHidden", .navigation, notes: "Old; prefer `.toolbar(.hidden, for: .navigationBar)`.") { m in
            m.form("_:bool?") { c, view in navigationBarHidden(c.bool(0, default: true), view) }
        }
        r.modifier("navigationBarBackButtonHidden", .navigation) { m in
            m.form("_:bool?") { c, view in view.navigationBarBackButtonHidden(c.bool(0, default: true)) }
        }
        r.modifier("navigationDestination", .navigation, notes: "`for:` with any type the links push, `isPresented:`, and `item:`.") { m in
            m.forms(["for:any destination:content", "isPresented:binding destination:content", "item:binding destination:content"]) { c, view in
                navigationDestination(c, view)
            }
        }
        r.modifier("navigationSplitViewStyle", .navigation, notes: "`.balanced`, `.prominentDetail`, or your own `NavigationSplitViewStyle`.") { m in
            m.styles("NavigationSplitViewStyle", ["automatic", "balanced", "prominentDetail"])
            m.form("_:NavigationSplitViewStyle") { c, view in
                if let s = KStyles.custom(c) { ControlsBridges.applyCustom("navigationSplitViewStyle", s, c, view) }
                else if c.symbol(0) == "balanced" { AnyView(view.navigationSplitViewStyle(.balanced)) }
                else if c.symbol(0) == "prominentDetail" { AnyView(view.navigationSplitViewStyle(.prominentDetail)) }
                else { view }
            }
        }
        r.modifier("navigationSplitViewColumnWidth", .navigation) { m in
            m.form("_:number") { c, view in view.navigationSplitViewColumnWidth(c.cg(0) ?? 320) }
            m.form("min:number? ideal:number max:number?") { c, view in
                view.navigationSplitViewColumnWidth(min: c.cg("min"), ideal: c.cg("ideal") ?? 320, max: c.cg("max"))
            }
        }
        r.modifier("navigationViewStyle", .navigation, notes: "Old; on iPhone every style is a stack.") { m in
            m.styles("NavigationViewStyle", ["automatic", "stack", "columns"])
            m.form("_:NavigationViewStyle") { c, view in
                #if os(iOS)
                if c.symbol(0) == "stack" { AnyView(view.navigationViewStyle(.stack)) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("navigationLinkIndicatorVisibility", .navigation, introduced: "17.0") { m in
            m.form("_:Visibility") { c, view in
                #if os(iOS)
                if #available(iOS 26.0, *) { AnyView(view.navigationLinkIndicatorVisibility(KControlValues.visibility(c[0]))) } else { view }
                #else
                view
                #endif
            }
        }
        // SwiftUI's enum-like types, written by name (`EditMode.inactive`): symbolic until read.
        for name in ["NavigationSplitViewVisibility", "NavigationSplitViewColumn", "EditMode", "TabRole", "SearchSuggestionsPlacement",
                     "TabBarMinimizeBehavior", "ToolbarRole", "ToolbarTitleDisplayMode", "PresentationAdaptation"] {
            r.type(name, .navigation) { t in
                t.internal()
                t.anyStatic { _, member in .native(.implicit(member, [])) }
            }
        }
        r.liveEnvironment("navigationLinkIndicatorVisibility", .navigation, read: { env, _ in
            #if os(iOS)
            if #available(iOS 26.0, *) { return KControlValues.visibilityValue(env.navigationLinkIndicatorVisibility) }
            #endif
            return .native(.implicit("automatic", []))
        })
    }

    @MainActor static func navigationBarTitleDisplayMode(_ mode: String?, _ view: AnyView) -> AnyView {
        #if os(iOS)
        switch mode {
        case "inline": return AnyView(view.navigationBarTitleDisplayMode(.inline))
        case "large": return AnyView(view.navigationBarTitleDisplayMode(.large))
        case nil: return view
        default: return AnyView(view.navigationBarTitleDisplayMode(.automatic))
        }
        #else
        return view
        #endif
    }

    @MainActor static func navigationBarHidden(_ hidden: Bool, _ view: AnyView) -> AnyView {
        #if os(iOS)
        return AnyView(view.toolbar(hidden ? .hidden : .automatic, for: .navigationBar))
        #else
        return view
        #endif
    }

    @MainActor static func navigationStack(_ c: KCall) -> AnyView {
        let root = c.r.renderContent(c["root"] ?? c.a.lastFunction)
        guard let b = c.kbinding("path") else { return AnyView(KZoomScope { NavigationStack { root } }) }
        // An array of values, or a `NavigationPath`: written back as it was.
        let path = Binding<[KNavValue]>(get: {
            let v = b.get()
            if KNavPath.isPath(v) { return KNavPath.items(v).map { KNavValue(value: $0) } }
            return ((try? c.interp.sequence(v)) ?? []).map { KNavValue(value: $0) }
        }, set: { new in
            if KNavPath.isPath(b.get()) { b.set(KNavPath.kv(new.map(\.value))) } else { b.set(.array(new.map(\.value))) }
        })
        return AnyView(KZoomScope { NavigationStack(path: path) { root } })
    }

    @MainActor static func splitView(_ c: KCall) -> AnyView {
        let r = c.r
        let sidebar = r.renderContent(c["sidebar"]), detail = r.renderContent(c["detail"])
        let middle = c["content"].map { r.renderContent($0) }
        let visibility: Binding<NavigationSplitViewVisibility> = {
            guard let b = c.kbinding("columnVisibility") else { return .constant(.automatic) }
            return Binding(get: {
                switch b.get() {
                case .native(.implicit("all", _)): return .all
                case .native(.implicit("doubleColumn", _)): return .doubleColumn
                case .native(.implicit("detailOnly", _)): return .detailOnly
                default: return .automatic
                }
            }, set: { v in
                let name = v == .all ? "all" : (v == .doubleColumn ? "doubleColumn" : (v == .detailOnly ? "detailOnly" : "automatic"))
                b.set(.native(.implicit(name, [])))
            })
        }()
        let compact: Binding<NavigationSplitViewColumn>? = c.kbinding("preferredCompactColumn").map { b in
            Binding(get: {
                switch b.get() {
                case .native(.implicit("detail", _)): return .detail
                case .native(.implicit("content", _)): return .content
                default: return .sidebar
                }
            }, set: { v in b.set(.native(.implicit(v == .detail ? "detail" : (v == .content ? "content" : "sidebar"), []))) })
        }
        if let middle {
            if let compact {
                return AnyView(KZoomScope { NavigationSplitView(columnVisibility: visibility, preferredCompactColumn: compact) { sidebar } content: { middle } detail: { detail } })
            }
            return AnyView(KZoomScope { NavigationSplitView(columnVisibility: visibility) { sidebar } content: { middle } detail: { detail } })
        }
        if let compact {
            return AnyView(KZoomScope { NavigationSplitView(columnVisibility: visibility, preferredCompactColumn: compact) { sidebar } detail: { detail } })
        }
        return AnyView(KZoomScope { NavigationSplitView(columnVisibility: visibility) { sidebar } detail: { detail } })
    }

    @MainActor static func navigationLink(_ c: KCall) -> AnyView {
        let r = c.r
        let title = ControlsBridges.stringTitle(c)
        // By the parameter each argument bound to: `NavigationLink { Detail() } label: { … }`'s
        // first closure is `destination:`, though it's written with no label.
        if let value = c["value"] {
            let label: AnyView = title.map { AnyView(Text($0)) } ?? r.renderContent(c["label"])
            return AnyView(NavigationLink(value: KNavValue(value: value)) { label })
        }
        let dest = c["destination"]
        let destination = KLazyView {
            if let dest, r.isFunction(dest) { return r.renderContent(dest) }
            return r.renderList(KBuiltins.asViews(dest ?? .void, c.interp))
        }
        if let title { return AnyView(NavigationLink(title) { destination }) }
        let labelFn = c["label"]
        return AnyView(NavigationLink { destination } label: { r.renderContent(labelFn) })
    }

    @MainActor static func navigationDestination(_ c: KCall, _ view: AnyView) -> AnyView {
        guard let fn = c.last, c.r.isFunction(fn) else { return view }
        let r = c.r
        if let b = c.kbinding("isPresented") {
            return AnyView(view.navigationDestination(isPresented: r.boolBinding(b)) { KLazyView { r.renderContent(fn) } })
        }
        if let b = c.kbinding("item") {
            let item = Binding<KNavValue?>(get: { let v = b.get(); return v.isNil ? nil : KNavValue(value: v) }, set: { b.set($0?.value ?? .nilValue) })
            return AnyView(view.navigationDestination(item: item) { nav in KLazyView { r.renderContent(fn, [nav.value]) } })
        }
        return AnyView(view.navigationDestination(for: KNavValue.self) { nav in KLazyView { r.renderContent(fn, [nav.value]) } })
    }

    // MARK: Navigation transitions

    static func transitions(_ r: KRegistry) {
        r.type("NavigationTransition", .navigation, support: .full, introduced: "18.0") { t in
            t.membersInManifest = true
            t.staticProperty("automatic") { _ in .native(.implicit("automatic", [])) }
            t.staticProperty("crossFade", notes: "iOS 27.") { _ in .native(.implicit("crossFade", [])) }
            t.staticMethod("zoom", "sourceID:any in:any", notes: "From the view marked `.matchedTransitionSource(id:in:)` with the same id.") { c in
                .native(.implicit("zoom", [c["sourceID"] ?? .nilValue]))
            }
        }
        r.modifier("navigationTransition", .navigation, introduced: "18.0",
                   notes: "`.zoom(sourceID:in:)` from a `.matchedTransitionSource`, `.crossFade` (iOS 27) or `.automatic`, on the pushed or presented view.") { m in
            m.form("_:NavigationTransition") { c, view in KZoomDestination(transition: c[0] ?? .nilValue, content: view) }
        }
        r.modifier("matchedTransitionSource", .navigation, introduced: "18.0", notes: "The namespace is the navigation stack's (or the sheet's): ids must be unique there.") { m in
            m.form("id:any in:any") { c, view in KZoomSource(id: c["id"] ?? .nilValue, content: view) }
            m.form("id:any in:any configuration:closure") { c, view in KZoomSource(id: c["id"] ?? .nilValue, content: view) }
            m.form("id:any in:any", receiver: "ToolbarContent") { _, view in view }
        }
    }
}

/// A `NavigationPath`, as a value: each change makes a new one.
@MainActor
enum KNavPath {
    final class Box { let items: [KV]; init(_ items: [KV]) { self.items = items } }
    static func kv(_ items: [KV]) -> KV { .native(.object("NavigationPath", KRef(Box(items)))) }
    static func isPath(_ v: KV) -> Bool { if case .native(.object("NavigationPath", _)) = v { return true }; return false }
    static func items(_ v: KV) -> [KV] {
        if case .native(.object(_, let ref)) = v, let b = ref.value as? Box { return b.items }
        return []
    }
}

// MARK: - Zoom transitions

extension EnvironmentValues {
    /// The namespace zoom transitions share: a navigation stack's, or a sheet's.
    @Entry var kilnZoomNamespace: Namespace.ID? = nil
}

/// Gives what's inside one namespace for `matchedTransitionSource` and `.zoom`.
struct KZoomScope<Content: View>: View {
    @Namespace private var namespace
    @ViewBuilder let content: Content
    var body: some View { content.environment(\.kilnZoomNamespace, namespace) }
}

struct KZoomSource: View {
    let id: KV
    let content: AnyView
    @Environment(\.kilnZoomNamespace) private var namespace
    var body: some View {
        if #available(iOS 18.0, macOS 15.0, *), let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

struct KZoomDestination: View {
    let transition: KV
    let content: AnyView
    @Environment(\.kilnZoomNamespace) private var namespace
    var body: some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            switch transition {
            case .native(.implicit("zoom", let args)) where namespace != nil:
                content.navigationTransition(.zoom(sourceID: args.first ?? .nilValue, in: namespace!))
            case .native(.implicit("crossFade", _)):
                if #available(iOS 27.0, *) { content.navigationTransition(.crossFade) } else { content }
            default:
                content.navigationTransition(.automatic)
            }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
