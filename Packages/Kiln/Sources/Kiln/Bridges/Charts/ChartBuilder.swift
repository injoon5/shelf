//
//  ChartBuilder.swift
//  Bridges: Swift Charts, built
//
//  How a chart's description becomes Swift Charts' own content. See
//  Charts.swift for the shape of it.
//

import SwiftUI
import Charts

/// A plottable value as the app wrote it: `.value("Day", day)`.
enum KPlot {
    case text(String, String)
    case whole(String, Int)
    case number(String, Double)
    case date(String, Date)

    var label: String {
        switch self {
        case .text(let l, _), .whole(let l, _), .number(let l, _), .date(let l, _): return l
        }
    }
    var kind: KPlotKind {
        switch self {
        case .text: return .text
        case .whole: return .whole
        case .number: return .number
        case .date: return .date
        }
    }
}

enum KPlotKind { case text, whole, number, date }

/// The Swift type an axis is plotted with.
protocol KPlotType: Plottable {
    static func from(_ p: KPlot) -> Self
    static func kv(_ v: Self) -> KV
}

extension String: KPlotType {
    static func from(_ p: KPlot) -> String {
        switch p {
        case .text(_, let s): return s
        case .whole(_, let i): return String(i)
        case .number(_, let d): return String(d)
        case .date(_, let d): return d.formatted()
        }
    }
    static func kv(_ v: String) -> KV { .string(v) }
}
extension Int: KPlotType {
    static func from(_ p: KPlot) -> Int {
        switch p {
        case .whole(_, let i): return i
        case .number(_, let d): return Int(d)
        default: return 0
        }
    }
    static func kv(_ v: Int) -> KV { .int(v) }
}
extension Double: KPlotType {
    static func from(_ p: KPlot) -> Double {
        switch p {
        case .whole(_, let i): return Double(i)
        case .number(_, let d): return d
        case .date(_, let d): return d.timeIntervalSinceReferenceDate
        default: return 0
        }
    }
    static func kv(_ v: Double) -> KV { .double(v) }
}
extension Date: KPlotType {
    static func from(_ p: KPlot) -> Date {
        if case .date(_, let d) = p { return d }
        return Date()
    }
    static func kv(_ v: Date) -> KV { .native(.date(v)) }
}

final class KAxisValueBox: NSObject {
    let value: AxisValue
    init(_ v: AxisValue) { value = v }
}

final class KChartProxyBox: NSObject {
    let proxy: ChartProxy?
    init(_ p: ChartProxy?) { proxy = p }
}

/// One mark: its kind, its arguments and its modifiers, innermost first.
struct KMarkSpec {
    let name: String
    let a: KArgs
    let modifiers: [KModifier]
}

@MainActor
struct KChartBuilder {
    let interp: KInterpreter
    var r: KRenderer { KRenderer(interp: interp) }

    // MARK: Reading the description

    func plot(_ v: KV?) -> KPlot? {
        guard case .native(.implicit("value", let pa))? = v, pa.count >= 2 else { return nil }
        let label = r.string(pa[0]) ?? ""
        switch pa[1] {
        case .int(let i): return .whole(label, i)
        case .double(let d): return .number(label, d)
        case .native(.date(let d)): return .date(label, d)
        case .binding(let b): return plot(.native(.implicit("value", [pa[0], b.get()])))
        default: return .text(label, r.string(pa[1]) ?? "")
        }
    }

    /// The chart's marks: the content closure's, or one set per element of `data`.
    func specs(_ c: KCall) -> [KMarkSpec] {
        let a = c.a
        var views: [KView] = []
        if let data = a.first, a.firstIsUnlabeled, !r.isFunction(data) {
            for e in (try? interp.sequence(data)) ?? [] { views += r.content(a.lastFunction, [e]) }
        } else {
            views = r.content(a.lastFunction)
        }
        return views.flatMap { specs($0) }
    }

    func specs(_ v: KView, depth: Int = 0) -> [KMarkSpec] {
        guard depth < 16 else { return [] }
        var modifiers: [KModifier] = []
        var node = v
        while case .modified(let inner, let m) = node.kind { modifiers.insert(m, at: 0); node = inner }
        switch node.kind {
        case .group(let vs), .conditional(_, let vs), .switchBranch(_, let vs):
            return vs.flatMap { specs($0, depth: depth + 1) }
        case .primitive("ForEach", let args, let labels, _):
            return r.forEachRows(KArgs(args: args, labels: labels)).flatMap { $0.views.flatMap { specs($0, depth: depth + 1) } }
        case .primitive("Plot", let args, let labels, _), .primitive("AnyChartContent", let args, let labels, _):
            let a = KArgs(args: args, labels: labels)
            if case .view(let inner)? = a.first { return specs(inner, depth: depth + 1).map { KMarkSpec(name: $0.name, a: $0.a, modifiers: $0.modifiers + modifiers) } }
            return r.content(a.lastFunction).flatMap { specs($0, depth: depth + 1) }
        case .primitive(let name, let args, let labels, _) where ChartsBridges.marks.contains(name):
            return [KMarkSpec(name: name, a: KArgs(args: args, labels: labels), modifiers: modifiers)]
        case .primitive(let name, let args, let labels, _) where ChartsBridges.plots.contains(name):
            return plotSpecs(name, KArgs(args: args, labels: labels), modifiers)
        default:
            return []
        }
    }

