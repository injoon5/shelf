//
//  Round1Core.swift
//  Bridges: Core's rest (PLAN.md §2): `TimelineView`'s schedules, the
//  macros the engine reads, `LocalizedStringKey` and the app protocols
//

import SwiftUI

extension CoreBridges {
    static func round1(_ r: KRegistry) {
        timeline(r)
        r.macro("Entry", .core, notes: "In `extension EnvironmentValues`, `FocusedValues`, `ContainerValues` or `Transaction`.")
        r.macro("Animatable", .core, notes: "On a `Shape`, view or `ViewModifier`: its number, point, size, rect and angle properties animate.")
        r.macro("AnimatableIgnored", .core)
        r.macro("State", .core, notes: "As the property wrapper.")
        r.type("LocalizedStringKey", .core, support: .full) { t in
            t.initializer("_:string") { c in .string(c.string(0) ?? "") }
            t.initializer("stringLiteral:string") { c in .string(c.string("stringLiteral") ?? "") }
        }
        r.protocolBridge("DynamicProperty", .core, requirements: ["update()?"], support: .partial,
                         notes: "Your own property wrappers can adopt it; `update()` isn't called, and `@State` inside one isn't kept.")
        r.protocolBridge("AnimatableModifier", .drawing, requirements: ["body(content:)", "animatableData?"], support: .full,
                         notes: "Deprecated in SwiftUI: an `Animatable` `ViewModifier`, which animates the same way.") { app in
            KModifierProxy(app: app)
        }
        r.protocolBridge("VectorArithmetic", .drawing, requirements: ["static zero", "static +", "static -", "scale(by:)", "magnitudeSquared"],
                         support: .full, notes: "Your own `animatableData` type animates through its stored numbers.")
    }

    // MARK: TimelineView

    static func timeline(_ r: KRegistry) {
        r.view("TimelineView", .core, notes: "`.animation`, `.periodic(from:by:)`, `.everyMinute` and `.explicit(dates)`; the closure gets `context.date`.") { v in
            v.form("_:any content:content") { c in
                let fn = c.contentValue(nil)
                let r = c.r
                let show: (TimelineViewDefaultContext) -> AnyView = { ctx in
                    let cadence: String = ctx.cadence == .live ? "live" : (ctx.cadence == .seconds ? "seconds" : "minutes")
                    return r.renderContent(fn, [.tuple([.native(.date(ctx.date)), .native(.implicit(cadence, []))], ["date", "cadence"])])
                }
                switch c[0] {
                case .native(.implicit(let name, let args))?:
                    let a = KArgs(args: args, labels: args.map { _ in nil })
                    switch name {
                    case "animation":
                        let minimum = args.first?.asDouble
                        let paused = args.count > 1 ? c.interp.truthy(args[1]) : false
                        TimelineView(.animation(minimumInterval: minimum, paused: paused)) { show($0) }
                    case "everyMinute":
                        TimelineView(.everyMinute) { show($0) }
                    case "explicit":
                        let dates = (a.first?.asArray ?? []).compactMap { v -> Date? in if case .native(.date(let d)) = v { return d }; return nil }
                        TimelineView(.explicit(dates)) { show($0) }
                    default:
                        let start: Date = { if case .native(.date(let d))? = a.first { return d }; return .now }()
                        TimelineView(.periodic(from: start, by: args.last?.asDouble ?? 1)) { show($0) }
                    }
                default:
                    TimelineView(.animation) { show($0) }
                }
            }
        }
    }
}
