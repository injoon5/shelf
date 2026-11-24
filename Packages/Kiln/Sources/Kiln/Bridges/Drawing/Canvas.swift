//
//  Canvas.swift
//  Bridges: `Canvas` and `GraphicsContext`
//
//  The app's renderer runs in a view's `body`, on the main thread, with a
//  size from a `GeometryReader`, and records what it draws: each fill,
//  stroke, text, image and symbol with the context's state at that moment
//  (its transform, clips, opacity, blend mode and filters), layers as nested
//  recordings. SwiftUI's own `Canvas` then replays that list into a real
//  `GraphicsContext`, so nothing of the app's runs where SwiftUI draws.
//
//  `GraphicsContext` is a value, as in SwiftUI: `var copy = context` and a
//  transform on the copy leave `context` alone. Its state is a small
//  `Hashable` struct (`KGCState`), and what it refers to (paths, shadings,
//  filters, clips) lives in the recording.
//
//  Inside a `TimelineView(.animation)`, the body runs every frame, so the
//  renderer does too.
//

import SwiftUI

// MARK: - The recording

/// One frame's drawing: the operations, and the values they refer to.
/// Recorded on the main thread; replayed wherever SwiftUI draws.
final class KCanvasRecording: @unchecked Sendable {
    enum Content {
        case fill(Path, GraphicsContext.Shading, FillStyle)
        case stroke(Path, GraphicsContext.Shading, StrokeStyle)
        case text(Text, KCanvasPlace)
        case image(Image, KCanvasPlace, GraphicsContext.Shading?)
        case symbol(KV, KCanvasPlace)
        case layer(KCanvasRecording)
        case clipToLayer(KCanvasRecording, Double, GraphicsContext.ClipOptions)
    }
    struct Op {
        let state: KGCState
        let content: Content
    }
    struct Clip {
        let path: Path
        let transform: CGAffineTransform
        let style: FillStyle
        let options: GraphicsContext.ClipOptions
    }

    var ops: [Op] = []
    var clips: [Clip] = []
    var filters: [GraphicsContext.Filter] = []
    /// The clips and filters a layer's context starts with are its parent's.
    weak var parent: KCanvasRecording?

    init() {}

    /// Draws the recording into a real context.
    func replay(in base: inout GraphicsContext) {
        for op in ops {
            var c = base
            for i in op.state.clips {
                let clip = clips[i]
                c.transform = clip.transform
                c.clip(to: clip.path, style: clip.style, options: clip.options)
            }
            c.transform = op.state.transform.affine
            c.opacity = op.state.opacity
            c.blendMode = KCanvas.blendMode(op.state.blend)
            for f in op.state.filters { c.addFilter(filters[f]) }
            switch op.content {
            case .fill(let path, let shading, let style):
                c.fill(path, with: shading, style: style)
            case .stroke(let path, let shading, let style):
                c.stroke(path, with: shading, style: style)
            case .text(let text, let place):
                switch place {
                case .at(let p, let anchor): c.draw(text, at: p, anchor: anchor)
                case .in(let rect): c.draw(text, in: rect)
                }
            case .image(let image, let place, let shading):
                var resolved = c.resolve(image)
                if let shading { resolved.shading = shading }
                switch place {
                case .at(let p, let anchor): c.draw(resolved, at: p, anchor: anchor)
                case .in(let rect): c.draw(resolved, in: rect)
                }
            case .symbol(let id, let place):
                guard let symbol = c.resolveSymbol(id: id) else { continue }
                switch place {
                case .at(let p, let anchor): c.draw(symbol, at: p, anchor: anchor)
                case .in(let rect): c.draw(symbol, in: rect)
                }
            case .layer(let sub):
                c.drawLayer { layer in sub.replay(in: &layer) }
            case .clipToLayer(let sub, let opacity, let options):
                // A clip for what's drawn after it in this context: kept on base.
                base.clipToLayer(opacity: opacity, options: options) { layer in sub.replay(in: &layer) }
            }
        }
    }
}

enum KCanvasPlace {
    case at(CGPoint, UnitPoint)
    case `in`(CGRect)
}

/// A 2D affine transform, `Hashable` (`CGAffineTransform` isn't everywhere).
struct KAffine: Hashable {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, tx = 0.0, ty = 0.0
    init(_ t: CGAffineTransform) { a = t.a; b = t.b; c = t.c; d = t.d; tx = t.tx; ty = t.ty }
    init() {}
    var affine: CGAffineTransform { CGAffineTransform(a: a, b: b, c: c, d: d, tx: tx, ty: ty) }
}

