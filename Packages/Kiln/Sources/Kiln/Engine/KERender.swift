//
//  KERender.swift
//  Kiln's engine
//
//  Turns view descriptions into real SwiftUI: each primitive by its view
//  bridge, each modifier by its modifier bridge (Registry/, Bridges/). What's
//  here is what every bridge shares: rendering content closures, and reading
//  colors, fonts, alignments, bindings and text from values.
//

import SwiftUI

// MARK: - Renderer

@MainActor
struct KRenderer {
    let interp: KInterpreter

    func render(_ v: KView) -> AnyView {
        switch v.kind {
        case .empty: return AnyView(EmptyView())
        case .error(let m): return AnyView(KErrorView(message: m))
        case .group(let vs): return renderList(vs)
        case .conditional(let b, let vs):
            return b ? AnyView(renderList(vs)) : AnyView(renderList(vs).id("else"))
        case .switchBranch(let i, let vs): return AnyView(renderList(vs).id(i))
        case .image(let img): return AnyView(img)
        case .textConcat: return AnyView(text(v) ?? Text(""))
        case .custom(let s):
            // An `Animatable` view interpolates; a representable shows its UIKit controller or view (§1.5).
            if s.type.isProxied, let proxy = interp.viewProxy(s) { return proxy }
            return AnyView(KHostView(value: s, interp: interp))
        case .primitive(let name, let args, let labels, let line):
            guard let b = interp.registry.view(name) else { return AnyView(KErrorView(message: "\(name) isn't supported in Kiln")) }
            return renderBridge(b, KArgs(args: args, labels: labels), line, v.bound)
        case .modified(let base, let m):
            return modified(base, m)
        }
    }

    func renderList(_ vs: [KView]) -> AnyView {
        if vs.isEmpty { return AnyView(EmptyView()) }
        if vs.count == 1 { return render(vs[0]) }
        return AnyView(ForEach(Array(vs.enumerated()), id: \.offset) { _, child in render(child) })
    }

    func content(_ f: KV?, _ args: [KV] = []) -> [KView] {
        guard case .function(let fn)? = f else {
            if let f { return KBuiltins.asViews(f, interp) }
            return []
        }
        do { return try interp.entry { try interp.callBuilder(fn, args) } }
        catch {
            interp.report(error)
            return [.error(interp.describeError(error))]
        }
    }

    func renderContent(_ f: KV?, _ args: [KV] = []) -> AnyView { renderList(content(f, args)) }

    func action(_ f: KV?) -> () -> Void {
        guard case .function(let fn)? = f else { return {} }
        return { [interp] in interp.perform(fn) }
    }

    // MARK: Values

    func string(_ v: KV?) -> String? {
        guard let v else { return nil }
        if case .view(let view) = v, let t = text(view) { _ = t; return plainText(view) }
        if case .nilValue = v { return nil }
        return interp.describe(v)
    }

    func plainText(_ v: KView) -> String? {
        if case .primitive("Text", let args, _, _) = v.kind, let first = args.first { return interp.describe(first) }
        if case .modified(let base, _) = v.kind { return plainText(base) }
        return nil
    }

    func double(_ v: KV?) -> Double? { v?.asDouble }

    func color(_ v: KV?) -> Color? {
        switch v {
        case .native(.color(let c))?: return c
        case .native(.implicit(let n, let a))?:
            if let c = KDrawing.colorNames[n] ?? KDrawing.systemColors[n] { return c }
            if n.hasSuffix(".opacity"), let base = KDrawing.colorNames[String(n.dropLast(8))] { return base.opacity(a.first?.asDouble ?? 1) }
            return nil
        case .enumV(let e)?: return KDrawing.colorNames[e.caseName]
        case .string(let s)?: return KDrawing.colorNames[s.lowercased()] ?? KDrawing.hexColor(s)
        case .view(let view)?:
            if case .primitive("Color", let args, _, _) = view.kind { return color(args.first) }
            // `.white.opacity(0.6)`: Color is also a View, so the opacity arrives as a modifier.
            if case .modified(let base, let m) = view.kind, m.name == "opacity", let c = color(.view(base)) {
                return c.opacity(m.first?.asDouble ?? 1)
            }
            return nil
        default: return nil
        }
    }