    /// A vectorized plot as one mark per element; a function plot sampled.
    func plotSpecs(_ name: String, _ a: KArgs, _ modifiers: [KModifier]) -> [KMarkSpec] {
        let markName = name.replacingOccurrences(of: "Plot", with: "Mark")
        if case .function(let fn)? = a["function"] ?? a.lastFunction {
            let (lo, hi) = domain(a["domain"])
            let n = 200
            var out: [KMarkSpec] = []
            for i in 0...n {
                let x = lo + (hi - lo) * Double(i) / Double(n)
                let y = (try? interp.entry { try interp.call(fn, [.double(x)], [nil]) }) ?? .nilValue
                func value(_ label: KV?, _ v: KV) -> KV { .native(.implicit("value", [label ?? .string(""), v])) }
                if a["yStart"] != nil {
                    // `AreaPlot(x:yStart:yEnd:)`: the function gives a pair.
                    let pair = y.asArray ?? { if case .tuple(let t, _) = y { return t }; return [] }()
                    guard pair.count == 2, pair[0].asDouble != nil, pair[1].asDouble != nil else { continue }
                    out.append(KMarkSpec(name: markName, a: KArgs(args: [value(a["x"], .double(x)), value(a["yStart"], pair[0]), value(a["yEnd"], pair[1])],
                                                                  labels: ["x", "yStart", "yEnd"]), modifiers: modifiers))
                } else {
                    guard let d = y.asDouble, d.isFinite else { continue }
                    out.append(KMarkSpec(name: markName, a: KArgs(args: [value(a["x"], .double(x)), value(a["y"], .double(d))], labels: ["x", "y"]),
                                         modifiers: modifiers))
                }
            }
            return out
        }
        // `BarPlot(data, x: .value("Day", \.day))`: each `\.keyPath` read from each element.
        guard let data = a.first else { return [] }
        var out: [KMarkSpec] = []
        for e in (try? interp.sequence(data)) ?? [] {
            var args: [KV] = []
            var labels: [String?] = []
            for (i, l) in a.labels.enumerated() where l != nil {
                args.append(project(a.args[i], e))
                labels.append(l)
            }
            out.append(KMarkSpec(name: markName, a: KArgs(args: args, labels: labels), modifiers: modifiers.map { m in
                var m = m
                m.args = m.args.map { project($0, e) }
                return m
            }))
        }
        return out
    }

    /// `.value("Day", \.day)` for one element: `.value("Day", element.day)`.
    func project(_ v: KV, _ element: KV) -> KV {
        switch v {
        case .native(.implicit("value", let pa)) where pa.count == 2:
            return .native(.implicit("value", [pa[0], project(pa[1], element)]))
        case .native(.keyPath(let comps)):
            var out = element
            for c in comps where c != "self" { out = (try? interp.member(out, c, line: 0)) ?? .nilValue }
            return out
        default:
            return v
        }
    }

    func domain(_ v: KV?) -> (Double, Double) {
        if case .range(let lo, let hi, _)? = v, let l = lo.asDouble, let h = hi.asDouble { return (l, h) }
        return (0, 1)
    }

    /// The kinds of the chart's axes: the first mark that has each.
    func kinds(_ specs: [KMarkSpec]) -> (KPlotKind, KPlotKind) {
        var x: KPlotKind?, y: KPlotKind?
        for s in specs {
            x = x ?? (plot(s.a["x"]) ?? plot(s.a["xStart"]))?.kind
            y = y ?? (plot(s.a["y"]) ?? plot(s.a["yStart"]))?.kind
            if x != nil && y != nil { break }
        }
        return (x ?? .text, y ?? .number)
    }

    // MARK: Building

    func chart(_ c: KCall) -> AnyView {
        let specs = self.specs(c)
        let (xk, yk) = kinds(specs)
        return withKinds(xk, yk, specs)
    }

    func withKinds(_ xk: KPlotKind, _ yk: KPlotKind, _ specs: [KMarkSpec]) -> AnyView {
        switch xk {
        case .text: return withY(String.self, yk, specs)
        case .whole: return withY(Int.self, yk, specs)
        case .number: return withY(Double.self, yk, specs)
        case .date: return withY(Date.self, yk, specs)
        }
    }

    func withY<X: KPlotType>(_ x: X.Type, _ yk: KPlotKind, _ specs: [KMarkSpec]) -> AnyView {
        switch yk {
        case .text: return build(x, String.self, specs)
        case .whole: return build(x, Int.self, specs)
        case .number: return build(x, Double.self, specs)
        case .date: return build(x, Date.self, specs)
        }
    }

    struct Item: Identifiable {
        let id: Int
        let content: AnyChartContent
    }

    func build<X: KPlotType, Y: KPlotType>(_ x: X.Type, _ y: Y.Type, _ specs: [KMarkSpec]) -> AnyView {
        let items = specs.enumerated().map { Item(id: $0.offset, content: mark($0.element, X.self, Y.self)) }
        return AnyView(Chart { ForEach(items) { $0.content } })
    }

    func value<P: KPlotType>(_ v: KV?, _: P.Type) -> PlottableValue<P>? {
        guard let p = plot(v) else { return nil }
        return .value(p.label, P.from(p))
    }

    func dimension(_ v: KV?) -> MarkDimension {
        switch v {
        case .int(let i)?: return .fixed(CGFloat(i))
        case .double(let d)?: return .fixed(d)
        case .native(.implicit("ratio", let a))?: return .ratio(a.first?.cg ?? 1)
        case .native(.implicit("fixed", let a))?: return .fixed(a.first?.cg ?? 1)
        case .native(.implicit("inset", let a))?: return .inset(a.first?.cg ?? 0)
        default: return .automatic
        }
    }

    func stacking(_ v: KV?) -> MarkStackingMethod {
        switch v {
        case .native(.implicit("normalized", _))?: return .normalized
        case .native(.implicit("center", _))?: return .center
        case .native(.implicit("unstacked", _))?: return .unstacked
        default: return .standard
        }
    }

