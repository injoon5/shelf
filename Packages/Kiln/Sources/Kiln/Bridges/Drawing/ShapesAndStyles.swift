//
//  ShapesAndStyles.swift
//  Bridges: shape operations, more shapes, shape styles and transitions
//
//  Shape operations (`inset`, `rotation`, `scale`, `transform`, `union` and
//  the other set operations) keep a shape a shape: the renderer's
//  `ShapeChain` collects them, so `fill` and `stroke` still reach the real
//  `Shape`.
//

import SwiftUI

extension DrawingBridges {
    /// Round 1's drawing bridges (PLAN.md §2), beyond §1.4's port.
    static func round1(_ r: KRegistry) {
        animators(r)
        glass(r)
        visualAndTransforms(r)
        shapeOperations(r)
        moreShapes(r)
        shapeStyles(r)
        transitionTypes(r)
    }

    // MARK: Shape operations

    static func shapeOperations(_ r: KRegistry) {
        r.modifier("inset", .drawing) { m in
            m.formOnBase("by:number", receiver: "InsettableShape") { c in shapeModifier(c) }
        }
        r.modifier("rotation", .drawing) { m in
            m.formOnBase("_:Angle anchor:UnitPoint?", receiver: "Shape") { c in shapeModifier(c) }
        }
        r.modifier("scale", .drawing) { m in
            m.formOnBase("_:number anchor:UnitPoint?", receiver: "Shape") { c in shapeModifier(c) }
            m.formOnBase("x:number? y:number? anchor:UnitPoint?", receiver: "Shape") { c in shapeModifier(c) }
        }
        r.modifier("transform", .drawing) { m in
            m.formOnBase("_:CGAffineTransform", receiver: "Shape") { c in shapeModifier(c) }
        }
        for name in ["union", "intersection", "subtracting", "symmetricDifference", "lineIntersection", "lineSubtraction"] {
            r.modifier(name, .drawing) { m in
                m.formOnBase("_:any eoFill:bool?", receiver: "Shape") { c in shapeModifier(c) }
            }
        }
        // `Circle().path(in: rect)`: a shape value's path, for `Canvas` and your own shapes.
        r.type("View", .drawing) { t in
            t.internal()
            t.method("path", "in:CGRect") { c in
                guard case .view(let v) = c.receiver, let chain = c.r.shapeChain(v) else { throw c.fail("is a method of shapes") }
                let rect = KCanvas.rect(c["in"]) ?? .zero
                let box = KPathBox()
                box.path = c.r.shapePath(chain, in: rect)
                return .native(.path(KRef(box)))
            }
        }
    }

    // MARK: More shapes

    static func moreShapes(_ r: KRegistry) {
        r.view("AnyShape", .drawing) { v in
            v.form("_:any") { c in
                if let s = shapeArg(c[0], c.r) { s } else { EmptyView() }
            }
        }
        r.view("ConcentricRectangle", .drawing, introduced: "26.0", notes: "Follows its container's corners, as SwiftUI's does.") { v in
            v.forms(["", "corners:any isUniform:bool?",
                     "topLeadingCorner:any? topTrailingCorner:any? bottomLeadingCorner:any? bottomTrailingCorner:any?",
                     "uniformTopCorners:any? uniformBottomCorners:any?", "uniformLeadingCorners:any? uniformTrailingCorners:any?"]) { c in
                KShapeKind("ConcentricRectangle", c.a).anyShape
            }
        }
        r.view("MeshGradient", .drawing, introduced: "18.0", notes: "`points:` as `[x, y]` pairs or `.init(x, y)`, and `colors:`.") { v in
            v.forms(["width:number height:number points:any colors:any background:Color? smoothsColors:bool? colorSpace:any?",
                     "width:number height:number bezierPoints:any colors:any background:Color? smoothsColors:bool? colorSpace:any?"]) { c in
                mesh(c)
            }
        }
        r.type("FillStyle", .drawing, support: .full) { t in
            t.initializer("eoFill:bool? antialiased:bool?") { c in
                .native(.boxed(KBoxed("FillStyle", KFillStyle(eoFill: c.bool("eoFill", default: false), antialiased: c.bool("antialiased", default: true)))))
            }
        }
    }

