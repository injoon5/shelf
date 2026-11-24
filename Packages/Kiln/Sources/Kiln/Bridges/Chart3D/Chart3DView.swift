//
//  Chart3DView.swift
//  Bridges: the 3D chart itself, and SurfacePlot's sampler (PLAN.md §3.7)
//

import SwiftUI
#if canImport(Charts) && !os(tvOS) && !os(watchOS)
import Charts
#if canImport(Spatial)
import Spatial
#endif

/// One axis's value: a number or a category.
enum K3DValue: Hashable {
    case number(Double)
    case text(String)
}

/// What a 3D mark's modifiers ask for.
struct K3DStyle {
    var color: AnyShapeStyle?
    var by: (label: String, value: K3DValue)?
    var surface: String?            // "heightBased", "normalBased"
    var metalness: Double?
    var roughness: Double?
    var symbol: String?             // "sphere", "cube", "cylinder", "cone"
    var symbolSize: CGFloat?
    var rotation: Rotation3D?

    @MainActor
    init(_ modifiers: [KModifier], renderer r: KRenderer) {
        for m in modifiers {
            switch m.name {
            case "foregroundStyle":
                if let v = m.arg("by"), let p = K3DMark.plottable(v, r) {
                    by = p
                } else if case .native(.implicit(let name, _))? = m.first, ["heightBased", "normalBased"].contains(name) {
                    surface = name
                } else if let s = r.shapeStyle(m.first) {
                    color = s
                }
            case "metalness": metalness = m.first?.asDouble
            case "roughness": roughness = m.first?.asDouble
            case "symbol":
                if case .native(.implicit(let name, _))? = m.first { symbol = name }
            case "symbolSize": symbolSize = m.first?.cg
            case "symbolRotation":
                if case .native(.boxed(let b))? = m.first { rotation = b.get(Rotation3D.self) }
            default: break
            }
        }
    }
}

/// A `PointMark`, `RuleMark` or `RectangleMark` with `x:y:z:`.
struct K3DMark: Identifiable {
    let id = UUID()
    let kind: String
    let x: (label: String, value: K3DValue)
    let y: (label: String, value: K3DValue)
    let z: (label: String, value: K3DValue)
    let style: K3DStyle

    @MainActor
    init?(view: KView, renderer r: KRenderer) {
        let (node, modifiers) = K3DMark.unwrap(view)
        guard case .primitive(let name, let args, let labels, _) = node.kind,
              ["PointMark", "RuleMark", "RectangleMark"].contains(name) else { return nil }
        let a = KArgs(args: args, labels: labels)
        guard let x = a["x"].flatMap({ K3DMark.plottable($0, r) }), let y = a["y"].flatMap({ K3DMark.plottable($0, r) }),
              let z = a["z"].flatMap({ K3DMark.plottable($0, r) }) else { return nil }
        kind = name
        self.x = x
        self.y = y
        self.z = z
        style = K3DStyle(modifiers, renderer: r)
    }

    /// The node under its modifiers, and the modifiers innermost first.
    static func unwrap(_ view: KView) -> (KView, [KModifier]) {
        var modifiers: [KModifier] = []
        var node = view
        while case .modified(let inner, let m) = node.kind { modifiers.insert(m, at: 0); node = inner }
        return (node, modifiers)
    }

    /// `.value("Label", v)`.
    @MainActor
    static func plottable(_ v: KV, _ r: KRenderer) -> (label: String, value: K3DValue)? {
        guard case .native(.implicit("value", let pa)) = v, pa.count >= 2 else { return nil }
        let label = r.string(pa[0]) ?? ""
        switch pa[1] {
        case .int(let i): return (label, .number(Double(i)))
        case .double(let d): return (label, .number(d))
        case .native(.date(let d)): return (label, .number(d.timeIntervalSinceReferenceDate))
        default: return (label, .text(r.string(pa[1]) ?? r.interp.describe(pa[1])))
        }
    }
}

/// A `SurfacePlot`: its labels, the app's function, and its style.
struct K3DSurface: Identifiable {
    let id: Int
    let labels: (x: String, y: String, z: String)
    let function: KFunction
    let interp: KInterpreter
    let style: K3DStyle

