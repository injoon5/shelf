//
//  CustomLayout.swift
//  Bridges: the `Layout` protocol and `AnyLayout` (PLAN.md §1.5, §2 Layout)
//
//  The app's `Layout` struct is shown by `KLayoutProxy`, a real `Layout`
//  whose `sizeThatFits` and `placeSubviews` call the app's, with SwiftUI's
//  values as Kiln's:
//
//  - `ProposedViewSize`: `width`/`height` (nil when unspecified),
//    `replacingUnspecifiedDimensions(by:)`, `.unspecified`, `.zero`, `.infinity`.
//  - `LayoutSubviews`: an array of `LayoutSubview`s, each with
//    `sizeThatFits(_:)`, `dimensions(in:)`, `place(at:anchor:proposal:)`,
//    `spacing` and `priority`.
//  - `ViewDimensions`: `width`, `height` and `[guide]`.
//  - The cache: `makeCache(subviews:)` and `updateCache(_:subviews:)`, any value,
//    passed `inout`.
//  - `animatableData`, so a layout's parameters animate.
//
//  `MyLayout { … }`, `MyLayout(spacing: 4) { … }`, a stored layout called
//  `layout { … }`, and `AnyLayout(…)` over the app's layout or
//  `HStackLayout`/`VStackLayout`/`ZStackLayout`/`GridLayout`, which animate
//  between each other.
//

import SwiftUI

struct KProposal: Hashable {
    var width: Double?
    var height: Double?
}

final class KLayoutCache {
    var value: KV = .void
}

final class KAnyLayoutBox {
    let layout: AnyLayout
    init(_ layout: AnyLayout) { self.layout = layout }
}

final class KSubviewBox {
    let subview: LayoutSubview
    init(_ s: LayoutSubview) { subview = s }
}

final class KDimensionsBox {
    let dimensions: ViewDimensions
    init(_ d: ViewDimensions) { dimensions = d }
}

final class KSpacingBox {
    let spacing: ViewSpacing
    init(_ s: ViewSpacing) { spacing = s }
}