    @MainActor static func mesh(_ c: KCall) -> AnyView {
        guard #available(iOS 18, macOS 15, *) else { return AnyView(EmptyView()) }
        let w = c.int("width") ?? 2, h = c.int("height") ?? 2
        func pair(_ v: KV) -> SIMD2<Float> {
            switch v {
            case .array(let a) where a.count >= 2: return SIMD2(Float(a[0].asDouble ?? 0), Float(a[1].asDouble ?? 0))
            case .native(.implicit(_, let a)) where a.count >= 2: return SIMD2(Float(a[0].asDouble ?? 0), Float(a[1].asDouble ?? 0))
            case .tuple(let a, _) where a.count >= 2: return SIMD2(Float(a[0].asDouble ?? 0), Float(a[1].asDouble ?? 0))
            case .native(.point(let x, let y)): return SIMD2(Float(x), Float(y))
            case .native(.boxed(let b)):
                if let p = b.get(SIMD2<Float>.self) { return p }
                return .zero
            default: return .zero
            }
        }
        let raw = (c["points"] ?? c["bezierPoints"])?.asArray ?? []
        var points = raw.map(pair)
        let colors = (c["colors"]?.asArray ?? []).compactMap { c.r.color($0) }
        // A mesh needs one point and color per vertex; fill in an even grid.
        if points.count != w * h {
            points = (0..<h).flatMap { y in (0..<w).map { x in SIMD2(Float(x) / Float(max(1, w - 1)), Float(y) / Float(max(1, h - 1))) } }
        }
        let filled = colors.count == w * h ? colors : (0..<(w * h)).map { colors.isEmpty ? Color.clear : colors[$0 % colors.count] }
        return AnyView(MeshGradient(width: w, height: h, points: points, colors: filled, background: c.color("background") ?? .clear,
                                    smoothsColors: c.bool("smoothsColors", default: true)))
    }

    // MARK: Shape styles

    static func shapeStyles(_ r: KRegistry) {
        r.extend("ShapeStyle") { t in
            for name in ["quinary", "link", "placeholder", "selection", "windowBackground", "fill"] {
                t.staticProperty(name) { _ in .native(.implicit(name, [])) }
            }
            for name in ["linearGradient", "radialGradient", "angularGradient", "conicGradient", "ellipticalGradient", "image", "shadow",
                         "opacity", "blendMode"] {
                t.staticMethod(name) { c in .native(.implicit(name, c.args)) }
            }
        }
        for (name, style) in [("AnyShapeStyle", ""), ("BackgroundStyle", "background"), ("FillShapeStyle", "fill"), ("ForegroundStyle", "foreground"),
                              ("LinkShapeStyle", "link"), ("PlaceholderTextShapeStyle", "placeholder"), ("SelectionShapeStyle", "selection"),
                              ("SeparatorShapeStyle", "separator"), ("TintShapeStyle", "tint"), ("WindowBackgroundShapeStyle", "windowBackground")] {
            r.type(name, .drawing, support: .full) { t in
                if style.isEmpty {
                    t.initializer("_:any") { c in c[0] ?? .nilValue }
                } else {
                    t.initializer("") { _ in .native(.implicit(style, [])) }
                }
            }
        }
        r.type("HierarchicalShapeStyle", .drawing, support: .full) { t in
            for name in ["primary", "secondary", "tertiary", "quaternary", "quinary"] { t.staticProperty(name) { _ in .native(.implicit(name, [])) } }
        }
        r.type("Material", .drawing, support: .full) { t in
            for (name, style) in [("ultraThin", "ultraThinMaterial"), ("thin", "thinMaterial"), ("regular", "regularMaterial"),
                                  ("thick", "thickMaterial"), ("ultraThick", "ultraThickMaterial"), ("bar", "bar")] {
                t.staticProperty(name) { _ in .native(.implicit(style, [])) }
            }
            t.implicit { name, _, _ in
                let map = ["ultraThin": "ultraThinMaterial", "thin": "thinMaterial", "regular": "regularMaterial", "thick": "thickMaterial",
                           "ultraThick": "ultraThickMaterial", "bar": "bar"]
                return map[name].map { .native(.implicit($0, [])) }
            }
        }
        r.type("ImagePaint", .drawing, support: .full) { t in
            t.initializer("image:any sourceRect:CGRect? scale:number?") { c in .native(.implicit("image", [c["image"] ?? .nilValue, c["sourceRect"] ?? .nilValue, c["scale"] ?? .double(1)])) }
        }
        r.type("AnyGradient", .drawing, support: .full) { t in
            t.initializer("_:any") { c in c[0] ?? .nilValue }
        }
    }

    // MARK: Transitions

