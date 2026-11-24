//
//  Haptics.swift
//  Bridges: haptic feedback (PLAN.md §3.1)
//
//  `.sensoryFeedback` in all three forms is SwiftUI's own modifier, so the
//  phone plays what a compiled app plays, when it plays it:
//
//      .sensoryFeedback(.success, trigger: saved)
//      .sensoryFeedback(.impact(weight: .heavy), trigger: count) { old, new in new > old }
//      .sensoryFeedback(trigger: score) { old, new in new > old ? .increase : .decrease }
//
//  A `SensoryFeedback` is a value (`KFeedback`), compared by value, so an
//  app can keep one in its state and switch over it.
//
//  UIKit's three generators, which models write as often, play through
//  UIKit on the phone (`KHaptics.play`). A check (a stub context) plays
//  nothing; every feedback a run asks for is recorded in `KHaptics.played`
//  for tests.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One `SensoryFeedback`: its name and, for the forms that take them, their arguments.
struct KFeedback: Hashable, KDescribable {
    var name: String
    var weight: String?
    var flexibility: String?
    var intensity: Double = 1
    /// `.selection(.on)`, `.press(.button)`, `.release(.slider)` (iOS 26).
    var option: String?

    static let plain = ["success", "warning", "error", "selection", "increase", "decrease", "start", "stop",
                        "alignment", "levelChange", "pathComplete", "impact"]

    var kv: KV { .native(.boxed(KBoxed("SensoryFeedback", self, caseName: name))) }

    func describe(_ interp: KInterpreter) -> String {
        var args: [String] = []
        if let weight { args.append("weight: .\(weight)") }
        if let flexibility { args.append("flexibility: .\(flexibility)") }
        if intensity != 1 { args.append("intensity: \(intensity)") }
        if let option { args.append(".\(option)") }
        return "SensoryFeedback." + name + (args.isEmpty ? "" : "(" + args.joined(separator: ", ") + ")")
    }

    /// `.success`, `.impact(weight: .heavy, intensity: 0.5)`, `.selection(.on)`.
    static func make(_ name: String, _ args: [KV], _ labels: [String?]) -> KFeedback? {
        func symbol(_ label: String?) -> String? {
            guard let i = labels.firstIndex(where: { $0 == label }), i < args.count else { return label == nil ? args.first.flatMap(sym) : nil }
            return sym(args[i])
        }
        func number(_ label: String) -> Double? { labels.firstIndex(of: label).flatMap { $0 < args.count ? args[$0].asDouble : nil } }
        switch name {
        case "impact" where !args.isEmpty:
            var f = KFeedback(name: "impact")
            if let w = symbol("weight") { f.weight = w }
            if let fl = symbol("flexibility") { f.flexibility = fl }
            if f.flexibility == nil, f.weight == nil { f.weight = "medium" }
            f.intensity = number("intensity") ?? 1
            return f
        case "selection" where !args.isEmpty, "press", "release":
            guard let o = args.first.flatMap(sym) else { return nil }
            return KFeedback(name: name, option: o)
        default:
            return plain.contains(name) && args.isEmpty ? KFeedback(name: name) : nil
        }
    }

    static func sym(_ v: KV) -> String? {
        switch v {
        case .native(.implicit(let n, let a)) where a.isEmpty: return n
        case .native(.boxed(let b)): return b.caseName
        default: return nil
        }
    }

    /// The app's value: a `SensoryFeedback`, or the symbol a closure returned.
    @MainActor static func from(_ v: KV?) -> KFeedback? {
        switch v {
        case .native(.boxed(let b))?: return b.get(KFeedback.self)
        case .native(.implicit(let n, let a))?: return make(n, a, a.map { _ in nil })
        default: return nil
        }
    }

