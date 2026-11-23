//
//  Animators.swift
//  Bridges: phase and keyframe animators, springs and curves, content
//  transitions and symbol effects
//
//  `phaseAnimator` is SwiftUI's own: each phase is a Kiln value (`KV` is
//  `Equatable`), and the content closure runs the app's code with SwiftUI's
//  content, as a `ViewModifier`'s body does.
//
//  Keyframes run on SwiftUI's own `KeyframeTimeline`, one per number: a
//  track on `\.scale` is one timeline, on a `CGPoint` two, each with the
//  track's keyframes (linear, spring, cubic and move are each linear in
//  their components, so splitting is exact). A `TimelineView(.animation)`
//  plays them, and the app's content closure gets the value each frame.
//

import SwiftUI

extension DrawingBridges {
    static func animators(_ r: KRegistry) {
        phases(r)
        keyframes(r)
        springsAndCurves(r)
        contentTransitions(r)
        symbolEffects(r)
    }

    // MARK: Phase animators

    static func phases(_ r: KRegistry) {
        r.modifier("phaseAnimator", .drawing) { m in
            for sig in ["_:any content:closure animation:closure?", "_:any trigger:any content:closure animation:closure?"] {
                m.form(sig) { c, view in
                    if case .function(let content)? = c["content"] {
                        KPhaseHost(phases: (try? c.interp.sequence(c[0] ?? .array([]))) ?? [], trigger: c["trigger"], content: content,
                                   animation: c.function("animation"), base: view, interp: c.interp)
                    } else {
                        view
                    }
                }
            }
            m.probe { base, a, interp in
                let phases = (try? interp.sequence(a.first ?? .array([]))) ?? []
                var calls: [KProbeCall] = []
                if case .function(let fn)? = a["content"] {
                    for p in phases.prefix(4) { calls.append(KProbeCall(fn: fn, args: [KNativeContent.value(AnyView(EmptyView())), p])) }
                }
                if case .function(let fn)? = a["animation"] { for p in phases.prefix(4) { calls.append(KProbeCall(fn: fn, args: [p], use: .action)) } }
                return calls
            }
        }
        r.view("PhaseAnimator", .drawing) { v in
            for sig in ["_:any content:closure animation:closure?", "_:any trigger:any content:closure animation:closure?"] {
                v.form(sig) { c in
                    if case .function(let content)? = c["content"] {
                        KPhaseHost(phases: (try? c.interp.sequence(c[0] ?? .array([]))) ?? [], trigger: c["trigger"], content: content,
                                   animation: c.function("animation"), base: nil, interp: c.interp)
                    }
                }
            }
            v.probe { _, a, interp in
                let phases = (try? interp.sequence(a.first ?? .array([]))) ?? []
                var calls: [KProbeCall] = []
                if case .function(let fn)? = a["content"] { for p in phases.prefix(4) { calls.append(KProbeCall(fn: fn, args: [p])) } }
                if case .function(let fn)? = a["animation"] { for p in phases.prefix(4) { calls.append(KProbeCall(fn: fn, args: [p], use: .action)) } }
                return calls
            }
        }
    }

    // MARK: Keyframes

