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
    /// Shapes the renderer's `ShapeChain` reads, Round 1's included.
    static let chainShapeNames: Set<String> = Set(shapeNames + ["ConcentricRectangle"])

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
                v.form("_:any") { c in c.r.shapeView(c.r.customShape(name, c.a)) { AnyView($0) } }
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
            t.manifestKind = "view"
            for sig in ["", "_:closure", "_:CGRect", "roundedRect:CGRect cornerRadius:number style:any?", "ellipseIn:CGRect"] {
                t.initializer(sig) { c in try path(c) }
            }
            t.initializer { c in try path(c) }
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
    }

    /// `Path()`, `Path(rect)`, `Path(ellipseIn:)`, `Path { p in … }`.
    @MainActor static func path(_ c: KCall) throws -> KV {
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
        /// `rotation`, `scale`, `union`… in order (ShapesAndStyles.swift).
        var ops: [(AnyShape) -> AnyShape] = []

        func applied(_ shape: AnyShape) -> AnyShape {
            var s = shape
            for op in ops { s = op(s) }
            return s
        }
    }

    func shapeChain(_ v: KView) -> ShapeChain? {
        switch v.kind {
        case .primitive(let n, let args, let labels, _):
            if n == "UserShape" || n == "PathShape" {
                return ShapeChain(kind: customShape(n, KArgs(args: args, labels: labels)))
            }
            if n == "AnyShape", let shape = DrawingBridges.shapeArg(args.first, self) { return ShapeChain(kind: .custom(shape)) }
            guard DrawingBridges.chainShapeNames.contains(n) else { return nil }
            return ShapeChain(kind: KShapeKind(n, KArgs(args: args, labels: labels)))
        case .modified(let base, let m) where m.name == "trim":
            guard var chain = shapeChain(base) else { return nil }
            chain.trim = (m.arg("from")?.asDouble ?? 0, m.arg("to")?.asDouble ?? 1)
            return chain
        case .modified(let base, let m) where m.name == "inset":
            guard let chain = shapeChain(base), chain.trim == nil, chain.ops.isEmpty, let inset = chain.kind.inset(m.arg("by")?.cg ?? 0) else { return nil }
            return ShapeChain(kind: .custom(inset))
        case .modified(let base, let m):
            guard var chain = shapeChain(base), let op = shapeOperation(m) else { return nil }
            if let t = chain.trim {
                // A trim before the operation is part of the shape it works on.
                let before = chain
                chain = ShapeChain(kind: .custom(AnyShape(before.applied(before.kind.anyShape).trim(from: t.0, to: t.1))))
            }
            chain.ops.append(op)
            return chain
        default:
            return nil
        }
    }

    func shapeModifier(_ chain: ShapeChain, _ m: KModifier) -> AnyView {
        let r = self
        return shapeView(chain.kind) { base in
            var shape = chain.applied(base)
            if let t = chain.trim { shape = AnyShape(shape.trim(from: t.0, to: t.1)) }
            switch m.name {
            case "trim":
                let from = m.arg("from")?.asDouble ?? 0, to = m.arg("to")?.asDouble ?? 1
                return AnyView(AnyShape(shape.trim(from: from, to: to)))
            case "fill":
                if let style = r.shapeStyle(m.first) { return AnyView(shape.fill(style)) }
                return AnyView(shape.fill(.foreground))
            case "stroke", "strokeBorder":
                let style = r.shapeStyle(m.unlabeled(0)) ?? AnyShapeStyle(.foreground)
                var ss = StrokeStyle(lineWidth: m.arg("lineWidth")?.asDouble ?? 1)
                if case .native(.strokeStyle(let k))? = m.arg("style") {
                    ss = StrokeStyle(lineWidth: k.lineWidth, lineCap: r.lineCap(k.lineCap), lineJoin: r.lineJoin(k.lineJoin), dash: k.dash.map { CGFloat($0) })
                }
                if m.name == "strokeBorder", chain.trim == nil, chain.ops.isEmpty, !chain.kind.isUser { return chain.kind.strokeBorder(style, ss) }
                return AnyView(shape.stroke(style, style: ss))
            default:
                return AnyView(shape)
            }
        }
    }

    /// A shape shown with `style` (its fill, stroke and trim). The app's own
    /// shape is drawn by `KShapeHost`, so its `path(in:)` runs in a view's
    /// `body`, on the main thread, even while SwiftUI animates it on its
    /// render thread.
    func shapeView(_ kind: KShapeKind, _ style: @escaping @MainActor (AnyShape) -> AnyView) -> AnyView {
        if case .user(let app) = kind { return AnyView(KShapeHost(app: app, style: style)) }
        return style(kind.anyShape)
    }

    func customShape(_ name: String, _ a: KArgs) -> KShapeKind {
        if name == "PathShape", case .native(.path(let box))? = a.first { return .custom(AnyShape(box.value.path)) }
        if let v = a.first, let t = v.userType, t.isShape, let app = KAppValue(v, interp) { return .user(app) }
        return .custom(AnyShape(Rectangle()))
    }

    func lineCap(_ s: String) -> CGLineCap { s == "round" ? .round : (s == "square" ? .square : .butt) }
    func lineJoin(_ s: String) -> CGLineJoin { s == "round" ? .round : (s == "bevel" ? .bevel : .miter) }

}