/// A `GraphicsContext` as the app holds it: a value.
struct KGCState: Hashable {
    let recording: KRef<KCanvasRecording>
    var transform = KAffine()
    var opacity = 1.0
    var blend = "normal"
    var clips: [Int] = []
    var filters: [Int] = []
    /// The size of the canvas, for `clipBoundingRect`.
    var width = 0.0, height = 0.0
}

/// `context.resolve(Text(…))`, `context.resolve(Image(…))`, `resolveSymbol(id:)`.
final class KCanvasResolved: NSObject {
    enum Kind { case text(Text, AnyView), image(Image, AnyView), symbol(KV) }
    let kind: Kind
    var shading: GraphicsContext.Shading?
    init(_ kind: Kind) { self.kind = kind }
}

/// A shading or filter as the app wrote it (`.color(.red)`,
/// `.linearGradient(g, startPoint:endPoint:)`), made real where it's drawn.
struct KSpec: Hashable {
    let name: String
    let args: [KV]
    let labels: [String?]
    var a: KArgs { KArgs(args: args, labels: labels.count == args.count ? labels : args.map { _ in nil }) }
}

@MainActor
enum KCanvas {
    nonisolated static func blendMode(_ name: String) -> GraphicsContext.BlendMode {
        let modes: [String: GraphicsContext.BlendMode] = [
            "normal": .normal, "multiply": .multiply, "screen": .screen, "overlay": .overlay, "darken": .darken, "lighten": .lighten,
            "colorDodge": .colorDodge, "colorBurn": .colorBurn, "softLight": .softLight, "hardLight": .hardLight, "difference": .difference,
            "exclusion": .exclusion, "hue": .hue, "saturation": .saturation, "color": .color, "luminosity": .luminosity, "clear": .clear,
            "copy": .copy, "sourceIn": .sourceIn, "sourceOut": .sourceOut, "sourceAtop": .sourceAtop, "destinationOver": .destinationOver,
            "destinationIn": .destinationIn, "destinationOut": .destinationOut, "destinationAtop": .destinationAtop, "xor": .xor,
            "plusDarker": .plusDarker, "plusLighter": .plusLighter,
        ]
        return modes[name] ?? .normal
    }

    static func state(_ v: KV) -> KGCState? { v.boxed(KGCState.self) }
    static func wrap(_ s: KGCState) -> KV { .native(.boxed(KBoxed("GraphicsContext", s))) }

    /// Runs the app's renderer for a canvas of `size`.
    static func record(_ renderer: KFunction, size: CGSize, _ interp: KInterpreter) -> KCanvasRecording {
        let recording = KCanvasRecording()
        let state = KGCState(recording: KRef(recording), width: size.width, height: size.height)
        var current = wrap(state)
        let context = KBinding.inOut(get: { current }, set: { current = $0 })
        do {
            _ = try interp.entry { try interp.call(renderer, [.binding(context), .native(.size(size.width, size.height))], [nil, nil]) }
        } catch {
            interp.report(error)
        }
        return recording
    }

    /// A drawing method's receiver: the state, and the recording it writes to.
    static func target(_ c: KCall) throws -> (KGCState, KCanvasRecording) {
        guard let s = state(c.receiver) else { throw c.fail("needs a GraphicsContext") }
        return (s, s.recording.value)
    }

    static func path(_ v: KV?, _ c: KCall) throws -> Path {
        switch v {
        case .native(.path(let box))?: return box.value.path
        default: break
        }
        throw c.fail("needs a Path: `Path { … }`, `Path(rect)` or a shape's `path(in:)`")
    }

    static func strokeStyle(_ v: KV?, _ r: KRenderer) -> StrokeStyle {
        guard case .native(.strokeStyle(let k))? = v else { return StrokeStyle(lineWidth: v?.cg ?? 1) }
        return StrokeStyle(lineWidth: k.lineWidth, lineCap: r.lineCap(k.lineCap), lineJoin: r.lineJoin(k.lineJoin), dash: k.dash.map { CGFloat($0) })
    }

    static func point(_ v: KV?) -> CGPoint {
        if case .native(.point(let x, let y))? = v { return CGPoint(x: x, y: y) }
        return .zero
    }