    static func keyframes(_ r: KRegistry) {
        for (name, sig) in [("KeyframeTrack", ["_:any content:content", "content:content"]),
                            ("LinearKeyframe", ["_:any duration:number timingCurve:UnitCurve?"]),
                            ("SpringKeyframe", ["_:any duration:number? spring:Spring? startVelocity:any?"]),
                            ("CubicKeyframe", ["_:any duration:number startVelocity:any? endVelocity:any?"]),
                            ("MoveKeyframe", ["_:any"])] {
            r.view(name, .drawing) { v in
                v.manifestKind = "content"
                v.forms(sig) { _ in EmptyView() }
            }
        }
        let modifierSigs = ["initialValue:any repeating:bool? content:closure keyframes:closure",
                            "initialValue:any trigger:any content:closure keyframes:closure"]
        r.modifier("keyframeAnimator", .drawing) { m in
            for sig in modifierSigs {
                m.form(sig) { c, view in keyframeHost(c, base: view) }
            }
            m.probe { _, a, interp in keyframeProbe(a, interp, modifier: true) }
        }
        r.view("KeyframeAnimator", .drawing) { v in
            for sig in modifierSigs {
                v.form(sig) { c in keyframeHost(c, base: nil) }
            }
            v.probe { _, a, interp in keyframeProbe(a, interp, modifier: false) }
        }
        r.type("KeyframeTimeline", .drawing, support: .full) { t in
            t.initializer("initialValue:any content:closure") { c in
                guard case .function(let fn)? = c["content"] else { throw c.fail("needs keyframes") }
                let initial = c["initialValue"] ?? .nilValue
                let plan = KKeyframes(initial: initial, tracks: try c.interp.entry { try c.interp.callBuilder(fn, []) }, interp: c.interp)
                return .native(.object("KeyframeTimeline", KRef(plan)))
            }
            t.property("duration") { c in .double(c.object(KKeyframes.self)?.duration ?? 0) }
            t.method("value", "time:number") { c in c.object(KKeyframes.self)?.value(at: c.double("time") ?? 0) ?? .nilValue }
            t.method("value", "progress:number") { c in
                guard let k = c.object(KKeyframes.self) else { return .nilValue }
                return k.value(at: (c.double("progress") ?? 0) * k.duration)
            }
        }
    }

    @MainActor static func keyframeHost(_ c: KCall, base: AnyView?) -> AnyView {
        guard case .function(let content)? = c["content"], case .function(let frames)? = c["keyframes"] else { return base ?? AnyView(EmptyView()) }
        return AnyView(KKeyframeHost(initial: c["initialValue"] ?? .nilValue, trigger: c["trigger"], repeating: c.bool("repeating", default: c["trigger"] == nil),
                                     content: content, keyframes: frames, base: base, interp: c.interp))
    }

    @MainActor static func keyframeProbe(_ a: KArgs, _ interp: KInterpreter, modifier: Bool) -> [KProbeCall] {
        let initial = a["initialValue"] ?? .nilValue
        var calls: [KProbeCall] = []
        if case .function(let fn)? = a["content"] {
            calls.append(KProbeCall(fn: fn, args: modifier ? [KNativeContent.value(AnyView(EmptyView())), initial] : [initial]))
        }
        if case .function(let fn)? = a["keyframes"] {
            calls.append(KProbeCall(fn: fn, args: [initial]))
        }
        return calls
    }

    // MARK: Springs and curves

