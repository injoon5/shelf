//
//  Effects.swift
//  Bridges: color, backgrounds and overlays, clipping, visual effects,
//  transforms, animation and transitions
//

import SwiftUI

extension DrawingBridges {
    static func effects(_ r: KRegistry) {
        styles(r)
        layers(r)
        visual(r)
        transforms(r)
        animation(r)
    }

    // MARK: Color and style

    static func styles(_ r: KRegistry) {
        r.modifier("foregroundColor", .drawing) { m in
            m.form("_:Color?") { c, view in
                if let col = c.color(0) { view.foregroundColor(col) } else { view }
            }
            m.text { c, t in c.color(0).map { t.foregroundColor($0) } ?? t }
        }
        r.modifier("foregroundStyle", .drawing) { m in
            m.form("_:ColorOrStyle") { c, view in
                if let s = c.shapeStyle(0) { view.foregroundStyle(s) } else { view }
            }
            m.form("_:ColorOrStyle _:ColorOrStyle") { c, view in
                if let a = c.shapeStyle(0), let b = c.shapeStyle(1) { AnyView(view.foregroundStyle(a, b)) }
                else if let a = c.shapeStyle(0) { AnyView(view.foregroundStyle(a)) }
                else { view }
            }
            m.form("_:ColorOrStyle _:ColorOrStyle _:ColorOrStyle") { c, view in
                if let a = c.shapeStyle(0), let b = c.shapeStyle(1), let s3 = c.shapeStyle(2) { AnyView(view.foregroundStyle(a, b, s3)) }
                else if let a = c.shapeStyle(0) { AnyView(view.foregroundStyle(a)) }
                else { view }
            }
            // On chart marks: a series, by value.
            m.form("by:any", receiver: "ChartContent") { _, view in view }
            m.text { c, t in
                if let col = c.color(0) { return t.foregroundColor(col) }
                // A gradient or material: Text takes any ShapeStyle (iOS 17).
                if let s = c.shapeStyle(0) { return t.foregroundStyle(s) }
                return t
            }
        }
        for name in ["tint", "accentColor"] {
            r.modifier(name, .drawing) { m in
                m.form("_:Color?") { c, view in
                    if let col = c.color(0) { view.tint(col) } else { view }
                }
            }
        }
    }

    // MARK: Backgrounds, overlays, clipping

    static func layers(_ r: KRegistry) {
        r.modifier("background", .drawing) { m in
            m.form("alignment:Alignment? content:content") { c, view in
                let content = c.content("content")
                view.background(alignment: c.alignment("alignment")) { content }
            }
            m.forms(["_:ColorOrStyle ignoresSafeAreaEdges:any?", "_:ColorOrStyle in:any fillStyle:any?", "_:ColorOrStyle alignment:Alignment?",
                     "ignoresSafeAreaEdges:any?"]) { c, view in background(c, view) }
        }
        r.modifier("overlay", .drawing) { m in
            m.form("alignment:Alignment? content:content") { c, view in
                let content = c.content("content")
                view.overlay(alignment: c.alignment("alignment")) { content }
            }
            m.form("_:any alignment:Alignment?") { c, view in
                view.overlay(alignment: c.alignment("alignment")) { c.r.renderList(KBuiltins.asViews(c[0] ?? .void, c.interp)) }
            }
            m.form("_:ColorOrStyle in:any fillStyle:any?") { c, view in
                if let s = c.shapeStyle(0), case .view(let sv)? = c["in"], let chain = c.r.shapeChain(sv) {
                    AnyView(view.overlay(chain.kind.anyShape.fill(s)))
                } else {
                    view
                }
            }
        }
        r.modifier("border", .drawing) { m in
            m.form("_:ColorOrStyle width:number?") { c, view in view.border(c.color(0) ?? .primary, width: c.cg("width") ?? 1) }
        }
        r.modifier("cornerRadius", .drawing) { m in
            m.form("_:number antialiased:bool?") { c, view in view.clipShape(RoundedRectangle(cornerRadius: c.cg(0) ?? 0)) }
            // On a bar mark: read by the chart.
            m.form("_:number style:any?", receiver: "ChartContent") { _, view in view }
        }
        r.modifier("clipShape", .drawing) { m in
            m.form("_:any style:any?") { c, view in
                if let shape = shapeArg(c[0], c.r) { view.clipShape(shape) } else { view }
            }
        }
        r.modifier("mask", .drawing) { m in
            m.form("alignment:Alignment? mask:content") { c, view in
                let mask = c.content("mask")
                view.mask(alignment: c.alignment("alignment")) { mask }
            }
            m.form("_:any") { c, view in
                if case .view(let mv)? = c[0] { view.mask { c.r.render(mv) } } else { view }
            }
        }
        r.modifier("clipped", .drawing) { m in
            m.form("antialiased:bool?") { _, view in view.clipped() }
        }
        r.modifier("shadow", .drawing) { m in
            m.form("color:ColorOrStyle? radius:number x:number? y:number?") { c, view in
                view.shadow(color: c.color("color") ?? Color.black.opacity(0.33), radius: c.cg("radius") ?? 4, x: c.cg("x") ?? 0, y: c.cg("y") ?? 0)
            }
        }
    }

