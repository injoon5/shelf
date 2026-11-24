//
//  Clocks.swift
//  Bridges: Duration and the clocks (Round 2C)
//
//  `Duration` is Swift's own value (`.seconds(90)`, arithmetic, comparison,
//  `components`, `formatted()`), and `ContinuousClock`/`SuspendingClock`
//  give real instants (`now`, `advanced(by:)`, `duration(to:)`, `measure`).
//

import SwiftUI

/// A `Duration`.
struct KDuration: Hashable, KDescribable {
    let d: Duration
    var seconds: Double { Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18 }
    var kv: KV { .native(.boxed(KBoxed("Duration", self))) }
    func describe(_ interp: KInterpreter) -> String { String(describing: d) }

    static func from(_ v: KV?) -> Duration? {
        switch v {
        case .native(.boxed(let b))?: return (b.value.base as? KDuration)?.d
        case .native(.implicit(let unit, let args))?: return make(unit, args.first)
        default: return nil
        }
    }

    static func make(_ unit: String, _ n: KV?) -> Duration? {
        guard let n else { return unit == "zero" ? .zero : nil }
        let isInt: Bool = { if case .int = n { return true }; return false }()
        let x = n.asDouble ?? 0
        switch unit {
        case "seconds": return isInt ? .seconds(Int(x)) : .seconds(x)
        case "milliseconds": return isInt ? .milliseconds(Int(x)) : .milliseconds(x)
        case "microseconds": return isInt ? .microseconds(Int(x)) : .microseconds(x)
        case "nanoseconds": return .nanoseconds(Int(x))
        default: return nil
        }
    }
}

/// An instant of a clock.
struct KInstant: Hashable, KDescribable {
    let continuous: ContinuousClock.Instant?
    let suspending: SuspendingClock.Instant?
    var kv: KV { .native(.boxed(KBoxed(continuous != nil ? "ContinuousClock.Instant" : "SuspendingClock.Instant", self))) }
    func describe(_ interp: KInterpreter) -> String {
        continuous.map { String(describing: $0) } ?? suspending.map { String(describing: $0) } ?? "Instant"
    }
    static func from(_ v: KV?) -> KInstant? {
        if case .native(.boxed(let b))? = v { return b.value.base as? KInstant }
        return nil
    }
    func advanced(by d: Duration) -> KInstant {
        KInstant(continuous: continuous?.advanced(by: d), suspending: suspending?.advanced(by: d))
    }
    func duration(to other: KInstant) -> Duration? {
        if let a = continuous, let b = other.continuous { return a.duration(to: b) }
        if let a = suspending, let b = other.suspending { return a.duration(to: b) }
        return nil
    }
    static func < (a: KInstant, b: KInstant) -> Bool? {
        if let x = a.continuous, let y = b.continuous { return x < y }
        if let x = a.suspending, let y = b.suspending { return x < y }
        return nil
    }
}