    static func springsAndCurves(_ r: KRegistry) {
        @MainActor func wrap(_ s: Spring) -> KV { .native(.boxed(KBoxed("Spring", s))) }
        @MainActor func spring(_ c: KCall) -> Spring { c.receiver.boxed(Spring.self) ?? Spring() }
        r.type("Spring", .drawing, support: .full) { t in
            t.initializer("duration:number? bounce:number?") { c in wrap(Spring(duration: c.double("duration") ?? 0.5, bounce: c.double("bounce") ?? 0)) }
            t.initializer("mass:number? stiffness:number damping:number allowOverDamping:bool?") { c in
                wrap(Spring(mass: c.double("mass") ?? 1, stiffness: c.double("stiffness") ?? 100, damping: c.double("damping") ?? 10,
                            allowOverDamping: c.bool("allowOverDamping", default: false)))
            }
            t.initializer("response:number dampingRatio:number") { c in wrap(Spring(response: c.double("response") ?? 0.5, dampingRatio: c.double("dampingRatio") ?? 1)) }
            t.initializer("settlingDuration:number dampingRatio:number epsilon:number?") { c in
                wrap(Spring(settlingDuration: c.double("settlingDuration") ?? 1, dampingRatio: c.double("dampingRatio") ?? 1, epsilon: c.double("epsilon") ?? 0.001))
            }
            for (name, s) in [("bouncy", Spring.bouncy), ("smooth", .smooth), ("snappy", .snappy)] {
                t.staticProperty(name) { _ in wrap(s) }
            }
            for name in ["bouncy", "smooth", "snappy"] {
                t.staticMethod(name, "duration:number? extraBounce:number?") { c in
                    let d = c.double("duration") ?? 0.5, b = c.double("extraBounce") ?? 0
                    return wrap(name == "bouncy" ? .bouncy(duration: d, extraBounce: b) : (name == "smooth" ? .smooth(duration: d, extraBounce: b) : .snappy(duration: d, extraBounce: b)))
                }
            }
            t.implicit { name, args, labels in
                switch name {
                case "bouncy": return wrap(.bouncy)
                case "smooth": return wrap(.smooth)
                case "snappy": return wrap(.snappy)
                default: return nil
                }
            }
            t.property("duration") { c in .double(spring(c).duration) }
            t.property("bounce") { c in .double(spring(c).bounce) }
            t.property("response") { c in .double(spring(c).response) }
            t.property("dampingRatio") { c in .double(spring(c).dampingRatio) }
            t.property("settlingDuration") { c in .double(spring(c).settlingDuration) }
            t.property("mass") { c in .double(spring(c).mass) }
            t.property("stiffness") { c in .double(spring(c).stiffness) }
            t.property("damping") { c in .double(spring(c).damping) }
            t.method("value", "fromValue:number toValue:number initialVelocity:number time:number") { c in
                .double(spring(c).value(fromValue: c.double("fromValue") ?? 0, toValue: c.double("toValue") ?? 1,
                                        initialVelocity: c.double("initialVelocity") ?? 0, time: c.double("time") ?? 0))
            }
            t.method("value", "target:number initialVelocity:number? time:number") { c in
                .double(spring(c).value(target: c.double("target") ?? 1, initialVelocity: c.double("initialVelocity") ?? 0, time: c.double("time") ?? 0))
            }
            t.method("velocity", "target:number initialVelocity:number? time:number") { c in
                .double(spring(c).velocity(target: c.double("target") ?? 1, initialVelocity: c.double("initialVelocity") ?? 0, time: c.double("time") ?? 0))
            }
        }

        @MainActor func curve(_ v: KV) -> UnitCurve { v.boxed(UnitCurve.self) ?? .linear }
        @MainActor func wrapCurve(_ u: UnitCurve) -> KV { .native(.boxed(KBoxed("UnitCurve", u))) }
        r.type("UnitCurve", .drawing, support: .full) { t in
            let named: [String: UnitCurve] = ["linear": .linear, "easeIn": .easeIn, "easeOut": .easeOut, "easeInOut": .easeInOut,
                                              "circularEaseIn": .circularEaseIn, "circularEaseOut": .circularEaseOut, "circularEaseInOut": .circularEaseInOut]
            for (name, u) in named { t.staticProperty(name) { _ in wrapCurve(u) } }
            t.staticMethod("bezier", "startControlPoint:any endControlPoint:any") { c in
                wrapCurve(.bezier(startControlPoint: KCurves.unitPoint(c["startControlPoint"], c.r), endControlPoint: KCurves.unitPoint(c["endControlPoint"], c.r)))
            }
            t.implicit { name, args, _ in
                if let u = named[name] { return wrapCurve(u) }
                return nil
            }
            t.method("value", "at:number") { c in .double(curve(c.receiver).value(at: c.double("at") ?? 0)) }
            t.method("velocity", "at:number") { c in .double(curve(c.receiver).velocity(at: c.double("at") ?? 0)) }
            t.property("inverse") { c in wrapCurve(curve(c.receiver).inverse) }
        }
    }

    // MARK: Content transitions

    static func contentTransitions(_ r: KRegistry) {
        r.type("ContentTransition", .drawing, support: .full) { t in
            for name in ["identity", "interpolate", "opacity", "symbolEffect"] { t.staticProperty(name) { _ in .native(.implicit(name, [])) } }
            t.staticMethod("numericText", "countsDown:bool?") { c in .native(.implicit("numericText", c.args)) }
            t.staticMethod("numericText", "value:number") { c in .native(.implicit("numericText.value", c.args)) }
            t.staticMethod("symbolEffect", "_:any options:any?") { c in .native(.implicit("symbolEffect", c.args)) }
        }
    }