    static func rect(_ v: KV?) -> CGRect? {
        if case .native(.rect(let x, let y, let w, let h))? = v { return CGRect(x: x, y: y, width: w, height: h) }
        return nil
    }

    static func unitPoint(_ v: KV?, _ r: KRenderer) -> UnitPoint {
        r.unitPoint(v) ?? .center
    }

    static func place(_ c: KCall) -> KCanvasPlace {
        if let rect = rect(c["in"]) { return .in(rect) }
        return .at(point(c["at"]), unitPoint(c["anchor"], c.r))
    }

    // MARK: Shading

    static func shading(_ v: KV?, _ r: KRenderer) -> GraphicsContext.Shading {
        switch v {
        case .native(.boxed(let b))?:
            if let s = b.get(KSpec.self) { return shading(s.name, s.args, s.labels, r) }
        case .native(.implicit(let name, let args))?:
            return shading(name, args, [], r)
        default:
            if let col = r.color(v) { return .color(col) }
            if let style = r.shapeStyle(v) { return .style(style) }
        }
        return .foreground
    }

    static func gradient(_ v: KV?, _ r: KRenderer) -> Gradient {
        if let g = v?.boxed(Gradient.self) { return g }
        if case .native(.implicit("gradient", let a))? = v, let colors = a.first?.asArray { return Gradient(colors: colors.compactMap { r.color($0) }) }
        if case .native(.implicit("gradientStops", let a))? = v, let stops = a.first?.asArray { return Gradient(stops: stops.compactMap { r.gradientStop($0) }) }
        if case .native(.color(let c))? = v { return Gradient(colors: [c, c]) }
        if let colors = v?.asArray { return Gradient(colors: colors.compactMap { r.color($0) }) }
        return Gradient(colors: [.primary, .secondary])
    }

    static func shading(_ name: String, _ args: [KV], _ labels: [String?], _ r: KRenderer) -> GraphicsContext.Shading {
        let a = KArgs(args: args, labels: labels.isEmpty ? args.map { _ in nil } : labels)
        switch name {
        case "color":
            if let red = a["red"]?.asDouble {
                return .color(Color(red: red, green: a["green"]?.asDouble ?? 0, blue: a["blue"]?.asDouble ?? 0, opacity: a["opacity"]?.asDouble ?? 1))
            }
            return .color(r.color(a.first) ?? .primary)
        case "style": return .style(r.shapeStyle(a.first) ?? AnyShapeStyle(.foreground))
        case "foreground": return .foreground
        case "linearGradient":
            return .linearGradient(gradient(a.first, r), startPoint: point(a["startPoint"]), endPoint: point(a["endPoint"]))
        case "radialGradient":
            return .radialGradient(gradient(a.first, r), center: point(a["center"]), startRadius: a["startRadius"]?.cg ?? 0,
                                   endRadius: a["endRadius"]?.cg ?? 100)
        case "conicGradient":
            return .conicGradient(gradient(a.first, r), center: point(a["center"]), angle: r.angle(a["angle"]))
        case "palette":
            return .palette((a.first?.asArray ?? []).map { shading($0, r) })
        case "tiledImage":
            if case .view(let v)? = a.first, let image = KCanvas.image(v, r) {
                return .tiledImage(image, origin: point(a["origin"]), sourceRect: rect(a["sourceRect"]) ?? CGRect(x: 0, y: 0, width: 1, height: 1),
                                   scale: a["scale"]?.cg ?? 1)
            }
            return .foreground
        default:
            if let col = KDrawing.colorNames[name] ?? KDrawing.systemColors[name] { return .color(col) }
            return .foreground
        }
    }

    static func image(_ v: KView, _ r: KRenderer) -> Image? {
        if case .image(let img) = v.kind { return img }
        if case .primitive("Image", let args, let labels, _) = v.kind {
            let a = KArgs(args: args, labels: labels)
            if let name = a["systemName"].flatMap({ r.string($0) }) { return Image(systemName: name) }
            if let name = a.first.flatMap({ r.string($0) }) { return Image(name) }
        }
        if case .modified(let base, _) = v.kind { return image(base, r) }
        return nil
    }

    // MARK: Filters

