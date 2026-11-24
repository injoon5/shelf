//
//  Charts.swift
//  Bridges: Swift Charts
//
//  A `Chart`'s marks are read, not shown: each becomes a point (x, y, angle,
//  series, color) and `KChartView` draws them all with Swift Charts.
//

import SwiftUI
import Charts

@objc(KilnBridges_Charts)
final class ChartsBridges: KBridgeFamily {
    static let marks = ["BarMark", "LineMark", "PointMark", "AreaMark", "SectorMark", "RuleMark", "RectangleMark"]

    override class func register(into r: KRegistry) {
        r.view("Chart", .charts, support: .partial, notes: "Bar, line, point, area, sector and rule marks, by value or by series; the axes and the legend can be hidden.") { v in
            v.forms(["content:content", "_:any content:content", "_:any id:any content:content"]) { c in chart(c) }
        }
        let signatures: [String: [String]] = [
            "SectorMark": ["angle:any innerRadius:any? outerRadius:any? angularInset:any?"],
            "RuleMark": ["x:any? xStart:any? xEnd:any? y:any? yStart:any? yEnd:any?"],
        ]
        for name in marks {
            r.view(name, .charts, support: .partial) { v in
                v.manifestKind = "content"
                v.forms(signatures[name] ?? ["x:any? xStart:any? xEnd:any? y:any? yStart:any? yEnd:any? width:any? height:any? stacking:any?"]) { _ in EmptyView() }
            }
        }

        // On the chart.
        for (name, axisLike) in [("chartLegend", true), ("chartXAxis", true), ("chartYAxis", true)] {
            r.modifier(name, .charts, support: .partial, notes: "`.hidden` hides it; content isn't customized yet.") { m in
                m.form(axisLike ? "_:any" : "_:any") { c, view in
                    if c.symbol(0) == "hidden" {
                        switch name {
                        case "chartLegend": AnyView(view.chartLegend(.hidden))
                        case "chartXAxis": AnyView(view.chartXAxis(.hidden))
                        default: AnyView(view.chartYAxis(.hidden))
                        }
                    } else {
                        view
                    }
                }
                m.form("content:content") { _, view in view }
                m.form("position:any? alignment:any? spacing:number? content:content") { _, view in view }
            }
        }
        r.modifier("chartYScale", .charts, support: .partial, notes: "`domain:` as a numeric range.") { m in
            m.form("domain:any range:any? type:any?") { c, view in
                if case .range(let lo, let hi, _)? = c["domain"], let l = lo.asDouble, let h = hi.asDouble { AnyView(view.chartYScale(domain: l...h)) } else { view }
            }
        }
        // Chart3D's `SurfacePlot` takes its domain from it (§3.7).
        r.modifier("chartXScale", .charts, support: .partial, notes: "`domain:` as a numeric range.") { m in
            m.form("domain:any? range:any? type:any?") { c, view in
                if case .range(let lo, let hi, _)? = c["domain"], let l = lo.asDouble, let h = hi.asDouble { AnyView(view.chartXScale(domain: l...h)) } else { view }
            }
            m.form("_:any") { _, view in view }
        }
        for name in ["chartForegroundStyleScale", "chartPlotStyle", "chartBackground", "chartOverlay"] {
            r.modifier(name, .charts, support: .stub) { m in
                m.stub(name == "chartPlotStyle" || name == "chartBackground" || name == "chartOverlay"
                       ? ["alignment:any? content:closure"] : ["domain:any? range:any? type:any?", "_:any"])
            }
        }

        // On the marks: read by the chart, or accepted.
        for (name, sigs) in [("annotation", ["position:any? alignment:any? spacing:number? content:content"]), ("interpolationMethod", ["_:any"]),
                             ("lineStyle", ["_:any"]), ("symbol", ["_:any", "by:any"]), ("symbolSize", ["_:any", "by:any"])] {
            r.modifier(name, .charts, support: .stub) { m in
                m.owner = "ChartContent"
                m.stub(sigs, receiver: "ChartContent")
            }
        }
    }

    @MainActor static func chart(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        var marks: [KView] = []
        if let data = a.first, a.firstIsUnlabeled, !r.isFunction(data) {
            for e in (try? c.interp.sequence(data)) ?? [] { marks += r.content(a.lastFunction, [e]).flatMap(\.flattened) }
        } else {
            for v in r.content(a.lastFunction).flatMap(\.flattened) {
                if v.primitiveName == "ForEach", case .primitive(_, let args, let labels, _) = v.kind {
                    for row in r.forEachRows(KArgs(args: args, labels: labels)) { marks += row.views.flatMap(\.flattened) }
                } else {
                    marks.append(v)
                }
            }
        }
        return AnyView(KChartView(points: marks.compactMap { KChartPoint(view: $0, renderer: r) }))
    }
}