    func shapeStyle(_ v: KV?) -> AnyShapeStyle? {
        if let c = color(v) { return AnyShapeStyle(c) }
        switch v {
        case .native(.implicit(let n, _))?:
            switch n {
            case "secondary": return AnyShapeStyle(.secondary)
            case "tertiary": return AnyShapeStyle(.tertiary)
            case "quaternary": return AnyShapeStyle(.quaternary)
            case "primary": return AnyShapeStyle(.primary)
            case "tint": return AnyShapeStyle(.tint)
            case "ultraThinMaterial": return AnyShapeStyle(.ultraThinMaterial)
            case "thinMaterial": return AnyShapeStyle(.thinMaterial)
            case "regularMaterial", "material": return AnyShapeStyle(.regularMaterial)
            case "thickMaterial": return AnyShapeStyle(.thickMaterial)
            case "ultraThickMaterial": return AnyShapeStyle(.ultraThickMaterial)
            case "bar": return AnyShapeStyle(.bar)
            case "background": return AnyShapeStyle(.background)
            case "foreground": return AnyShapeStyle(.foreground)
            case "separator": return AnyShapeStyle(.separator)
            default:
                if n.hasSuffix(".gradient"), let c = KDrawing.colorNames[String(n.dropLast(9))] { return AnyShapeStyle(c.gradient) }
                return nil
            }
        case .view(let view)?:
            return gradient(view).map { AnyShapeStyle($0) }
        default: return nil
        }
    }

    func gradient(_ v: KView) -> AnyShapeStyle? {
        guard case .primitive(let name, let args, let labels, _) = v.kind else { return nil }
        let a = KArgs(args: args, labels: labels)
        let colors = (a["colors"]?.asArray ?? gradientColors(a["gradient"]) ?? []).compactMap { color($0) }
        let stops = colors.isEmpty ? [Color.blue, .purple] : colors
        switch name {
        case "LinearGradient":
            return AnyShapeStyle(LinearGradient(colors: stops, startPoint: unitPoint(a["startPoint"]) ?? .top, endPoint: unitPoint(a["endPoint"]) ?? .bottom))
        case "RadialGradient":
            return AnyShapeStyle(RadialGradient(colors: stops, center: unitPoint(a["center"]) ?? .center,
                                                startRadius: a["startRadius"]?.asDouble ?? 0, endRadius: a["endRadius"]?.asDouble ?? 200))
        case "AngularGradient":
            return AnyShapeStyle(AngularGradient(colors: stops, center: unitPoint(a["center"]) ?? .center))
        case "EllipticalGradient":
            return AnyShapeStyle(EllipticalGradient(colors: stops))
        default: return nil
        }
    }

    func gradientColors(_ v: KV?) -> [KV]? {
        if case .native(.implicit(_, let args))? = v { return args.first?.asArray }
        return nil
    }

    func unitPoint(_ v: KV?) -> SwiftUI.UnitPoint? {
        guard case .native(.implicit(let n, _))? = v else { return nil }
        let map: [String: SwiftUI.UnitPoint] = ["top": .top, "bottom": .bottom, "leading": .leading, "trailing": .trailing, "center": .center,
            "topLeading": .topLeading, "topTrailing": .topTrailing, "bottomLeading": .bottomLeading, "bottomTrailing": .bottomTrailing]
        return map[n]
    }

    func font(_ v: KV?) -> Font? {
        switch v {
        case .native(.font(let f))?: return f
        case .native(.implicit(let n, let a))?:
            if let f = KTextBridges.fontStyles[n] { return f }
            let parts = n.split(separator: ".").map(String.init)
            if let base = parts.first.flatMap({ KTextBridges.fontStyles[$0] }) {
                var f = base
                for p in parts.dropFirst() {
                    switch p {
                    case "bold": f = f.bold()
                    case "italic": f = f.italic()
                    case "monospacedDigit": f = f.monospacedDigit()
                    case "monospaced": f = f.monospaced()
                    case "weight":
                        if case .native(.implicit(let w, _))? = a.first { f = f.weight(KTextBridges.weight(w)) }
                    default: break
                    }
                }
                return f
            }
            return KTextBridges.font(n, a, [])
        default: return nil
        }
    }

    func horizontalAlignment(_ v: KV?) -> HorizontalAlignment {
        guard case .native(.implicit(let n, _))? = v else { return .center }
        switch n {
        case "leading": return .leading
        case "trailing": return .trailing
        case "listRowSeparatorLeading": return .listRowSeparatorLeading
        default: return .center
        }
    }

    func verticalAlignment(_ v: KV?) -> VerticalAlignment {
        guard case .native(.implicit(let n, _))? = v else { return .center }
        switch n {
        case "top": return .top
        case "bottom": return .bottom
        case "firstTextBaseline": return .firstTextBaseline
        case "lastTextBaseline": return .lastTextBaseline
        default: return .center
        }
    }

    func alignment(_ v: KV?) -> SwiftUI.Alignment {
        guard case .native(.implicit(let n, _))? = v else { return .center }
        let map: [String: SwiftUI.Alignment] = ["top": .top, "bottom": .bottom, "leading": .leading, "trailing": .trailing,
            "center": .center, "topLeading": .topLeading, "topTrailing": .topTrailing, "bottomLeading": .bottomLeading,
            "bottomTrailing": .bottomTrailing]
        return map[n] ?? .center
    }