    /// `.background(style)`, `.background(style, in: shape)`, `.background(view)`.
    @MainActor static func background(_ c: KCall, _ view: AnyView) -> AnyView {
        let first = c[0]
        if let style = c.shapeStyle(0) {
            if let shape = shapeArg(c["in"], c.r) { return AnyView(view.background(style, in: shape)) }
            if case .native(.color(let col))? = first { return AnyView(view.background(col)) }
            return AnyView(view.background(style))
        }
        if let v = first {
            let views = KBuiltins.asViews(v, c.interp)
            if !views.isEmpty { return AnyView(view.background(c.r.renderList(views))) }
        }
        return view
    }

    /// A shape argument: a shape view, or `.circle`, `.capsule`, `.rect(cornerRadius:)`.
    @MainActor static func shapeArg(_ v: KV?, _ r: KRenderer) -> AnyShape? {
        switch v {
        case .view(let sv)?:
            return r.shapeChain(sv)?.kind.anyShape
        case .native(.implicit(let n, let a))?:
            switch n {
            case "circle": return AnyShape(Circle())
            case "capsule": return AnyShape(Capsule())
            case "rect":
                if let cr = a.first?.asDouble { return AnyShape(RoundedRectangle(cornerRadius: cr)) }
                return AnyShape(Rectangle())
            case "ellipse": return AnyShape(Ellipse())
            default: return nil
            }
        default: return nil
        }
    }

    // MARK: Visual effects

    static func visual(_ r: KRegistry) {
        r.modifier("opacity", .drawing) { m in m.form("_:number") { c, view in view.opacity(c.double(0) ?? 1) } }
        r.modifier("blur", .drawing) { m in m.form("radius:number opaque:bool?") { c, view in view.blur(radius: c.cg("radius") ?? 0) } }
        r.modifier("brightness", .drawing) { m in m.form("_:number") { c, view in view.brightness(c.double(0) ?? 0) } }
        r.modifier("contrast", .drawing) { m in m.form("_:number") { c, view in view.contrast(c.double(0) ?? 1) } }
        r.modifier("saturation", .drawing) { m in m.form("_:number") { c, view in view.saturation(c.double(0) ?? 1) } }
        r.modifier("grayscale", .drawing) { m in m.form("_:number") { c, view in view.grayscale(c.double(0) ?? 0) } }
        r.modifier("hueRotation", .drawing) { m in m.form("_:Angle") { c, view in view.hueRotation(c.angle(0)) } }
        r.modifier("colorMultiply", .drawing) { m in
            m.form("_:Color") { c, view in
                if let col = c.color(0) { view.colorMultiply(col) } else { view }
            }
        }
        r.modifier("colorInvert", .drawing) { m in m.form("") { _, view in view.colorInvert() } }
        r.modifier("blendMode", .drawing, support: .stub, notes: "Always `.normal`.") { m in m.form("_:BlendMode") { _, view in view.blendMode(.normal) } }
        r.modifier("compositingGroup", .drawing) { m in m.form("") { _, view in view.compositingGroup() } }
        r.modifier("drawingGroup", .drawing) { m in m.form("opaque:bool? colorMode:any?") { _, view in view.drawingGroup() } }
        r.modifier("luminanceToAlpha", .drawing, support: .stub) { m in m.stub([""]) }
    }