    static func filter(_ name: String, _ a: KArgs, _ r: KRenderer) -> GraphicsContext.Filter? {
        switch name {
        case "blur": return .blur(radius: a["radius"]?.cg ?? a.first?.cg ?? 0)
        case "shadow":
            return .shadow(color: r.color(a["color"]) ?? Color(.sRGBLinear, white: 0, opacity: 0.33), radius: a["radius"]?.cg ?? 0,
                           x: a["x"]?.cg ?? 0, y: a["y"]?.cg ?? 0)
        case "colorMultiply": return .colorMultiply(r.color(a.first) ?? .white)
        case "grayscale": return .grayscale(a.first?.asDouble ?? 1)
        case "saturation": return .saturation(a.first?.asDouble ?? 1)
        case "brightness": return .brightness(a.first?.asDouble ?? 0)
        case "contrast": return .contrast(a.first?.asDouble ?? 1)
        case "hueRotation": return .hueRotation(r.angle(a.first))
        case "colorInvert": return .colorInvert(a.first?.asDouble ?? 1)
        case "luminanceToAlpha": return .luminanceToAlpha
        case "alphaThreshold": return .alphaThreshold(min: a["min"]?.asDouble ?? 0.5, max: a["max"]?.asDouble ?? 1, color: r.color(a["color"]) ?? .black)
        case "projectionTransform": return nil
        default: return nil
        }
    }

    /// The size a resolved text or image takes, measured as SwiftUI lays it out.
    static func measure(_ view: AnyView, in size: CGSize) -> CGSize {
        #if canImport(UIKit)
        let host = UIHostingController(rootView: view)
        return host.sizeThatFits(in: size)
        #elseif canImport(AppKit)
        let host = NSHostingController(rootView: view)
        return host.sizeThatFits(in: size)
        #else
        return .zero
        #endif
    }
}

// MARK: - Bridges

extension DrawingBridges {
    static func canvas(_ r: KRegistry) {
        r.view("Canvas", .drawing, notes: "The renderer runs on the main thread each time the view updates; in a `TimelineView(.animation)` that's every frame. `withCGContext` isn't there.") { v in
            for sig in ["opaque:bool? colorMode:any? rendersAsynchronously:bool? renderer:closure",
                        "opaque:bool? colorMode:any? rendersAsynchronously:bool? renderer:closure symbols:content"] {
                v.form(sig) { c in
                    if case .function(let fn)? = c["renderer"] {
                        KCanvasView(renderer: fn, symbols: c.has("symbols") ? c.views("symbols") : [], opaque: c.bool("opaque", default: false),
                                    interp: c.interp)
                    }
                }
            }
            v.probe { _, a, interp in
                guard case .function(let fn)? = a["renderer"] else { return [] }
                let recording = KCanvasRecording()
                var current = KCanvas.wrap(KGCState(recording: KRef(recording), width: 393, height: 400))
                let ctx = KBinding.inOut(get: { current }, set: { current = $0 })
                var calls = [KProbeCall(fn: fn, args: [.binding(ctx), .native(.size(393, 400))], use: .action)]
                if case .function(let symbols)? = a["symbols"] { calls.append(KProbeCall(fn: symbols)) }
                return calls
            }
        }

        r.type("GraphicsContext", .drawing, support: .full,
               notes: "Fill, stroke, text, images, symbols, transforms, clips, layers and filters; a value, like SwiftUI's.") { t in
            graphicsContext(t)
        }
        // `.color(.red)`, `.blur(radius: 4)`: kept as written, made real where they're drawn.
        for (name, members) in [("GraphicsContext.Shading", ["color", "style", "linearGradient", "radialGradient", "conicGradient", "palette",
                                                             "tiledImage", "foreground"]),
                                ("GraphicsContext.Filter", ["blur", "shadow", "colorMultiply", "grayscale", "saturation", "brightness", "contrast",
                                                            "hueRotation", "colorInvert", "luminanceToAlpha", "alphaThreshold"])] {
            r.type(name, .drawing) { t in
                t.internal()
                for m in members {
                    t.staticMethod(m) { c in .native(.boxed(KBoxed(name, KSpec(name: m, args: c.args, labels: c.labels)))) }
                }
                for m in ["foreground", "luminanceToAlpha"] where members.contains(m) {
                    t.staticProperty(m) { _ in .native(.boxed(KBoxed(name, KSpec(name: m, args: [], labels: [])))) }
                }
                t.implicit { m, args, labels in .native(.boxed(KBoxed(name, KSpec(name: m, args: args, labels: labels)))) }
            }
        }
        r.type("GraphicsContext.ResolvedText", .drawing) { t in
            t.internal()
            t.method("measure", "in:CGSize") { c in
                guard let res = c.object(KCanvasResolved.self), case .text(_, let view) = res.kind else { return .native(.size(0, 0)) }
                var size = CGSize(width: 10_000, height: 10_000)
                if case .native(.size(let w, let h))? = c["in"] { size = CGSize(width: w, height: h) }
                let s = KCanvas.measure(view, in: size)
                return .native(.size(s.width, s.height))
            }
            t.property("shading", { _ in .nilValue }, set: { c in
                c.object(KCanvasResolved.self)?.shading = KCanvas.shading(c[0], c.r)
            })
        }
        r.type("GraphicsContext.ResolvedImage", .drawing) { t in
            t.internal()
            t.property("size") { c in
                guard let res = c.object(KCanvasResolved.self), case .image(_, let view) = res.kind else { return .native(.size(0, 0)) }
                let s = KCanvas.measure(view, in: CGSize(width: 10_000, height: 10_000))
                return .native(.size(s.width, s.height))
            }
            t.property("baseline") { _ in .double(0) }
            t.property("shading", { _ in .nilValue }, set: { c in
                c.object(KCanvasResolved.self)?.shading = KCanvas.shading(c[0], c.r)
            })
        }
        r.type("GraphicsContext.ResolvedSymbol", .drawing) { t in
            t.internal()
            t.property("size") { _ in .native(.size(0, 0)) }
        }
    }