    func edges(_ v: KV?) -> Edge.Set {
        switch v {
        case .native(.implicit(let n, _))?:
            let map: [String: Edge.Set] = ["all": .all, "horizontal": .horizontal, "vertical": .vertical, "top": .top,
                                           "bottom": .bottom, "leading": .leading, "trailing": .trailing]
            return map[n] ?? .all
        case .array(let items)?:
            return items.reduce(into: Edge.Set()) { $0.formUnion(edges($1)) }
        default: return .all
        }
    }

    func angle(_ v: KV?) -> Angle {
        switch v {
        case .native(.angle(let d))?: return .degrees(d)
        case .native(.implicit("degrees", let a))?: return .degrees(a.first?.asDouble ?? 0)
        case .native(.implicit("radians", let a))?: return .radians(a.first?.asDouble ?? 0)
        default: return .degrees(v?.asDouble ?? 0)
        }
    }

    func animation(_ v: KV?) -> Animation? {
        switch v {
        case .native(.animation(let a))?: return a.value
        case .native(.implicit(let n, let a))?:
            let parts = n.split(separator: ".").map(String.init)
            var anim = KDrawing.animation(parts.first ?? n, a, [])
            for p in parts.dropFirst() where p == "repeatForever" { anim = anim?.repeatForever(autoreverses: true) }
            return anim ?? .default
        case .nilValue?: return nil
        default: return .default
        }
    }

    func binding(_ v: KV?) -> KBinding? {
        if case .binding(let b)? = v { return b }
        return nil
    }

    func stringBinding(_ b: KBinding) -> Binding<String> {
        Binding(get: { b.get().asString ?? (b.get().isNil ? "" : interp.describe(b.get())) }, set: { b.set(.string($0)) })
    }

    func boolBinding(_ b: KBinding) -> Binding<Bool> {
        Binding(get: { interp.truthy(b.get()) }, set: { b.set(.bool($0)) })
    }

    func doubleBinding(_ b: KBinding) -> Binding<Double> {
        let isInt: Bool = { if case .int = b.get() { return true }; return false }()
        return Binding(get: { b.get().asDouble ?? 0 }, set: { b.set(isInt ? .int(Int($0.rounded())) : .double($0)) })
    }

    func range(_ v: KV?) -> ClosedRange<Double>? {
        guard case .range(let lo, let hi, let closed)? = v, let l = lo.asDouble, var h = hi.asDouble else { return nil }
        if !closed, case .int = hi { h -= 1 }
        return l...max(l, h)
    }

    // MARK: Text

    func text(_ v: KView) -> Text? {
        switch v.kind {
        case .primitive("Text", let args, let labels, _):
            return textOf(KArgs(args: args, labels: labels))
        case .textConcat(let a, let b):
            guard let ta = text(a), let tb = text(b) else { return nil }
            return ta + tb
        case .modified(let base, let m):
            guard let t = text(base), let modified = textModifier(t, base, m) else { return nil }
            return modified
        default:
            return nil
        }
    }

    func textOf(_ a: KArgs) -> Text {
        if let lit = a["_literal"]?.asString { return Text(LocalizedStringKey(lit)) }
        if let s = a["verbatim"]?.asString { return Text(verbatim: s) }
        if let t = attributedText(a) { return t }
        guard let first = a.first else { return Text("") }
        if let style = a["format"] { return Text(verbatim: KFormatting.formatted(first, style, interp)) }
        if case .native(.date(let d)) = first, case .native(.implicit(let s, _))? = a["style"] {
            switch s {
            case "time": return Text(d, style: .time)
            case "date": return Text(d, style: .date)
            case "relative": return Text(d, style: .relative)
            case "timer": return Text(d, style: .timer)
            case "offset": return Text(d, style: .offset)
            default: return Text(d, style: .date)
            }
        }
        if case .view(let v) = first, let t = text(v) { return t }
        return Text(verbatim: interp.describe(first))
    }

    func isFunction(_ v: KV) -> Bool { if case .function = v { return true }; return false }

    /// Views whose content closure runs once per element, as `ForEach`'s does
    /// (the probe and the transcript expand their rows).
    static let eachRowNames: Set<String> = ["ForEach", "SliderTickContentForEach", "OutlineGroup"]

    struct Row: Identifiable {
        let id: KV
        let views: [KView]
    }