    @MainActor static func contentTransition(_ v: KV?, _ interp: KInterpreter) -> ContentTransition {
        guard case .native(.implicit(let name, let args))? = v else { return .opacity }
        switch name {
        case "identity": return .identity
        case "interpolate": return .interpolate
        case "opacity": return .opacity
        case "numericText":
            return .numericText(countsDown: args.first.map { interp.truthy($0) } ?? false)
        case "numericText.value":
            return .numericText(value: args.first?.asDouble ?? 0)
        case "symbolEffect":
            if let effect = args.first, case .native(.implicit(let e, _)) = effect, e.hasPrefix("replace") {
                return .symbolEffect(KSymbolEffects.replace(e))
            }
            return .symbolEffect
        default:
            return name.hasPrefix("numericText") ? .numericText() : .opacity
        }
    }

    // MARK: Symbol effects

    static func symbolEffects(_ r: KRegistry) {
        r.modifier("symbolEffect", .drawing, notes: "`.bounce`, `.pulse`, `.variableColor`, `.scale`, `.appear`, `.disappear`, `.breathe`, `.wiggle`, `.rotate` and `.drawOn`, with their directions and options.") { m in
            m.form("_:any options:any? value:any") { c, view in
                KSymbolEffects.discrete(view, c.symbol(0) ?? "bounce", KSymbolEffects.options(c["options"]), value: c["value"] ?? .nilValue)
            }
            m.form("_:any options:any? isActive:bool?") { c, view in
                KSymbolEffects.indefinite(view, c.symbol(0) ?? "pulse", KSymbolEffects.options(c["options"]), isActive: c.bool("isActive", default: true))
            }
        }
        r.modifier("symbolEffectsRemoved", .drawing) { m in
            m.form("_:bool?") { c, view in view.symbolEffectsRemoved(c.bool(0, default: true)) }
        }
        r.modifier("symbolVariant", .drawing) { m in
            m.form("_:SymbolVariants") { c, view in view.symbolVariant(KSymbolEffects.variants(c.symbol(0))) }
        }
        r.type("SymbolVariants", .drawing) { t in
            t.internal()
            t.anyStatic { _, name in .native(.implicit(name, [])) }
        }
        r.type("SymbolEffectOptions", .drawing) { t in
            t.internal()
            t.anyStatic { _, name in .native(.implicit(name, [])) }
            t.anyStaticMethod { c, name in .native(.implicit(name, c.args)) }
        }
    }
}

// MARK: - Curves

@MainActor
enum KCurves {
    static func unitPoint(_ v: KV?, _ r: KRenderer) -> UnitPoint {
        if case .native(.implicit("unitPoint", let a))? = v { return UnitPoint(x: a.first?.asDouble ?? 0, y: a.last?.asDouble ?? 0) }
        if case .native(.point(let x, let y))? = v { return UnitPoint(x: x, y: y) }
        return r.unitPoint(v) ?? .center
    }
}

// MARK: - Phase animator

/// SwiftUI's `phaseAnimator`, with the app's content and animation closures.
struct KPhaseHost: View {
    let phases: [KV]
    let trigger: KV?
    let content: KFunction
    let animation: KFunction?
    /// The view the modifier is on; nil for `PhaseAnimator`.
    let base: AnyView?
    let interp: KInterpreter

    var body: some View {
        if phases.isEmpty {
            base ?? AnyView(EmptyView())
        } else if let base {
            if let trigger {
                base.phaseAnimator(phases, trigger: trigger) { view, phase in show(phase, AnyView(view)) } animation: { anim($0) }
            } else {
                base.phaseAnimator(phases) { view, phase in show(phase, AnyView(view)) } animation: { anim($0) }
            }
        } else if let trigger {
            PhaseAnimator(phases, trigger: trigger) { phase in show(phase, nil) } animation: { anim($0) }
        } else {
            PhaseAnimator(phases) { phase in show(phase, nil) } animation: { anim($0) }
        }
    }

