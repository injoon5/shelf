//
//  Charts.swift
//  Bridges: Swift Charts
//
//  A `Chart`'s content is a description while the app's code runs, as views
//  are: marks with their modifiers. `KChartBuilder` makes each one Swift
//  Charts' own (`BarMark(x:y:)` with `.foregroundStyle(by:)` and the rest),
//  erased to `AnyChartContent`, and the real `Chart` shows them all.
//
//  A plottable's type is fixed per axis in Swift Charts, so a chart's x and y
//  types are found first (text, a whole number, a number, a date), and the
//  marks are built for those types (`KPlotType`).
//
//  Vectorized plots (`BarPlot(data, x: .value("Day", \.day), …)`) are the
//  same marks, one per element; function plots (`LinePlot(x:y:domain:)
//  { x in … }`) are sampled on the main thread, where the app's code runs.
//
//  Axis marks run the app's closure per axis value, inside Swift Charts.
//

import SwiftUI
import Charts

@objc(KilnBridges_Charts)
final class ChartsBridges: KBridgeFamily {
    static let marks = ["BarMark", "LineMark", "PointMark", "AreaMark", "SectorMark", "RuleMark", "RectangleMark"]
    static let plots = ["BarPlot", "LinePlot", "PointPlot", "AreaPlot", "SectorPlot", "RulePlot", "RectanglePlot"]

    override class func register(into r: KRegistry) {
        chart(r)
        content(r)
        markModifiers(r)
        axes(r)
        scalesAndLegends(r)
        interaction(r)
        values(r)
    }

    // MARK: Chart

    static func chart(_ r: KRegistry) {
        r.view("Chart", .charts, notes: "Its content is marks, plots, `ForEach` and `if`; give each axis one kind of value (text, numbers or dates).") { v in
            v.forms(["content:content", "_:any content:content", "_:any id:any content:content"]) { c in
                KChartBuilder(interp: c.interp).chart(c)
            }
        }
    }

    static func content(_ r: KRegistry) {
        let markSigs: [String: [String]] = [
            "BarMark": ["x:any? y:any? width:any? height:any? stacking:any?", "xStart:any xEnd:any y:any? height:any?",
                        "x:any? yStart:any yEnd:any width:any?", "xStart:any xEnd:any yStart:any yEnd:any"],
            "LineMark": ["x:any y:any series:any?"],
            "PointMark": ["x:any? y:any?"],
            "AreaMark": ["x:any y:any stacking:any?", "x:any yStart:any yEnd:any series:any?", "xStart:any xEnd:any y:any series:any?",
                         "x:any y:any series:any? stacking:any?"],
            "SectorMark": ["angle:any innerRadius:any? outerRadius:any? angularInset:any?"],
            "RuleMark": ["x:any? yStart:any? yEnd:any?", "y:any? xStart:any? xEnd:any?", "xStart:any xEnd:any y:any", "x:any yStart:any yEnd:any"],
            "RectangleMark": ["x:any? y:any? width:any? height:any?", "xStart:any xEnd:any y:any? height:any?", "x:any? yStart:any yEnd:any width:any?",
                              "xStart:any xEnd:any yStart:any yEnd:any"],
        ]
        for name in marks {
            r.view(name, .charts) { v in
                v.manifestKind = "content"
                v.forms(markSigs[name] ?? []) { _ in EmptyView() }
            }
        }
        let plotSigs: [String: [String]] = [
            "LinePlot": ["x:any y:any domain:any? function:closure", "x:any y:any t:any domain:any function:closure", "_:any x:any y:any series:any?"],
            "AreaPlot": ["x:any y:any domain:any? function:closure", "x:any yStart:any yEnd:any domain:any? function:closure",
                         "_:any x:any y:any stacking:any?", "_:any x:any yStart:any yEnd:any"],
            "BarPlot": ["_:any x:any? y:any? width:any? height:any? stacking:any?", "_:any xStart:any xEnd:any y:any? height:any?",
                        "_:any x:any? yStart:any yEnd:any width:any?"],
            "PointPlot": ["_:any x:any? y:any?"],
            "RulePlot": ["_:any x:any? yStart:any? yEnd:any?", "_:any y:any? xStart:any? xEnd:any?", "_:any xStart:any xEnd:any y:any?",
                         "_:any x:any? yStart:any yEnd:any"],
            "RectanglePlot": ["_:any x:any? y:any? width:any? height:any?", "_:any xStart:any xEnd:any yStart:any yEnd:any"],
            "SectorPlot": ["_:any angle:any innerRadius:any? outerRadius:any? angularInset:any?"],
        ]
        for name in plots {
            r.view(name, .charts, introduced: "18.0", notes: name == "LinePlot" || name == "AreaPlot" ? "A function's plot is sampled at 200 points of `domain:` (or the x scale's)." : nil) { v in
                v.manifestKind = "content"
                v.forms(plotSigs[name] ?? []) { _ in EmptyView() }
                v.probe { _, a, _ in
                    guard case .function(let fn)? = a["function"] else { return [] }
                    return [KProbeCall(fn: fn, args: [.double(0.5)], use: .action)]
                }
            }
        }
        for (name, sigs) in [("Plot", ["content:content"]), ("AnyChartContent", ["_:any", "erasing:any"]), ("AnyAxisContent", ["_:any", "erasing:any"])] {
            r.view(name, .charts) { v in
                v.manifestKind = "content"
                v.forms(sigs) { _ in EmptyView() }
            }
        }
        r.view("BasicChartSymbolShape", .charts) { v in
            v.forms(["_:any"]) { c in
                ChartSymbolsView(name: c.symbol(0) ?? "circle")
            }
        }
        r.type("BasicChartSymbolShape", .charts, support: .full) { t in
            for name in ["circle", "square", "triangle", "diamond", "pentagon", "plus", "cross", "asterisk"] {
                t.staticProperty(name) { _ in .native(.implicit(name, [])) }
            }
        }
    }