/// The app's own `Shape` (PLAN.md §1.5's Shape proxy), where a `Shape` value
/// is needed (`.clipShape`, `.background(in:)`, `AnyShape`): `path(in:)`
/// runs the app's code. `animatableData` is the app's (`AnimatablePair`,
/// `@Animatable`, a hand-written one), read once on the main thread and then
/// kept, because SwiftUI interpolates it on its render thread; the app's
/// value gets it when `path(in:)` runs.
struct KUserShape: Shape, @unchecked Sendable {
    let app: KAppValue
    var data: KAnimVector

    @MainActor init(app: KAppValue) {
        self.app = app
        data = KAnimatable.data(app)
    }

    nonisolated var animatableData: KAnimVector {
        get { data }
        set { data = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let data = self.data
        return KDelegates.onMain { KAnimatable.path(app, data, rect) }
    }
}

/// The app's shape shown as a view: an `Animatable` view whose `body` draws
/// the app's path for the size it's given, so the app's code runs on the
/// main thread each frame SwiftUI animates it.
struct KShapeHost: View, Animatable {
    let app: KAppValue
    var data: KAnimVector
    let style: @MainActor (AnyShape) -> AnyView

    init(app: KAppValue, style: @escaping @MainActor (AnyShape) -> AnyView) {
        self.app = app
        self.style = style
        data = KAnimatable.data(app)
    }

    nonisolated var animatableData: KAnimVector {
        get { data }
        set { data = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            style(AnyShape(MainActor.assumeIsolated { KAnimatable.path(app, data, CGRect(origin: .zero, size: geo.size)) }))
        }
    }
}

enum KShapeKind {
    case circle, rectangle, capsule, ellipse, container
    case custom(AnyShape)
    /// The app's own `Shape`.
    case user(KAppValue)
    case rounded(Double, RoundedCornerStyle)
    case uneven(Double, Double, Double, Double)

    @MainActor
    init(_ name: String, _ a: KArgs) {
        switch name {
        case "Circle": self = .circle
        case "Capsule": self = .capsule
        case "Ellipse": self = .ellipse
        case "ContainerRelativeShape": self = .container
        case "ConcentricRectangle":
            if #available(iOS 26, macOS 26, *) { self = .custom(AnyShape(ConcentricRectangle())) } else { self = .container }
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

    @MainActor var anyShape: AnyShape {
        switch self {
        case .circle: return AnyShape(Circle())
        case .rectangle: return AnyShape(Rectangle())
        case .capsule: return AnyShape(Capsule())
        case .ellipse: return AnyShape(Ellipse())
        case .container: return AnyShape(ContainerRelativeShape())
        case .custom(let s): return s
        case .user(let app): return AnyShape(KUserShape(app: app))
        case .rounded(let r, let s): return AnyShape(RoundedRectangle(cornerRadius: r, style: s))
        case .uneven(let tl, let bl, let br, let tr):
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: tl, bottomLeadingRadius: bl, bottomTrailingRadius: br, topTrailingRadius: tr))
        }
    }

    var isUser: Bool { if case .user = self { return true }; return false }

    /// `inset(by:)` on a shape that's insettable.
    @MainActor func inset(_ amount: CGFloat) -> AnyShape? {
        switch self {
        case .circle: return AnyShape(Circle().inset(by: amount))
        case .rectangle: return AnyShape(Rectangle().inset(by: amount))
        case .capsule: return AnyShape(Capsule().inset(by: amount))
        case .ellipse: return AnyShape(Ellipse().inset(by: amount))
        case .container: return AnyShape(ContainerRelativeShape().inset(by: amount))
        case .rounded(let r, let s): return AnyShape(RoundedRectangle(cornerRadius: r, style: s).inset(by: amount))
        case .uneven(let tl, let bl, let br, let tr):
            return AnyShape(UnevenRoundedRectangle(topLeadingRadius: tl, bottomLeadingRadius: bl, bottomTrailingRadius: br, topTrailingRadius: tr).inset(by: amount))
        default: return nil
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