extension LayoutBridges {
    static func customLayouts(_ r: KRegistry) {
        r.protocolBridge("Layout", .layout,
                         requirements: ["sizeThatFits(proposal:subviews:cache:)", "placeSubviews(in:proposal:subviews:cache:)",
                                        "makeCache(subviews:)?", "updateCache(_:subviews:)?", "animatableData?"],
                         support: .full,
                         notes: "`sizeThatFits` and `placeSubviews` with `subview.sizeThatFits`, `place(at:anchor:proposal:)` and a cache; `MyLayout { … }` or `AnyLayout(MyLayout())`.") { app in
            KLayoutProxy(app: app)
        }

        r.type("ProposedViewSize", .layout) { t in
            t.initializer("width:any height:any") { c in proposal(c.args[0].asDouble, c.args[1].asDouble) }
            t.initializer("_:CGSize") { c in
                if case .native(.size(let w, let h)) = c.args[0] { return proposal(w, h) }
                return proposal(nil, nil)
            }
            let statics: [String: KV] = ["unspecified": proposal(nil, nil), "zero": proposal(0, 0), "infinity": proposal(.infinity, .infinity)]
            for (name, v) in statics { t.staticProperty(name) { _ in v } }
            t.implicit { name, _, _ in statics[name] }
            t.property("width") { c in proposalValue(c.receiver).width.map(KV.double) ?? .nilValue }
            t.property("height") { c in proposalValue(c.receiver).height.map(KV.double) ?? .nilValue }
            t.method("replacingUnspecifiedDimensions", "by:CGSize?") { c in
                var by = CGSize(width: 10, height: 10)
                if case .native(.size(let w, let h))? = c["by"] { by = CGSize(width: w, height: h) }
                let p = proposalValue(c.receiver)
                return .native(.size(p.width ?? by.width, p.height ?? by.height))
            }
        }

        r.type("LayoutSubview", .layout) { t in
            @MainActor func sub(_ c: KCall) throws -> LayoutSubview {
                if case .native(.object(_, let ref)) = c.receiver, let b = ref.value as? KSubviewBox { return b.subview }
                throw c.fail("needs a subview")
            }
            t.method("sizeThatFits", "_:ProposedViewSize") { c in
                let s = try sub(c).sizeThatFits(proposedSize(c.args[0]))
                return .native(.size(s.width, s.height))
            }
            t.method("dimensions", "in:ProposedViewSize") { c in
                .native(.object("ViewDimensions", KRef(KDimensionsBox(try sub(c).dimensions(in: proposedSize(c.args[0]))))))
            }
            t.method("place", "at:CGPoint anchor:UnitPoint? proposal:ProposedViewSize") { c in
                guard case .native(.point(let x, let y)) = c.args[0] else { throw c.fail("needs a CGPoint") }
                try sub(c).place(at: CGPoint(x: x, y: y), anchor: c.unitPoint("anchor") ?? .topLeading, proposal: proposedSize(c["proposal"]))
                return .void
            }
            t.property("priority") { c in .double(Double(try sub(c).priority)) }
            t.property("spacing") { c in .native(.object("ViewSpacing", KRef(KSpacingBox(try sub(c).spacing)))) }
        }

        r.type("ViewDimensions", .layout) { t in
            @MainActor func dims(_ c: KCall) -> ViewDimensions? {
                if case .native(.object(_, let ref)) = c.receiver, let b = ref.value as? KDimensionsBox { return b.dimensions }
                return nil
            }
            t.property("width") { c in .double(Double(dims(c)?.width ?? 0)) }
            t.property("height") { c in .double(Double(dims(c)?.height ?? 0)) }
            t.method("subscript", "_:any") { c in
                guard let d = dims(c) else { return .double(0) }
                let name = c.symbol(0) ?? ""
                switch name {
                case "leading": return .double(Double(d[HorizontalAlignment.leading]))
                case "trailing": return .double(Double(d[HorizontalAlignment.trailing]))
                case "top": return .double(Double(d[VerticalAlignment.top]))
                case "bottom": return .double(Double(d[VerticalAlignment.bottom]))
                case "firstTextBaseline": return .double(Double(d[VerticalAlignment.firstTextBaseline]))
                case "lastTextBaseline": return .double(Double(d[VerticalAlignment.lastTextBaseline]))
                case "centerY": return .double(Double(d[VerticalAlignment.center]))
                default: return .double(Double(d[HorizontalAlignment.center]))
                }
            }
        }

        r.type("ViewSpacing", .layout) { t in
            t.staticProperty("zero") { _ in .native(.object("ViewSpacing", KRef(KSpacingBox(.zero)))) }
            t.method("distance", "to:any along:Axis") { c in
                guard case .native(.object(_, let a)) = c.receiver, let mine = a.value as? KSpacingBox,
                      case .native(.object(_, let b)) = c.args[0], let other = b.value as? KSpacingBox else { return .double(0) }
                return .double(Double(mine.spacing.distance(to: other.spacing, along: c.symbol("along") == "vertical" ? .vertical : .horizontal)))
            }
        }

        // `AnyLayout`, and the stack layouts it switches between (animated, like SwiftUI's).
        r.type("AnyLayout", .layout) { t in
            t.initializer("_:any") { c in
                if case .native(.object("AnyLayout", _)) = c.args[0] { return c.args[0] }
                if let proxy = c.interp.proxy(for: c.args[0], as: "Layout") as? KLayoutProxy { return anyLayout(AnyLayout(proxy)) }
                throw c.fail("needs a Layout")
            }
            t.method("callAsFunction", "content:content") { c in layoutView(c.receiver, c.args[0], c.line) }
        }
        let stacks: [(String, String, @MainActor (KCall) -> AnyLayout)] = [
            ("HStackLayout", "alignment:VerticalAlignment? spacing:number?", { c in AnyLayout(HStackLayout(alignment: c.verticalAlignment("alignment"), spacing: c.cg("spacing"))) }),
            ("VStackLayout", "alignment:HorizontalAlignment? spacing:number?", { c in AnyLayout(VStackLayout(alignment: c.horizontalAlignment("alignment"), spacing: c.cg("spacing"))) }),
            ("ZStackLayout", "alignment:Alignment?", { c in AnyLayout(ZStackLayout(alignment: c.alignment("alignment"))) }),
            ("GridLayout", "alignment:Alignment? horizontalSpacing:number? verticalSpacing:number?", { c in
                AnyLayout(GridLayout(alignment: c.alignment("alignment"), horizontalSpacing: c.cg("horizontalSpacing"), verticalSpacing: c.cg("verticalSpacing")))
            }),
        ]
        for (name, sig, make) in stacks {
            r.type(name, .layout) { t in
                t.initializer(sig) { c in anyLayout(make(c)) }
                t.initializer(sig + " content:content") { c in
                    layoutView(anyLayout(make(c)), c["content"] ?? .void, c.line)
                }
            }
        }
        r.view("LayoutView", .layout) { v in
            v.engineOnly()
            v.form("_:any content:content") { c in
                if case .native(.object(_, let ref))? = c[0], let box = ref.value as? KAnyLayoutBox {
                    box.layout { c.content("content") }
                } else {
                    c.content("content")
                }
            }
        }
    }

    // MARK: Values

