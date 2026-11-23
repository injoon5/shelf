//
//  Formatting.swift
//  Bridges: formatting numbers and dates
//
//  `String(format:)`, `value.formatted(style)`, `Text(value, format:)` and
//  `"\(value, format:)"`, with Swift's and Foundation's rules.
//

import SwiftUI

@MainActor
enum KFormatting {
    /// `String(format:)` with Swift's argument types.
    static func format(_ fmt: String, _ args: [KV], _ interp: KInterpreter) -> String {
        var cargs: [CVarArg] = []
        var specs: [Character] = []
        var i = fmt.startIndex
        while i < fmt.endIndex {
            if fmt[i] == "%" {
                var j = fmt.index(after: i)
                while j < fmt.endIndex, !"dDiuUxXoOfFeEgGcsS@%".contains(fmt[j]) { j = fmt.index(after: j) }
                if j < fmt.endIndex, fmt[j] != "%" { specs.append(fmt[j]) }
                i = j < fmt.endIndex ? fmt.index(after: j) : j
            } else { i = fmt.index(after: i) }
        }
        for (k, a) in args.enumerated() {
            let spec: Character = k < specs.count ? specs[k] : "@"
            switch spec {
            case "d", "D", "i", "u", "U", "x", "X", "o", "O", "c":
                cargs.append(a.asInt ?? Int(a.asDouble ?? 0))
            case "f", "F", "e", "E", "g", "G":
                cargs.append(a.asDouble ?? 0)
            default:
                cargs.append(interp.describe(a))
            }
        }
        let normalized = fmt.replacingOccurrences(of: "%s", with: "%@").replacingOccurrences(of: "%S", with: "%@")
        return String(format: normalized, arguments: cargs)
    }

    /// `value.formatted(style)`.
    static func formatted(_ v: KV, _ style: KV, _ interp: KInterpreter) -> String {
        if case .native(.date(let d)) = v {
            if case .native(.format(let f)) = style, f.kind == .dateTime, !f.components.isEmpty {
                var fs = Date.FormatStyle()
                for c in f.components {
                    switch c {
                    case "hour": fs = fs.hour()
                    case "minute": fs = fs.minute()
                    case "second": fs = fs.second()
                    case "day": fs = fs.day()
                    case "month": fs = fs.month()
                    case "year": fs = fs.year()
                    case "weekday": fs = fs.weekday()
                    default: break
                    }
                }
                return d.formatted(fs)
            }
            if case .native(.implicit(let s, _)) = style {
                switch s {
                case "relative": return d.formatted(.relative(presentation: .named))
                case "time": return d.formatted(date: .omitted, time: .shortened)
                case "date": return d.formatted(date: .abbreviated, time: .omitted)
                default: break
                }
            }
            return d.formatted()
        }
        guard let x = v.asDouble else { return interp.describe(v) }
        let isInt: Bool = { if case .int = v { return true }; return false }()
        guard case .native(.format(let f)) = style else {
            if case .native(.implicit(let n, let a)) = style, let resolved = interp.resolveImplicit(n, a, expectedType: nil),
               case .native(.format) = resolved {
                return formatted(v, resolved, interp)
            }
            return isInt ? Int(x).formatted() : x.formatted()
        }
        switch f.kind {
        case .currency(let code):
            var s = FloatingPointFormatStyle<Double>.Currency(code: code)
            if let r = f.fraction { s = s.precision(.fractionLength(r)) }
            return x.formatted(s)
        case .percent:
            var s = FloatingPointFormatStyle<Double>.Percent()
            if let r = f.fraction { s = s.precision(.fractionLength(r)) }
            return (isInt ? x / 100 : x).formatted(s)
        default:
            if isInt && f.fraction == nil { return Int(x).formatted(.number.grouping(f.grouping ? .automatic : .never)) }
            var s = FloatingPointFormatStyle<Double>.number.grouping(f.grouping ? .automatic : .never)
            if let r = f.fraction { s = s.precision(.fractionLength(r)) }
            return x.formatted(s)
        }
    }
}