    // MARK: On marks

    static func markModifiers(_ r: KRegistry) {
        // Each is read by `KChartBuilder` when the chart is built.
        let forms: [(String, [String])] = [
            ("annotation", ["position:any? alignment:Alignment? spacing:number? overflowResolution:any? content:content"]),
            ("interpolationMethod", ["_:any"]),
            ("lineStyle", ["_:StrokeStyle", "by:any"]),
            ("symbol", ["_:any", "by:any", "symbol:content"]),
            ("symbolSize", ["_:any", "by:any"]),
            ("position", ["by:any axis:any? span:any?"]),
            ("accessibilityHidden", ["_:bool"]),
            ("accessibilityIdentifier", ["_:string"]),
            ("accessibilityLabel", ["_:any"]),
            ("accessibilityValue", ["_:any"]),
            ("alignsMarkStylesWithPlotArea", ["_:bool?"]),
            ("blur", ["radius:number"]),
            ("clipShape", ["_:any style:any?"]),
            ("compositingLayer", ["", "style:closure"]),
            ("mask", ["content:content"]),
            ("offset", ["_:CGSize", "x:number? y:number?", "x:number? yStart:number? yEnd:number?", "xStart:number? xEnd:number? y:number?",
                        "xStart:number? xEnd:number? yStart:number? yEnd:number?"]),
            ("opacity", ["_:number"]),
            ("shadow", ["color:Color? radius:number x:number? y:number?"]),
            ("zIndex", ["_:number"]),
        ]
        // Modifiers SwiftUI also has on views (`opacity`, `blur`…) are other
        // families' bridges: their chart forms are added to them.
        for (name, sigs) in forms {
            if let existing = r.modifier(name) {
                for sig in sigs {
                    existing.forms.append(.init(overload: KOverload(params: KSignature.parse(sig), availability: nil, notes: nil, receiver: "ChartContent"),
                                                apply: { _, v in v ?? AnyView(EmptyView()) }))
                }
                continue
            }
            r.modifier(name, .charts) { m in
                m.owner = "ChartContent"
                for sig in sigs { m.form(sig, receiver: "ChartContent") { _, view in view } }
            }
        }
    }

    // MARK: Axes

