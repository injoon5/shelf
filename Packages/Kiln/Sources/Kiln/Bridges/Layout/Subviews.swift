//
//  Subviews.swift
//  Bridges: a container's subviews and sections, container values, and
//  iOS 27.1's ArrangementView
//
//  `Group(subviews: content) { subviews in … }` and `ForEach(subviews:)`
//  hand the app SwiftUI's own resolved subviews (a `ForEach` inside counts
//  each row), as views it can modify and count. `Group(sections:)` and
//  `ForEach(sections:)` give each `Section`'s `header`, `content` and
//  `footer`. `.containerValue(\.icon, "star")` is read back as
//  `subview.containerValues.icon`, with the app's `@Entry` default.
//
//  `Group` is registered by Core and `ForEach` by Lists; their subview forms
//  call into here.
//

import SwiftUI

/// A subview SwiftUI resolved: shown as itself, with its id and container values.
@available(iOS 18.0, macOS 15.0, *)
final class KSubviewViewBox: KNativeViewBox {
    let subview: Subview
    init(_ subview: Subview) {
        self.subview = subview
        super.init(subview)
    }
}

/// Values set with `.containerValue(\.name, v)`, keyed by name.
@available(iOS 18.0, macOS 15.0, *)
struct KContainerValuesKey: ContainerValueKey {
    static let defaultValue: [String: KV] = [:]
}

@available(iOS 18.0, macOS 15.0, *)
extension ContainerValues {
    var kilnValues: [String: KV] {
        get { self[KContainerValuesKey.self] }
        set { self[KContainerValuesKey.self] = newValue }
    }

    /// `\.[kiln: "icon"]`: one value, so several `.containerValue`s add up.
    subscript(kiln name: String) -> KV {
        get { kilnValues[name] ?? .nilValue }
        set { kilnValues[name] = newValue }
    }
}

/// A subview's container values: SwiftUI's, or (only checked) its own modifiers'.
final class KContainerValuesBox {
    private let native: Any?
    private let values: [String: KV]
    @available(iOS 18.0, macOS 15.0, *)
    init(native: ContainerValues) { self.native = native; values = [:] }
    init(values: [String: KV]) { native = nil; self.values = values }

    func value(_ name: String) -> KV {
        if #available(iOS 18.0, macOS 15.0, *), let v = native as? ContainerValues { return v[kiln: name] }
        return values[name] ?? .nilValue
    }
}

@MainActor
enum KSubviews {
    /// The view a `subviews:` or `sections:` argument names (`content`, a closure, a view).
    static func source(_ v: KV?, _ r: KRenderer) -> AnyView {
        guard let v else { return AnyView(EmptyView()) }
        if r.isFunction(v) { return r.renderContent(v) }
        return r.renderList(KBuiltins.asViews(v, r.interp))
    }

    @available(iOS 18.0, macOS 15.0, *)
    static func subview(_ s: Subview) -> KV {
        .view(.primitive("KilnNativeView", [.native(.object("NativeView", KRef(KSubviewViewBox(s))))], [nil], line: 0))
    }

    @available(iOS 18.0, macOS 15.0, *)
    static func collection(_ c: SubviewsCollection) -> KV { .array(c.map { subview($0) }) }

    @available(iOS 18.0, macOS 15.0, *)
    static func section(_ s: SectionConfiguration) -> KV {
        .tuple([KStyles.view(s.header), collection(s.content), KStyles.view(s.footer), .string("\(s.id)")],
               ["header", "content", "footer", "id"])
    }

    @available(iOS 18.0, macOS 15.0, *)
    static func sections(_ c: SectionCollection) -> KV { .array(c.map { section($0) }) }

    // When the app is only checked (`Kiln.validate`, the transcript): its own descriptions.

