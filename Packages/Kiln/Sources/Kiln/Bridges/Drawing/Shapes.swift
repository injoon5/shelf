//
//  Shapes.swift
//  Bridges: shapes, gradients and paths
//
//  A shape keeps its shape-ness through `trim`, so `fill`, `stroke` and
//  `strokeBorder` reach the real `Shape`. Your own `Shape` structs are shown
//  by `KUserShape`, which runs their `path(in:)` whenever SwiftUI draws.
//

import SwiftUI

extension DrawingBridges {
    static let shapeNames = ["Circle", "Rectangle", "RoundedRectangle", "Capsule", "Ellipse", "UnevenRoundedRectangle", "ContainerRelativeShape"]

    static func shapes(_ r: KRegistry) {
        let signatures: [String: [String]] = [
            "Circle": [""], "Rectangle": [""], "Ellipse": [""], "ContainerRelativeShape": [""],
            "Capsule": ["style:RoundedCornerStyle?"],
            "RoundedRectangle": ["cornerRadius:number style:RoundedCornerStyle?", "cornerSize:CGSize style:RoundedCornerStyle?"],
            "UnevenRoundedRectangle": ["topLeadingRadius:number? bottomLeadingRadius:number? bottomTrailingRadius:number? topTrailingRadius:number? style:RoundedCornerStyle?"],
        ]
        for name in shapeNames {
            r.view(name, .drawing) { v in
                v.forms(signatures[name] ?? [""]) { c in KShapeKind(name, c.a).anyShape }
            }
        }
        for name in ["UserShape", "PathShape"] {
            r.view(name, .drawing) { v in
                v.engineOnly()
                v.form("_:any") { c in KShapeKind.custom(c.r.customShape(name, c.a)).anyShape }
            }
        }

        // Gradients, as views and as styles (`.fill(LinearGradient(…))`).
        let gradients: [String: [String]] = [
            "LinearGradient": ["colors:[Color] startPoint:UnitPoint? endPoint:UnitPoint?", "gradient:any startPoint:UnitPoint endPoint:UnitPoint",
                               "stops:any startPoint:UnitPoint endPoint:UnitPoint"],
            "RadialGradient": ["colors:[Color] center:UnitPoint startRadius:number endRadius:number",
                               "gradient:any center:UnitPoint startRadius:number endRadius:number"],
            "AngularGradient": ["colors:[Color] center:UnitPoint startAngle:Angle? endAngle:Angle?", "gradient:any center:UnitPoint startAngle:Angle? endAngle:Angle?",
                                "colors:[Color] center:UnitPoint angle:Angle"],
            "EllipticalGradient": ["colors:[Color] center:UnitPoint? startRadiusFraction:number? endRadiusFraction:number?",
                                   "gradient:any center:UnitPoint? startRadiusFraction:number? endRadiusFraction:number?"],
        ]
        for (name, sigs) in gradients {
            r.view(name, .drawing, support: .partial, notes: "Colors only: `stops:` aren't placed.") { v in
                v.forms(sigs) { c in
                    if let g = c.r.gradient(KView.primitive(name, c.args, c.labels, line: c.line)) { Rectangle().fill(g) } else { EmptyView() }
                }
            }
        }

        r.type("Path", .drawing, notes: "`move(to:)`, lines, arcs, curves, rects and ellipses; a `Path` in a body is drawn like a shape.") { t in
            t.initializer { c in
                let box = KPathBox()
                if case .native(.rect(let x, let y, let w, let h))? = c.first {
                    let rect = CGRect(x: x, y: y, width: w, height: h)
                    if c.labels.first == "ellipseIn" { box.path = Path(ellipseIn: rect) }
                    else if let cr = c.arg("cornerRadius")?.asDouble { box.path = Path(roundedRect: rect, cornerRadius: cr) }
                    else { box.path = Path(rect) }
                }
                if case .function(let f)? = c.last { _ = try c.interp.call(f, [.native(.path(KRef(box)))], [nil]) }
                return .native(.path(KRef(box)))
            }
            @MainActor func box(_ c: KCall) -> KPathBox { if case .native(.path(let b)) = c.receiver { return b.value }; return KPathBox() }
            @MainActor func pt(_ v: KV?) -> CGPoint { if case .native(.point(let x, let y))? = v { return CGPoint(x: x, y: y) }; return .zero }
            @MainActor func rect(_ v: KV?) -> CGRect {
                if case .native(.rect(let x, let y, let w, let h))? = v { return CGRect(x: x, y: y, width: w, height: h) }
                return .zero
            }
            @MainActor func ang(_ v: KV?) -> Angle { if case .native(.angle(let d))? = v { return .degrees(d) }; return .degrees(v?.asDouble ?? 0) }
            t.method("move") { c in box(c).path.move(to: pt(c.arg("to") ?? c.first)); return .void }
            t.method("addLine") { c in box(c).path.addLine(to: pt(c.arg("to") ?? c.first)); return .void }
            t.method("addLines") { c in box(c).path.addLines((c.first?.asArray ?? []).map { pt($0) }); return .void }
            t.method("addArc") { c in
                if let center = c.arg("center") {
                    box(c).path.addArc(center: pt(center), radius: c.arg("radius")?.cg ?? 10, startAngle: ang(c.arg("startAngle")),
                                       endAngle: ang(c.arg("endAngle")), clockwise: c.arg("clockwise").map { c.interp.truthy($0) } ?? false)
                }
                return .void
            }
            t.method("addRect") { c in box(c).path.addRect(rect(c.first)); return .void }
            t.method("addEllipse") { c in box(c).path.addEllipse(in: rect(c.arg("in") ?? c.first)); return .void }
            t.method("addRoundedRect") { c in
                var radius = 8.0
                if case .native(.size(let w, _))? = c.arg("cornerSize") { radius = w }
                if let cr = c.arg("cornerRadius")?.asDouble { radius = cr }
                box(c).path.addRoundedRect(in: rect(c.arg("in") ?? c.first), cornerSize: CGSize(width: radius, height: radius))
                return .void
            }
            t.method("addQuadCurve") { c in box(c).path.addQuadCurve(to: pt(c.arg("to")), control: pt(c.arg("control"))); return .void }
            t.method("addCurve") { c in
                box(c).path.addCurve(to: pt(c.arg("to")), control1: pt(c.arg("control1")), control2: pt(c.arg("control2")))
                return .void
            }
            t.method("closeSubpath") { c in box(c).path.closeSubpath(); return .void }
            t.method("addPath") { c in
                if case .native(.path(let other))? = c.first { box(c).path.addPath(other.value.path) }
                return .void
            }
        }

        r.view("Canvas", .drawing, support: .stub, notes: "Draws nothing yet: draw with a custom `Shape` instead.") { v in
            v.form("opaque:bool? colorMode:any? rendersAsynchronously:bool? renderer:closure") { c in
                let _ = c.interp.warn("Canvas isn't supported in Kiln yet; it draws nothing.")
                EmptyView()
            }
        }

        // Modifiers that keep a shape a shape.
        r.modifier("fill", .drawing) { m in
            m.formOnBase("_:ColorOrStyle? style:any?", receiver: "Shape") { c in shapeModifier(c) }
        }
        for name in ["stroke", "strokeBorder"] {
            r.modifier(name, .drawing) { m in
                for sig in ["_:ColorOrStyle? lineWidth:number? antialiased:bool?", "_:ColorOrStyle? style:StrokeStyle antialiased:bool?"] {
                    m.formOnBase(sig, receiver: name == "stroke" ? "Shape" : "InsettableShape") { c in shapeModifier(c) }
                }
            }
        }
        r.modifier("trim", .drawing) { m in
            m.formOnBase("from:number? to:number?", receiver: "Shape") { c in shapeModifier(c) }
        }
        for (name, sigs) in [("inset", ["by:number"]), ("rotation", ["_:Angle anchor:UnitPoint?"]), ("scale", ["_:number anchor:UnitPoint?", "x:number? y:number? anchor:UnitPoint?"])] {
            r.modifier(name, .drawing, support: .stub, notes: "Accepted on a shape, with no effect yet.") { m in
                for s in sigs { m.formOnBase(s, receiver: "Shape") { c in shapeModifier(c) } }
            }
        }
    }