    static func axes(_ r: KRegistry) {
        for name in ["chartXAxis", "chartYAxis"] {
            r.modifier(name, .charts, notes: "`.hidden`, or `AxisMarks` with grid lines, ticks and labels.") { m in
                // The content form first: a trailing closure would bind `_:any` too.
                m.formOnBase("content:content") { c in KChartBuilder(interp: c.interp).axis(c, name) }
                m.formOnBase("_:any") { c in KChartBuilder(interp: c.interp).axisVisibility(c, name) }
            }
        }
        r.view("AxisMarks", .charts) { v in
            v.manifestKind = "content"
            v.forms(["preset:any? position:any? values:any? content:closure", "preset:any? position:any? values:any? stroke:any?"]) { _ in EmptyView() }
            v.probe { _, a, _ in
                guard case .function(let fn)? = a["content"] else { return [] }
                return [KProbeCall(fn: fn, args: [KChartBuilder.axisValueSample])]
            }
        }
        for (name, sigs) in [("AxisGridLine", ["centered:bool? stroke:StrokeStyle?"]),
                             ("AxisTick", ["centered:bool? length:any? stroke:StrokeStyle?"]),
                             ("AxisValueLabel", ["centered:bool? anchor:any? multiLabelAlignment:any? collisionResolution:any? offsetsMarks:bool? orientation:any? horizontalSpacing:number? verticalSpacing:number?",
                                                 "format:any centered:bool? anchor:any? multiLabelAlignment:any? collisionResolution:any? offsetsMarks:bool? orientation:any? horizontalSpacing:number? verticalSpacing:number?",
                                                 "_:any centered:bool? anchor:any? multiLabelAlignment:any? collisionResolution:any? offsetsMarks:bool? orientation:any? horizontalSpacing:number? verticalSpacing:number?",
                                                 "centered:bool? anchor:any? multiLabelAlignment:any? collisionResolution:any? offsetsMarks:bool? orientation:any? horizontalSpacing:number? verticalSpacing:number? content:content"])] {
            r.view(name, .charts) { v in
                v.manifestKind = "content"
                v.forms(sigs) { _ in EmptyView() }
            }
        }
        for name in ["chartXAxisLabel", "chartYAxisLabel"] {
            r.modifier(name, .charts) { m in
                m.form("_:any position:any? alignment:Alignment? spacing:number?") { c, view in
                    let label = Text(c.title(0))
                    let pos = KChartBuilder.annotationPosition(c.symbol("position"))
                    if name == "chartXAxisLabel" {
                        AnyView(view.chartXAxisLabel(position: pos, alignment: c.has("alignment") ? c.alignment("alignment") : nil, spacing: c.cg("spacing")) { label })
                    } else {
                        AnyView(view.chartYAxisLabel(position: pos, alignment: c.has("alignment") ? c.alignment("alignment") : nil, spacing: c.cg("spacing")) { label })
                    }
                }
                m.form("position:any? alignment:Alignment? spacing:number? content:content") { c, view in
                    let content = c.content("content")
                    let pos = KChartBuilder.annotationPosition(c.symbol("position"))
                    if name == "chartXAxisLabel" {
                        AnyView(view.chartXAxisLabel(position: pos, alignment: c.has("alignment") ? c.alignment("alignment") : nil, spacing: c.cg("spacing")) { content })
                    } else {
                        AnyView(view.chartYAxisLabel(position: pos, alignment: c.has("alignment") ? c.alignment("alignment") : nil, spacing: c.cg("spacing")) { content })
                    }
                }
            }
        }
        for name in ["chartXAxisStyle", "chartYAxisStyle", "chartPlotStyle"] {
            r.modifier(name, .charts) { m in
                m.form("content:closure") { c, view in
                    if case .function(let fn)? = c["content"] {
                        let interp = c.interp
                        let style: (AnyView) -> AnyView = { content in KRenderer(interp: interp).renderContent(.function(fn), [KNativeContent.value(content)]) }
                        switch name {
                        case "chartXAxisStyle": AnyView(view.chartXAxisStyle { style(AnyView($0)) })
                        case "chartYAxisStyle": AnyView(view.chartYAxisStyle { style(AnyView($0)) })
                        default: AnyView(view.chartPlotStyle { style(AnyView($0)) })
                        }
                    } else {
                        view
                    }
                }
                m.probe { _, a, _ in
                    guard case .function(let fn)? = a["content"] else { return [] }
                    return [KProbeCall(fn: fn, args: [KNativeContent.value(AnyView(EmptyView()))])]
                }
            }
        }
    }