    var swiftUI: SensoryFeedback {
        switch name {
        case "success": return .success
        case "warning": return .warning
        case "error": return .error
        case "selection":
            #if os(iOS)
            if #available(iOS 26, *), let option {
                switch option {
                case "maximum": return .selection(.maximum)
                case "minimum": return .selection(.minimum)
                case "on": return .selection(.on)
                case "off": return .selection(.off)
                default: break
                }
            }
            #endif
            return .selection
        case "increase": return .increase
        case "decrease": return .decrease
        case "start": return .start
        case "stop": return .stop
        case "alignment": return .alignment
        case "levelChange": return .levelChange
        case "pathComplete":
            if #available(iOS 17.5, macOS 14.5, *) { return .pathComplete }
            return .success
        case "press":
            #if os(iOS)
            if #available(iOS 26, *) {
                switch option {
                case "buttonIconOnly": return .press(.buttonIconOnly)
                case "slider": return .press(.slider)
                case "toggle": return .press(.toggle)
                case "tab": return .press(.tab)
                default: return .press(.button)
                }
            }
            #endif
            return .impact(weight: .light)
        case "release":
            #if os(iOS)
            if #available(iOS 26, *) { return .release(.slider) }
            #endif
            return .impact(weight: .light)
        default:
            if let flexibility {
                let f: SensoryFeedback.Flexibility = flexibility == "rigid" ? .rigid : (flexibility == "soft" ? .soft : .solid)
                return .impact(flexibility: f, intensity: intensity)
            }
            if weight == nil && intensity == 1 { return .impact }
            let w: SensoryFeedback.Weight = weight == "light" ? .light : (weight == "heavy" ? .heavy : .medium)
            return .impact(weight: w, intensity: intensity)
        }
    }
}

/// UIKit's feedback generators, and what a run played.
@MainActor
enum KHaptics {
    /// Every feedback asked for, in order (`"impact(medium)"`, `"notification(success)"`,
    /// `"selection"`), in stub contexts too: what tests read.
    static var played: [String] = []

    final class Generator: KDescribable {
        let kind: String
        var style: String
        #if canImport(UIKit) && os(iOS)
        lazy var impact = UIImpactFeedbackGenerator(style: Self.impactStyle(style))
        lazy var notification = UINotificationFeedbackGenerator()
        lazy var selection = UISelectionFeedbackGenerator()
        static func impactStyle(_ s: String) -> UIImpactFeedbackGenerator.FeedbackStyle {
            switch s {
            case "light": return .light
            case "heavy": return .heavy
            case "soft": return .soft
            case "rigid": return .rigid
            default: return .medium
            }
        }
        #endif
        init(kind: String, style: String) {
            self.kind = kind
            self.style = style
        }
        func describe(_ interp: KInterpreter) -> String { kind }
    }

    static func play(_ g: Generator, _ what: String, _ c: KCall, intensity: Double? = nil, prepareOnly: Bool = false) {
        if !prepareOnly { played.append(what) }
        guard !c.context.isStub else { return }
        #if canImport(UIKit) && os(iOS)
        switch g.kind {
        case "UIImpactFeedbackGenerator":
            if prepareOnly { g.impact.prepare() }
            else if let intensity { g.impact.impactOccurred(intensity: CGFloat(intensity)) }
            else { g.impact.impactOccurred() }
        case "UINotificationFeedbackGenerator":
            if prepareOnly { g.notification.prepare(); return }
            let type: UINotificationFeedbackGenerator.FeedbackType = what.contains("warning") ? .warning : (what.contains("error") ? .error : .success)
            g.notification.notificationOccurred(type)
        default:
            if prepareOnly { g.selection.prepare() } else { g.selection.selectionChanged() }
        }
        #endif
    }

    /// The app's closure, called where SwiftUI asks (a condition, a feedback).
    static func ask(_ interp: KInterpreter, _ f: KFunction, _ args: [KV]) -> KV? {
        do {
            return try interp.entry { try interp.call(f, args, args.map { _ in nil }) }
        } catch {
            interp.report(error)
            return nil
        }
    }
}