    static func proposal(_ w: Double?, _ h: Double?) -> KV {
        .native(.boxed(KBoxed("ProposedViewSize", KProposal(width: w, height: h))))
    }

    static func proposal(_ p: ProposedViewSize) -> KV { proposal(p.width.map { Double($0) }, p.height.map { Double($0) }) }

    static func proposalValue(_ v: KV?) -> KProposal {
        if case .native(.boxed(let b))? = v, let p = b.get(KProposal.self) { return p }
        if case .native(.size(let w, let h))? = v { return KProposal(width: w, height: h) }
        return KProposal()
    }

    static func proposedSize(_ v: KV?) -> ProposedViewSize {
        let p = proposalValue(v)
        return ProposedViewSize(width: p.width.map { CGFloat($0) }, height: p.height.map { CGFloat($0) })
    }

    static func anyLayout(_ l: AnyLayout) -> KV { .native(.object("AnyLayout", KRef(KAnyLayoutBox(l)))) }

    static func subviews(_ s: LayoutSubviews) -> KV {
        .array(s.map { .native(.object("LayoutSubview", KRef(KSubviewBox($0)))) })
    }

    /// `layout { … }`: the layout with its content, as a view.
    static func layoutView(_ layout: KV, _ content: KV, _ line: Int) -> KV {
        .view(.primitive("LayoutView", [layout, content], [nil, "content"], line: line))
    }
}

extension KInterpreter {
    /// `MyLayout(spacing: 4) { … }` or `layout { … }` for the app's `Layout`.
    func layoutCall(_ layout: KV, _ content: KV, _ line: Int) -> KV? {
        guard let proxy = proxy(for: layout, as: "Layout") as? KLayoutProxy else { return nil }
        return LayoutBridges.layoutView(LayoutBridges.anyLayout(AnyLayout(proxy)), content, line)
    }
}

/// The app's `Layout`: SwiftUI asks it to size and place the subviews, and
/// it asks the app's methods.
///
/// SwiftUI may lay out on its render thread while it animates, and the app's
/// code runs on the main thread: off it, a call waits for the main thread
/// (`KDelegates.onMain`). `animatableData` is kept, and given to the app's
/// value when a method runs.
struct KLayoutProxy: Layout, @unchecked Sendable {
    let base: KAppValue
    var data: KAnimVector
    typealias Cache = KLayoutCache

    @MainActor init(app: KAppValue) {
        base = app
        data = KAnimatable.data(app)
    }

    @MainActor var app: KAppValue { KAnimatable.applied(base, data) }

    nonisolated var animatableData: KAnimVector {
        get { data }
        set { data = newValue }
    }

    private static func cacheBinding(_ cache: KLayoutCache) -> KV {
        .binding(KBinding(get: { cache.value }, set: { cache.value = $0 }))
    }

    nonisolated func makeCache(subviews: Subviews) -> KLayoutCache {
        KDelegates.onMain {
            let cache = KLayoutCache()
            if base.implements("makeCache", labels: ["subviews"]) {
                var a = app
                cache.value = a.callReporting("makeCache", [LayoutBridges.subviews(subviews)], labels: ["subviews"])
            }
            return cache
        }
    }

    nonisolated func updateCache(_ cache: inout KLayoutCache, subviews: Subviews) {
        let c = cache
        KDelegates.onMain {
            var a = app
            if base.implements("updateCache", labels: [nil, "subviews"]) {
                _ = a.callReporting("updateCache", [Self.cacheBinding(c), LayoutBridges.subviews(subviews)], labels: [nil, "subviews"])
            } else if base.implements("makeCache", labels: ["subviews"]) {
                c.value = a.callReporting("makeCache", [LayoutBridges.subviews(subviews)], labels: ["subviews"])
            }
        }
    }

    nonisolated func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout KLayoutCache) -> CGSize {
        let c = cache
        return KDelegates.onMain {
            var a = app
            let v = a.callReporting("sizeThatFits", [LayoutBridges.proposal(proposal), LayoutBridges.subviews(subviews), Self.cacheBinding(c)],
                                    labels: ["proposal", "subviews", "cache"], fallback: .nilValue)
            if case .native(.size(let w, let h)) = v { return CGSize(width: w, height: h) }
            return proposal.replacingUnspecifiedDimensions()
        }
    }

    nonisolated func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout KLayoutCache) {
        let c = cache
        KDelegates.onMain {
            var a = app
            _ = a.callReporting("placeSubviews", [.native(.rect(bounds.minX, bounds.minY, bounds.width, bounds.height)), LayoutBridges.proposal(proposal),
                                                  LayoutBridges.subviews(subviews), Self.cacheBinding(c)],
                                labels: ["in", "proposal", "subviews", "cache"])
        }
    }
}