    static func transitionTypes(_ r: KRegistry) {
        r.extend("Transition") { t in
            t.staticProperty("blurReplace") { _ in .native(.implicit("blurReplace", [])) }
            t.staticMethod("blurReplace", "_:any?") { c in .native(.implicit("blurReplace", c.args)) }
            t.staticProperty("symbolEffect") { _ in .native(.implicit("symbolEffect", [])) }
            t.staticMethod("symbolEffect", "_:any options:any?") { c in .native(.implicit("symbolEffect", c.args)) }
            t.staticMethod("offset", "_:CGSize") { c in .native(.implicit("offset", c.args)) }
            t.staticMethod("offset", "x:number? y:number?") { c in
                .native(.implicit("offset", [.native(.size(c.double("x") ?? 0, c.double("y") ?? 0))]))
            }
            t.property("properties") { _ in .tuple([.bool(true)], ["hasMotion"]) }
        }
        r.extend("AnyTransition") { t in
            t.staticMethod("offset", "_:CGSize") { c in .native(.transition("offset", c.args)) }
            t.staticMethod("offset", "x:number? y:number?") { c in
                .native(.transition("offset", [.native(.size(c.double("x") ?? 0, c.double("y") ?? 0))]))
            }
        }
        let types: [(String, String, [String])] = [
            ("OpacityTransition", "opacity", [""]), ("IdentityTransition", "identity", [""]), ("SlideTransition", "slide", [""]),
            ("ScaleTransition", "scale", ["_:number anchor:UnitPoint?"]), ("MoveTransition", "move", ["edge:Edge"]),
            ("PushTransition", "push", ["edge:Edge"]), ("OffsetTransition", "offset", ["_:CGSize"]),
            ("BlurReplaceTransition", "blurReplace", ["configuration:any"]), ("AsymmetricTransition", "asymmetric", ["insertion:any removal:any"]),
            ("SymbolEffectTransition", "symbolEffect", ["effect:any options:any?"]),
        ]
        for (name, member, sigs) in types {
            r.type(name, .drawing, support: .full) { t in
                for sig in sigs {
                    t.initializer(sig) { c in
                        if member == "asymmetric" { return .native(.transition("asymmetric", [c["insertion"] ?? .nilValue, c["removal"] ?? .nilValue])) }
                        return .native(.implicit(member, c.args))
                    }
                }
            }
        }
    }

    @MainActor static func blurReplace(_ args: [KV]) -> AnyTransition {
        if case .native(.implicit("upUp", _))? = args.first { return AnyTransition(BlurReplaceTransition(configuration: .upUp)) }
        return AnyTransition(BlurReplaceTransition(configuration: .downUp))
    }
}

extension KRenderer {
    /// A shape chain's path in `rect`.
    func shapePath(_ chain: ShapeChain, in rect: CGRect) -> Path {
        if case .user(let app) = chain.kind { return KAnimatable.path(app, KAnimatable.data(app), rect) }
        return chain.applied(chain.kind.anyShape).path(in: rect)
    }

    /// A shape operation that keeps a shape a shape (`inset`, `rotation`,
    /// `union`…), as a function on the shape so far; nil for any other modifier.
    func shapeOperation(_ m: KModifier) -> ((AnyShape) -> AnyShape)? {
        let a = KArgs(args: m.args, labels: m.labels)
        let anchor = unitPoint(a["anchor"]) ?? .center
        switch m.name {
        case "rotation":
            let angle = self.angle(a.first)
            return { AnyShape($0.rotation(angle, anchor: anchor)) }
        case "scale":
            if let s = a.unlabeled(0)?.cg { return { AnyShape($0.scale(s, anchor: anchor)) } }
            let x = a["x"]?.cg ?? 1, y = a["y"]?.cg ?? 1
            return { AnyShape($0.scale(x: x, y: y, anchor: anchor)) }
        case "transform":
            let t = KAffines.affine(a.first)
            return { AnyShape($0.transform(t)) }
        case "union", "intersection", "subtracting", "symmetricDifference", "lineIntersection", "lineSubtraction":
            guard let other = DrawingBridges.shapeArg(a.first, self) else { return nil }
            let eo = a["eoFill"].map { interp.truthy($0) } ?? false
            switch m.name {
            case "union": return { AnyShape($0.union(other, eoFill: eo)) }
            case "intersection": return { AnyShape($0.intersection(other, eoFill: eo)) }
            case "subtracting": return { AnyShape($0.subtracting(other, eoFill: eo)) }
            case "symmetricDifference": return { AnyShape($0.symmetricDifference(other, eoFill: eo)) }
            case "lineIntersection": return { AnyShape($0.lineIntersection(other, eoFill: eo)) }
            default: return { AnyShape($0.lineSubtraction(other, eoFill: eo)) }
            }
        default:
            return nil
        }
    }
}