    func mark<X: KPlotType, Y: KPlotType>(_ s: KMarkSpec, _: X.Type, _: Y.Type) -> AnyChartContent {
        let a = s.a
        let x = value(a["x"], X.self), y = value(a["y"], Y.self)
        let xs = value(a["xStart"], X.self), xe = value(a["xEnd"], X.self)
        let ys = value(a["yStart"], Y.self), ye = value(a["yEnd"], Y.self)
        var out: AnyChartContent
        switch s.name {
        case "LineMark":
            if let x, let y {
                if let series = plot(a["series"]) { out = AnyChartContent(erasing: LineMark(x: x, y: y, series: .value(series.label, String.from(series)))) }
                else { out = AnyChartContent(erasing: LineMark(x: x, y: y)) }
            } else { out = AnyChartContent(erasing: LineMark(x: .value("x", 0), y: .value("y", 0))) }
        case "PointMark":
            if let x, let y { out = AnyChartContent(erasing: PointMark(x: x, y: y)) }
            else if let x { out = AnyChartContent(erasing: PointMark(x: x)) }
            else if let y { out = AnyChartContent(erasing: PointMark(y: y)) }
            else { out = AnyChartContent(erasing: PointMark(x: .value("x", 0))) }
        case "AreaMark":
            if let x, let ys, let ye { out = AnyChartContent(erasing: AreaMark(x: x, yStart: ys, yEnd: ye)) }
            else if let xs, let xe, let y { out = AnyChartContent(erasing: AreaMark(xStart: xs, xEnd: xe, y: y)) }
            else if let x, let y {
                if let series = plot(a["series"]) {
                    out = AnyChartContent(erasing: AreaMark(x: x, y: y, series: .value(series.label, String.from(series)), stacking: stacking(a["stacking"])))
                } else {
                    out = AnyChartContent(erasing: AreaMark(x: x, y: y, stacking: stacking(a["stacking"])))
                }
            } else { out = AnyChartContent(erasing: AreaMark(x: .value("x", 0), y: .value("y", 0))) }
        case "RuleMark":
            if let x, let ys, let ye { out = AnyChartContent(erasing: RuleMark(x: x, yStart: ys, yEnd: ye)) }
            else if let xs, let xe, let y { out = AnyChartContent(erasing: RuleMark(xStart: xs, xEnd: xe, y: y)) }
            else if let x { out = AnyChartContent(erasing: RuleMark(x: x)) }
            else if let y { out = AnyChartContent(erasing: RuleMark(y: y)) }
            else { out = AnyChartContent(erasing: RuleMark(y: .value("y", 0))) }
        case "RectangleMark":
            if let xs, let xe, let ys, let ye { out = AnyChartContent(erasing: RectangleMark(xStart: xs, xEnd: xe, yStart: ys, yEnd: ye)) }
            else if let xs, let xe, let y { out = AnyChartContent(erasing: RectangleMark(xStart: xs, xEnd: xe, y: y, height: dimension(a["height"]))) }
            else if let x, let ys, let ye { out = AnyChartContent(erasing: RectangleMark(x: x, yStart: ys, yEnd: ye, width: dimension(a["width"]))) }
            else if let x, let y { out = AnyChartContent(erasing: RectangleMark(x: x, y: y, width: dimension(a["width"]), height: dimension(a["height"]))) }
            else { out = AnyChartContent(erasing: RectangleMark(x: .value("x", 0), y: .value("y", 0))) }
        case "SectorMark":
            let angle = value(a["angle"], Double.self) ?? .value("Value", 0)
            out = AnyChartContent(erasing: SectorMark(angle: angle, innerRadius: dimension(a["innerRadius"]), outerRadius: dimension(a["outerRadius"]),
                                                      angularInset: a["angularInset"]?.cg ?? 0))
        default:
            if let xs, let xe, let ys, let ye { out = AnyChartContent(erasing: RectangleMark(xStart: xs, xEnd: xe, yStart: ys, yEnd: ye)) }
            else if let xs, let xe, let y { out = AnyChartContent(erasing: BarMark(xStart: xs, xEnd: xe, y: y, height: dimension(a["height"]))) }
            else if let x, let ys, let ye { out = AnyChartContent(erasing: BarMark(x: x, yStart: ys, yEnd: ye, width: dimension(a["width"]))) }
            else if let x, let y { out = AnyChartContent(erasing: BarMark(x: x, y: y, width: dimension(a["width"]), height: dimension(a["height"]), stacking: stacking(a["stacking"]))) }
            else if let x { out = AnyChartContent(erasing: BarMark(x: x)) }
            else if let y { out = AnyChartContent(erasing: BarMark(y: y)) }
            else { out = AnyChartContent(erasing: BarMark(x: .value("x", 0))) }
        }
        for m in s.modifiers { out = apply(m, out) }
        return out
    }

    // MARK: Mark modifiers

    func by<C: ChartContent>(_ v: KV?, _ c: C, _ make: (C, KPlot) -> AnyChartContent) -> AnyChartContent? {
        guard let p = plot(v) else { return nil }
        return make(c, p)
    }