extension ConcurrencyBridges {
    static func clocks(_ r: KRegistry) {
        r.type("Duration", .concurrency, support: .full,
               notes: "`.seconds(_:)`, `.milliseconds(_:)`…, `+ - * /`, comparison, `components`, `formatted()` (`.units`, `.time`); `Task.sleep(for:)` takes one.") { t in
            for unit in ["seconds", "milliseconds", "microseconds", "nanoseconds"] {
                t.staticMethod(unit, "_:number") { c in KDuration.make(unit, c.first).map { KDuration(d: $0).kv } ?? .nilValue }
            }
            t.staticProperty("zero") { _ in KDuration(d: .zero).kv }
            t.implicit { name, args, _ in
                if name == "zero", args.isEmpty { return KDuration(d: .zero).kv }
                guard args.count == 1 else { return nil }
                return KDuration.make(name, args[0]).map { KDuration(d: $0).kv }
            }
            @MainActor func d(_ c: KCall) -> Duration { KDuration.from(c.receiver) ?? .zero }
            t.property("components") { c in
                let comps = d(c).components
                return .tuple([.int(Int(comps.seconds)), .int(Int(comps.attoseconds))], ["seconds", "attoseconds"])
            }
            t.property("description") { c in .string(String(describing: d(c))) }
            t.method("formatted", "_:any?") { c in .string(KDurationFormat.format(d(c), c.first, c.interp)) }
            for op in ["+", "-"] {
                t.operator(op) { a, b, _ in
                    guard let x = KDuration.from(a), let y = KDuration.from(b) else { return nil }
                    return KDuration(d: op == "+" ? x + y : x - y).kv
                }
            }
            t.operator("*") { a, b, _ in
                if let x = KDuration.from(a), let n = b.asInt, case .int = b { return KDuration(d: x * n).kv }
                if let x = KDuration.from(a), let n = b.asDouble { return KDuration(d: x * n).kv }
                if let x = KDuration.from(b), let n = a.asInt, case .int = a { return KDuration(d: x * n).kv }
                return nil
            }
            t.operator("/") { a, b, _ in
                guard let x = KDuration.from(a) else { return nil }
                if let y = KDuration.from(b) { return .double(x / y) }
                if case .int(let n) = b { return KDuration(d: x / n).kv }
                if let n = b.asDouble { return KDuration(d: x / n).kv }
                return nil
            }
            t.operator("<") { a, b, _ in
                guard let x = KDuration.from(a), let y = KDuration.from(b) else { return nil }
                return .bool(x < y)
            }
            t.operator("prefix-") { a, _, _ in KDuration.from(a).map { KDuration(d: .zero - $0).kv } }
        }
        r.addLiteralCoercion("Duration") { v, _ in
            if case .native(.implicit) = v { return KDuration.from(v).map { KDuration(d: $0).kv } }
            return nil
        }

        for (name, isContinuous) in [("ContinuousClock", true), ("SuspendingClock", false)] {
            @MainActor func now() -> KV {
                isContinuous ? KInstant(continuous: .now, suspending: nil).kv : KInstant(continuous: nil, suspending: .now).kv
            }
            r.type(name, .concurrency, support: .full, notes: isContinuous ? "`ContinuousClock.now`, `clock.now`, instants' `advanced(by:)`, `duration(to:)` and `-`, and `measure { … }`." : nil) { t in
                t.initializer("") { _ in .native(.object(name, KRef(NSObject()))) }
                t.staticProperty("now") { _ in now() }
                t.property("now") { _ in now() }
                t.property("minimumResolution") { _ in KDuration(d: .nanoseconds(1)).kv }
                t.method("measure", "_:closure") { c in
                    guard case .function(let f)? = c.first else { throw c.fail("needs a closure") }
                    let start = ContinuousClock.now
                    _ = try c.interp.call(f, [], [])
                    return KDuration(d: start.duration(to: .now)).kv
                }
            }
            r.type(name + ".Instant", .concurrency, support: .full) { t in
                t.staticProperty("now") { _ in now() }
                t.method("advanced", "by:any") { c in
                    guard let i = KInstant.from(c.receiver), let d = KDuration.from(c["by"]) else { throw c.fail("needs a Duration") }
                    return i.advanced(by: d).kv
                }
                t.method("duration", "to:any") { c in
                    guard let i = KInstant.from(c.receiver), let j = KInstant.from(c["to"]), let d = i.duration(to: j) else { throw c.fail("needs an instant of the same clock") }
                    return KDuration(d: d).kv
                }
                t.operator("<") { a, b, _ in
                    guard let x = KInstant.from(a), let y = KInstant.from(b), let lt = x < y else { return nil }
                    return .bool(lt)
                }
                t.operator("-") { a, b, _ in
                    guard let x = KInstant.from(a) else { return nil }
                    if let y = KInstant.from(b), let d = y.duration(to: x) { return KDuration(d: d).kv }
                    if let d = KDuration.from(b) { return x.advanced(by: .zero - d).kv }
                    return nil
                }
                t.operator("+") { a, b, _ in
                    guard let x = KInstant.from(a), let d = KDuration.from(b) else { return nil }
                    return x.advanced(by: d).kv
                }
            }
        }
    }
}

/// `duration.formatted(…)`: `.units(allowed:width:)`, `.time(pattern:)`, or the default.
@MainActor
enum KDurationFormat {
    static func format(_ d: Duration, _ style: KV?, _ interp: KInterpreter) -> String {
        guard case .native(.implicit(let name, let args))? = style else { return d.formatted() }
        switch name {
        case "time":
            let pattern: Duration.TimeFormatStyle.Pattern
            switch args.first.flatMap(symbol) {
            case "hourMinute": pattern = .hourMinute
            case "minuteSecond": pattern = .minuteSecond
            default: pattern = .hourMinuteSecond
            }
            return d.formatted(.time(pattern: pattern))
        case "units":
            var allowed: Set<Duration.UnitsFormatStyle.Unit> = [.hours, .minutes, .seconds]
            var width: Duration.UnitsFormatStyle.UnitWidth = .abbreviated
            for a in args {
                if case .array(let us) = a {
                    let mapped = us.compactMap(symbol).compactMap(unit)
                    if !mapped.isEmpty { allowed = Set(mapped) }
                } else if let s = symbol(a) {
                    switch s {
                    case "wide": width = .wide
                    case "narrow": width = .narrow
                    case "condensedAbbreviated": width = .condensedAbbreviated
                    default: width = .abbreviated
                    }
                }
            }
            return d.formatted(.units(allowed: allowed, width: width))
        default:
            return d.formatted()
        }
    }

    static func symbol(_ v: KV) -> String? {
        if case .native(.implicit(let n, _)) = v { return n }
        return nil
    }

    static func unit(_ s: String) -> Duration.UnitsFormatStyle.Unit? {
        switch s {
        case "weeks": return .weeks
        case "days": return .days
        case "hours": return .hours
        case "minutes": return .minutes
        case "seconds": return .seconds
        case "milliseconds": return .milliseconds
        default: return nil
        }
    }
}