    func show(_ phase: KV, _ view: AnyView?) -> AnyView {
        let r = KRenderer(interp: interp)
        return r.renderContent(.function(content), view.map { [KNativeContent.value($0), phase] } ?? [phase])
    }

    func anim(_ phase: KV) -> Animation? {
        guard let animation else { return .default }
        let v = (try? interp.entry { try interp.call(animation, [phase], [nil]) }) ?? .nilValue
        if case .nilValue = v { return nil }
        return KRenderer(interp: interp).animation(v)
    }
}

// MARK: - Keyframes

/// The app's keyframes, as SwiftUI timelines: one per number of each track.
@MainActor
final class KKeyframes: NSObject {
    enum Frame {
        case linear(KV, Double, UnitCurve)
        case spring(KV, Double?, Spring, KV?)
        case cubic(KV, Double, KV?, KV?)
        case move(KV)
        var target: KV {
            switch self {
            case .linear(let v, _, _), .spring(let v, _, _, _), .cubic(let v, _, _, _), .move(let v): return v
            }
        }
    }
    struct Track {
        let path: [String]
        let template: KV
        let timelines: [KeyframeTimeline<Double>]
    }

    let initial: KV
    let interp: KInterpreter
    private(set) var tracks: [Track] = []
    private(set) var duration: Double = 0

    init(initial: KV, tracks views: [KView], interp: KInterpreter) {
        self.initial = initial
        self.interp = interp
        super.init()
        let r = KRenderer(interp: interp)
        for view in views.flatMap(\.flattened) {
            guard case .primitive("KeyframeTrack", let args, let labels, _) = view.kind else { continue }
            let a = KArgs(args: args, labels: labels)
            var path: [String] = []
            if case .native(.keyPath(let comps))? = a.first { path = comps.filter { $0 != "self" } }
            let start = read(initial, path)
            let frames = r.content(a.lastFunction).flatMap(\.flattened).compactMap { frame($0, r) }
            let components = Self.components(start)
            var timelines: [KeyframeTimeline<Double>] = []
            for i in components.indices {
                let parts = frames.map { Self.part($0, i) }
                timelines.append(KeyframeTimeline(initialValue: components[i]) {
                    KeyframeTrack {
                        for p in parts {
                            switch p {
                            case .linear(let to, let d, let curve): LinearKeyframe(to, duration: d, timingCurve: curve)
                            case .spring(let to, let d, let s, let v): SpringKeyframe(to, duration: d, spring: s, startVelocity: v)
                            case .cubic(let to, let d, let sv, let ev): CubicKeyframe(to, duration: d, startVelocity: sv, endVelocity: ev)
                            case .move(let to): MoveKeyframe(to)
                            }
                        }
                    }
                })
            }
            tracks.append(Track(path: path, template: start, timelines: timelines))
            duration = max(duration, timelines.map(\.duration).max() ?? 0)
        }
    }

    /// One number of a keyframe.
    enum Part {
        case linear(Double, Double, UnitCurve)
        case spring(Double, Double?, Spring, Double?)
        case cubic(Double, Double, Double?, Double?)
        case move(Double)
    }

    static func part(_ f: Frame, _ i: Int) -> Part {
        func at(_ v: KV?) -> Double? { v.map { components($0) }.flatMap { i < $0.count ? $0[i] : nil } }
        switch f {
        case .linear(let to, let d, let curve): return .linear(at(to) ?? 0, d, curve)
        case .spring(let to, let d, let s, let v): return .spring(at(to) ?? 0, d, s, at(v))
        case .cubic(let to, let d, let sv, let ev): return .cubic(at(to) ?? 0, d, at(sv), at(ev))
        case .move(let to): return .move(at(to) ?? 0)
        }
    }