    /// The rows of a ForEach / List(data): one per element, with SwiftUI ids.
    func forEachRows(_ a: KArgs) -> [Row] {
        // `ForEach(subviews:)` and `ForEach(sections:)` when shown headless: the content's own views.
        if a["subviews"] != nil || a["sections"] != nil {
            let items = a["subviews"] != nil ? KSubviews.headlessCollection(a["subviews"], interp) : KSubviews.headlessSections(a["sections"], interp)
            return (items.asArray ?? []).enumerated().map { i, item in Row(id: .int(i), views: content(a.lastFunction, [item])) }
        }
        guard let data = a.first else { return [] }
        let fn = a.lastFunction
        var elements: [KV] = []
        var bindingSource: KBinding? = nil
        switch data {
        case .binding(let b):
            bindingSource = b
            elements = (try? interp.sequence(b.get())) ?? []
        default:
            elements = (try? interp.sequence(data)) ?? []
        }
        var ids: [KV] = elements.enumerated().map { i, e in rowID(e, a["id"]) ?? .int(i) }
        if Set(ids).count != ids.count { ids = elements.indices.map { .int($0) } }
        var rows: [Row] = []
        for (i, e) in elements.enumerated() {
            var arg = e
            if let src = bindingSource {
                let id = ids[i]
                let keyPath = a["id"]
                let interp = self.interp
                arg = .binding(KBinding(get: {
                    let current = (try? interp.sequence(src.get())) ?? []
                    if let match = current.enumerated().first(where: { (KRenderer(interp: interp).rowID($0.element, keyPath) ?? .int($0.offset)) == id }) {
                        return match.element
                    }
                    return e
                }, set: { newValue in
                    guard case .array(var current) = src.get() else { return }
                    if let idx = current.indices.first(where: { (KRenderer(interp: interp).rowID(current[$0], keyPath) ?? .int($0)) == id }) {
                        current[idx] = newValue
                        src.set(.array(current))
                    }
                }))
            }
            rows.append(Row(id: ids[i], views: content(fn, [arg])))
        }
        return rows
    }

    func rowID(_ e: KV, _ keyPath: KV?) -> KV? {
        if case .native(.keyPath(let comps))? = keyPath {
            var v = e
            for c in comps where c != "self" { v = (try? interp.member(v, c, line: 0)) ?? .nilValue }
            return v
        }
        switch e {
        case .structV, .object, .enumV:
            // ForEach and List need `id:` or Identifiable elements (an enum without payloads is its own id via `id: \.self`).
            if let t = e.userType, !t.conformances.contains("Identifiable") {
                interp.report(interp.fail("ForEach needs `id:` or Identifiable elements: '\(t.name)' isn't Identifiable. Add `: Identifiable` and an `id`, or pass `id: \\.self`"))
            }
            if let id = try? interp.member(e, "id", line: 0) { return id }
            return e
        default:
            return e
        }
    }

    func closureParamCount(_ f: KV) -> Int {
        if case .function(let fn) = f, case .closure(let c, _) = fn.kind { return c.params.count }
        return 0
    }

    func modified(_ base: KView, _ m: KModifier) -> AnyView {
        guard let b = interp.registry.modifier(m.name) else { return render(base) }
        return renderModifier(b, base, m)
    }

    func rootPrimitive(_ v: KView) -> KView.Kind? {
        if case .modified(let b, _) = v.kind { return rootPrimitive(b) }
        if case .textConcat = v.kind { return .primitive("Text", [], [], line: 0) }
        return v.kind
    }
}

/// A NavigationLink(value:) payload.
struct KNavValue: Hashable {
    let value: KV
}

/// ScrollViewProxy held by reference so interpreted code can call scrollTo.
final class KScrollProxy: NSObject {
    let proxy: ScrollViewProxy
    init(_ proxy: ScrollViewProxy) { self.proxy = proxy }
}

/// Positional and labeled arguments of a view constructor.
struct KArgs {
    let args: [KV]
    let labels: [String?]

    subscript(_ label: String) -> KV? {
        if let i = labels.firstIndex(where: { $0 == label }) { return args[i] }
        return nil
    }
    var first: KV? { args.first }
    /// `labels.first == nil` would compare a `String??` and miss `[nil, …]`.
    var firstIsUnlabeled: Bool { (labels.first ?? nil) == nil }
    func unlabeled(_ n: Int) -> KV? {
        let u = zip(labels, args).filter { $0.0 == nil }.map(\.1)
        return n < u.count ? u[n] : nil
    }
    var lastFunction: KV? { args.last(where: { if case .function = $0 { return true }; return false }) }
    var firstFunction: KV? { args.first(where: { if case .function = $0 { return true }; return false }) }
    func unlabeledFunction(_ n: Int) -> KV? {
        let u = zip(labels, args).filter { $0.0 == nil }.map(\.1).filter { if case .function = $0 { return true }; return false }
        return n < u.count ? u[n] : nil
    }
}

extension KV {
    /// A number as CGFloat (SwiftUI's optional CGFloat parameters).
    var cg: CGFloat? { asDouble.map { CGFloat($0) } }
}

