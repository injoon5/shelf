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
        for name in ["chartXScale", "chartForegroundStyleScale", "chartPlotStyle", "chartBackground", "chartOverlay"] {
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
