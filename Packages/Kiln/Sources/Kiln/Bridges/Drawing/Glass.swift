//
//  Glass.swift
//  Bridges: Liquid Glass, matched geometry, `visualEffect`, transactions,
//  blend modes and transforms
//
//  Glass is iOS 26's: `Glass` values are kept as written (`.regular`,
//  `.clear.tint(.blue).interactive()`) and made real where the view is shown.
//  `@Namespace` is the host's real namespace (KEHostInputs), so
//  `matchedGeometryEffect`, `glassEffectID` and `glassEffectUnion` are
//  SwiftUI's own.
//

import SwiftUI

/// A `Glass` as the app wrote it: its base and what's chained on it.
struct KGlass: Hashable {
    var base = "regular"
    var tint: Color?
    var interactive = false

    @available(iOS 26, macOS 26, *)
    var glass: Glass {
        var g: Glass = base == "clear" ? .clear : (base == "identity" ? .identity : .regular)
        if let tint { g = g.tint(tint) }
        if interactive { g = g.interactive() }
        return g
    }
}

extension DrawingBridges {
    static func glass(_ r: KRegistry) {
        @MainActor func wrap(_ g: KGlass) -> KV { .native(.boxed(KBoxed("Glass", g))) }
        @MainActor func glass(_ v: KV?) -> KGlass {
            if let g = v?.boxed(KGlass.self) { return g }
            if case .native(.implicit(let n, _))? = v { return KGlass(base: n) }
            return KGlass()
        }
        r.type("Glass", .drawing, support: .full, introduced: "26.0") { t in
            for name in ["regular", "clear", "identity"] { t.staticProperty(name) { _ in wrap(KGlass(base: name)) } }
            t.implicit { name, _, _ in ["regular", "clear", "identity"].contains(name) ? wrap(KGlass(base: name)) : nil }
            t.method("tint", "_:Color?") { c in
                var g = glass(c.receiver)
                g.tint = c.color(0)
                return wrap(g)
            }
            t.method("interactive", "_:bool?") { c in
                var g = glass(c.receiver)
                g.interactive = c.bool(0, default: true)
                return wrap(g)
            }
        }
        r.modifier("glassEffect", .drawing, introduced: "26.0", notes: "iOS 26's Liquid Glass, in a capsule unless `in:` gives a shape.") { m in
            m.form("_:Glass? in:any?") { c, view in
                if #available(iOS 26, macOS 26, *) {
                    let g = glass(c[0]).glass
                    if let shape = shapeArg(c["in"], c.r) { AnyView(view.glassEffect(g, in: shape)) } else { AnyView(view.glassEffect(g)) }
                } else {
                    view
                }
            }
        }
        r.view("GlassEffectContainer", .drawing, introduced: "26.0") { v in
            v.form("spacing:number? content:content") { c in
                if #available(iOS 26, macOS 26, *) {
                    GlassEffectContainer(spacing: c.cg("spacing")) { c.content("content") }
                } else {
                    c.content("content")
                }
            }
        }
        r.modifier("glassEffectID", .drawing, introduced: "26.0") { m in
            m.form("_:any in:any") { c, view in
                if #available(iOS 26, macOS 26, *), let ns = c.interp.namespace(c["in"]) {
                    AnyView(view.glassEffectID(c[0].map { KNamespacedID(slot: ns.slot, id: $0) }, in: ns.id))
                } else {
                    view
                }
            }
        }
        r.modifier("glassEffectUnion", .drawing, introduced: "26.0") { m in
            m.form("id:any namespace:any") { c, view in
                if #available(iOS 26, macOS 26, *), let ns = c.interp.namespace(c["namespace"]) {
                    AnyView(view.glassEffectUnion(id: c["id"].map { KNamespacedID(slot: ns.slot, id: $0) }, namespace: ns.id))
                } else {
                    view
                }
            }
        }
        r.modifier("glassEffectTransition", .drawing, introduced: "26.0") { m in
            m.form("_:any") { c, view in
                if #available(iOS 26, macOS 26, *) {
                    switch c.symbol(0) {
                    case "identity": AnyView(view.glassEffectTransition(.identity))
                    case "materialize": AnyView(view.glassEffectTransition(.materialize))
                    default: AnyView(view.glassEffectTransition(.matchedGeometry))
                    }
                } else {
                    view
                }
            }
        }
        r.modifier("backgroundExtensionEffect", .drawing, introduced: "26.0") { m in
            m.form("") { _, view in
                if #available(iOS 26, macOS 26, *) { AnyView(view.backgroundExtensionEffect()) } else { view }
            }
            m.form("isEnabled:bool") { c, view in
                if #available(iOS 26, macOS 26, *) { AnyView(view.backgroundExtensionEffect(isEnabled: c.bool("isEnabled", default: true))) } else { view }
            }
        }

        // MARK: Matched geometry

        r.modifier("matchedGeometryEffect", .drawing, notes: "With an `@Namespace` of the same view, or one passed down as `Namespace.ID`.") { m in
            m.form("id:any in:any properties:any? anchor:UnitPoint? isSource:bool?") { c, view in
                if let ns = c.interp.namespace(c["in"]) {
                    let props: MatchedGeometryProperties = c.symbol("properties") == "position" ? .position : (c.symbol("properties") == "size" ? .size : .frame)
                    AnyView(view.matchedGeometryEffect(id: KNamespacedID(slot: ns.slot, id: c["id"] ?? .nilValue), in: ns.id, properties: props,
                                                       anchor: c.unitPoint("anchor") ?? .center, isSource: c.bool("isSource", default: true)))
                } else {
                    view
                }
            }
        }
        r.type("Namespace.ID", .environment) { t in t.internal() }
    }

    // MARK: Visual effects, transactions, transforms

    static func visualAndTransforms(_ r: KRegistry) {
        r.modifier("visualEffect", .drawing, support: .partial,
                   notes: "Its closure runs on the main thread when the view's frame changes, so a scroll-driven effect follows one frame behind.") { m in
            m.form("_:closure") { c, view in
                if case .function(let fn)? = c[0] { KVisualEffectHost(content: view, effect: fn, interp: c.interp) } else { view }
            }
            m.probe { _, a, interp in
                guard case .function(let fn)? = a.first else { return [] }
                return [KProbeCall(fn: fn, args: [KNativeContent.value(AnyView(EmptyView())), KVisualEffectGeometry.sample])]
            }
        }
        r.type("VisualEffectGeometry", .drawing) { t in
            t.internal()
            @MainActor func g(_ c: KCall) -> KVisualEffectGeometry { c.object(KVisualEffectGeometry.self) ?? KVisualEffectGeometry() }
            t.property("size") { c in .native(.size(g(c).size.width, g(c).size.height)) }
            t.method("frame", "in:any") { c in
                let f = c.symbol("in") == "local" ? CGRect(origin: .zero, size: g(c).size) : g(c).global
                return .native(.rect(f.minX, f.minY, f.width, f.height))
            }
            t.method("bounds", "of:any") { c in
                let f = g(c).global
                return .native(.rect(f.minX, f.minY, f.width, f.height))
            }
            t.property("safeAreaInsets") { _ in .tuple([.double(0), .double(0), .double(0), .double(0)], ["top", "leading", "bottom", "trailing"]) }
        }

        r.modifier("transaction", .drawing) { m in
            m.form("_:closure") { c, view in
                if case .function(let fn)? = c[0] { AnyView(view.transaction { t in KTransactions.run(fn, &t, c.interp) }) } else { view }
            }
            m.form("value:any _:closure") { c, view in
                if case .function(let fn)? = c[0] { AnyView(view.transaction(value: c["value"] ?? .nilValue) { t in KTransactions.run(fn, &t, c.interp) }) } else { view }
            }
            m.probe { _, a, _ in
                guard case .function(let fn)? = a.lastFunction else { return [] }
                let tx = KV.native(.object("Transaction", KRef(KTransactionBox(Transaction()))))
                return [KProbeCall(fn: fn, args: [.binding(.inOut(get: { tx }, set: { _ in }))], use: .action)]
            }
        }

        r.modifier("transformEffect", .drawing) { m in
            m.form("_:CGAffineTransform") { c, view in view.transformEffect(KAffines.affine(c[0])) }
        }
        r.modifier("projectionEffect", .drawing, support: .partial, notes: "A `ProjectionTransform` made from a `CGAffineTransform`.") { m in
            m.form("_:ProjectionTransform") { c, view in view.projectionEffect(ProjectionTransform(KAffines.affine(c[0]))) }
        }
        r.type("ProjectionTransform", .drawing, support: .partial, notes: "From a `CGAffineTransform`; 3D transforms aren't bridged.") { t in
            t.initializer("_:CGAffineTransform") { c in c[0] ?? KAffines.wrap(.identity) }
            t.initializer("") { _ in KAffines.wrap(.identity) }
        }

        let blendModes: [String: BlendMode] = [
            "normal": .normal, "multiply": .multiply, "screen": .screen, "overlay": .overlay, "darken": .darken, "lighten": .lighten,
            "colorDodge": .colorDodge, "colorBurn": .colorBurn, "softLight": .softLight, "hardLight": .hardLight, "difference": .difference,
            "exclusion": .exclusion, "hue": .hue, "saturation": .saturation, "color": .color, "luminosity": .luminosity,
            "sourceAtop": .sourceAtop, "destinationOver": .destinationOver, "destinationOut": .destinationOut, "plusDarker": .plusDarker,
            "plusLighter": .plusLighter,
        ]
        r.modifier("blendMode", .drawing) { m in
            m.form("_:BlendMode") { c, view in view.blendMode(blendModes[c.symbol(0) ?? "normal"] ?? .normal) }
        }
        r.type("BlendMode", .drawing) { t in
            t.internal()
            t.anyStatic { _, name in .native(.implicit(name, [])) }
        }
        r.modifier("luminanceToAlpha", .drawing) { m in m.form("") { _, view in view.luminanceToAlpha() } }
        r.modifier("materialActiveAppearance", .drawing, introduced: "18.0") { m in
            m.form("_:any") { c, view in
                if #available(iOS 18, macOS 15, *) {
                    switch c.symbol(0) {
                    case "active": AnyView(view.materialActiveAppearance(.active))
                    #if os(macOS)
                    case "inactive": AnyView(view.materialActiveAppearance(.inactive))
                    #endif
                    case "matchWindow": AnyView(view.materialActiveAppearance(.matchWindow))
                    default: AnyView(view.materialActiveAppearance(.automatic))
                    }
                } else {
                    view
                }
            }
        }
        r.modifier("allowedDynamicRange", .drawing) { m in
            m.form("_:any") { c, view in
                switch c.symbol(0) {
                case "high": view.allowedDynamicRange(.high)
                case "constrainedHigh": view.allowedDynamicRange(.constrainedHigh)
                case "standard": view.allowedDynamicRange(.standard)
                default: view.allowedDynamicRange(nil)
                }
            }
        }
        r.modifier("asyncImageURLSession", .drawing, introduced: "27.0", notes: "`URLSession.shared`; Shelf apps share one session.") { m in
            m.form("_:any") { _, view in
                if #available(iOS 27, macOS 27, *) { AnyView(view.asyncImageURLSession(.shared)) } else { view }
            }
        }
    }
}