    @MainActor static func graphicsContext(_ t: KTypeBuilder) {
        @MainActor func mutate(_ c: inout KCall, _ change: (inout KGCState) -> Void) throws -> KV {
            guard var s = KCanvas.state(c.receiver) else { throw c.fail("needs a GraphicsContext") }
            change(&s)
            c.mutated = KCanvas.wrap(s)
            return .void
        }
        @MainActor func record(_ c: KCall, _ content: KCanvasRecording.Content) throws -> KV {
            let (s, rec) = try KCanvas.target(c)
            rec.ops.append(.init(state: s, content: content))
            return .void
        }
        @MainActor func fillStyle(_ v: KV?) -> FillStyle {
            if let f = v?.boxed(KFillStyle.self) { return FillStyle(eoFill: f.eoFill, antialiased: f.antialiased) }
            return FillStyle()
        }

        t.method("fill", "_:any with:GraphicsContext.Shading style:FillStyle?") { c in
            try record(c, .fill(try KCanvas.path(c[0], c), KCanvas.shading(c["with"], c.r), fillStyle(c["style"])))
        }
        t.method("stroke", "_:any with:GraphicsContext.Shading lineWidth:number?") { c in
            try record(c, .stroke(try KCanvas.path(c[0], c), KCanvas.shading(c["with"], c.r), StrokeStyle(lineWidth: c.cg("lineWidth") ?? 1)))
        }
        t.method("stroke", "_:any with:GraphicsContext.Shading style:StrokeStyle") { c in
            try record(c, .stroke(try KCanvas.path(c[0], c), KCanvas.shading(c["with"], c.r), KCanvas.strokeStyle(c["style"], c.r)))
        }
        for sig in ["_:any at:CGPoint anchor:UnitPoint?", "_:any in:CGRect"] {
            t.method("draw", sig) { c in
                let place = KCanvas.place(c)
                switch c[0] {
                case .view(let v)?:
                    if let text = c.r.text(v) { return try record(c, .text(text, place)) }
                    if let image = KCanvas.image(v, c.r) { return try record(c, .image(image, place, nil)) }
                    throw c.fail("draws a Text or an Image")
                case .native(.object(_, let ref))?:
                    guard let res = ref.value as? KCanvasResolved else { break }
                    switch res.kind {
                    case .text(let text, _): return try record(c, .text(text, place))
                    case .image(let image, _): return try record(c, .image(image, place, res.shading))
                    case .symbol(let id): return try record(c, .symbol(id, place))
                    }
                default: break
                }
                throw c.fail("draws a Text, an Image, or what `resolve` and `resolveSymbol` return")
            }
        }
        t.method("resolve", "_:any") { c in
            guard case .view(let v)? = c[0] else { throw c.fail("resolves a Text or an Image") }
            if let text = c.r.text(v) {
                return .native(.object("GraphicsContext.ResolvedText", KRef(KCanvasResolved(.text(text, AnyView(text))))))
            }
            if let image = KCanvas.image(v, c.r) {
                return .native(.object("GraphicsContext.ResolvedImage", KRef(KCanvasResolved(.image(image, c.r.render(v))))))
            }
            throw c.fail("resolves a Text or an Image")
        }
        t.method("resolveSymbol", "id:any") { c in
            .native(.object("GraphicsContext.ResolvedSymbol", KRef(KCanvasResolved(.symbol(c["id"] ?? .nilValue)))))
        }
        t.method("translateBy", "x:number y:number") { c in
            let x = c.cg("x") ?? 0, y = c.cg("y") ?? 0
            return try mutate(&c) { $0.transform = KAffine($0.transform.affine.translatedBy(x: x, y: y)) }
        }
        t.method("scaleBy", "x:number y:number") { c in
            let x = c.cg("x") ?? 1, y = c.cg("y") ?? 1
            return try mutate(&c) { $0.transform = KAffine($0.transform.affine.scaledBy(x: x, y: y)) }
        }
        t.method("rotate", "by:Angle") { c in
            let angle = c.angle("by")
            return try mutate(&c) { $0.transform = KAffine($0.transform.affine.rotated(by: angle.radians)) }
        }
        t.method("concatenate", "_:any") { c in
            let m = KAffines.affine(c[0])
            return try mutate(&c) { $0.transform = KAffine(m.concatenating($0.transform.affine)) }
        }
        t.method("clip", "to:any style:FillStyle? options:any?") { c in
            let (s, rec) = try KCanvas.target(c)
            let options: GraphicsContext.ClipOptions = c.symbol("options") == "inverse" ? .inverse : []
            rec.clips.append(.init(path: try KCanvas.path(c["to"], c), transform: s.transform.affine, style: fillStyle(c["style"]), options: options))
            let i = rec.clips.count - 1
            return try mutate(&c) { $0.clips.append(i) }
        }
        t.method("clipToLayer", "opacity:number? options:any? content:closure") { c in
            let (s, rec) = try KCanvas.target(c)
            guard case .function(let fn)? = c["content"] else { return .void }
            let sub = KCanvasRecording()
            sub.clips = rec.clips
            sub.filters = rec.filters
            var inner = KCanvas.wrap(KGCState(recording: KRef(sub), transform: s.transform, clips: s.clips, width: s.width, height: s.height))
            _ = try c.interp.call(fn, [.binding(.inOut(get: { inner }, set: { inner = $0 }))], [nil])
            let options: GraphicsContext.ClipOptions = c.symbol("options") == "inverse" ? .inverse : []
            rec.ops.append(.init(state: s, content: .clipToLayer(sub, c.double("opacity") ?? 1, options)))
            return .void
        }
        t.method("drawLayer", "content:closure") { c in
            let (s, rec) = try KCanvas.target(c)
            guard case .function(let fn)? = c["content"] else { return .void }
            let sub = KCanvasRecording()
            sub.clips = rec.clips
            // The layer's context starts where this one is, except for what
            // applies to the layer as a whole (opacity, blend, filters).
            var inner = KCanvas.wrap(KGCState(recording: KRef(sub), transform: s.transform, clips: s.clips, width: s.width, height: s.height))
            _ = try c.interp.call(fn, [.binding(.inOut(get: { inner }, set: { inner = $0 }))], [nil])
            rec.ops.append(.init(state: s, content: .layer(sub)))
            return .void
        }
        t.method("addFilter", "_:any options:any?") { c in
            let (_, rec) = try KCanvas.target(c)
            var spec = c[0]?.boxed(KSpec.self)
            if spec == nil, case .native(.implicit(let name, let args))? = c[0] { spec = KSpec(name: name, args: args, labels: []) }
            guard let spec, let f = KCanvas.filter(spec.name, spec.a, c.r) else { throw c.fail("needs a GraphicsContext.Filter") }
            rec.filters.append(f)
            let i = rec.filters.count - 1
            return try mutate(&c) { $0.filters.append(i) }
        }
        t.property("opacity", { c in .double(KCanvas.state(c.receiver)?.opacity ?? 1) }, set: { c in
            let v = c.double(0) ?? 1
            _ = try mutate(&c) { $0.opacity = v }
        })
        t.property("blendMode", { c in .native(.implicit(KCanvas.state(c.receiver)?.blend ?? "normal", [])) }, set: { c in
            let v = c.symbol(0) ?? "normal"
            _ = try mutate(&c) { $0.blend = v }
        })
        t.property("transform", { c in KAffines.wrap(KCanvas.state(c.receiver)?.transform.affine ?? .identity) }, set: { c in
            let m = KAffines.affine(c[0])
            _ = try mutate(&c) { $0.transform = KAffine(m) }
        })
        t.property("clipBoundingRect") { c in
            let s = KCanvas.state(c.receiver)
            return .native(.rect(0, 0, s?.width ?? 0, s?.height ?? 0))
        }
    }
}

