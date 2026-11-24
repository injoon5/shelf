//
//  Chart3D.swift
//  Bridges: Swift Charts in 3D (PLAN.md §3.7)
//
//  `Chart3D` with the 3D forms of `PointMark`, `RuleMark` and
//  `RectangleMark` (`x:y:z:`), `SurfacePlot`, their modifiers
//  (`foregroundStyle` with a color, `.heightBased` or `by:`, `metalness`,
//  `roughness`, `symbol`, `symbolSize`, `symbolRotation`), and the chart's
//  `chart3DPose`, `chart3DCameraProjection`, `chartZScale`, `chartZAxis`,
//  `chartZAxisLabel` and `chartZSelection`.
//
//  As with `Chart` (Charts.swift), the marks are read, not shown: each
//  becomes a `K3DMark` and `KChart3DView` draws them with Swift Charts.
//
//  `SurfacePlot`'s function is the app's closure. Swift Charts calls it
//  once per sample, 256 × 256 per pass, which the interpreter can't keep up
//  with: so Kiln samples the app's function on a grid of at most
//  `KSurfaceSampler.side` × `side` points over the domain Swift Charts asks
//  for, and Swift Charts gets a native function that interpolates the grid
//  (`Benchmarks/README.md` has the timing behind the cap).
//
//  The marks' 2D bridges are Charts' (Bridges/Charts); this family adds
//  their `x:y:z:` forms, so Charts' file doesn't change.
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif
#if canImport(Spatial)
import Spatial
#endif

@objc(KilnBridges_Chart3D)
final class Chart3DBridges: KBridgeFamily {
    static let iOS26 = "26.0"

    override class func register(into r: KRegistry) {
        chart(r)
        marks(r)
        chartModifiers(r)
        contentModifiers(r)
        values(r)
    }

    // MARK: Chart3D and its content