    /// A shape modifier on a shape; anything else is shown unchanged.
    @MainActor static func shapeModifier(_ c: KCall) -> AnyView {
        guard let base = c.base else { return AnyView(EmptyView()) }
        guard let chain = c.r.shapeChain(base) else { return c.view }
        return c.r.shapeModifier(chain, KModifier(name: c.memberName, args: c.args, labels: c.labels, line: c.line))
    }
}

extension KRenderer {
    // MARK: Shapes

    /// A shape plus the shape-preserving operations applied to it so far.
    struct ShapeChain {
        var kind: KShapeKind
        var trim: (Double, Double)? = nil
    }

    func shapeChain(_ v: KView) -> ShapeChain? {
        switch v.kind {
        case .primitive(let n, let args, let labels, _):
            if n == "UserShape" || n == "PathShape" {
                return ShapeChain(kind: .custom(customShape(n, KArgs(args: args, labels: labels))))
            }
            guard ["Circle", "Rectangle", "RoundedRectangle", "Capsule", "Ellipse", "UnevenRoundedRectangle", "ContainerRelativeShape"].contains(n) else { return nil }
            return ShapeChain(kind: KShapeKind(n, KArgs(args: args, labels: labels)))
        case .modified(let base, let m) where m.name == "trim":
            guard var chain = shapeChain(base) else { return nil }
            chain.trim = (m.arg("from")?.asDouble ?? 0, m.arg("to")?.asDouble ?? 1)
            return chain
        default:
            return nil
        }
    }