    @MainActor
    init?(view: KView, renderer r: KRenderer, index: Int = 0) {
        let (node, modifiers) = K3DMark.unwrap(view)
        guard case .primitive("SurfacePlot", let args, let labels, _) = node.kind else { return nil }
        let a = KArgs(args: args, labels: labels)
        guard case .function(let f)? = a["function"] ?? a.lastFunction else { return nil }
        id = index
        self.labels = (r.string(a["x"]) ?? "x", r.string(a["y"]) ?? "y", r.string(a["z"]) ?? "z")
        function = f
        interp = r.interp
        style = K3DStyle(modifiers, renderer: r)
    }
}

// MARK: - The chart

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct KChart3DView: View {
    let marks: [K3DMark]
    let surfaces: [K3DSurface]
    @State private var samplers = KSurfaceSamplers()

    var body: some View {
        // Reading `revision` redraws the chart when a grid is ready.
        let _ = samplers.revision
        let fitted = surfaces.enumerated().map { i, s in (s, samplers.sampler(i, for: s, marks: marks)) }
        Chart3D {
            ForEach(marks) { m in
                K3DMarkContent(mark: m)
            }
            // A new grid is new content, or Swift Charts keeps the surface it drew.
            ForEach(fitted, id: \.1.identity) { surface, sampler in
                K3DSurfaceContent(surface: surface, sampler: sampler)
            }
        }
    }
}

/// A `PointMark(x:y:z:)`. The chart has checked its values are numbers.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct K3DMarkContent: Chart3DContent {
    let mark: K3DMark

    var body: some Chart3DContent {
        K3DStyled(content: PointMark(x: .value(mark.x.label, mark.x.value.number),
                                     y: .value(mark.y.label, mark.y.value.number),
                                     z: .value(mark.z.label, mark.z.value.number)),
                  style: mark.style)
    }
}

extension K3DValue {
    var number: Double { if case .number(let n) = self { return n }; return 0 }
    var isNumber: Bool { if case .number = self { return true }; return false }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct K3DSurfaceContent: Chart3DContent {
    let surface: K3DSurface
    let sampler: KSurfaceSampler

    var body: some Chart3DContent {
        let s = sampler
        K3DStyled(content: SurfacePlot(x: surface.labels.x, y: surface.labels.y, z: surface.labels.z) { x, z in s.value(x, z) },
                  style: surface.style)
    }
}

/// A mark with the modifiers its description asked for.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
struct K3DStyled<C: Chart3DContent>: Chart3DContent {
    let content: C
    let style: K3DStyle

    var body: some Chart3DContent {
        material(symbol(colored(content)))
    }

    @Chart3DContentBuilder
    func colored<T: Chart3DContent>(_ c: T) -> some Chart3DContent {
        if let surface = style.surface {
            c.foregroundStyle(surface == "normalBased" ? .normalBased : .heightBased)
        } else if let by = style.by {
            switch by.value {
            case .number(let n): c.foregroundStyle(by: .value(by.label, n))
            case .text(let s): c.foregroundStyle(by: .value(by.label, s))
            }
        } else if let color = style.color {
            c.foregroundStyle(color)
        } else {
            c
        }
    }

    @Chart3DContentBuilder
    func symbol<T: Chart3DContent>(_ c: T) -> some Chart3DContent {
        if let name = style.symbol {
            sized(rotated(c.symbol(name == "cube" ? .cube : name == "cylinder" ? .cylinder : name == "cone" ? .cone : .sphere)))
        } else {
            sized(rotated(c))
        }
    }

    @Chart3DContentBuilder
    func rotated<T: Chart3DContent>(_ c: T) -> some Chart3DContent {
        if let r = style.rotation { c.symbolRotation(r) } else { c }
    }

    @Chart3DContentBuilder
    func sized<T: Chart3DContent>(_ c: T) -> some Chart3DContent {
        if let s = style.symbolSize { c.symbolSize(s) } else { c }
    }

    @Chart3DContentBuilder
    func material<T: Chart3DContent>(_ c: T) -> some Chart3DContent {
        if let m = style.metalness, let r = style.roughness { c.metalness(m).roughness(r) }
        else if let m = style.metalness { c.metalness(m) }
        else if let r = style.roughness { c.roughness(r) }
        else { c }
    }
}

#endif

// MARK: - SurfacePlot's sampler

/// The chart's samplers, one per `SurfacePlot`, kept across redraws.
@MainActor
@Observable
final class KSurfaceSamplers {
    /// Bumped when a grid is ready, so the chart redraws with it.
    var revision = 0
    @ObservationIgnored private var made: [Int: KSurfaceSampler] = [:]