// MARK: - Transactions

@MainActor
enum KTransactions {
    /// The app's `{ t in t.animation = … }` on a real transaction.
    static func run(_ fn: KFunction, _ t: inout Transaction, _ interp: KInterpreter) {
        let box = KTransactionBox(t)
        let value = KV.native(.object("Transaction", KRef(box)))
        _ = try? interp.entry { try interp.call(fn, [.binding(.inOut(get: { value }, set: { _ in }))], [nil]) }
        t = box.transaction
    }
}

// MARK: - visualEffect

/// What a `visualEffect` closure reads: the view's size and frame.
final class KVisualEffectGeometry: NSObject {
    var size: CGSize = .zero
    var global: CGRect = .zero
    @MainActor static var sample: KV { .native(.object("VisualEffectGeometry", KRef(KVisualEffectGeometry()))) }
}

/// The app's effect, applied with the view's geometry from `onGeometryChange`.
struct KVisualEffectHost: View {
    let content: AnyView
    let effect: KFunction
    let interp: KInterpreter
    @State private var frame: CGRect = .zero

    var body: some View {
        let geometry = KVisualEffectGeometry()
        geometry.size = frame.size
        geometry.global = frame
        return KRenderer(interp: interp).renderContent(.function(effect), [KNativeContent.value(content),
                                                                           .native(.object("VisualEffectGeometry", KRef(geometry)))])
            .onGeometryChange(for: CGRect.self) { proxy in proxy.frame(in: .global) } action: { frame = $0 }
    }
}