    static func headlessViews(_ v: KV?, _ interp: KInterpreter) -> [KView] {
        guard let v else { return [] }
        var views: [KView]
        if case .function(let f) = v { views = (try? interp.callBuilder(f)) ?? [] } else { views = KBuiltins.asViews(v, interp) }
        var out: [KView] = []
        for view in views.flatMap(\.flattened) {
            if KRenderer.eachRowNames.contains(view.primitiveName ?? ""), case .primitive(_, let args, let labels, _) = view.kind {
                for row in KRenderer(interp: interp).forEachRows(KArgs(args: args, labels: labels)) { out += row.views.flatMap(\.flattened) }
            } else {
                out.append(view)
            }
        }
        return out
    }

    static func headlessCollection(_ v: KV?, _ interp: KInterpreter) -> KV { .array(headlessViews(v, interp).map { .view($0) }) }

    static func headlessSections(_ v: KV?, _ interp: KInterpreter) -> KV {
        var out: [KV] = []
        for (i, view) in headlessViews(v, interp).enumerated() {
            guard view.primitiveName == "Section", case .primitive(_, let args, let labels, _) = view.kind else { continue }
            let a = KArgs(args: args, labels: labels)
            let header: KV = a["header"].map { h in interp.isFunctionValue(h) ? .view(.group((try? interp.callBuilder(h.function!)) ?? [])) : h }
                ?? (a.first?.asString.map { .view(.primitive("Text", [.string($0)], [nil], line: 0)) } ?? .view(.empty))
            let body = a.args.last { if case .function = $0 { return true }; return false }
            out.append(.tuple([header, headlessCollection(body, interp), a["footer"] ?? .view(.empty), .int(i)], ["header", "content", "footer", "id"]))
        }
        return .array(out)
    }
}

extension KInterpreter {
    func isFunctionValue(_ v: KV) -> Bool { if case .function = v { return true }; return false }
}

extension KV {
    var function: KFunction? { if case .function(let f) = self { return f }; return nil }
}