    func frame(_ v: KView, _ r: KRenderer) -> Frame? {
        guard case .primitive(let name, let args, let labels, _) = v.kind else { return nil }
        let a = KArgs(args: args, labels: labels)
        let to = a.first ?? .double(0)
        switch name {
        case "LinearKeyframe": return .linear(to, a["duration"]?.asDouble ?? 0, a["timingCurve"]?.boxed(UnitCurve.self) ?? .linear)
        case "SpringKeyframe": return .spring(to, a["duration"]?.asDouble, a["spring"]?.boxed(Spring.self) ?? Spring(), a["startVelocity"])
        case "CubicKeyframe": return .cubic(to, a["duration"]?.asDouble ?? 0, a["startVelocity"], a["endVelocity"])
        case "MoveKeyframe": return .move(to)
        default: return nil
        }
    }

    /// The numbers a value animates: a number, an angle's degrees, a point's or size's two, a rect's four.
    static func components(_ v: KV) -> [Double] {
        switch v {
        case .int(let i): return [Double(i)]
        case .double(let d): return [d]
        case .native(.angle(let d)): return [d]
        case .native(.point(let x, let y)), .native(.size(let x, let y)): return [x, y]
        case .native(.rect(let x, let y, let w, let h)): return [x, y, w, h]
        default: return []
        }
    }

    static func rebuild(_ template: KV, _ c: [Double]) -> KV {
        switch template {
        case .int, .double: return .double(c.first ?? 0)
        case .native(.angle): return .native(.angle(c.first ?? 0))
        case .native(.point): return .native(.point(c[0], c[1]))
        case .native(.size): return .native(.size(c[0], c[1]))
        case .native(.rect): return .native(.rect(c[0], c[1], c[2], c[3]))
        default: return template
        }
    }

    func read(_ v: KV, _ path: [String]) -> KV {
        var out = v
        for p in path { out = (try? interp.member(out, p, line: 0)) ?? .nilValue }
        return out
    }

    /// The value at `time` seconds into the keyframes.
    func value(at time: Double) -> KV {
        let box = KBox(initial)
        for track in tracks {
            let v = Self.rebuild(track.template, track.timelines.map { $0.value(time: time) })
            if track.path.isEmpty { box.value = v; continue }
            var loc = KLocation.box(box)
            for p in track.path { loc = .member(loc, p) }
            try? interp.write(loc, v)
        }
        return box.value
    }
}

/// Plays the app's keyframes: restarts on `trigger`, or loops when `repeating`.
struct KKeyframeHost: View {
    let initial: KV
    let trigger: KV?
    let repeating: Bool
    let content: KFunction
    let keyframes: KFunction
    let base: AnyView?
    let interp: KInterpreter
    @State private var start: Date?
    @State private var plan: KKeyframes?
    @State private var held: KV?

    var body: some View {
        let running = start != nil
        TimelineView(.animation(paused: !running)) { timeline in
            show(value(at: timeline.date))
        }
        .onAppear { if repeating && trigger == nil { begin() } }
        .onChange(of: trigger ?? .nilValue) { _, _ in begin() }
    }

    func begin() {
        let from = held ?? initial
        let views = (try? interp.entry { try interp.callBuilder(keyframes, [from]) }) ?? []
        plan = KKeyframes(initial: from, tracks: views, interp: interp)
        start = Date()
    }

    func value(at date: Date) -> KV {
        guard let plan, let start else { return held ?? initial }
        var t = date.timeIntervalSince(start)
        if plan.duration <= 0 { return plan.value(at: 0) }
        if repeating {
            t = t.truncatingRemainder(dividingBy: plan.duration)
        } else if t >= plan.duration {
            let end = plan.value(at: plan.duration)
            DispatchQueue.main.async {
                held = end
                self.start = nil
            }
            return end
        }
        return plan.value(at: t)
    }

    func show(_ value: KV) -> AnyView {
        let r = KRenderer(interp: interp)
        return r.renderContent(.function(content), base.map { [KNativeContent.value($0), value] } ?? [value])
    }
}

// MARK: - Symbol effects