/// `FillStyle(eoFill:antialiased:)`.
struct KFillStyle: Hashable {
    var eoFill = false
    var antialiased = true
}

/// Shows the app's `Canvas`: its renderer runs here, in `body`.
struct KCanvasView: View {
    let renderer: KFunction
    let symbols: [KView]
    let opaque: Bool
    let interp: KInterpreter

    var body: some View {
        GeometryReader { geo in
            let recording = KCanvas.record(renderer, size: geo.size, interp)
            if symbols.isEmpty {
                Canvas(opaque: opaque) { context, _ in recording.replay(in: &context) }
            } else {
                let r = KRenderer(interp: interp)
                Canvas(opaque: opaque) { context, _ in recording.replay(in: &context) } symbols: {
                    ForEach(Array(symbols.enumerated()), id: \.offset) { _, view in
                        r.render(view.removing("tag")).tag(view.modifier("tag")?.first ?? .nilValue)
                    }
                }
            }
        }
    }
}

// MARK: - CGAffineTransform

@MainActor
enum KAffines {
    static func affine(_ v: KV?) -> CGAffineTransform { v?.boxed(KAffine.self)?.affine ?? .identity }
    static func wrap(_ t: CGAffineTransform) -> KV { .native(.boxed(KBoxed("CGAffineTransform", KAffine(t)))) }