    func shapeModifier(_ chain: ShapeChain, _ m: KModifier) -> AnyView {
        var shape = chain.kind.anyShape
        if let t = chain.trim { shape = AnyShape(shape.trim(from: t.0, to: t.1)) }
        switch m.name {
        case "trim":
            let from = m.arg("from")?.asDouble ?? 0, to = m.arg("to")?.asDouble ?? 1
            return AnyView(AnyShape(shape.trim(from: from, to: to)))
        case "fill":
            if let style = shapeStyle(m.first) { return AnyView(shape.fill(style)) }
            return AnyView(shape.fill(.foreground))
        case "stroke", "strokeBorder":
            let style = shapeStyle(m.unlabeled(0)) ?? AnyShapeStyle(.foreground)
            var ss = StrokeStyle(lineWidth: m.arg("lineWidth")?.asDouble ?? 1)
            if case .native(.strokeStyle(let k))? = m.arg("style") {
                ss = StrokeStyle(lineWidth: k.lineWidth, lineCap: lineCap(k.lineCap), lineJoin: lineJoin(k.lineJoin), dash: k.dash.map { CGFloat($0) })
            }
            if m.name == "strokeBorder", chain.trim == nil { return chain.kind.strokeBorder(style, ss) }
            return AnyView(shape.stroke(style, style: ss))
        default:
            return AnyView(shape)
        }
    }

    func customShape(_ name: String, _ a: KArgs) -> AnyShape {
        if name == "PathShape", case .native(.path(let box))? = a.first { return AnyShape(box.value.path) }
        if case .structV(let s)? = a.first { return AnyShape(KUserShape(value: s, interp: interp)) }
        return AnyShape(Rectangle())
    }

    func lineCap(_ s: String) -> CGLineCap { s == "round" ? .round : (s == "square" ? .square : .butt) }
    func lineJoin(_ s: String) -> CGLineJoin { s == "round" ? .round : (s == "bevel" ? .bevel : .miter) }

}

/// The concrete shape types, so `strokeBorder` (InsettableShape only) works.
/// A Shape struct written in the interpreted code: its `path(in:)` runs there.
struct KUserShape: Shape {
    let value: KStructValue
    let interp: KInterpreter

    nonisolated func path(in rect: CGRect) -> Path {
        MainActor.assumeIsolated {
            guard let m = value.type.method("path") else { return Path(rect) }
            let ctx = KSelfContext(type: value.type, location: .box(KBox(.structV(value))))
            let r = KV.native(.rect(rect.minX, rect.minY, rect.width, rect.height))
            do {
                let result = try interp.entry { try interp.invoke(m, args: [r], labels: ["in"], selfContext: ctx, parent: interp.globalEnv) }
                if case .native(.path(let box)) = result { return box.value.path }
            } catch {
                interp.report(error)
            }
            return Path()
        }
    }
}

enum KShapeKind {
    case circle, rectangle, capsule, ellipse, container
    case custom(AnyShape)
    case rounded(Double, RoundedCornerStyle)
    case uneven(Double, Double, Double, Double)

    @MainActor
    init(_ name: String, _ a: KArgs) {
        switch name {
        case "Circle": self = .circle
        case "Capsule": self = .capsule
        case "Ellipse": self = .ellipse
        case "ContainerRelativeShape": self = .container
        case "RoundedRectangle":
            var style: RoundedCornerStyle = .circular
            if case .native(.implicit("continuous", _))? = a["style"] { style = .continuous }
            if let r = a["cornerRadius"]?.asDouble { self = .rounded(r, style) }
            else if case .native(.size(let w, _))? = a["cornerSize"] { self = .rounded(w, style) }
            else { self = .rounded(8, style) }
        case "UnevenRoundedRectangle":
            self = .uneven(a["topLeadingRadius"]?.asDouble ?? 0, a["bottomLeadingRadius"]?.asDouble ?? 0,
                           a["bottomTrailingRadius"]?.asDouble ?? 0, a["topTrailingRadius"]?.asDouble ?? 0)
        default: self = .rectangle
        }
    }

    var anyShape: AnyShape {
        switch self {
        case .circle: return AnyShape(Circle())
        case .rectangle: return AnyShape(Rectangle())
        case .capsule: return AnyShape(Capsule())
        case .ellipse: return AnyShape(Ellipse())
        case .container: return AnyShape(ContainerRelativeShape())
        case .custom(let s): return s
        case .rounded(let r, let s): return AnyShape(RoundedRectangle(cornerRadius: r, style: s))
        case .uneven(let tl, let bl, let br, let tr):
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: tl, bottomLeadingRadius: bl, bottomTrailingRadius: br, topTrailingRadius: tr))
        }
    }

    func strokeBorder(_ style: AnyShapeStyle, _ ss: StrokeStyle) -> AnyView {
        switch self {
        case .circle: return AnyView(Circle().strokeBorder(style, style: ss))
        case .capsule: return AnyView(Capsule().strokeBorder(style, style: ss))
        case .ellipse: return AnyView(Ellipse().strokeBorder(style, style: ss))
        case .rounded(let r, let s): return AnyView(RoundedRectangle(cornerRadius: r, style: s).strokeBorder(style, style: ss))
        default: return AnyView(Rectangle().strokeBorder(style, style: ss))
        }
    }
}