    // MARK: Transforms

    static func transforms(_ r: KRegistry) {
        r.modifier("rotationEffect", .drawing) { m in
            m.form("_:Angle anchor:UnitPoint?") { c, view in view.rotationEffect(c.angle(0), anchor: c.unitPoint("anchor") ?? .center) }
        }
        r.modifier("rotation3DEffect", .drawing) { m in
            m.form("_:Angle axis:any anchor:UnitPoint? anchorZ:number? perspective:number?") { c, view in
                view.rotation3DEffect(c.angle(0), axis: axis(c["axis"]), perspective: c.cg("perspective") ?? 1)
            }
        }
        r.modifier("scaleEffect", .drawing) { m in
            m.form("_:any anchor:UnitPoint?") { c, view in
                if let s = c.cg(0) {
                    AnyView(view.scaleEffect(s, anchor: c.unitPoint("anchor") ?? .center))
                } else if case .native(.size(let w, let h))? = c[0] {
                    AnyView(view.scaleEffect(x: w, y: h, anchor: c.unitPoint("anchor") ?? .center))
                } else {
                    view
                }
            }
            m.form("x:number? y:number? anchor:UnitPoint?") { c, view in
                view.scaleEffect(x: c.cg("x") ?? 1, y: c.cg("y") ?? 1, anchor: c.unitPoint("anchor") ?? .center)
            }
        }
    }

    @MainActor static func axis(_ v: KV?) -> (CGFloat, CGFloat, CGFloat) {
        guard case .tuple(let vals, let labels)? = v else { return (0, 1, 0) }
        func value(_ l: String, _ i: Int) -> Double { labels.firstIndex(of: l).flatMap { vals[$0].asDouble } ?? (i < vals.count ? vals[i].asDouble ?? 0 : 0) }
        return (value("x", 0), value("y", 1), value("z", 2))
    }

    // MARK: Animation and transitions

    static func animation(_ r: KRegistry) {
        r.modifier("animation", .drawing) { m in
            m.form("_:Animation? value:any") { c, view in view.animation(c.animation(0), value: c["value"] ?? .nilValue) }
            m.form("_:Animation?", notes: "Deprecated in SwiftUI: animates every change.") { c, view in view.animation(c.animation(0), value: UUID()) }
        }
        r.modifier("transition", .drawing) { m in
            m.form("_:AnyTransition") { c, view in view.transition(transition(c[0])) }
        }
        r.modifier("contentTransition", .drawing, support: .partial, notes: "`.numericText()`; anything else cross-fades.") { m in
            m.form("_:ContentTransition") { c, view in
                if let n = c.symbol(0), n.hasPrefix("numericText") { view.contentTransition(.numericText()) } else { view.contentTransition(.opacity) }
            }
        }
    }

    static func transition(_ v: KV?) -> AnyTransition {
        guard case .native(let n)? = v else { return .opacity }
        var name = "opacity"
        var args: [KV] = []
        if case .implicit(let nm, let a) = n { name = nm; args = a }
        if case .transition(let nm, let a) = n { name = nm; args = a }
        switch name.split(separator: ".").first.map(String.init) ?? name {
        case "scale": return .scale
        case "slide": return .slide
        case "move":
            if case .native(.implicit(let e, _))? = args.first {
                let edges: [String: Edge] = ["top": .top, "bottom": .bottom, "leading": .leading, "trailing": .trailing]
                return .move(edge: edges[e] ?? .bottom)
            }
            return .move(edge: .bottom)
        case "push": return .push(from: .trailing)
        case "identity": return .identity
        default: return .opacity
        }
    }
}