// MARK: - More shape styles

extension KRenderer {
    /// The shape styles §1.4's renderer doesn't name: `.quinary`, `.link`,
    /// gradients written as style members, a style's `.opacity`, `.shadow`
    /// and `.blendMode`.
    func moreShapeStyle(_ name: String, _ args: [KV]) -> AnyShapeStyle? {
        let parts = name.split(separator: ".").map(String.init)
        if parts.count > 1, let last = parts.last, ["opacity", "shadow", "blendMode"].contains(last) {
            let baseName = parts.dropLast().joined(separator: ".")
            guard let base = shapeStyle(.native(.implicit(baseName, last == "opacity" ? [] : []))) ?? color(.native(.implicit(baseName, []))).map({ AnyShapeStyle($0) }) else { return nil }
            switch last {
            case "opacity": return AnyShapeStyle(base.opacity(args.first?.asDouble ?? 1))
            case "shadow": return AnyShapeStyle(base.shadow(shadowStyle(args.first)))
            default: return AnyShapeStyle(base.blendMode(blendModeValue(args.first)))
            }
        }
        switch name {
        case "quinary": return AnyShapeStyle(.quinary)
        case "link": return AnyShapeStyle(.link)
        case "placeholder": return AnyShapeStyle(.placeholder)
        case "selection": return AnyShapeStyle(.selection)
        case "windowBackground": return AnyShapeStyle(.windowBackground)
        case "fill": return AnyShapeStyle(.fill)
        case "linearGradient":
            return AnyShapeStyle(LinearGradient(gradient: KCanvas.gradient(args.first, self), startPoint: unitPoint(args.count > 1 ? args[1] : nil) ?? .top,
                                                endPoint: unitPoint(args.count > 2 ? args[2] : nil) ?? .bottom))
        case "radialGradient":
            return AnyShapeStyle(RadialGradient(gradient: KCanvas.gradient(args.first, self), center: unitPoint(args.count > 1 ? args[1] : nil) ?? .center,
                                                startRadius: args.count > 2 ? args[2].cg ?? 0 : 0, endRadius: args.count > 3 ? args[3].cg ?? 100 : 100))
        case "angularGradient", "conicGradient":
            return AnyShapeStyle(AngularGradient(gradient: KCanvas.gradient(args.first, self), center: unitPoint(args.count > 1 ? args[1] : nil) ?? .center))
        case "ellipticalGradient":
            return AnyShapeStyle(EllipticalGradient(gradient: KCanvas.gradient(args.first, self), center: unitPoint(args.count > 1 ? args[1] : nil) ?? .center))
        case "image":
            if case .view(let v)? = args.first, let image = KCanvas.image(v, self) {
                return AnyShapeStyle(ImagePaint(image: image, scale: args.last?.cg ?? 1))
            }
            return nil
        default:
            return nil
        }
    }

    func shadowStyle(_ v: KV?) -> ShadowStyle {
        guard case .native(.implicit(let kind, let args))? = v else { return .drop(radius: 4) }
        let a = KArgs(args: args, labels: args.map { _ in nil })
        let col = color(a.first(where: { if case .native(.color) = $0 { return true }; return false })) ?? Color(.sRGBLinear, white: 0, opacity: 0.33)
        let radius = args.first(where: { $0.asDouble != nil })?.cg ?? 4
        return kind == "inner" ? .inner(color: col, radius: radius) : .drop(color: col, radius: radius)
    }

    func blendModeValue(_ v: KV?) -> BlendMode {
        let map: [String: BlendMode] = ["multiply": .multiply, "screen": .screen, "overlay": .overlay, "darken": .darken, "lighten": .lighten,
                                        "colorDodge": .colorDodge, "colorBurn": .colorBurn, "softLight": .softLight, "hardLight": .hardLight,
                                        "difference": .difference, "exclusion": .exclusion, "plusLighter": .plusLighter, "plusDarker": .plusDarker]
        if case .native(.implicit(let n, _))? = v { return map[n] ?? .normal }
        return .normal
    }
}

extension KArgs {
    func first(where p: (KV) -> Bool) -> KV? { args.first(where: p) }
}