// MARK: - The chart itself

struct KChartPoint: Identifiable {
    enum Axis: Hashable { case text(String), number(Double), date(Date) }
    let id = UUID()
    let kind: String
    var x: Axis?
    var y: Axis?
    var xLabel = "x"
    var yLabel = "y"
    var angle: Double?
    var color: Color?
    var series: String?
    var seriesLabel = "Series"
    var cornerRadius: Double?

    @MainActor
    init?(view: KView, renderer r: KRenderer) {
        var modifiers: [KModifier] = []
        var node = view
        while case .modified(let inner, let m) = node.kind { modifiers.append(m); node = inner }
        guard case .primitive(let name, let args, let labels, _) = node.kind,
              ["BarMark", "LineMark", "PointMark", "AreaMark", "SectorMark", "RuleMark", "RectangleMark"].contains(name) else { return nil }
        kind = name
        let a = KArgs(args: args, labels: labels)
        func plottable(_ v: KV?) -> (String, Axis)? {
            guard case .native(.implicit("value", let pa))? = v, pa.count >= 2 else { return nil }
            let label = r.string(pa[0]) ?? ""
            switch pa[1] {
            case .int(let i): return (label, .number(Double(i)))
            case .double(let d): return (label, .number(d))
            case .native(.date(let d)): return (label, .date(d))
            default: return (label, .text(r.string(pa[1]) ?? ""))
            }
        }
        if let (l, v) = plottable(a["x"]) { xLabel = l; x = v }
        if let (l, v) = plottable(a["y"]) { yLabel = l; y = v }
        if let (_, v) = plottable(a["angle"]), case .number(let n) = v { angle = n }
        for m in modifiers {
            if m.name == "foregroundStyle" {
                if let by = m.arg("by"), case .native(.implicit("value", let pa)) = by, pa.count >= 2 {
                    seriesLabel = r.string(pa[0]) ?? "Series"
                    series = r.string(pa[1])
                } else if let c = r.color(m.first) {
                    color = c
                }
            }
            if m.name == "cornerRadius" { cornerRadius = m.first?.asDouble }
        }
    }

    var xText: String { if case .text(let s)? = x { return s }; return "" }
    var yText: String { if case .text(let s)? = y { return s }; return "" }
    var xNumber: Double { if case .number(let n)? = x { return n }; return 0 }
    var yNumber: Double { if case .number(let n)? = y { return n }; return 0 }
    var xDate: Date { if case .date(let d)? = x { return d }; return Date() }
    var xIsText: Bool { if case .text? = x { return true }; return false }
    var xIsDate: Bool { if case .date? = x { return true }; return false }
    var yIsText: Bool { if case .text? = y { return true }; return false }
}

struct KChartView: View {
    let points: [KChartPoint]

    var body: some View {
        Chart {
            ForEach(points) { p in
                mark(p)
            }
        }
    }

    @ChartContentBuilder
    func mark(_ p: KChartPoint) -> some ChartContent {
        if p.kind == "SectorMark" {
            SectorMark(angle: .value("Value", p.angle ?? 0), innerRadius: .ratio(0.5), angularInset: 1.5)
                .foregroundStyle(by: .value(p.seriesLabel, p.series ?? "\(p.angle ?? 0)"))
        } else if p.kind == "RuleMark" {
            RuleMark(y: .value(p.yLabel, p.yNumber))
                .foregroundStyle(p.color ?? .red)
        } else if p.xIsText {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xText), y: PlottableValue.value(p.yLabel, p.yNumber)), p)
        } else if p.xIsDate {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xDate), y: PlottableValue.value(p.yLabel, p.yNumber)), p)
        } else if p.yIsText {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xNumber), y: PlottableValue.value(p.yLabel, p.yText)), p)
        } else {
            styled(barOrLine(p, x: PlottableValue.value(p.xLabel, p.xNumber), y: PlottableValue.value(p.yLabel, p.yNumber)), p)
        }
    }

    @ChartContentBuilder
    func barOrLine<X: Plottable, Y: Plottable>(_ p: KChartPoint, x: PlottableValue<X>, y: PlottableValue<Y>) -> some ChartContent {
        switch p.kind {
        case "LineMark": LineMark(x: x, y: y)
        case "PointMark": PointMark(x: x, y: y)
        case "AreaMark": AreaMark(x: x, y: y)
        default: BarMark(x: x, y: y)
        }
    }

    @ChartContentBuilder
    func styled<C: ChartContent>(_ c: C, _ p: KChartPoint) -> some ChartContent {
        if let s = p.series {
            c.foregroundStyle(by: .value(p.seriesLabel, s))
        } else {
            c.foregroundStyle(p.color ?? .accentColor)
        }
    }
}