    // MARK: Scales and legends

    static func scalesAndLegends(_ r: KRegistry) {
        for name in ["chartXScale", "chartYScale"] {
            r.modifier(name, .charts, notes: "`domain:` a range or the values in order, and `type:`.") { m in
                m.form("domain:any range:any? type:any?") { c, view in KChartBuilder.scale(c, view, x: name == "chartXScale") }
                m.form("domain:any type:any?") { c, view in KChartBuilder.scale(c, view, x: name == "chartXScale") }
                m.form("range:any type:any?") { c, view in KChartBuilder.scale(c, view, x: name == "chartXScale") }
                m.form("type:any?") { c, view in KChartBuilder.scale(c, view, x: name == "chartXScale") }
            }
        }
        r.modifier("chartForegroundStyleScale", .charts, notes: "A dictionary literal's order isn't kept: use `domain:` and `range:` to fix the legend's order.") { m in
            m.form("_:any") { c, view in KChartBuilder.styleScale(c, view) }
            m.form("domain:any range:any type:any?") { c, view in KChartBuilder.styleScale(c, view) }
            m.form("range:any type:any?") { c, view in KChartBuilder.styleScale(c, view) }
            m.form("mapping:closure") { c, view in KChartBuilder.styleScale(c, view) }
            m.form("type:any?") { _, view in view }
        }
        r.modifier("chartLineStyleScale", .charts) { m in
            m.form("_:any") { c, view in KChartBuilder.lineStyleScale(c, view) }
            m.form("domain:any range:any type:any?") { c, view in KChartBuilder.lineStyleScale(c, view) }
            m.form("range:any type:any?") { c, view in KChartBuilder.lineStyleScale(c, view) }
            m.form("mapping:closure") { _, view in view }
        }
        r.modifier("chartSymbolScale", .charts) { m in
            m.form("_:any") { c, view in KChartBuilder.symbolScale(c, view) }
            m.form("domain:any range:any") { c, view in KChartBuilder.symbolScale(c, view) }
            m.form("range:any") { c, view in KChartBuilder.symbolScale(c, view) }
            m.form("mapping:closure") { _, view in view }
        }
        r.modifier("chartSymbolSizeScale", .charts) { m in
            m.form("_:any") { c, view in KChartBuilder.symbolSizeScale(c, view) }
            m.form("domain:any range:any type:any?") { c, view in KChartBuilder.symbolSizeScale(c, view) }
            m.form("range:any type:any?") { c, view in KChartBuilder.symbolSizeScale(c, view) }
            m.form("type:any?") { _, view in view }
        }
        r.modifier("chartLegend", .charts) { m in
            m.form("_:any") { c, view in
                switch c.symbol(0) {
                case "hidden": AnyView(view.chartLegend(.hidden))
                case "visible": AnyView(view.chartLegend(.visible))
                default: AnyView(view.chartLegend(.automatic))
                }
            }
            m.form("position:any? alignment:Alignment? spacing:number?") { c, view in
                view.chartLegend(position: KChartBuilder.annotationPosition(c.symbol("position")), alignment: c.has("alignment") ? c.alignment("alignment") : nil,
                                 spacing: c.cg("spacing"))
            }
            m.form("position:any? alignment:Alignment? spacing:number? content:content") { c, view in
                let content = c.content("content")
                view.chartLegend(position: KChartBuilder.annotationPosition(c.symbol("position")), alignment: c.has("alignment") ? c.alignment("alignment") : nil,
                                 spacing: c.cg("spacing")) { content }
            }
        }
        r.modifier("chartBackground", .charts) { m in
            m.form("alignment:Alignment? content:closure") { c, view in KChartBuilder.proxyLayer(c, view, overlay: false) }
            m.probe { _, a, _ in a.lastFunction.map { if case .function(let f) = $0 { return [KProbeCall(fn: f, args: [KChartBuilder.proxySample])] }; return [] } ?? [] }
        }
        r.modifier("chartOverlay", .charts) { m in
            m.form("alignment:Alignment? content:closure") { c, view in KChartBuilder.proxyLayer(c, view, overlay: true) }
            m.probe { _, a, _ in a.lastFunction.map { if case .function(let f) = $0 { return [KProbeCall(fn: f, args: [KChartBuilder.proxySample])] }; return [] } ?? [] }
        }
    }

