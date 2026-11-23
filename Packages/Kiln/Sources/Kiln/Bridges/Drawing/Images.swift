//
//  Images.swift
//  Bridges: Image, AsyncImage and the image modifiers
//
//  An image's own modifiers (`resizable`, `renderingMode`) have to reach the
//  `Image` itself, so the first one rebuilds the image with all of them and
//  applies the rest of the chain after.
//

import SwiftUI

extension DrawingBridges {
    static func images(_ r: KRegistry) {
        r.view("Image", .drawing, support: .partial, notes: "SF Symbols (`systemName:`), the host's images by name; other assets show a placeholder.") { v in
            v.forms(["_:any", "_:any bundle:any?", "systemName:string", "systemName:string variableValue:number?",
                     "decorative:string bundle:any?", "uiImage:any"]) { c in image(c) }
            // `Image(uiImage:)` made natively arrives as an image already.
            v.make { c in
                if c.args.count == 1, (c.labels.first ?? nil) == nil, case .view = c.args[0] { return c.args[0] }
                return .view(KView(.primitive("Image", c.args, c.labels, line: c.line), bound: c.overload.map { KBound(overload: $0, binding: c.binding) }))
            }
        }
        r.view("AsyncImage", .drawing, support: .partial) { v in
            v.forms(["url:any scale:number?", "url:any scale:number? content:content placeholder:content",
                     "url:any scale:number? transaction:any? content:content"]) { c in asyncImage(c) }
        }
        r.type("AsyncImagePhase", .drawing) { t in t.internal() }

        for name in ["resizable", "renderingMode", "interpolation", "antialiased"] {
            let sig: [String: String] = ["resizable": "capInsets:any? resizingMode:any?", "renderingMode": "_:Image.TemplateRenderingMode?",
                                         "interpolation": "_:Image.Interpolation", "antialiased": "_:bool"]
            r.modifier(name, .drawing, support: name == "resizable" || name == "renderingMode" ? .full : .stub) { m in
                m.formOnBase(sig[name]!, receiver: "Image") { c in imageChain(c) ?? c.view }
            }
        }
        r.modifier("symbolRenderingMode", .drawing) { m in
            m.form("_:SymbolRenderingMode?") { c, view in
                switch c.symbol(0) {
                case "multicolor": view.symbolRenderingMode(.multicolor)
                case "hierarchical": view.symbolRenderingMode(.hierarchical)
                case "palette": view.symbolRenderingMode(.palette)
                case nil: view
                default: view.symbolRenderingMode(.monochrome)
                }
            }
        }
        r.modifier("imageScale", .drawing) { m in
            m.form("_:Image.Scale") { c, view in
                if let n = c.symbol(0) { view.imageScale(n == "large" ? .large : (n == "small" ? .small : .medium)) } else { view }
            }
        }
        r.modifier("symbolEffect", .drawing, support: .stub, notes: "Accepted; the symbol doesn't animate yet.") { m in
            m.stub(["_:any options:any? value:any?", "_:any options:any? isActive:bool?"])
        }
    }

    @MainActor static func image(_ c: KCall) -> AnyView {
        let a = c.a
        if let s = a["systemName"].flatMap({ c.r.string($0) }) { return AnyView(Image(systemName: s)) }
        if let n = a.first?.asString {
            if let host = Kiln.hostImageProvider?(n) { return AnyView(host) }
            #if canImport(UIKit)
            if UIImage(named: n) == nil { return AnyView(Image(systemName: "photo").foregroundStyle(.secondary)) }
            #endif
            return AnyView(Image(n))
        }
        return AnyView(Image(systemName: "photo"))
    }

    /// The image rebuilt with its own modifiers, then the rest of its chain.
    @MainActor static func imageChain(_ c: KCall) -> AnyView? {
        guard let base = c.base else { return nil }
        let current = KModifier(name: c.memberName, args: c.args, labels: c.labels, line: c.line)
        var chain: [KModifier] = []
        var node = base
        while case .modified(let inner, let mm) = node.kind { chain.insert(mm, at: 0); node = inner }
        guard case .primitive(let name, let args, let labels, _) = node.kind, name == "Image" else {
            if case .image(var img) = node.kind {
                if current.name == "resizable" { img = img.resizable() }
                return AnyView(img)
            }
            return nil
        }
        let a = KArgs(args: args, labels: labels)
        var image: Image
        if let s = a["systemName"].flatMap({ c.r.string($0) }) { image = Image(systemName: s) }
        else if let n = a.first?.asString { image = Kiln.hostImageProvider?(n) ?? Image(n) }
        else { image = Image(systemName: "photo") }
        var applied = chain + [current]
        if let i = applied.firstIndex(where: { $0.name == "resizable" }) { image = image.resizable(); applied.remove(at: i) }
        if let rm = applied.first(where: { $0.name == "renderingMode" }), case .native(.implicit(let n, _))? = rm.first {
            image = image.renderingMode(n == "template" ? .template : .original)
        }
        var out = AnyView(image)
        let own: Set<String> = ["renderingMode", "resizable", "interpolation", "antialiased"]
        for mm in applied where !own.contains(mm.name) { out = c.r.applyModifier(mm, to: out, base: .empty) }
        return out
    }

    @MainActor static func asyncImage(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        var url: URL? = nil
        if case .native(.url(let u))? = a["url"] ?? a.first { url = u }
        if let s = (a["url"] ?? a.first)?.asString { url = URL(string: s) }
        let contentFn = a["content"] ?? a.unlabeledFunction(0)
        let placeholderFn = a["placeholder"]
        guard let contentFn else { return AnyView(AsyncImage(url: url)) }
        if placeholderFn != nil {
            return AnyView(AsyncImage(url: url) { image in
                r.renderContent(contentFn, [.view(.image(image))])
            } placeholder: {
                r.renderContent(placeholderFn)
            })
        }
        return AnyView(AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): r.renderContent(contentFn, [.native(.asyncPhase("success", KRef(image)))])
            case .failure: r.renderContent(contentFn, [.native(.asyncPhase("failure", KRef(nil)))])
            default: r.renderContent(contentFn, [.native(.asyncPhase("empty", KRef(nil)))])
            }
        })
    }
}
