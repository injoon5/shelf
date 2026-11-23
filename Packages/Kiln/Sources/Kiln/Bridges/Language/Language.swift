//
//  Language.swift
//  Bridges: Swift's standard library
//
//  The global functions (`print`, `min`, `zip`, `stride` …), numbers and
//  `Bool`. Strings are in Strings.swift; arrays, sets, dictionaries, ranges and
//  what every sequence has are in Collections.swift.
//
//  The standard library's methods take their arguments loosely (a nil
//  signature): Kiln has always accepted `prefix(3)` and `prefix(while:)` from
//  one bridge that reads what's there.
//

import SwiftUI

@objc(KilnBridges_Language)
final class LanguageBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        globals(r)
        numbers(r)
        strings(r)
        collections(r)
    }

    // MARK: Global functions

    static func globals(_ r: KRegistry) {
        r.addConstant("pi") { _ in .double(.pi) }

        for name in ["print", "debugPrint", "NSLog"] {
            r.function(name, .language, owner: name == "NSLog" ? "Foundation" : "Swift") { c in
                let sep = c.arg("separator")?.asString ?? " "
                let items = zip(c.args, c.labels).filter { $0.1 == nil }.map { c.interp.describe($0.0) }
                c.interp.console += items.joined(separator: sep) + (c.arg("terminator")?.asString ?? "\n")
                return .void
            }
        }
        for name in ["min", "max"] {
            r.function(name, .language) { c in
                var vals = zip(c.args, c.labels).filter { $0.1 == nil }.map(\.0)
                if vals.count == 1, let a = vals[0].asArray { vals = a }
                guard var best = vals.first else { return .nilValue }
                for v in vals.dropFirst() where try c.interp.compare(name == "min" ? "<" : ">", v, best, c.line) { best = v }
                if vals.contains(where: { if case .double = $0 { return true }; return false }), let d = best.asDouble { return .double(d) }
                return best
            }
        }
        r.function("abs", .language) { c in
            if case .int(let i)? = c.first { return .int(abs(i)) }
            return .double(abs(c.first?.asDouble ?? 0))
        }
        let unary: [String: (Double) -> Double] = ["sqrt": sqrt, "floor": floor, "ceil": ceil, "round": { $0.rounded() },
            "sin": sin, "cos": cos, "tan": tan, "exp": exp, "log": log, "log2": log2, "log10": log10, "atan": atan,
            "asin": asin, "acos": acos, "trunc": trunc, "cbrt": cbrt]
        for (name, f) in unary {
            r.function(name, .language, owner: "Foundation") { c in .double(f(c.first?.asDouble ?? 0)) }
        }
        let binary: [String: (Double, Double) -> Double] = ["pow": pow, "atan2": atan2, "hypot": hypot]
        for (name, f) in binary {
            r.function(name, .language, owner: "Foundation") { c in .double(f(c.at(0)?.asDouble ?? 0, c.at(1)?.asDouble ?? 0)) }
        }
        r.function("fmod", .language, owner: "Foundation") { c in .double(fmod(c.at(0)?.asDouble ?? 0, c.at(1)?.asDouble ?? 1)) }
        r.function("zip", .language) { c in
            let a = try c.interp.sequence(c.at(0) ?? .nilValue), b = try c.interp.sequence(c.at(1) ?? .nilValue)
            return .array(zip(a, b).map { .tuple([$0, $1], [nil, nil]) })
        }
        r.function("stride", .language) { c in
            guard let from = c.arg("from"), let by = c.arg("by") else { throw c.interp.fail("stride needs from:, to:/through:, by:", c.line) }
            let through = c.arg("through"), to = c.arg("to")
            if case .int(let f) = from, case .int(let s) = by, let end = (through ?? to)?.asInt {
                if through != nil { return .array(Array(stride(from: f, through: end, by: s)).map { .int($0) }) }
                return .array(Array(stride(from: f, to: end, by: s)).map { .int($0) })
            }
            let f = from.asDouble ?? 0, s = by.asDouble ?? 1, e = (through ?? to)?.asDouble ?? 0
            if through != nil { return .array(Array(stride(from: f, through: e, by: s)).map { .double($0) }) }
            return .array(Array(stride(from: f, to: e, by: s)).map { .double($0) })
        }
        r.function("type", .language) { c in .type(.builtin(c.first?.typeName ?? "Any")) }
        for name in ["fatalError", "preconditionFailure", "assertionFailure"] {
            r.function(name, .language) { c in throw c.interp.fail("Fatal error: \(c.first.map { c.interp.describe($0) } ?? "")", c.line) }
        }
        for name in ["precondition", "assert"] {
            r.function(name, .language) { c in
                if let cond = c.first, !c.interp.truthy(cond) {
                    throw c.interp.fail("Assertion failed: \(c.args.count > 1 ? c.interp.describe(c.args[1]) : "")", c.line)
                }
                return .void
            }
        }
        r.function("swap", .language) { c in
            if case .binding(let a)? = c.first, case .binding(let b)? = c.last {
                let t = a.get(); a.set(b.get()); b.set(t)
            }
            return .void
        }
        r.function("repeatElement", .language) { c in .array(Array(repeating: c.at(0) ?? .void, count: c.arg("count")?.asInt ?? 0)) }
    }

    // MARK: Numbers and Bool

    static func numbers(_ r: KRegistry) {
        r.type("Int", .language, support: .full) { t in
            t.initializer { c in
                switch c.first {
                case .int(let i)?: return .int(i)
                case .double(let d)?: return d.isFinite ? .int(Int(d)) : .nilValue
                case .string(let s)?: return Int(s.trimmingCharacters(in: .whitespaces)).map { .int($0) } ?? .nilValue
                case .bool(let b)?: return .int(b ? 1 : 0)
                default: return .int(0)
                }
            }
            t.staticProperties(["max": .int(.max), "min": .int(.min), "zero": .int(0)])
            t.staticMethod("random") { c in try random(c, isInt: true) }
            t.property("description") { c in .string(String(c.receiver.asInt ?? 0)) }
            t.property("magnitude") { c in
                let i = c.receiver.asInt ?? 0
                return .int(i.magnitude > UInt(Int.max) ? Int.max : Int(i.magnitude))
            }
            t.property("isZero") { c in .bool(c.receiver.asInt == 0) }
            t.property("signum") { c in .int((c.receiver.asInt ?? 0).signum()) }
            t.method("isMultiple") { c in .bool((c.receiver.asInt ?? 0).isMultiple(of: (c.arg("of") ?? c.at(0))?.asInt ?? 1)) }
            t.method("formatted") { c in .string(KFormatting.formatted(c.receiver, c.first ?? .nilValue, c.interp)) }
            t.method("advanced") { c in .int((c.receiver.asInt ?? 0) + ((c.arg("by") ?? c.at(0))?.asInt ?? 0)) }
            t.method("distance") { c in .int(((c.arg("to") ?? c.at(0))?.asInt ?? 0) - (c.receiver.asInt ?? 0)) }
            t.method("quotientAndRemainder") { c in
                let (q, rem) = (c.receiver.asInt ?? 0).quotientAndRemainder(dividingBy: (c.arg("dividingBy") ?? c.at(0))?.asInt ?? 1)
                return .tuple([.int(q), .int(rem)], ["quotient", "remainder"])
            }
            t.method("clamped") { c in
                let i = c.receiver.asInt ?? 0
                guard case .range(let lo, let hi, _)? = c.arg("to") else { throw c.noMember() }
                return .int(min(max(i, lo.asInt ?? i), hi.asInt ?? i))
            }
            // The rest of a number's methods, as a Double (`rounded`, `squareRoot`).
            t.fallback("FloatingPoint") { v, _ in .double(Double(v.asInt ?? 0)) }
        }
        for alias in ["Int64", "Int32", "UInt", "Int16", "Int8"] { r.alias(alias, to: "Int") }

        r.type("Double", .language, support: .full) { t in
            t.initializer { c in
                switch c.first {
                case .int(let i)?: return .double(Double(i))
                case .double(let d)?: return .double(d)
                case .string(let s)?: return Double(s.trimmingCharacters(in: .whitespaces)).map { .double($0) } ?? .nilValue
                default: return .double(0)
                }
            }
            t.staticProperties(["pi": .double(.pi), "infinity": .double(.infinity), "greatestFiniteMagnitude": .double(.greatestFiniteMagnitude),
                                "leastNormalMagnitude": .double(.leastNormalMagnitude), "nan": .double(.nan), "zero": .double(0)])
            t.staticMethod("random") { c in try random(c, isInt: false) }
            t.implicit { name, _, _ in
                switch name {
                case "infinity": return .double(.infinity)
                case "zero": return .double(0)
                case "pi": return .double(.pi)
                default: return nil
                }
            }
            t.property("description") { c in .string(String(describing: c.receiver.asDouble ?? 0)) }
            t.property("magnitude") { c in .double((c.receiver.asDouble ?? 0).magnitude) }
            t.property("isNaN") { c in .bool((c.receiver.asDouble ?? 0).isNaN) }
            t.property("isFinite") { c in .bool((c.receiver.asDouble ?? 0).isFinite) }
            t.property("isInfinite") { c in .bool((c.receiver.asDouble ?? 0).isInfinite) }
            t.property("isZero") { c in .bool(c.receiver.asDouble == 0) }
            t.fallback("FloatingPoint") { v, _ in v }
        }
        for alias in ["CGFloat", "Float", "TimeInterval", "Float64"] { r.alias(alias, to: "Double") }

        // What Int and Double share, as Double's (an Int arrives converted).
        r.type("FloatingPoint", .language, support: .full) { t in
            t.namespace()
            t.method("rounded") { c in
                let d = c.receiver.asDouble ?? 0
                guard case .native(.implicit(let rule, _))? = c.first else { return .double(d.rounded()) }
                switch rule {
                case "up": return .double(d.rounded(.up))
                case "down": return .double(d.rounded(.down))
                case "towardZero": return .double(d.rounded(.towardZero))
                case "awayFromZero": return .double(d.rounded(.awayFromZero))
                case "toNearestOrEven": return .double(d.rounded(.toNearestOrEven))
                default: return .double(d.rounded())
                }
            }
            t.method("squareRoot") { c in .double((c.receiver.asDouble ?? 0).squareRoot()) }
            t.method("truncatingRemainder") { c in
                .double((c.receiver.asDouble ?? 0).truncatingRemainder(dividingBy: (c.arg("dividingBy") ?? c.first)?.asDouble ?? 1))
            }
            t.method("remainder") { c in .double((c.receiver.asDouble ?? 0).remainder(dividingBy: c.first?.asDouble ?? 1)) }
            t.method("formatted") { c in .string(KFormatting.formatted(c.receiver, c.first ?? .nilValue, c.interp)) }
            t.method("isMultiple") { c in .bool(fmod(c.receiver.asDouble ?? 0, c.first?.asDouble ?? 1) == 0) }
            t.method("clamped") { c in
                let d = c.receiver.asDouble ?? 0
                guard case .range(let lo, let hi, _)? = c.first else { throw c.noMember() }
                return .double(min(max(d, lo.asDouble ?? d), hi.asDouble ?? d))
            }
            t.method("description") { c in .string(String(describing: c.receiver.asDouble ?? 0)) }
        }

        r.type("Bool", .language, support: .full) { t in
            t.initializer { c in
                if case .string(let s)? = c.first { return s == "true" ? .bool(true) : (s == "false" ? .bool(false) : .nilValue) }
                return .bool(c.first.map { c.interp.truthy($0) } ?? false)
            }
            t.staticMethod("random") { c in .bool(Bool.random(using: &c.interp.rng)) }
            t.property("description") { c in .string(c.receiver.asBool == true ? "true" : "false") }
            t.property("toggled") { c in .bool(!(c.receiver.asBool ?? false)) }
            t.method("toggle") { c in
                c.mutated = .bool(!(c.receiver.asBool ?? false))
                return .void
            }
        }
    }

    /// `Int.random(in:)`, `Double.random(in:)`: from the run's seeded generator.
    static func random(_ c: KCall, isInt: Bool) throws -> KV {
        guard case .range(let lo, let hi, let closed)? = c.arg("in") ?? c.first else { return .int(0) }
        if isInt, let l = lo.asInt, let h = hi.asInt {
            if closed ? l > h : l >= h { throw c.interp.fail("Int.random(in:) needs a non-empty range", c.line) }
            return .int(closed ? Int.random(in: l...h, using: &c.interp.rng) : Int.random(in: l..<h, using: &c.interp.rng))
        }
        let l = lo.asDouble ?? 0, h = hi.asDouble ?? 1
        return .double(closed ? Double.random(in: l...h, using: &c.interp.rng) : Double.random(in: l..<h, using: &c.interp.rng))
    }
}