@MainActor
enum KSymbolEffects {
    static func options(_ v: KV?) -> SymbolEffectOptions {
        guard case .native(.implicit(let name, let args))? = v else { return .default }
        var o: SymbolEffectOptions = .default
        for part in name.split(separator: ".") {
            switch part {
            case "repeating": o = o.repeating
            case "nonRepeating": o = o.nonRepeating
            case "repeat":
                if let n = args.first?.asInt { o = o.repeat(n) }
                else if case .native(.implicit(let kind, let a))? = args.first, kind.hasPrefix("periodic"), #available(iOS 18, macOS 15, *) {
                    o = o.repeat(.periodic(a.first?.asInt, delay: a.last?.asDouble))
                } else if #available(iOS 18, macOS 15, *), case .native(.implicit("continuous", _))? = args.first {
                    o = o.repeat(.continuous)
                }
            case "speed": o = o.speed(args.last?.asDouble ?? 1)
            default: break
            }
        }
        return o
    }

    static func variants(_ name: String?) -> SymbolVariants {
        var v: SymbolVariants = .none
        for part in (name ?? "").split(separator: ".") {
            switch part {
            case "fill": v = v.fill
            case "circle": v = v.circle
            case "square": v = v.square
            case "rectangle": v = v.rectangle
            case "slash": v = v.slash
            default: break
            }
        }
        return v
    }

    static func replace(_ name: String) -> ReplaceSymbolEffect {
        var e: ReplaceSymbolEffect = .replace
        let parts = Set(name.split(separator: ".").map(String.init))
        if parts.contains("downUp") { e = e.downUp }
        if parts.contains("upUp") { e = e.upUp }
        if parts.contains("offUp") { e = e.offUp }
        if parts.contains("byLayer") { e = e.byLayer }
        if parts.contains("wholeSymbol") { e = e.wholeSymbol }
        return e
    }

    /// `.symbolEffect(.bounce, value: count)`: plays when `value` changes.
    static func discrete(_ view: AnyView, _ name: String, _ o: SymbolEffectOptions, value: KV) -> AnyView {
        let parts = Set(name.split(separator: ".").map(String.init))
        let base = String(name.split(separator: ".").first ?? "bounce")
        switch base {
        case "pulse":
            var e: PulseSymbolEffect = .pulse
            if parts.contains("byLayer") { e = e.byLayer }
            if parts.contains("wholeSymbol") { e = e.wholeSymbol }
            return AnyView(view.symbolEffect(e, options: o, value: value))
        case "variableColor":
            var e: VariableColorSymbolEffect = .variableColor
            if parts.contains("iterative") { e = e.iterative }
            if parts.contains("cumulative") { e = e.cumulative }
            if parts.contains("reversing") { e = e.reversing }
            if parts.contains("hideInactiveLayers") { e = e.hideInactiveLayers }
            if parts.contains("dimInactiveLayers") { e = e.dimInactiveLayers }
            return AnyView(view.symbolEffect(e, options: o, value: value))
        case "breathe", "wiggle", "rotate":
            if #available(iOS 18, macOS 15, *) {
                switch base {
                case "breathe":
                    var e: BreatheSymbolEffect = .breathe
                    if parts.contains("pulse") { e = e.pulse }
                    if parts.contains("plain") { e = e.plain }
                    if parts.contains("byLayer") { e = e.byLayer }
                    return AnyView(view.symbolEffect(e, options: o, value: value))
                case "wiggle":
                    return AnyView(view.symbolEffect(wiggle(parts), options: o, value: value))
                default:
                    var e: RotateSymbolEffect = .rotate
                    if parts.contains("clockwise") { e = e.clockwise }
                    if parts.contains("counterClockwise") { e = e.counterClockwise }
                    if parts.contains("byLayer") { e = e.byLayer }
                    return AnyView(view.symbolEffect(e, options: o, value: value))
                }
            }
            return view
        default:
            var e: BounceSymbolEffect = .bounce
            if parts.contains("up") { e = e.up }
            if parts.contains("down") { e = e.down }
            if parts.contains("byLayer") { e = e.byLayer }
            if parts.contains("wholeSymbol") { e = e.wholeSymbol }
            return AnyView(view.symbolEffect(e, options: o, value: value))
        }
    }

    @available(iOS 18, macOS 15, *)
    static func wiggle(_ parts: Set<String>) -> WiggleSymbolEffect {
        var e: WiggleSymbolEffect = .wiggle
        for (name, w) in [("up", WiggleSymbolEffect.wiggle.up), ("down", .wiggle.down), ("left", .wiggle.left), ("right", .wiggle.right),
                          ("forward", .wiggle.forward), ("backward", .wiggle.backward), ("clockwise", .wiggle.clockwise),
                          ("counterClockwise", .wiggle.counterClockwise)] where parts.contains(name) {
            e = w
        }
        if parts.contains("byLayer") { e = e.byLayer }
        return e
    }

    /// `.symbolEffect(.pulse)`, `.symbolEffect(.scale.up, isActive: x)`: runs while active.
    static func indefinite(_ view: AnyView, _ name: String, _ o: SymbolEffectOptions, isActive: Bool) -> AnyView {
        let parts = Set(name.split(separator: ".").map(String.init))
        let base = String(name.split(separator: ".").first ?? "pulse")
        switch base {
        case "variableColor":
            var e: VariableColorSymbolEffect = .variableColor
            if parts.contains("iterative") { e = e.iterative }
            if parts.contains("cumulative") { e = e.cumulative }
            if parts.contains("reversing") { e = e.reversing }
            if parts.contains("hideInactiveLayers") { e = e.hideInactiveLayers }
            if parts.contains("dimInactiveLayers") { e = e.dimInactiveLayers }
            return AnyView(view.symbolEffect(e, options: o, isActive: isActive))
        case "scale":
            var e: ScaleSymbolEffect = .scale
            if parts.contains("up") { e = e.up }
            if parts.contains("down") { e = e.down }
            if parts.contains("byLayer") { e = e.byLayer }
            return AnyView(view.symbolEffect(e, options: o, isActive: isActive))
        case "appear":
            var e: AppearSymbolEffect = .appear
            if parts.contains("up") { e = e.up }
            if parts.contains("down") { e = e.down }
            if parts.contains("byLayer") { e = e.byLayer }
            return AnyView(view.symbolEffect(e, options: o, isActive: isActive))
        case "disappear":
            var e: DisappearSymbolEffect = .disappear
            if parts.contains("up") { e = e.up }
            if parts.contains("down") { e = e.down }
            if parts.contains("byLayer") { e = e.byLayer }
            return AnyView(view.symbolEffect(e, options: o, isActive: isActive))
        case "breathe", "wiggle", "rotate", "bounce":
            if #available(iOS 18, macOS 15, *) {
                switch base {
                case "breathe": return AnyView(view.symbolEffect(BreatheSymbolEffect.breathe, options: o, isActive: isActive))
                case "wiggle": return AnyView(view.symbolEffect(wiggle(parts), options: o, isActive: isActive))
                case "rotate": return AnyView(view.symbolEffect(RotateSymbolEffect.rotate, options: o, isActive: isActive))
                default: return AnyView(view.symbolEffect(BounceSymbolEffect.bounce, options: o, isActive: isActive))
                }
            }
            return view
        case "drawOn", "drawOff":
            if #available(iOS 26, macOS 26, *) {
                if base == "drawOn" { return AnyView(view.symbolEffect(DrawOnSymbolEffect.drawOn, options: o, isActive: isActive)) }
                return AnyView(view.symbolEffect(DrawOffSymbolEffect.drawOff, options: o, isActive: isActive))
            }
            return view
        default:
            var e: PulseSymbolEffect = .pulse
            if parts.contains("byLayer") { e = e.byLayer }
            if parts.contains("wholeSymbol") { e = e.wholeSymbol }
            return AnyView(view.symbolEffect(e, options: o, isActive: isActive))
        }
    }
}