    static func register(_ r: KRegistry) {
        r.type("CGAffineTransform", .drawing) { t in
            t.initializer("translationX:number y:number") { c in wrap(CGAffineTransform(translationX: c.cg("translationX") ?? 0, y: c.cg("y") ?? 0)) }
            t.initializer("scaleX:number y:number") { c in wrap(CGAffineTransform(scaleX: c.cg("scaleX") ?? 1, y: c.cg("y") ?? 1)) }
            t.initializer("rotationAngle:number") { c in wrap(CGAffineTransform(rotationAngle: c.cg("rotationAngle") ?? 0)) }
            t.initializer("a:number b:number c:number d:number tx:number ty:number") { c in
                wrap(CGAffineTransform(a: c.cg("a") ?? 1, b: c.cg("b") ?? 0, c: c.cg("c") ?? 0, d: c.cg("d") ?? 1, tx: c.cg("tx") ?? 0, ty: c.cg("ty") ?? 0))
            }
            t.initializer("") { _ in wrap(.identity) }
            t.staticProperty("identity") { _ in wrap(.identity) }
            t.implicit { name, _, _ in name == "identity" ? wrap(.identity) : nil }
            t.method("translatedBy", "x:number y:number") { c in wrap(affine(c.receiver).translatedBy(x: c.cg("x") ?? 0, y: c.cg("y") ?? 0)) }
            t.method("scaledBy", "x:number y:number") { c in wrap(affine(c.receiver).scaledBy(x: c.cg("x") ?? 1, y: c.cg("y") ?? 1)) }
            t.method("rotated", "by:number") { c in wrap(affine(c.receiver).rotated(by: c.cg("by") ?? 0)) }
            t.method("concatenating", "_:any") { c in wrap(affine(c.receiver).concatenating(affine(c[0]))) }
            t.method("inverted", "") { c in wrap(affine(c.receiver).inverted()) }
            t.property("isIdentity") { c in .bool(affine(c.receiver).isIdentity) }
            for (name, path) in [("a", \CGAffineTransform.a), ("b", \.b), ("c", \.c), ("d", \.d), ("tx", \.tx), ("ty", \.ty)] {
                t.property(name) { c in .double(affine(c.receiver)[keyPath: path]) }
            }
        }
    }
}