    static func chart(_ r: KRegistry) {
        r.view("Chart3D", .chart3D, introduced: iOS26) { v in
            v.forms(["content:content", "_:any content:content", "_:any id:any content:content"]) { c in
                #if canImport(Charts) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    chart3D(c)
                }
                #endif
            }
        }
        r.view("SurfacePlot", .chart3D, introduced: iOS26) { v in
            v.manifestKind = "content"
            v.form("x:title y:title z:title function:closure") { _ in EmptyView() }
            // A check calls the function once, as Swift Charts would, with a point: it returns a number, not views.
            v.probe { _, a, _ in
                guard case .function(let f)? = a["function"] ?? a.lastFunction else { return [] }
                return [KProbeCall(fn: f, args: [.double(0.5), .double(0.5)], use: .action)]
            }
        }
    }

    /// The 3D forms of Charts' marks: `PointMark(x:y:z:)`.
    static func marks(_ r: KRegistry) {
        for name in ["PointMark", "RuleMark", "RectangleMark"] {
            guard let b = r.view(name) else { continue }
            KViewBuilder(b).form("x:any y:any z:any", introduced: iOS26) { _ in EmptyView() }
        }
    }

    // MARK: On the chart

    static func chartModifiers(_ r: KRegistry) {
        r.modifier("chart3DPose", .chart3D, introduced: iOS26) { m in
            // A binding (`$pose`, which the chart moves as people drag) or a pose.
            m.form("_:any") { c, view in
                #if canImport(Charts) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    if let b = c.kbinding(0) {
                        AnyView(view.chart3DPose(Binding<Chart3DPose>(get: { K3D.pose(b.get()) ?? .default }, set: { p in K3D.later { if K3D.pose(b.get()) != p { b.set(K3D.value(p)) } } })))
                    } else if let pose = K3D.pose(c[0]) {
                        AnyView(view.chart3DPose(pose))
                    } else { view }
                } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("chart3DCameraProjection", .chart3D, introduced: iOS26) { m in
            m.form("_:any?") { c, view in
                #if canImport(Charts) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
                    switch c.symbol(0) {
                    case "orthographic": AnyView(view.chart3DCameraProjection(.orthographic))
                    case "perspective": AnyView(view.chart3DCameraProjection(.perspective))
                    default: AnyView(view.chart3DCameraProjection(.automatic))
                    }
                } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("chartZScale", .chart3D, support: .partial, introduced: iOS26, notes: "`domain:` as a numeric range.") { m in
            m.form("domain:any range:any? type:any?") { c, view in
                #if canImport(Charts) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), case .range(let lo, let hi, _)? = c["domain"],
                   let l = lo.asDouble, let h = hi.asDouble, l <= h {
                    AnyView(view.chartZScale(domain: l...h))
                } else { view }
                #else
                view
                #endif
            }
            m.form("range:any type:any?") { _, view in view }
        }
        r.modifier("chartZAxis", .chart3D, support: .partial, introduced: iOS26, notes: "`.hidden` hides it; its marks aren't customized yet.") { m in
            m.form("_:any") { c, view in
                #if canImport(Charts) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), c.symbol(0) == "hidden" { AnyView(view.chartZAxis(.hidden)) } else { view }
                #else
                view
                #endif
            }
            m.form("content:content") { _, view in view }
        }
        r.modifier("chartZAxisLabel", .chart3D, introduced: iOS26) { m in
            m.form("_:title position:any? alignment:any? spacing:number?") { c, view in
                #if canImport(Charts) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) { AnyView(view.chartZAxisLabel(c.title(0))) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("chartZSelection", .chart3D, support: .partial, introduced: iOS26, notes: "A number's `value:` binding.") { m in
            m.form("value:binding") { c, view in
                #if canImport(Charts) && !os(tvOS) && !os(watchOS)
                if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let b = c.kbinding("value") {
                    AnyView(view.chartZSelection(value: Binding<Double?>(get: { b.get().asDouble }, set: { v in K3D.later { if b.get().asDouble != v { b.set(v.map(KV.double) ?? .nilValue) } } })))
                } else { view }
                #else
                view
                #endif
            }
            m.form("range:binding") { _, view in view }
        }
    }

    // MARK: On the content: read by the chart

    static func contentModifiers(_ r: KRegistry) {
        let receiver = "Chart3DContent"
        for name in ["metalness", "roughness"] {
            r.modifier(name, .chart3D, introduced: iOS26) { m in
                m.owner = receiver
                m.form("_:number", receiver: receiver) { _, view in view }
            }
        }
        r.modifier("symbolRotation", .chart3D, introduced: iOS26) { m in
            m.owner = receiver
            m.form("_:Rotation3D", receiver: receiver) { _, view in view }
        }
        // Forms other families' modifiers gain on 3D content: what they do
        // there, the chart reads (`K3DMark`).
        let shared: [(String, [String])] = [
            ("foregroundStyle", ["_:ColorOrStyle", "by:any"]),
            ("symbol", ["_:any"]),
            ("symbolSize", ["_:any"]),
        ]
        for (name, sigs) in shared {
            guard let b = r.modifier(name) else { continue }
            let builder = KModifierBuilder(b)
            for sig in sigs { builder.form(sig, receiver: receiver, introduced: iOS26) { _, view in view } }
        }
        // `.foregroundStyle(.heightBased)` on a `SurfacePlot`.
        if let b = r.modifier("foregroundStyle"), b.styles == nil {
            KModifierBuilder(b).styles("Chart3DSurfaceStyle", ["heightBased", "normalBased"])
        }
    }

    // MARK: Values

    static func values(_ r: KRegistry) {
        r.type("Chart3DPose", .chart3D, support: .full, introduced: iOS26) { t in
            #if canImport(Charts) && !os(tvOS) && !os(watchOS)
            t.initializer("azimuth:any inclination:any") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { throw c.fail("Chart3DPose needs iOS 26") }
                return K3D.value(Chart3DPose(azimuth: K3D.angle(c["azimuth"]), inclination: K3D.angle(c["inclination"])))
            }
            t.anyStatic { c, name in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let pose = K3D.namedPose(name) else { return nil }
                return K3D.value(pose)
            }
            t.implicit { name, _, _ in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let pose = K3D.namedPose(name) else { return nil }
                return K3D.value(pose)
            }
            t.property("azimuth") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let p = K3D.pose(c.receiver) else { return .nilValue }
                return K3D.value(p.azimuth)
            }
            t.property("inclination") { c in
                guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let p = K3D.pose(c.receiver) else { return .nilValue }
                return K3D.value(p.inclination)
            }
            #endif
        }
        r.type("Angle2D", .chart3D, support: .full) { t in
            #if canImport(Spatial)
            t.initializer("degrees:number") { c in K3D.value(Angle2D(degrees: c.double("degrees") ?? 0)) }
            t.initializer("radians:number") { c in K3D.value(Angle2D(radians: c.double("radians") ?? 0)) }
            t.staticMethod("degrees", "_:number") { c in K3D.value(Angle2D(degrees: c.double(0) ?? 0)) }
            t.staticMethod("radians", "_:number") { c in K3D.value(Angle2D(radians: c.double(0) ?? 0)) }
            t.property("degrees") { c in .double(K3D.angle(c.receiver).degrees) }
            t.property("radians") { c in .double(K3D.angle(c.receiver).radians) }
            #endif
        }
        r.type("Rotation3D", .chart3D, support: .full) { t in
            #if canImport(Spatial)
            t.initializer("angle:any axis:any") { c in
                .native(.boxed(KBoxed("Rotation3D", K3D.rotation(angle: c["angle"], axis: c["axis"]))))
            }
            t.staticProperty("identity") { _ in .native(.boxed(KBoxed("Rotation3D", Rotation3D.identity))) }
            #endif
        }
        r.type("RotationAxis3D", .chart3D, support: .full) { t in
            t.initializer("x:number y:number z:number") { c in
                .native(.implicit("axis", [.double(c.double("x") ?? 0), .double(c.double("y") ?? 0), .double(c.double("z") ?? 0)]))
            }
            t.anyStatic { _, name in .native(.implicit(name, [])) }
        }
        r.type("Chart3DCameraProjection", .chart3D, support: .full, introduced: iOS26) { t in t.anyStatic { _, name in .native(.implicit(name, [])) } }
        r.type("BasicChart3DSymbolShape", .chart3D, support: .full, introduced: iOS26) { t in t.anyStatic { _, name in .native(.implicit(name, [])) } }
    }

    // MARK: Reading the chart

    #if canImport(Charts) && !os(tvOS) && !os(watchOS)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @MainActor static func chart3D(_ c: KCall) -> AnyView {
        let a = c.a, r = c.r
        var views: [KView] = []
        if let data = a.first, a.firstIsUnlabeled, !r.isFunction(data) {
            for e in (try? c.interp.sequence(data)) ?? [] { views += r.content(a.lastFunction, [e]).flatMap(\.flattened) }
        } else {
            for v in r.content(a.lastFunction).flatMap(\.flattened) {
                if v.primitiveName == "ForEach", case .primitive(_, let args, let labels, _) = v.kind {
                    for row in r.forEachRows(KArgs(args: args, labels: labels)) { views += row.views.flatMap(\.flattened) }
                } else {
                    views.append(v)
                }
            }
        }
        var marks: [K3DMark] = []
        var surfaces: [K3DSurface] = []
        var problem: String?
        for v in views {
            if let s = K3DSurface(view: v, renderer: r, index: surfaces.count) { surfaces.append(s); continue }
            guard let m = K3DMark(view: v, renderer: r) else { continue }
            // What Swift Charts would stop the whole app for, reported instead.
            if m.kind != "PointMark" {
                problem = problem ?? "a \(m.kind) in a Chart3D needs an extent Swift Charts only makes for binned values; use PointMark or SurfacePlot"
            } else if let axis = [m.x, m.y, m.z].first(where: { !$0.value.isNumber }) {
                problem = problem ?? "Chart3D plots numbers on every axis, and \"\(axis.label)\" isn't one"
            } else {
                marks.append(m)
            }
        }
        if let problem { c.interp.report(c.fail(problem)) }
        return AnyView(KChart3DView(marks: marks, surfaces: surfaces))
    }
    #endif
}