    func sampler(_ index: Int, for surface: KSurfaceAppFunction, marks: [KSurfaceDomainHint]) -> KSurfaceSampler {
        let s = made[index] ?? {
            let s = KSurfaceSampler { [weak self] in self?.revision += 1 }
            made[index] = s
            return s
        }()
        s.use(surface.function, surface.interp, hint: KSurfaceSampler.domain(of: marks))
        return s
    }
}

/// What a sampler needs of a `SurfacePlot`.
@MainActor
protocol KSurfaceAppFunction {
    var function: KFunction { get }
    var interp: KInterpreter { get }
}

/// What a sampler can learn the domain from before Swift Charts asks.
protocol KSurfaceDomainHint {
    var xNumber: Double? { get }
    var zNumber: Double? { get }
}

#if canImport(Charts) && !os(tvOS) && !os(watchOS)
extension K3DSurface: KSurfaceAppFunction {}
extension K3DMark: KSurfaceDomainHint {
    var xNumber: Double? { if case .number(let n) = x.value { return n }; return nil }
    var zNumber: Double? { if case .number(let n) = z.value { return n }; return nil }
}
#endif

/// Samples the app's surface function on a grid of at most `side` × `side`
/// points, and answers Swift Charts' 256 × 256 calls by interpolating it.
///
/// The domain is the one Swift Charts asks about: it's guessed at first (the
/// other marks' extent, or −1…1, Swift Charts' own default), and when a
/// call falls outside it, the calls' extent is sampled and the chart drawn
/// again. A new function (the app's state changed) is sampled at once, on
/// the main thread, in the chart's `body`. While new functions come quickly
/// (a slider being dragged), the grid is `coarse` per side, a quarter of the
/// calls, and the full grid follows once they stop.
final class KSurfaceSampler: @unchecked Sendable {
    /// Points per side. 2,304 calls of the app's function per sampling:
    /// 17 ms for a line of trigonometry on an M2 Pro, where Swift Charts'
    /// own 256 × 256 would take 500 ms a pass (Benchmarks/README.md, §3.7).
    static let side = 48
    /// Points per side while the function keeps changing.
    static let coarse = 24
    /// New functions this close together are "coming quickly".
    static let settle: TimeInterval = 0.25

    struct Grid {
        var n: Int                 // points per side
        var x0: Double, x1: Double, z0: Double, z1: Double
        var values: [Double]       // n × n, row by row in z
    }

    private let lock = NSLock()
    private var grid: Grid?
    /// Bumped with each grid, so the chart draws the surface again.
    @MainActor private(set) var generation = 0
    @MainActor var identity: String { "\(ObjectIdentifier(self).hashValue)-\(generation)" }
    /// The extent of the calls since the grid was made, and whether one missed it.
    private var seen: (x0: Double, x1: Double, z0: Double, z1: Double)?
    private var missed = false
    private var resampleScheduled = false
    private let redraw: @MainActor () -> Void
    @MainActor private var function: KFunction?
    @MainActor private weak var interp: KInterpreter?
    @MainActor private var lastNewFunction: TimeInterval = -.infinity
    @MainActor private var refine: DispatchWorkItem?

    init(redraw: @escaping @MainActor () -> Void) { self.redraw = redraw }

    /// The domain the other marks suggest, or Swift Charts' default.
    static func domain(of marks: [KSurfaceDomainHint]) -> (Double, Double, Double, Double) {
        let xs = marks.compactMap(\.xNumber), zs = marks.compactMap(\.zNumber)
        let x = xs.isEmpty ? (-1.0, 1.0) : (xs.min()!, xs.max()!)
        let z = zs.isEmpty ? (-1.0, 1.0) : (zs.min()!, zs.max()!)
        return (x.0, x.1 > x.0 ? x.1 : x.0 + 1, z.0, z.1 > z.0 ? z.1 : z.0 + 1)
    }