extension LayoutBridges {
    static func subviews(_ r: KRegistry) {
        // What SwiftUI hands `Group(subviews:)` and `ForEach(subviews:)`; never written as a call.
        for (name, notes) in [("Subview", "A resolved subview: show it, modify it, and read `id` and `containerValues`."),
                              ("SubviewsCollection", "`Group(subviews:)`'s subviews: an array you can count, index, slice and `ForEach` over."),
                              ("SubviewsCollectionSlice", "A slice of the subviews (`subviews.prefix(3)`, `subviews.dropFirst()`)."),
                              ("GroupElementsOfContent", "What `Group(subviews:transform:)` makes."),
                              ("GroupSectionsOfContent", "What `Group(sections:transform:)` makes.")] {
            r.view(name, .layout, notes: notes) { v in v.bridge.constructible = false }
        }
        r.view("EquatableView", .layout, notes: "Shows its content; Kiln redraws it with its parent.") { v in
            v.form("content:any") { c in c.r.renderList(KBuiltins.asViews(c["content"] ?? .void, c.interp)) }
        }
        // `subview.id`, `subview.containerValues.icon`.
        r.type("View", .layout) { t in
            t.internal()
            t.anyProperty { c, name in
                guard case .view(let v) = c.receiver, name == "id" || name == "containerValues" else { return nil }
                if #available(iOS 18.0, macOS 15.0, *), case .primitive("KilnNativeView", let args, _, _) = v.kind,
                   case .native(.object(_, let ref))? = args.first, let box = ref.value as? KSubviewViewBox {
                    return name == "id" ? .string("\(box.subview.id)")
                        : .native(.object("ContainerValues", KRef(KContainerValuesBox(native: box.subview.containerValues))))
                }
                // Only checked (`Kiln.validate`): the view's own description.
                var values: [String: KV] = [:]
                var node = v
                while case .modified(let base, let m) = node.kind {
                    if m.name == "containerValue", case .native(.keyPath(let comps))? = m.first, let key = comps.last, values[key] == nil {
                        values[key] = m.args.count > 1 ? m.args[1] : .nilValue
                    }
                    node = base
                }
                return name == "id" ? .int(ObjectIdentifier(v).hashValue) : .native(.object("ContainerValues", KRef(KContainerValuesBox(values: values))))
            }
        }
        r.type("ContainerValues", .layout) { t in
            t.internal()
            t.anyProperty { c, name in
                guard case .native(.object(_, let ref)) = c.receiver, let box = ref.value as? KContainerValuesBox else { return nil }
                let v = box.value(name)
                return v.isNil ? (c.interp.userEnvironmentValue(name, owner: "ContainerValues") ?? .nilValue) : v
            }
        }
        r.modifier("containerValue", .layout, notes: "Declare the key with `extension ContainerValues { @Entry var icon: String = \"\" }`; read it as `subview.containerValues.icon`.") { m in
            m.form("_:any _:any") { c, view in
                if #available(iOS 18.0, macOS 15.0, *), case .native(.keyPath(let comps))? = c[0], let key = comps.last {
                    AnyView(view.containerValue(\.[kiln: key], c[1] ?? .nilValue))
                } else { view }
            }
        }
        r.protocolBridge("ContainerValueKey", .layout, requirements: ["defaultValue"], support: .partial,
                         notes: "Prefer `@Entry` in `extension ContainerValues`; a key type's `defaultValue` isn't read.")
    }

    // MARK: Group and ForEach forms

    @MainActor static func groupSubviews(_ c: KCall) -> AnyView {
        guard #available(iOS 18.0, macOS 15.0, *) else { return c.r.renderContent(c["subviews"] ?? c["sections"]) }
        let r = c.r
        let transform = c["transform"] ?? c.last
        if c["sections"] != nil {
            return AnyView(Group(sections: KSubviews.source(c["sections"], r)) { sections in r.renderContent(transform, [KSubviews.sections(sections)]) })
        }
        return AnyView(Group(subviews: KSubviews.source(c["subviews"], r)) { subviews in r.renderContent(transform, [KSubviews.collection(subviews)]) })
    }

    @MainActor static func forEachSubview(_ c: KCall) -> AnyView {
        guard #available(iOS 18.0, macOS 15.0, *) else { return c.r.renderContent(c["subviews"] ?? c["sections"]) }
        let r = c.r
        let content = c["content"] ?? c.last
        if c["sections"] != nil {
            return AnyView(ForEach(sections: KSubviews.source(c["sections"], r)) { section in r.renderContent(content, [KSubviews.section(section)]) })
        }
        return AnyView(ForEach(subviews: KSubviews.source(c["subviews"], r)) { subview in r.renderContent(content, [KSubviews.subview(subview)]) })
    }

    // MARK: ArrangementView (iOS 27.1)

    static func arrangements(_ r: KRegistry) {
        r.protocolBridge("ArrangementViewStyle", .layout, requirements: ["makeBody(configuration:)"], support: .full,
                         notes: "`makeBody(configuration:)` gets SwiftUI's configuration: `primary` and `secondary`.")
        r.view("ArrangementView", .layout, introduced: "27.1", notes: "A primary and a secondary view, split or overlaid by `.arrangementViewStyle(.split)` or `.overlay`.") { v in
            v.form("primary:content secondary:content") { c in arrangementView(c) }
        }
        r.modifier("arrangementViewStyle", .layout, introduced: "27.1") { m in
            m.styles("ArrangementViewStyle", ["automatic", "split", "overlay"])
            m.form("_:ArrangementViewStyle") { c, view in arrangementStyle(c, view) }
        }
        r.modifier("splitArrangementLayoutRatio", .layout, introduced: "27.1") { m in
            m.forms(["_:number?", "minHorizontal:number? idealHorizontal:number? maxHorizontal:number? minVertical:number? idealVertical:number? maxVertical:number?"]) { c, view in
                arrangementModifier("splitArrangementLayoutRatio", c, view)
            }
        }
        r.modifier("splitArrangementLayoutSize", .layout, introduced: "27.1") { m in
            m.form("minWidth:number? idealWidth:number? maxWidth:number? minHeight:number? idealHeight:number? maxHeight:number?") { c, view in
                arrangementModifier("splitArrangementLayoutSize", c, view)
            }
        }
        r.modifier("splitArrangementFixedLayoutSize", .layout, introduced: "27.1") { m in
            m.form("horizontal:bool? vertical:bool?") { c, view in arrangementModifier("splitArrangementFixedLayoutSize", c, view) }
        }
        r.modifier("overlayArrangementEdge", .layout, introduced: "27.1") { m in
            m.form("_:any?") { c, view in arrangementModifier("overlayArrangementEdge", c, view) }
        }
    }

    @MainActor static func arrangementModifier(_ name: String, _ c: KCall, _ v: AnyView) -> AnyView {
        #if os(iOS)
        guard #available(iOS 27.1, *) else { return v }
        switch name {
        case "splitArrangementLayoutRatio":
            if c.labels.first == .some(nil) || c.labels.isEmpty { return AnyView(v.splitArrangementLayoutRatio(c.cg(0))) }
            return AnyView(v.splitArrangementLayoutRatio(minHorizontal: c.cg("minHorizontal"), idealHorizontal: c.cg("idealHorizontal"), maxHorizontal: c.cg("maxHorizontal"),
                                                          minVertical: c.cg("minVertical"), idealVertical: c.cg("idealVertical"), maxVertical: c.cg("maxVertical")))
        case "splitArrangementLayoutSize":
            return AnyView(v.splitArrangementLayoutSize(minWidth: c.cg("minWidth"), idealWidth: c.cg("idealWidth"), maxWidth: c.cg("maxWidth"),
                                                        minHeight: c.cg("minHeight"), idealHeight: c.cg("idealHeight"), maxHeight: c.cg("maxHeight")))
        case "splitArrangementFixedLayoutSize":
            return AnyView(v.splitArrangementFixedLayoutSize(horizontal: c.bool("horizontal", default: true), vertical: c.bool("vertical", default: true)))
        default:
            switch c.symbol(0) {
            case "top": return AnyView(v.overlayArrangementEdge(VerticalEdge.top))
            case "bottom": return AnyView(v.overlayArrangementEdge(VerticalEdge.bottom))
            case "leading": return AnyView(v.overlayArrangementEdge(HorizontalEdge.leading))
            case "trailing": return AnyView(v.overlayArrangementEdge(HorizontalEdge.trailing))
            default: return AnyView(v.overlayArrangementEdge(HorizontalEdge?.none))
            }
        }
        #else
        return v
        #endif
    }

    @MainActor static func arrangementView(_ c: KCall) -> AnyView {
        let primary = c.content("primary"), secondary = c.content("secondary")
        #if os(iOS)
        if #available(iOS 27.1, *) { return AnyView(ArrangementView { primary } secondary: { secondary }) }
        #endif
        return AnyView(VStack { primary; secondary })
    }

    @MainActor static func arrangementStyle(_ c: KCall, _ view: AnyView) -> AnyView {
        #if os(iOS)
        guard #available(iOS 27.1, *) else { return view }
        if let s = KStyles.custom(c) { return AnyView(view.arrangementViewStyle(KArrangementViewStyle(style: s, interp: c.interp))) }
        switch c.symbol(0) {
        case "split": return AnyView(view.arrangementViewStyle(.split))
        case "overlay": return AnyView(view.arrangementViewStyle(.overlay))
        default: return AnyView(view.arrangementViewStyle(.automatic))
        }
        #else
        return view
        #endif
    }
}

#if os(iOS)
@available(iOS 27.1, *)
struct KArrangementViewStyle: ArrangementViewStyle {
    let style: KStructValue
    let interp: KInterpreter
    func makeBody(configuration: Configuration) -> some View {
        KStyles.body(style, interp, KStyles.config("ArrangementViewStyle", configuration, [
            "primary": KStyles.view(configuration.primary), "secondary": KStyles.view(configuration.secondary),
        ]))
    }
}
#endif