    func apply(_ m: KModifier, _ c: AnyChartContent) -> AnyChartContent {
        let a = KArgs(args: m.args, labels: m.labels)
        switch m.name {
        case "foregroundStyle":
            if let p = plot(a["by"]) {
                switch p {
                case .text(let l, let s): return AnyChartContent(erasing: c.foregroundStyle(by: .value(l, s)))
                case .whole(let l, let i): return AnyChartContent(erasing: c.foregroundStyle(by: .value(l, String(i))))
                case .number(let l, let d): return AnyChartContent(erasing: c.foregroundStyle(by: .value(l, d)))
                case .date(let l, let d): return AnyChartContent(erasing: c.foregroundStyle(by: .value(l, d)))
                }
            }
            if let style = r.shapeStyle(a.first) { return AnyChartContent(erasing: c.foregroundStyle(style)) }
            return c
        case "position":
            guard let p = plot(a["by"]) else { return c }
            let axis: Axis? = a["axis"].flatMap { if case .native(.implicit(let n, _)) = $0 { return n == "vertical" ? .vertical : .horizontal }; return nil }
            let span = dimension(a["span"])
            return AnyChartContent(erasing: c.position(by: .value(p.label, String.from(p)), axis: axis, span: span))
        case "symbol":
            if let p = plot(a["by"]) { return AnyChartContent(erasing: c.symbol(by: .value(p.label, String.from(p)))) }
            if case .function = a["symbol"] ?? a.lastFunction ?? .nilValue {
                let view = r.renderContent(a["symbol"] ?? a.lastFunction)
                return AnyChartContent(erasing: c.symbol { view })
            }
            if case .native(.implicit(let n, _))? = a.first { return AnyChartContent(erasing: c.symbol(Self.symbolShape(n))) }
            return c
        case "symbolSize":
            if let p = plot(a["by"]) { return AnyChartContent(erasing: c.symbolSize(by: .value(p.label, Double.from(p)))) }
            if case .native(.size(let w, let h))? = a.first { return AnyChartContent(erasing: c.symbolSize(CGSize(width: w, height: h))) }
            return AnyChartContent(erasing: c.symbolSize(a.first?.cg ?? 30))
        case "lineStyle":
            if let p = plot(a["by"]) { return AnyChartContent(erasing: c.lineStyle(by: .value(p.label, String.from(p)))) }
            return AnyChartContent(erasing: c.lineStyle(KCanvas.strokeStyle(a.first, r)))
        case "interpolationMethod":
            return AnyChartContent(erasing: c.interpolationMethod(Self.interpolation(a.first)))
        case "annotation":
            let view = r.renderContent(a["content"] ?? a.lastFunction)
            return AnyChartContent(erasing: c.annotation(position: Self.annotationPosition(a["position"].flatMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil }),
                                                         alignment: a["alignment"].map { r.alignment($0) } ?? .center, spacing: a["spacing"]?.cg) { view })
        case "cornerRadius":
            return AnyChartContent(erasing: c.cornerRadius(a.first?.cg ?? 0, style: a["style"].map { r.symbolName($0) == "continuous" ? .continuous : .circular } ?? .continuous))
        case "opacity": return AnyChartContent(erasing: c.opacity(a.first?.asDouble ?? 1))
        case "blur": return AnyChartContent(erasing: c.blur(radius: a["radius"]?.cg ?? 0))
        case "shadow":
            return AnyChartContent(erasing: c.shadow(color: r.color(a["color"]) ?? Color(.sRGBLinear, white: 0, opacity: 0.33), radius: a["radius"]?.cg ?? 0,
                                                     x: a["x"]?.cg ?? 0, y: a["y"]?.cg ?? 0))
        case "offset":
            if case .native(.size(let w, let h))? = a.first { return AnyChartContent(erasing: c.offset(CGSize(width: w, height: h))) }
            if a["yStart"] != nil || a["yEnd"] != nil { return AnyChartContent(erasing: c.offset(x: a["x"]?.cg ?? 0, yStart: a["yStart"]?.cg ?? 0, yEnd: a["yEnd"]?.cg ?? 0)) }
            if a["xStart"] != nil || a["xEnd"] != nil {
                return AnyChartContent(erasing: c.offset(xStart: a["xStart"]?.cg ?? 0, xEnd: a["xEnd"]?.cg ?? 0, yStart: a["yStart"]?.cg ?? 0, yEnd: a["yEnd"]?.cg ?? 0))
            }
            return AnyChartContent(erasing: c.offset(x: a["x"]?.cg ?? 0, y: a["y"]?.cg ?? 0))
        case "zIndex": return AnyChartContent(erasing: c.zIndex(a.first?.asDouble ?? 0))
        case "clipShape":
            if let shape = DrawingBridges.shapeArg(a.first, r) { return AnyChartContent(erasing: c.clipShape(shape)) }
            return c
        case "compositingLayer": return AnyChartContent(erasing: c.compositingLayer())
        case "mask":
            let inner = r.content(a.lastFunction).flatMap { specs($0) }
            guard let first = inner.first else { return c }
            let maskContent = mark(first, Double.self, Double.self)
            return AnyChartContent(erasing: c.mask { maskContent })
        case "alignsMarkStylesWithPlotArea":
            return AnyChartContent(erasing: c.alignsMarkStylesWithPlotArea(a.first.map { interp.truthy($0) } ?? true))
        case "accessibilityLabel": return AnyChartContent(erasing: c.accessibilityLabel(Text(r.string(a.first) ?? "")))
        case "accessibilityValue": return AnyChartContent(erasing: c.accessibilityValue(Text(r.string(a.first) ?? "")))
        case "accessibilityHidden": return AnyChartContent(erasing: c.accessibilityHidden(a.first.map { interp.truthy($0) } ?? true))
        case "accessibilityIdentifier": return AnyChartContent(erasing: c.accessibilityIdentifier(r.string(a.first) ?? ""))
        default:
            return c
        }
    }

    static func symbolShape(_ name: String) -> BasicChartSymbolShape {
        switch name {
        case "square": return .square
        case "triangle": return .triangle
        case "diamond": return .diamond
        case "pentagon": return .pentagon
        case "plus": return .plus
        case "cross": return .cross
        case "asterisk": return .asterisk
        default: return .circle
        }
    }

    static func interpolation(_ v: KV?) -> InterpolationMethod {
        guard case .native(.implicit(let n, _))? = v else { return .linear }
        switch n {
        case "catmullRom": return .catmullRom
        case "cardinal": return .cardinal
        case "monotone": return .monotone
        case "stepStart": return .stepStart
        case "stepCenter": return .stepCenter
        case "stepEnd": return .stepEnd
        default: return .linear
        }
    }

    static func annotationPosition(_ name: String?) -> AnnotationPosition {
        switch name {
        case "top": return .top
        case "bottom": return .bottom
        case "leading": return .leading
        case "trailing": return .trailing
        case "overlay": return .overlay
        case "topLeading": return .topLeading
        case "topTrailing": return .topTrailing
        case "bottomLeading": return .bottomLeading
        case "bottomTrailing": return .bottomTrailing
        default: return .automatic
        }
    }

    // MARK: Axes

    /// The chart the modifier is on, and its axis kinds.
    func chartKinds(_ base: KView?) -> (KPlotKind, KPlotKind) {
        var node = base
        while let n = node, case .modified(let inner, _) = n.kind { node = inner }
        guard let n = node, case .primitive("Chart", let args, let labels, let line) = n.kind else { return (.text, .number) }
        let call = KCall(interp: interp, name: "Chart", line: line, args: args, labels: labels, overload: nil, binding: [])
        return kinds(specs(call))
    }

    func axisVisibility(_ c: KCall, _ name: String) -> AnyView {
        let view = c.view
        let vis: Visibility = c.symbol(0) == "hidden" ? .hidden : (c.symbol(0) == "visible" ? .visible : .automatic)
        return name == "chartXAxis" ? AnyView(view.chartXAxis(vis)) : AnyView(view.chartYAxis(vis))
    }

    static var axisValueSample: KV { .native(.object("AxisValue", KRef(NSObject()))) }
    static var proxySample: KV { .native(.object("ChartProxy", KRef(KChartProxyBox(nil)))) }

    func axis(_ c: KCall, _ name: String) -> AnyView {
        let view = c.view
        let (xk, yk) = chartKinds(c.base)
        let kind = name == "chartXAxis" ? xk : yk
        let parts = r.content(c["content"]).flatMap(\.flattened)
        let contents = parts.map { axisContent($0, kind) }
        let erased = AnyAxisContentList(items: contents)
        return name == "chartXAxis" ? AnyView(view.chartXAxis { erased.body }) : AnyView(view.chartYAxis { erased.body })
    }

    struct AnyAxisContentList {
        let items: [AnyAxisContent]
        @AxisContentBuilder var body: some AxisContent {
            if items.count > 0 { items[0] }
            if items.count > 1 { items[1] }
            if items.count > 2 { items[2] }
            if items.count > 3 { items[3] }
        }
    }

    func axisContent(_ v: KView, _ kind: KPlotKind) -> AnyAxisContent {
        guard case .primitive("AxisMarks", let args, let labels, _) = v.kind else { return AnyAxisContent(erasing: AxisMarks()) }
        let a = KArgs(args: args, labels: labels)
        let preset: AxisMarkPreset = {
            switch a["preset"].flatMap({ r.symbolName($0) }) {
            case "aligned": return .aligned
            case "extended": return .extended
            case "inset": return .inset
            default: return .automatic
            }
        }()
        let position: AxisMarkPosition = {
            switch a["position"].flatMap({ r.symbolName($0) }) {
            case "leading": return .leading
            case "trailing": return .trailing
            case "top": return .top
            case "bottom": return .bottom
            default: return .automatic
            }
        }()
        let interp = self.interp
        let fn = a["content"]
        let make: (AxisValue) -> KAxisMarkList = { value in
            MainActor.assumeIsolated {
                let views = KRenderer(interp: interp).content(fn, [.native(.object("AxisValue", KRef(KAxisValueBox(value))))]).flatMap(\.flattened)
                return KAxisMarkList(items: views.map { KChartBuilder(interp: interp).axisMark($0, kind, value) })
            }
        }
        if fn == nil {
            return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: axisValues(a["values"])))
        }
        if let list = a["values"]?.asArray {
            switch kind {
            case .text: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: list.map { r.string($0) ?? "" }) { make($0).body })
            case .date: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: list.compactMap { if case .native(.date(let d)) = $0 { return d }; return nil }) { make($0).body })
            default: return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: list.compactMap(\.asDouble)) { make($0).body })
            }
        }
        return AnyAxisContent(erasing: AxisMarks(preset: preset, position: position, values: axisValues(a["values"])) { make($0).body })
    }

    func axisValues(_ v: KV?) -> AxisMarkValues {
        guard case .native(.implicit(let n, let args))? = v else { return .automatic }
        switch n {
        case "automatic":
            if let count = args.first?.asInt { return .automatic(desiredCount: count) }
            return .automatic
        case "stride":
            if let by = args.first?.asDouble { return .stride(by: by) }
            if case .native(.implicit(let unit, _))? = args.first {
                let units: [String: Calendar.Component] = ["day": .day, "hour": .hour, "minute": .minute, "month": .month, "year": .year,
                                                           "weekOfYear": .weekOfYear, "second": .second, "weekday": .weekday]
                return .stride(by: units[unit] ?? .day, count: args.count > 1 ? args[1].asInt ?? 1 : 1)
            }
            return .automatic
        default: return .automatic
        }
    }

    struct KAxisMarkList {
        let items: [AnyAxisMark]
        @AxisMarkBuilder var body: some AxisMark {
            if items.count > 0 { items[0] }
            if items.count > 1 { items[1] }
            if items.count > 2 { items[2] }
            if items.count > 3 { items[3] }
            if items.count > 4 { items[4] }
        }
    }

    func axisMark(_ v: KView, _ kind: KPlotKind, _ value: AxisValue) -> AnyAxisMark {
        var modifiers: [KModifier] = []
        var node = v
        while case .modified(let inner, let m) = node.kind { modifiers.insert(m, at: 0); node = inner }
        var out: AnyAxisMark
        guard case .primitive(let name, let args, let labels, _) = node.kind else { return AnyAxisMark(erasing: AxisGridLine()) }
        let a = KArgs(args: args, labels: labels)
        let centered = a["centered"].map { interp.truthy($0) }
        let stroke: StrokeStyle? = a["stroke"].map { KCanvas.strokeStyle($0, r) }
        switch name {
        case "AxisTick":
            out = AnyAxisMark(erasing: AxisTick(centered: centered, length: a["length"]?.cg ?? 4, stroke: stroke))
        case "AxisValueLabel":
            let anchor = a["anchor"].flatMap { r.unitPoint($0) }
            if let fmt = a["format"] {
                let typeName: String = { switch kind { case .text: return "String"; case .whole: return "Int"; case .date: return "Date"; case .number: return "Double" } }()
                let text = KFormatting.formatted(Self.axisValue(value, as: .type(.builtin(typeName))), fmt, interp)
                out = AnyAxisMark(erasing: AxisValueLabel(centered: centered, anchor: anchor) { Text(text) })
            } else if case .function = a["content"] ?? .nilValue {
                let content = r.renderContent(a["content"])
                out = AnyAxisMark(erasing: AxisValueLabel(centered: centered, anchor: anchor) { content })
            } else if let title = a.first.flatMap({ r.string($0) }) {
                out = AnyAxisMark(erasing: AxisValueLabel(LocalizedStringKey(title), centered: centered, anchor: anchor))
            } else {
                out = AnyAxisMark(erasing: AxisValueLabel(centered: centered, anchor: anchor))
            }
        default:
            out = AnyAxisMark(erasing: AxisGridLine(centered: centered, stroke: stroke))
        }
        for m in modifiers {
            switch m.name {
            case "foregroundStyle": if let s = r.shapeStyle(m.first) { out = AnyAxisMark(erasing: out.foregroundStyle(s)) }
            case "font": out = AnyAxisMark(erasing: out.font(r.font(m.first)))
            case "offset":
                let ma = KArgs(args: m.args, labels: m.labels)
                out = AnyAxisMark(erasing: out.offset(x: ma["x"]?.cg ?? 0, y: ma["y"]?.cg ?? 0))
            default: break
            }
        }
        return out
    }

    static func axisValue(_ v: AxisValue, as type: KV?) -> KV {
        switch type {
        case .type(let t)?:
            switch t.name {
            case "String": return v.as(String.self).map { .string($0) } ?? .nilValue
            case "Int": return v.as(Int.self).map { .int($0) } ?? .nilValue
            case "Date": return v.as(Date.self).map { .native(.date($0)) } ?? .nilValue
            default: return v.as(Double.self).map { .double($0) } ?? .nilValue
            }
        default: return v.as(Double.self).map { .double($0) } ?? .nilValue
        }
    }

    // MARK: Scales

    static func scale(_ c: KCall, _ view: AnyView, x: Bool) -> AnyView {
        let type: ScaleType? = {
            switch c.symbol("type") {
            case "linear": return .linear
            case "log": return .log
            case "squareRoot": return .squareRoot
            case "date": return .date
            case "category": return .category
            case "symmetricLog": return .symmetricLog
            default: return nil
            }
        }()
        switch c["domain"] {
        case .range(let lo, let hi, _)?:
            if case .native(.date(let l)) = lo, case .native(.date(let h)) = hi {
                return x ? AnyView(view.chartXScale(domain: l...h, type: type)) : AnyView(view.chartYScale(domain: l...h, type: type))
            }
            if let l = lo.asDouble, let h = hi.asDouble {
                return x ? AnyView(view.chartXScale(domain: l...h, type: type)) : AnyView(view.chartYScale(domain: l...h, type: type))
            }
            return view
        case .array(let items)?:
            let names = items.map { c.r.string($0) ?? "" }
            return x ? AnyView(view.chartXScale(domain: names, type: type)) : AnyView(view.chartYScale(domain: names, type: type))
        default:
            if let type { return x ? AnyView(view.chartXScale(type: type)) : AnyView(view.chartYScale(type: type)) }
            return view
        }
    }

    static func styleScale(_ c: KCall, _ view: AnyView) -> AnyView {
        if case .dict(let d)? = c[0] {
            let pairs = d.map { (c.r.string($0.key) ?? "", c.r.shapeStyle($0.value) ?? AnyShapeStyle(.foreground)) }.sorted { $0.0 < $1.0 }
            return AnyView(view.chartForegroundStyleScale(domain: pairs.map(\.0), range: pairs.map(\.1)))
        }
        if let domain = c["domain"]?.asArray, let range = c["range"]?.asArray {
            return AnyView(view.chartForegroundStyleScale(domain: domain.map { c.r.string($0) ?? "" }, range: range.map { c.r.shapeStyle($0) ?? AnyShapeStyle(.foreground) }))
        }
        if let range = c["range"]?.asArray {
            return AnyView(view.chartForegroundStyleScale(range: range.map { c.r.shapeStyle($0) ?? AnyShapeStyle(.foreground) }))
        }
        if case .function(let fn)? = c["mapping"] ?? c[0] {
            let interp = c.interp
            return AnyView(view.chartForegroundStyleScale { (value: String) -> AnyShapeStyle in
                let v = (try? interp.entry { try interp.call(fn, [.string(value)], [nil]) }) ?? .nilValue
                return KRenderer(interp: interp).shapeStyle(v) ?? AnyShapeStyle(.foreground)
            })
        }
        return view
    }

    static func lineStyleScale(_ c: KCall, _ view: AnyView) -> AnyView {
        if case .dict(let d)? = c[0] {
            let pairs = d.map { (c.r.string($0.key) ?? "", KCanvas.strokeStyle($0.value, c.r)) }.sorted { $0.0 < $1.0 }
            return AnyView(view.chartLineStyleScale(domain: pairs.map(\.0), range: pairs.map(\.1)))
        }
        if let domain = c["domain"]?.asArray, let range = c["range"]?.asArray {
            return AnyView(view.chartLineStyleScale(domain: domain.map { c.r.string($0) ?? "" }, range: range.map { KCanvas.strokeStyle($0, c.r) }))
        }
        if let range = c["range"]?.asArray { return AnyView(view.chartLineStyleScale(range: range.map { KCanvas.strokeStyle($0, c.r) })) }
        return view
    }

    static func symbolScale(_ c: KCall, _ view: AnyView) -> AnyView {
        func shape(_ v: KV) -> any ChartSymbolShape { symbolShape(c.r.symbolName(v) ?? "circle") }
        if case .dict(let d)? = c[0] {
            let pairs = d.map { (c.r.string($0.key) ?? "", shape($0.value)) }.sorted { $0.0 < $1.0 }
            return AnyView(view.chartSymbolScale(domain: pairs.map(\.0), range: pairs.map(\.1)))
        }
        if let domain = c["domain"]?.asArray, let range = c["range"]?.asArray {
            return AnyView(view.chartSymbolScale(domain: domain.map { c.r.string($0) ?? "" }, range: range.map(shape)))
        }
        if let range = c["range"]?.asArray { return AnyView(view.chartSymbolScale(range: range.map(shape))) }
        return view
    }

    static func symbolSizeScale(_ c: KCall, _ view: AnyView) -> AnyView {
        if case .range(let lo, let hi, _)? = c["range"], let l = lo.cg, let h = hi.cg {
            if case .range(let dlo, let dhi, _)? = c["domain"], let a = dlo.asDouble, let b = dhi.asDouble {
                return AnyView(view.chartSymbolSizeScale(domain: a...b, range: l...h))
            }
            return AnyView(view.chartSymbolSizeScale(range: l...h))
        }
        return view
    }

    // MARK: Selection and scrolling

    /// A binding of the axis's type to the app's.
    static func typed<P: KPlotType>(_ b: KBinding, _: P.Type) -> Binding<P?> {
        Binding(get: {
            switch b.get() {
            case .string(let s): return s as? P ?? (P.self == Double.self ? Double(s) as? P : nil)
            case .int(let i): return (i as? P) ?? (Double(i) as? P)
            case .double(let d): return (d as? P) ?? (P.self == Int.self ? Int(d.rounded()) as? P : nil)
            case .native(.date(let d)): return d as? P
            default: return nil
            }
        }, set: { v in b.set(v.map { P.kv($0) } ?? .nilValue) })
    }

    static func typedRange<P: KPlotType & Comparable>(_ b: KBinding, _: P.Type) -> Binding<ClosedRange<P>?> {
        Binding(get: {
            guard case .range(let lo, let hi, _) = b.get() else { return nil }
            let l = typed(KBinding.constant(lo), P.self).wrappedValue, h = typed(KBinding.constant(hi), P.self).wrappedValue
            guard let l, let h else { return nil }
            return l...max(l, h)
        }, set: { v in b.set(v.map { .range(P.kv($0.lowerBound), P.kv($0.upperBound), closed: true) } ?? .nilValue) })
    }

    static func selection(_ c: KCall, x: Bool, range: Bool) -> AnyView {
        let view = c.view
        guard let b = c.kbinding(range ? "range" : "value") else { return view }
        let (xk, yk) = KChartBuilder(interp: c.interp).chartKinds(c.base)
        switch (x ? xk : yk, range, x) {
        case (.text, false, true): return AnyView(view.chartXSelection(value: typed(b, String.self)))
        case (.whole, false, true): return AnyView(view.chartXSelection(value: typed(b, Int.self)))
        case (.number, false, true): return AnyView(view.chartXSelection(value: typed(b, Double.self)))
        case (.date, false, true): return AnyView(view.chartXSelection(value: typed(b, Date.self)))
        case (.text, false, false): return AnyView(view.chartYSelection(value: typed(b, String.self)))
        case (.whole, false, false): return AnyView(view.chartYSelection(value: typed(b, Int.self)))
        case (.number, false, false): return AnyView(view.chartYSelection(value: typed(b, Double.self)))
        case (.date, false, false): return AnyView(view.chartYSelection(value: typed(b, Date.self)))
        case (.text, true, _): return view
        case (.whole, true, true): return AnyView(view.chartXSelection(range: typedRange(b, Int.self)))
        case (.number, true, true): return AnyView(view.chartXSelection(range: typedRange(b, Double.self)))
        case (.date, true, true): return AnyView(view.chartXSelection(range: typedRange(b, Date.self)))
        case (.whole, true, false): return AnyView(view.chartYSelection(range: typedRange(b, Int.self)))
        case (.number, true, false): return AnyView(view.chartYSelection(range: typedRange(b, Double.self)))
        case (.date, true, false): return AnyView(view.chartYSelection(range: typedRange(b, Date.self)))
        }
    }

    static func angleSelection(_ c: KCall) -> AnyView {
        let view = c.view
        guard let b = c.kbinding("value") else { return view }
        if case .int = b.get() { return AnyView(view.chartAngleSelection(value: typed(b, Int.self))) }
        return AnyView(view.chartAngleSelection(value: typed(b, Double.self)))
    }

    static func scrollPosition(_ c: KCall) -> AnyView {
        let view = c.view
        let (xk, yk) = KChartBuilder(interp: c.interp).chartKinds(c.base)
        if let initial = c["initialX"] ?? c["initialY"] {
            let isX = c.has("initialX")
            switch initial {
            case .native(.date(let d)): return isX ? AnyView(view.chartScrollPosition(initialX: d)) : AnyView(view.chartScrollPosition(initialY: d))
            case .string(let s): return isX ? AnyView(view.chartScrollPosition(initialX: s)) : AnyView(view.chartScrollPosition(initialY: s))
            default:
                let d = initial.asDouble ?? 0
                return isX ? AnyView(view.chartScrollPosition(initialX: d)) : AnyView(view.chartScrollPosition(initialY: d))
            }
        }
        if let b = c.kbinding("x") {
            switch xk {
            case .date: return AnyView(view.chartScrollPosition(x: Binding(get: { typed(b, Date.self).wrappedValue ?? Date() }, set: { b.set(.native(.date($0))) })))
            case .text: return AnyView(view.chartScrollPosition(x: Binding(get: { typed(b, String.self).wrappedValue ?? "" }, set: { b.set(.string($0)) })))
            default: return AnyView(view.chartScrollPosition(x: Binding(get: { b.get().asDouble ?? 0 }, set: { b.set(.double($0)) })))
            }
        }
        if let b = c.kbinding("y") {
            switch yk {
            case .date: return AnyView(view.chartScrollPosition(y: Binding(get: { typed(b, Date.self).wrappedValue ?? Date() }, set: { b.set(.native(.date($0))) })))
            case .text: return AnyView(view.chartScrollPosition(y: Binding(get: { typed(b, String.self).wrappedValue ?? "" }, set: { b.set(.string($0)) })))
            default: return AnyView(view.chartScrollPosition(y: Binding(get: { b.get().asDouble ?? 0 }, set: { b.set(.double($0)) })))
            }
        }
        return view
    }

    static func scrollTarget(_ c: KCall, _ view: AnyView) -> AnyView {
        guard case .native(.implicit(let name, let args))? = c[0] else { return view }
        if name == "paging" { return AnyView(view.chartScrollTargetBehavior(.valueAligned(unit: 1))) }
        guard name.hasPrefix("valueAligned") else { return view }
        if let unit = args.first?.asDouble { return AnyView(view.chartScrollTargetBehavior(.valueAligned(unit: unit))) }
        if case .native(.object(_, let ref))? = args.first, let comps = ref.value as? NSDateComponents {
            return AnyView(view.chartScrollTargetBehavior(.valueAligned(matching: comps as DateComponents)))
        }
        return view
    }

    // MARK: ChartProxy

    static func proxyLayer(_ c: KCall, _ view: AnyView, overlay: Bool) -> AnyView {
        guard case .function(let fn)? = c.a.lastFunction else { return view }
        let interp = c.interp, align = c.alignment("alignment")
        let make: (ChartProxy) -> AnyView = { proxy in
            KRenderer(interp: interp).renderContent(.function(fn), [.native(.object("ChartProxy", KRef(KChartProxyBox(proxy))))])
        }
        return overlay ? AnyView(view.chartOverlay(alignment: align) { make($0) }) : AnyView(view.chartBackground(alignment: align) { make($0) })
    }

    @MainActor static func proxyMembers(_ t: KTypeBuilder) {
        @MainActor func proxy(_ c: KCall) -> ChartProxy? { c.object(KChartProxyBox.self)?.proxy }
        t.property("plotSize") { c in proxy(c).map { .native(.size($0.plotSize.width, $0.plotSize.height)) } ?? .native(.size(0, 0)) }
        t.property("plotAreaSize") { c in proxy(c).map { .native(.size($0.plotSize.width, $0.plotSize.height)) } ?? .native(.size(0, 0)) }
        for axis in ["X", "Y"] {
            t.method("value", "at\(axis):number as:any?") { c in
                guard let p = proxy(c) else { return .nilValue }
                let at = c.cg(.label("at" + axis)) ?? 0
                let typeName: String = { if case .type(let t)? = c["as"] { return t.name }; return "Double" }()
                switch typeName {
                case "String": return (axis == "X" ? p.value(atX: at, as: String.self) : p.value(atY: at, as: String.self)).map { .string($0) } ?? .nilValue
                case "Int": return (axis == "X" ? p.value(atX: at, as: Int.self) : p.value(atY: at, as: Int.self)).map { .int($0) } ?? .nilValue
                case "Date": return (axis == "X" ? p.value(atX: at, as: Date.self) : p.value(atY: at, as: Date.self)).map { .native(.date($0)) } ?? .nilValue
                default: return (axis == "X" ? p.value(atX: at, as: Double.self) : p.value(atY: at, as: Double.self)).map { .double($0) } ?? .nilValue
                }
            }
            t.method("position", "for\(axis):any") { c in
                guard let p = proxy(c), let v = c[.label("for" + axis)] else { return .nilValue }
                let pos: CGFloat?
                switch v {
                case .string(let s): pos = axis == "X" ? p.position(forX: s) : p.position(forY: s)
                case .native(.date(let d)): pos = axis == "X" ? p.position(forX: d) : p.position(forY: d)
                case .int(let i): pos = axis == "X" ? p.position(forX: i) : p.position(forY: i)
                default: pos = axis == "X" ? p.position(forX: v.asDouble ?? 0) : p.position(forY: v.asDouble ?? 0)
                }
                return pos.map { .double($0) } ?? .nilValue
            }
            t.method("select\(axis)Value", "at:number") { c in
                guard let p = proxy(c) else { return .void }
                if axis == "X" { p.selectXValue(at: c.cg("at") ?? 0) } else { p.selectYValue(at: c.cg("at") ?? 0) }
                return .void
            }
        }
    }
}

extension KRenderer {
    func symbolName(_ v: KV) -> String? {
        if case .native(.implicit(let n, _)) = v { return n }
        return nil
    }
}

/// `.chartGesture { proxy in DragGesture()… }`: the app's gesture, given the proxy.
struct KChartGestureHost: View {
    let content: AnyView
    let make: KFunction
    let interp: KInterpreter
    @GestureState private var active = false

    var body: some View {
        content.chartGesture { proxy in
            MainActor.assumeIsolated {
                let v = (try? interp.entry { try interp.call(make, [.native(.object("ChartProxy", KRef(KChartProxyBox(proxy))))], [nil]) }) ?? .nilValue
                return KGestureBuilder(interp: interp, active: $active, resets: KGestureResets()).build(v) ?? AnyGesture(TapGesture().map { KV.void })
            }
        }
    }
}
