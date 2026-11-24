//
//  ImageRendering.swift
//  Bridges: ImageRenderer and UIGraphicsImageRenderer (Round 2C)
//
//  `ImageRenderer(content:)` renders a view the app built (SwiftUI's own
//  renderer, on the main actor): `uiImage`, `cgImage`, `scale`,
//  `proposedSize`. `UIGraphicsImageRenderer(size:).image { ctx in … }` runs
//  the app's drawing code inside UIKit's image context: `UIColor.setFill()`,
//  `ctx.fill(_:)`, `ctx.cgContext`'s paths and fills, `UIBezierPath`, and
//  drawing images and strings.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// An `ImageRenderer` for a view the app built.
@MainActor
final class KImageRendererBox {
    let renderer: ImageRenderer<AnyView>
    init(_ view: AnyView) { renderer = ImageRenderer(content: view) }
}

extension DrawingBridges {
    /// `"x".draw(at:withAttributes:)`: on Language's `String`, in the second pass.
    static func imageRenderingLater(_ r: KRegistry) {
        #if canImport(UIKit)
        r.extend("String") { t in
            t.method("draw", "at:any withAttributes:any?") { c in
                if let p = KImageDrawing.point(c["at"]) { (c.receiver.asString ?? "").draw(at: p, withAttributes: KStrings.attributes(c["withAttributes"])) }
                return .void
            }
            t.method("draw", "in:any withAttributes:any?") { c in
                if let rect = KImageDrawing.rect(c["in"]) { (c.receiver.asString ?? "").draw(in: rect, withAttributes: KStrings.attributes(c["withAttributes"])) }
                return .void
            }
        }
        #endif
    }