    // MARK: Selection and scrolling

    static func interaction(_ r: KRegistry) {
        for name in ["chartXSelection", "chartYSelection"] {
            r.modifier(name, .charts, introduced: "17.0", notes: "The binding's type is the axis's: `String?`, `Int?`, `Double?` or `Date?`.") { m in
                m.formOnBase("value:binding") { c in KChartBuilder.selection(c, x: name == "chartXSelection", range: false) }
                m.formOnBase("range:binding") { c in KChartBuilder.selection(c, x: name == "chartXSelection", range: true) }
            }
        }
        r.modifier("chartAngleSelection", .charts, introduced: "17.0") { m in
            m.formOnBase("value:binding") { c in KChartBuilder.angleSelection(c) }
        }
        r.modifier("chartScrollableAxes", .charts, introduced: "17.0") { m in
            m.form("_:any") { c, view in
                let axes: Axis.Set = c.symbol(0) == "vertical" ? .vertical : (c.symbol(0) == "horizontal" ? .horizontal : (c.symbol(0) == nil ? [] : [.horizontal, .vertical]))
                view.chartScrollableAxes(axes)
            }
        }
        for name in ["chartXVisibleDomain", "chartYVisibleDomain"] {
            r.modifier(name, .charts, introduced: "17.0", notes: "For a date axis, `length:` is in seconds.") { m in
                m.form("length:number") { c, view in
                    let length = c.double("length") ?? 1
                    if name == "chartXVisibleDomain" { AnyView(view.chartXVisibleDomain(length: length)) } else { AnyView(view.chartYVisibleDomain(length: length)) }
                }
            }
        }
        r.modifier("chartScrollPosition", .charts, introduced: "17.0") { m in
            for sig in ["initialX:any", "initialY:any", "x:binding", "y:binding"] {
                m.formOnBase(sig) { c in KChartBuilder.scrollPosition(c) }
            }
        }
        r.modifier("chartScrollTargetBehavior", .charts, support: .partial, introduced: "17.0",
                   notes: "`.valueAligned(unit:)` and `.valueAligned(matching:)` with `DateComponents`; `.paging`.") { m in
            m.form("_:any") { c, view in KChartBuilder.scrollTarget(c, view) }
        }
        r.modifier("chartGesture", .charts, introduced: "17.0") { m in
            m.form("_:closure") { c, view in
                if case .function(let fn)? = c[0] { KChartGestureHost(content: view, make: fn, interp: c.interp) } else { view }
            }
            m.probe { _, a, _ in
                guard case .function(let fn)? = a.first else { return [] }
                return [KProbeCall(fn: fn, args: [KChartBuilder.proxySample], use: .action)]
            }
        }
    }

    // MARK: Values

    static func values(_ r: KRegistry) {
        r.type("PlottableValue", .charts, support: .full) { t in
            t.staticMethod("value", "_:any _:any") { c in .native(.implicit("value", c.args)) }
        }
        r.type("ChartProxy", .charts, support: .full) { t in
            KChartBuilder.proxyMembers(t)
        }
        r.type("AxisValue", .charts) { t in
            t.internal()
            t.method("as", "_:any") { c in
                guard let v = c.object(KAxisValueBox.self) else { return .nilValue }
                return KChartBuilder.axisValue(v.value, as: c[0])
            }
            t.property("index") { c in .int(c.object(KAxisValueBox.self)?.value.index ?? 0) }
            t.property("count") { c in .int(c.object(KAxisValueBox.self)?.value.count ?? 0) }
        }
        r.type("MarkDimension", .charts) { t in
            t.internal()
            t.anyStatic { _, name in .native(.implicit(name, [])) }
            t.anyStaticMethod { c, name in .native(.implicit(name, c.args)) }
        }
    }
}

/// A chart symbol shape shown as a view (`BasicChartSymbolShape.circle`).
struct ChartSymbolsView: View {
    let name: String
    var body: some View {
        KChartBuilder.symbolShape(name).frame(width: 10, height: 10)
    }
}