    /// The function the app's chart has now: sampled at once if it's new.
    @MainActor
    func use(_ f: KFunction, _ interp: KInterpreter, hint: (Double, Double, Double, Double)) {
        guard f !== function else { return }
        function = f
        self.interp = interp
        let current = lock.withLock { grid.map { ($0.x0, $0.x1, $0.z0, $0.z1) } }
        let now = ProcessInfo.processInfo.systemUptime
        let quick = now - lastNewFunction < Self.settle
        lastNewFunction = now
        sample(over: current ?? hint, side: quick ? Self.coarse : Self.side)
        if quick { scheduleRefine() }
    }

    /// The full grid, once the function has stopped changing.
    @MainActor
    private func scheduleRefine() {
        refine?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let g = self.lock.withLock({ self.grid }), g.n < Self.side else { return }
                self.sample(over: (g.x0, g.x1, g.z0, g.z1))
                self.redraw()
            }
        }
        refine = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: work)
    }

    /// Swift Charts' call: the grid, interpolated.
    func value(_ x: Double, _ z: Double) -> Double {
        lock.lock()
        defer { lock.unlock() }
        if let s = seen { seen = (min(s.x0, x), max(s.x1, x), min(s.z0, z), max(s.z1, z)) } else { seen = (x, x, z, z) }
        guard let g = grid else { scheduleResample(); return 0 }
        // Swift Charts samples a little past the domain's ends: within 2% is in.
        let mx = (g.x1 - g.x0) * 0.02, mz = (g.z1 - g.z0) * 0.02
        if x < g.x0 - mx || x > g.x1 + mx || z < g.z0 - mz || z > g.z1 + mz { missed = true; scheduleResample() }
        return Self.interpolate(g, x, z)
    }

    static func interpolate(_ g: Grid, _ x: Double, _ z: Double) -> Double {
        let n = g.n
        let fx = min(max((x - g.x0) / max(g.x1 - g.x0, .ulpOfOne), 0), 1) * Double(n - 1)
        let fz = min(max((z - g.z0) / max(g.z1 - g.z0, .ulpOfOne), 0), 1) * Double(n - 1)
        let i = min(Int(fx), n - 2), j = min(Int(fz), n - 2)
        let tx = fx - Double(i), tz = fz - Double(j)
        let v00 = g.values[j * n + i], v10 = g.values[j * n + i + 1]
        let v01 = g.values[(j + 1) * n + i], v11 = g.values[(j + 1) * n + i + 1]
        return (v00 * (1 - tx) + v10 * tx) * (1 - tz) + (v01 * (1 - tx) + v11 * tx) * tz
    }

    /// Called with the lock held.
    private func scheduleResample() {
        guard !resampleScheduled else { return }
        resampleScheduled = true
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                let (extent, wasMissed) = lock.withLock { () -> ((Double, Double, Double, Double)?, Bool) in
                    resampleScheduled = false
                    defer { missed = false }
                    return (seen.map { ($0.x0, $0.x1, $0.z0, $0.z1) }, missed || grid == nil)
                }
                guard wasMissed, let extent, extent.0 < extent.1, extent.2 < extent.3 else { return }
                sample(over: extent)
                redraw()
            }
        }
    }

    /// The app's function on the grid, on the main thread.
    @MainActor
    func sample(over d: (Double, Double, Double, Double), side n: Int = KSurfaceSampler.side) {
        guard let function, let interp else { return }
        var values = [Double](repeating: 0, count: n * n)
        var failed = false
        // Swift Charts calls the function while it draws: a counter it bumps
        // is the app's business, not a reason to draw the app again.
        interp.holdingGlobalRedraws { interp.entry {
            for j in 0..<n where !failed {
                let z = d.2 + (d.3 - d.2) * Double(j) / Double(n - 1)
                for i in 0..<n {
                    let x = d.0 + (d.1 - d.0) * Double(i) / Double(n - 1)
                    do {
                        let v = try interp.call(function, [.double(x), .double(z)], [nil, nil])
                        values[j * n + i] = v.asDouble ?? 0
                    } catch {
                        interp.report(error)
                        failed = true
                        break
                    }
                }
            }
        } }
        generation += 1
        lock.withLock {
            grid = Grid(n: n, x0: d.0, x1: d.1, z0: d.2, z1: d.3, values: values)
            seen = nil
            missed = false
        }
    }
}