    static func imageRendering(_ r: KRegistry) {
        r.type("ImageRenderer", .drawing, support: .full,
               notes: "`ImageRenderer(content:)` of a view: `uiImage`, `cgImage`, `scale`, `proposedSize`; share or save the image.") { t in
            t.initializer("content:content") { c in
                .native(.object("ImageRenderer", KRef(KImageRendererBox(c.content("content")))))
            }
            @MainActor func box(_ c: KCall) -> KImageRendererBox? { c.object(KImageRendererBox.self) }
            #if canImport(UIKit)
            t.property("uiImage") { c in box(c)?.renderer.uiImage.map { .native(.object("UIImage", KRef($0))) } ?? .nilValue }
            #endif
            t.property("cgImage") { c in box(c)?.renderer.cgImage.map { .native(.object("CGImage", KRef($0))) } ?? .nilValue }
            t.property("scale", { c in .double(Double(box(c)?.renderer.scale ?? 1)) }, set: { c in box(c)?.renderer.scale = c.first?.cg ?? 1 })
            t.property("isOpaque", { c in .bool(box(c)?.renderer.isOpaque ?? false) }, set: { c in box(c)?.renderer.isOpaque = c.first?.asBool ?? false })
            t.property("proposedSize", { _ in .nilValue }, set: { c in
                if case .native(.size(let w, let h))? = c.first { box(c)?.renderer.proposedSize = ProposedViewSize(width: w, height: h) }
            })
        }
        r.type("CGImage", .drawing, support: .full) { t in
            @MainActor func img(_ c: KCall) -> CGImage? { c.object(CGImage.self) }
            t.property("width") { c in .int(img(c)?.width ?? 0) }
            t.property("height") { c in .int(img(c)?.height ?? 0) }
        }

        #if canImport(UIKit)
        r.type("UIGraphicsImageRenderer", .drawing, support: .partial,
               notes: "`image { ctx in … }`, `pngData`, `jpegData`: fill and stroke rects and paths (`ctx.cgContext`, `UIBezierPath`), colors with `setFill()`/`setStroke()`, and draw images and strings.") { t in
            t.initializer("size:any format:any?") { c in
                guard case .native(.size(let w, let h))? = c["size"] else { throw c.fail("needs a CGSize") }
                return .native(.object("UIGraphicsImageRenderer", KRef(UIGraphicsImageRenderer(size: CGSize(width: w, height: h)))))
            }
            t.initializer("bounds:any format:any?") { c in
                guard case .native(.rect(let x, let y, let w, let h))? = c["bounds"] else { throw c.fail("needs a CGRect") }
                return .native(.object("UIGraphicsImageRenderer", KRef(UIGraphicsImageRenderer(bounds: CGRect(x: x, y: y, width: w, height: h)))))
            }
            @MainActor func run(_ c: KCall, _ ref: KArgRef, _ draw: (UIGraphicsImageRenderer, (UIGraphicsImageRendererContext) -> Void) -> KV) throws -> KV {
                guard let renderer = c.object(UIGraphicsImageRenderer.self), case .function(let f)? = c[ref] else { throw c.fail("needs a drawing closure") }
                var failure: Error?
                let out = draw(renderer) { ctx in
                    do { _ = try c.interp.call(f, [.native(.object("UIGraphicsImageRendererContext", KRef(ctx)))], [nil]) } catch { failure = error }
                }
                if let failure { throw failure }
                return out
            }
            t.method("image", "actions:closure") { c in
                try run(c, "actions") { r, draw in .native(.object("UIImage", KRef(r.image(actions: draw)))) }
            }
            t.method("pngData", "actions:closure") { c in try run(c, "actions") { r, draw in KBuiltins.data(r.pngData(actions: draw)) } }
            t.method("jpegData", "withCompressionQuality:number actions:closure") { c in
                let q = c.double("withCompressionQuality") ?? 0.8
                return try run(c, "actions") { r, draw in KBuiltins.data(r.jpegData(withCompressionQuality: q, actions: draw)) }
            }
        }
        r.type("UIGraphicsImageRendererContext", .drawing, support: .partial) { t in
            @MainActor func ctx(_ c: KCall) -> UIGraphicsImageRendererContext? { c.object(UIGraphicsImageRendererContext.self) }
            t.property("cgContext") { c in ctx(c).map { .native(.object("CGContext", KRef($0.cgContext))) } ?? .nilValue }
            t.method("fill", "_:any blendMode:any?") { c in if let rect = KImageDrawing.rect(c[0]) { ctx(c)?.fill(rect) }; return .void }
            t.method("stroke", "_:any blendMode:any?") { c in if let rect = KImageDrawing.rect(c[0]) { ctx(c)?.stroke(rect) }; return .void }
            t.method("clip", "to:any") { c in if let rect = KImageDrawing.rect(c["to"]) { ctx(c)?.clip(to: rect) }; return .void }
        }
        r.type("CGContext", .drawing, support: .partial,
               notes: "In `UIGraphicsImageRenderer`: colors, line width, rects, ellipses, lines and paths, fill and stroke, and transforms.") { t in
            @MainActor func g(_ c: KCall) -> CGContext? { c.object(CGContext.self) }
            t.method("setFillColor", "_:any") { c in if let col = KImageDrawing.color(c[0], c) { g(c)?.setFillColor(col.cgColor) }; return .void }
            t.method("setStrokeColor", "_:any") { c in if let col = KImageDrawing.color(c[0], c) { g(c)?.setStrokeColor(col.cgColor) }; return .void }
            t.method("setLineWidth", "_:number") { c in g(c)?.setLineWidth(c.cg(0) ?? 1); return .void }
            t.method("setAlpha", "_:number") { c in g(c)?.setAlpha(c.cg(0) ?? 1); return .void }
            for name in ["fill", "stroke", "fillEllipse", "strokeEllipse", "addRect", "addEllipse", "clip"] {
                let sig = name.hasSuffix("Ellipse") || name == "addEllipse" ? "in:any" : (name == "clip" ? "to:any" : "_:any")
                t.method(name, sig) { c in
                    guard let gc = g(c), let rect = KImageDrawing.rect(c.args.first) else { return .void }
                    switch name {
                    case "fill": gc.fill(rect)
                    case "stroke": gc.stroke(rect)
                    case "fillEllipse": gc.fillEllipse(in: rect)
                    case "strokeEllipse": gc.strokeEllipse(in: rect)
                    case "addRect": gc.addRect(rect)
                    case "addEllipse": gc.addEllipse(in: rect)
                    default: gc.clip(to: rect)
                    }
                    return .void
                }
            }
            t.method("move", "to:any") { c in if let p = KImageDrawing.point(c["to"]) { g(c)?.move(to: p) }; return .void }
            t.method("addLine", "to:any") { c in if let p = KImageDrawing.point(c["to"]) { g(c)?.addLine(to: p) }; return .void }
            t.method("strokePath", "") { c in g(c)?.strokePath(); return .void }
            t.method("fillPath", "") { c in g(c)?.fillPath(); return .void }
            t.method("beginPath", "") { c in g(c)?.beginPath(); return .void }
            t.method("closePath", "") { c in g(c)?.closePath(); return .void }
            t.method("translateBy", "x:number y:number") { c in g(c)?.translateBy(x: c.cg("x") ?? 0, y: c.cg("y") ?? 0); return .void }
            t.method("scaleBy", "x:number y:number") { c in g(c)?.scaleBy(x: c.cg("x") ?? 1, y: c.cg("y") ?? 1); return .void }
            t.method("rotate", "by:number") { c in g(c)?.rotate(by: c.cg("by") ?? 0); return .void }
            t.method("saveGState", "") { c in g(c)?.saveGState(); return .void }
            t.method("restoreGState", "") { c in g(c)?.restoreGState(); return .void }
        }
        r.type("UIBezierPath", .drawing, support: .partial) { t in
            t.initializer("") { _ in .native(.object("UIBezierPath", KRef(UIBezierPath()))) }
            t.initializer("rect:any") { c in .native(.object("UIBezierPath", KRef(UIBezierPath(rect: KImageDrawing.rect(c["rect"]) ?? .zero)))) }
            t.initializer("ovalIn:any") { c in .native(.object("UIBezierPath", KRef(UIBezierPath(ovalIn: KImageDrawing.rect(c["ovalIn"]) ?? .zero)))) }
            t.initializer("roundedRect:any cornerRadius:number") { c in
                .native(.object("UIBezierPath", KRef(UIBezierPath(roundedRect: KImageDrawing.rect(c["roundedRect"]) ?? .zero, cornerRadius: c.cg("cornerRadius") ?? 0))))
            }
            @MainActor func p(_ c: KCall) -> UIBezierPath? { c.object(UIBezierPath.self) }
            t.method("move", "to:any") { c in if let pt = KImageDrawing.point(c["to"]) { p(c)?.move(to: pt) }; return .void }
            t.method("addLine", "to:any") { c in if let pt = KImageDrawing.point(c["to"]) { p(c)?.addLine(to: pt) }; return .void }
            t.method("close", "") { c in p(c)?.close(); return .void }
            t.method("fill", "") { c in p(c)?.fill(); return .void }
            t.method("stroke", "") { c in p(c)?.stroke(); return .void }
            t.property("lineWidth", { c in .double(Double(p(c)?.lineWidth ?? 1)) }, set: { c in p(c)?.lineWidth = c.first?.cg ?? 1 })
        }
        // Colors set for UIKit drawing: `UIColor.red.setFill()`.
        r.extend("Color") { t in
            for name in ["setFill", "setStroke", "set"] {
                t.method(name, "") { c in
                    guard let col = KImageDrawing.color(c.receiver, c) else { return .void }
                    switch name {
                    case "setFill": col.setFill()
                    case "setStroke": col.setStroke()
                    default: col.set()
                    }
                    return .void
                }
            }
            t.property("cgColor") { c in KImageDrawing.color(c.receiver, c).map { .native(.object("CGColor", KRef($0.cgColor))) } ?? .nilValue }
        }
        r.extend("UIImage") { t in
            t.method("draw", "in:any") { c in if let rect = KImageDrawing.rect(c["in"]) { c.object(UIImage.self)?.draw(in: rect) }; return .void }
            t.method("draw", "at:any") { c in if let p = KImageDrawing.point(c["at"]) { c.object(UIImage.self)?.draw(at: p) }; return .void }
            t.property("scale") { c in .double(Double(c.object(UIImage.self)?.scale ?? 1)) }
        }
        #endif
    }
}

@MainActor
enum KImageDrawing {
    static func rect(_ v: KV?) -> CGRect? {
        if case .native(.rect(let x, let y, let w, let h))? = v { return CGRect(x: x, y: y, width: w, height: h) }
        if case .native(.size(let w, let h))? = v { return CGRect(x: 0, y: 0, width: w, height: h) }
        return nil
    }
    static func point(_ v: KV?) -> CGPoint? {
        if case .native(.point(let x, let y))? = v { return CGPoint(x: x, y: y) }
        return nil
    }
    #if canImport(UIKit)
    static func color(_ v: KV?, _ c: KCall) -> UIColor? {
        guard let v, let color = c.r.color(v) else { return nil }
        return UIColor(color)
    }
    #endif
}