@objc(KilnBridges_Haptics)
final class HapticsBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        feedback(r)
        generators(r)
    }

    static func feedback(_ r: KRegistry) {
        r.type("SensoryFeedback", .haptics, support: .full,
               notes: "`.success`, `.warning`, `.error`, `.selection`, `.increase`, `.decrease`, `.start`, `.stop`, `.alignment`, `.levelChange`, `.pathComplete`, `.impact(weight:intensity:)`, `.impact(flexibility:intensity:)`; iOS 26's `.press`, `.release` and `.selection(_:)`.") { t in
            t.membersInManifest = true
            for name in KFeedback.plain { t.staticProperty(name) { _ in KFeedback(name: name).kv } }
            t.staticMethod("impact", "weight:SensoryFeedback.Weight? intensity:number?") { c in
                KFeedback.make("impact", c.args, c.labels)?.kv ?? KFeedback(name: "impact").kv
            }
            t.staticMethod("impact", "flexibility:SensoryFeedback.Flexibility intensity:number?") { c in
                KFeedback.make("impact", c.args, c.labels)?.kv ?? KFeedback(name: "impact").kv
            }
            t.staticMethod("selection", "_:SensoryFeedback.SelectionFeedback", introduced: "26.0") { c in
                KFeedback.make("selection", c.args, c.labels)?.kv ?? KFeedback(name: "selection").kv
            }
            t.staticMethod("press", "_:SensoryFeedback.PressFeedback", introduced: "26.0") { c in
                KFeedback.make("press", c.args, c.labels)?.kv ?? KFeedback(name: "press", option: "button").kv
            }
            t.staticMethod("release", "_:SensoryFeedback.ReleaseFeedback", introduced: "26.0") { c in
                KFeedback.make("release", c.args, c.labels)?.kv ?? KFeedback(name: "release", option: "slider").kv
            }
            t.implicit { name, args, labels in KFeedback.make(name, args, labels)?.kv }
            t.property("description") { c in .string(c.interp.describe(c.receiver)) }
        }
        // The arguments' own types: symbols the feedback reads.
        for (type, names) in [("SensoryFeedback.Weight", ["light", "medium", "heavy"]),
                              ("SensoryFeedback.Flexibility", ["rigid", "solid", "soft"]),
                              ("SensoryFeedback.SelectionFeedback", ["maximum", "minimum", "on", "off"]),
                              ("SensoryFeedback.PressFeedback", ["button", "buttonIconOnly", "slider", "toggle", "tab"]),
                              ("SensoryFeedback.ReleaseFeedback", ["slider"])] {
            r.type(type, .haptics, support: .full) { t in
                for n in names { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
                t.implicit { name, args, _ in names.contains(name) && args.isEmpty ? .native(.implicit(name, [])) : nil }
            }
        }

        r.modifier("sensoryFeedback", .haptics,
                   notes: "SwiftUI's own: plays when `trigger` changes (and `condition` says so, or the closure returns a feedback).") { m in
            m.form("_:SensoryFeedback trigger:any") { c, view in
                view.sensoryFeedback((KFeedback.from(c[0]) ?? KFeedback(name: "impact")).swiftUI, trigger: c["trigger"] ?? .void)
            }
            m.form("_:SensoryFeedback trigger:any condition:closure") { c, view in
                let fb = (KFeedback.from(c[0]) ?? KFeedback(name: "impact")).swiftUI
                if let f = c.function("condition") {
                    let interp = c.interp
                    view.sensoryFeedback(fb, trigger: c["trigger"] ?? .void) { old, new in
                        KHaptics.ask(interp, f, [old, new]).map { interp.truthy($0) } ?? false
                    }
                } else {
                    view.sensoryFeedback(fb, trigger: c["trigger"] ?? .void)
                }
            }
            m.form("trigger:any _:closure") { c, view in
                if let f = c.function(0) {
                    let interp = c.interp
                    let n = c.r.closureParamCount(.function(f))
                    view.sensoryFeedback(trigger: c["trigger"] ?? .void) { old, new in
                        KFeedback.from(KHaptics.ask(interp, f, n == 0 ? [] : [old, new]))?.swiftUI
                    }
                } else {
                    view
                }
            }
            // A check calls the closures as SwiftUI would: with the trigger as old and new value.
            m.probe { base, args, interp in
                guard let trigger = args["trigger"] else { return [] }
                return args.args.compactMap { v -> KProbeCall? in
                    guard case .function(let f) = v else { return nil }
                    let n = KRenderer(interp: interp).closureParamCount(v)
                    return KProbeCall(fn: f, args: n == 0 ? [] : [trigger, trigger], use: .action)
                }
            }
        }
    }

    static func generators(_ r: KRegistry) {
        @MainActor func gen(_ c: KCall) -> KHaptics.Generator? { c.object(KHaptics.Generator.self) }
        @MainActor func make(_ kind: String, _ style: String) -> KV { .native(.object(kind, KRef(KHaptics.Generator(kind: kind, style: style)))) }
        let note = "Plays through UIKit, as compiled; a check plays nothing."

        r.type("UIImpactFeedbackGenerator", .haptics, support: .full, notes: note) { t in
            t.initializer("") { _ in make("UIImpactFeedbackGenerator", "medium") }
            t.initializer("style:UIImpactFeedbackGenerator.FeedbackStyle") { c in make("UIImpactFeedbackGenerator", c.symbol("style") ?? "medium") }
            t.initializer("style:UIImpactFeedbackGenerator.FeedbackStyle view:any") { c in make("UIImpactFeedbackGenerator", c.symbol("style") ?? "medium") }
            t.method("impactOccurred", "") { c in
                if let g = gen(c) { KHaptics.play(g, "impact(\(g.style))", c) }
                return .void
            }
            t.method("impactOccurred", "intensity:number") { c in
                if let g = gen(c) { KHaptics.play(g, "impact(\(g.style), \(c.double("intensity") ?? 1))", c, intensity: c.double("intensity")) }
                return .void
            }
            t.method("impactOccurred", "at:CGPoint") { c in
                if let g = gen(c) { KHaptics.play(g, "impact(\(g.style))", c) }
                return .void
            }
            t.method("impactOccurred", "intensity:number at:CGPoint") { c in
                if let g = gen(c) { KHaptics.play(g, "impact(\(g.style), \(c.double("intensity") ?? 1))", c, intensity: c.double("intensity")) }
                return .void
            }
            t.method("prepare", "") { c in
                if let g = gen(c) { KHaptics.play(g, "", c, prepareOnly: true) }
                return .void
            }
        }
        r.type("UIImpactFeedbackGenerator.FeedbackStyle", .haptics, support: .full) { t in
            let styles = ["light", "medium", "heavy", "soft", "rigid"]
            for s in styles { t.staticProperty(s) { _ in .native(.implicit(s, [])) } }
            t.implicit { name, args, _ in styles.contains(name) && args.isEmpty ? .native(.implicit(name, [])) : nil }
        }

        r.type("UINotificationFeedbackGenerator", .haptics, support: .full, notes: note) { t in
            t.initializer("") { _ in make("UINotificationFeedbackGenerator", "") }
            t.initializer("view:any") { _ in make("UINotificationFeedbackGenerator", "") }
            for sig in ["_:UINotificationFeedbackGenerator.FeedbackType", "_:UINotificationFeedbackGenerator.FeedbackType at:CGPoint"] {
                t.method("notificationOccurred", sig) { c in
                    if let g = gen(c) { KHaptics.play(g, "notification(\(c.symbol(0) ?? "success"))", c) }
                    return .void
                }
            }
            t.method("prepare", "") { c in
                if let g = gen(c) { KHaptics.play(g, "", c, prepareOnly: true) }
                return .void
            }
        }
        r.type("UINotificationFeedbackGenerator.FeedbackType", .haptics, support: .full) { t in
            let types = ["success", "warning", "error"]
            for s in types { t.staticProperty(s) { _ in .native(.implicit(s, [])) } }
            t.implicit { name, args, _ in types.contains(name) && args.isEmpty ? .native(.implicit(name, [])) : nil }
        }

        r.type("UISelectionFeedbackGenerator", .haptics, support: .full, notes: note) { t in
            t.initializer("") { _ in make("UISelectionFeedbackGenerator", "") }
            t.initializer("view:any") { _ in make("UISelectionFeedbackGenerator", "") }
            t.method("selectionChanged", "") { c in
                if let g = gen(c) { KHaptics.play(g, "selection", c) }
                return .void
            }
            t.method("selectionChanged", "at:CGPoint") { c in
                if let g = gen(c) { KHaptics.play(g, "selection", c) }
                return .void
            }
            t.method("prepare", "") { c in
                if let g = gen(c) { KHaptics.play(g, "", c, prepareOnly: true) }
                return .void
            }
        }
    }
}