// MARK: - Values

@MainActor
enum K3D {
    /// Swift Charts sets a 3D chart's bindings from its own tasks, off the
    /// main thread, and while it draws: the app's state changes on the main
    /// thread, just after, and only when the value is new.
    nonisolated static func later(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }

    #if canImport(Spatial)
    static func value(_ a: Angle2D) -> KV { .native(.boxed(KBoxed("Angle2D", a))) }
    #endif
    #if canImport(Charts) && !os(tvOS) && !os(watchOS)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func value(_ p: Chart3DPose) -> KV { .native(.boxed(KBoxed("Chart3DPose", p))) }
    #endif

    #if canImport(Spatial)
    /// `.degrees(30)`, `Angle2D(degrees: 30)`, or SwiftUI's `Angle`.
    static func angle(_ v: KV?) -> Angle2D {
        if case .native(.boxed(let b))? = v, let a = b.get(Angle2D.self) { return a }
        if case .native(.implicit(let name, let args))? = v, let x = args.first?.asDouble {
            return name == "radians" ? Angle2D(radians: x) : Angle2D(degrees: x)
        }
        if case .native(.angle(let degrees))? = v { return Angle2D(degrees: degrees) }
        return Angle2D(degrees: v?.asDouble ?? 0)
    }

    static func rotation(angle: KV?, axis: KV?) -> Rotation3D {
        let a = Self.angle(angle)
        var vector = RotationAxis3D.y
        if case .native(.implicit(let name, let args))? = axis {
            switch name {
            case "x": vector = .x
            case "z": vector = .z
            case "xy": vector = .xy
            case "yz": vector = .yz
            case "xz": vector = .xz
            case "xyz": vector = .xyz
            case "axis" where args.count == 3:
                vector = RotationAxis3D(x: args[0].asDouble ?? 0, y: args[1].asDouble ?? 0, z: args[2].asDouble ?? 0)
            default: vector = .y
            }
        }
        return Rotation3D(angle: a, axis: vector)
    }
    #endif

    #if canImport(Charts) && !os(tvOS) && !os(watchOS)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func pose(_ v: KV?) -> Chart3DPose? {
        switch v {
        case .native(.boxed(let b))?: return b.get(Chart3DPose.self)
        case .native(.implicit(let name, _))?: return namedPose(name)
        default: return nil
        }
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    static func namedPose(_ name: String) -> Chart3DPose? {
        switch name {
        case "default": return .default
        case "front": return .front
        case "back": return .back
        case "top": return .top
        case "bottom": return .bottom
        case "left": return .left
        case "right": return .right
        default: return nil
        }
    }
    #endif
}
