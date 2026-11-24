//
//  ParseStrategies.swift
//  Bridges: parsing text into numbers, money and dates, and Decimal (PLAN.md §3.3)
//
//      let when = try Date("2026-11-24T09:30:00Z", strategy: .iso8601)
//      let day = try Date("Nov 24, 2026", strategy: .dateTime.month().day().year())
//      let total = try Decimal("$1,234.50", format: .currency(code: "USD"))
//      let share = try Double("45%", format: .percent)
//
//  Each is Foundation's own parse strategy, so what parses (and what
//  throws) is what a compiled app sees. `Int`, `Double` and `Date` are other
//  families' types: their initializers send `format:` and `strategy:` here.
//  `Decimal` is Foundation's, with its own arithmetic, so `0.1 + 0.2` is
//  exactly `0.3`.
//

import SwiftUI

/// A `Decimal`, Foundation's own.
struct KDecimal: Hashable, KDescribable {
    var d: Decimal
    init(_ d: Decimal) { self.d = d }
    var kv: KV { .native(.boxed(KBoxed("Decimal", self))) }
    func describe(_ interp: KInterpreter) -> String { d.description }
    var double: Double { NSDecimalNumber(decimal: d).doubleValue }

    static func from(_ v: KV?) -> Decimal? {
        switch v {
        case .native(.boxed(let b))?: return b.get(KDecimal.self)?.d
        case .int(let i)?: return Decimal(i)
        case .double(let x)?: return Decimal(string: String(x)) ?? Decimal(x)
        default: return nil
        }
    }
}

@MainActor
enum KParsing {
    /// A thrown parse error, as Foundation's reads.
    static func failure(_ text: String, _ what: String) -> KEThrown {
        KEThrown(value: KBuiltins.errorValue("Cannot parse \(text) as \(what)."))
    }

    /// `Int(_:format:)`, `Double(_:format:)`, `Decimal(_:format:)`.
    static func number(_ c: KCall, _ kind: String) throws -> KV {
        let text = c.first.flatMap { $0.asString } ?? ""
        let style = c.arg("format") ?? c.arg("strategy") ?? .nilValue
        var f = KFormat(kind: .number)
        if case .native(.format(let x)) = style { f = x }
        let locale = Locale.current
        do {
            switch (kind, f.kind) {
            case ("Int", .currency(let code)):
                return .int(try IntegerFormatStyle<Int>.Currency(code: code, locale: locale).parseStrategy.parse(text))
            case ("Int", .percent):
                return .int(try IntegerFormatStyle<Int>.Percent(locale: locale).parseStrategy.parse(text))
            case ("Int", _):
                return .int(try IntegerFormatStyle<Int>(locale: locale).parseStrategy.parse(text))
            case ("Double", .currency(let code)):
                return .double(try FloatingPointFormatStyle<Double>.Currency(code: code, locale: locale).parseStrategy.parse(text))
            case ("Double", .percent):
                return .double(try FloatingPointFormatStyle<Double>.Percent(locale: locale).parseStrategy.parse(text))
            case ("Double", _):
                return .double(try FloatingPointFormatStyle<Double>(locale: locale).parseStrategy.parse(text))
            case (_, .currency(let code)):
                return KDecimal(try Decimal.FormatStyle.Currency(code: code, locale: locale).parseStrategy.parse(text)).kv
            case (_, .percent):
                return KDecimal(try Decimal.FormatStyle.Percent(locale: locale).parseStrategy.parse(text)).kv
            default:
                return KDecimal(try Decimal.FormatStyle(locale: locale).parseStrategy.parse(text)).kv
            }
        } catch {
            throw failure(text, kind)
        }
    }

    /// `Date(_:strategy:)`: `.iso8601`, `.dateTime` with its parts, or a `Date.FormatStyle`.
    static func date(_ c: KCall) throws -> KV {
        let text = c.first.flatMap { $0.asString } ?? ""
        let style = c.arg("strategy") ?? .nilValue
        do {
            switch style {
            case .native(.implicit("iso8601", _)):
                return .native(.date(try Date(text, strategy: .iso8601)))
            case .native(.format(let f)):
                var fs = Date.FormatStyle()
                if f.kind == .dateTime && f.components.isEmpty { fs = Date.FormatStyle(date: .abbreviated, time: .shortened) }
                for part in f.components {
                    switch part {
                    case "year": fs = fs.year()
                    case "month": fs = fs.month()
                    case "day": fs = fs.day()
                    case "hour": fs = fs.hour()
                    case "minute": fs = fs.minute()
                    case "second": fs = fs.second()
                    case "weekday": fs = fs.weekday()
                    default: break
                    }
                }
                return .native(.date(try Date(text, strategy: fs.parseStrategy)))
            case .native(.object("Date.FormatStyle", let ref)):
                guard let fs = ref.value as? KDateStyleBox else { break }
                return .native(.date(try Date(text, strategy: fs.style.parseStrategy)))
            default:
                break
            }
        } catch {
            throw failure(text, "a date")
        }
        throw c.fail("strategy: takes .iso8601, .dateTime with its parts, or Date.FormatStyle(date:time:)")
    }
}

final class KDateStyleBox {
    let style: Date.FormatStyle
    init(_ s: Date.FormatStyle) { style = s }
}

extension KTextBridges {
    static func parseStrategies(_ r: KRegistry) {
        r.type("Decimal", .text, support: .full,
               notes: "Exact decimal arithmetic: `Decimal(string:)`, `Decimal(12.5)`, `try Decimal(\"$1.50\", format: .currency(code:))`, `+ - * /`, comparisons, `.formatted(.currency(code:))`, `NSDecimalNumber(decimal:).doubleValue`.") { t in
            t.initializer("string:string") { c in Decimal(string: c.string("string") ?? "").map { KDecimal($0).kv } ?? .nilValue }
            t.initializer("_:string format:any") { c in try KParsing.number(c, "Decimal") }
            t.initializer("_:string strategy:any") { c in try KParsing.number(c, "Decimal") }
            t.initializer("_:any") { c in
                guard let d = KDecimal.from(c[0]) else { throw c.fail("needs a number") }
                return KDecimal(d).kv
            }
            t.initializer("") { _ in KDecimal(0).kv }
            t.staticProperty("zero") { _ in KDecimal(0).kv }
            t.staticProperty("pi") { _ in KDecimal(Decimal.pi).kv }
            @MainActor func me(_ c: KCall) throws -> Decimal {
                guard let d = KDecimal.from(c.receiver) else { throw c.noMember() }
                return d
            }
            t.property("description") { c in .string(try me(c).description) }
            t.property("isZero") { c in .bool(try me(c).isZero) }
            t.property("isNaN") { c in .bool(try me(c).isNaN) }
            t.property("magnitude") { c in KDecimal(try me(c).magnitude).kv }
            t.property("doubleValue") { c in .double(NSDecimalNumber(decimal: try me(c)).doubleValue) }
            t.method("formatted", "") { c in .string(try me(c).formatted()) }
            t.method("formatted", "_:any") { c in .string(KFormatting.formatted(c.receiver, c[0] ?? .nilValue, c.interp)) }
            t.method("rounded", "_:number? _:any?") { c in
                var x = try me(c), out = Decimal()
                let mode: NSDecimalNumber.RoundingMode = ["down": .down, "up": .up, "bankers": .bankers][c.symbol(1) ?? ""] ?? .plain
                NSDecimalRound(&out, &x, c.int(0) ?? 0, mode)
                return KDecimal(out).kv
            }
            for op in ["+", "-", "*", "/"] {
                t.operator(op) { a, b, line in
                    guard let x = KDecimal.from(a), let y = KDecimal.from(b) else { return nil }
                    switch op {
                    case "+": return KDecimal(x + y).kv
                    case "-": return KDecimal(x - y).kv
                    case "*": return KDecimal(x * y).kv
                    default:
                        guard !y.isZero else { throw KERuntimeError(message: "Division by zero", line: line) }
                        return KDecimal(x / y).kv
                    }
                }
            }
            t.operator("<") { a, b, _ in
                guard let x = KDecimal.from(a), let y = KDecimal.from(b) else { return nil }
                return .bool(x < y)
            }
        }
        r.type("NSDecimalNumber", .text, support: .full) { t in
            t.initializer("decimal:any") { c in .native(.object("NSDecimalNumber", KRef(NSDecimalNumber(decimal: KDecimal.from(c["decimal"]) ?? 0)))) }
            t.initializer("string:string") { c in .native(.object("NSDecimalNumber", KRef(NSDecimalNumber(string: c.string("string") ?? "")))) }
            @MainActor func n(_ c: KCall) -> NSDecimalNumber { c.object(NSDecimalNumber.self) ?? .zero }
            t.property("doubleValue") { c in .double(n(c).doubleValue) }
            t.property("intValue") { c in .int(n(c).intValue) }
            t.property("stringValue") { c in .string(n(c).stringValue) }
            t.property("decimalValue") { c in KDecimal(n(c).decimalValue).kv }
        }
        r.type("Date.FormatStyle", .text, support: .full, notes: "`Date.FormatStyle(date:time:)` as a `Date(_:strategy:)` parse strategy.") { t in
            t.initializer("date:any? time:any?") { c in
                let ds = c["date"].map(FoundationBridges.dateFormatStyle)
                let ts = c["time"].map(FoundationBridges.timeFormatStyle)
                return .native(.object("Date.FormatStyle", KRef(KDateStyleBox(Date.FormatStyle(date: ds, time: ts)))))
            }
            t.property("parseStrategy") { c in c.receiver }
        }
        KFormatting.valueFormatters["Decimal"] = { v, style, interp in
            guard case .native(.boxed(let b)) = v, let d = b.get(KDecimal.self)?.d else { return nil }
            guard case .native(.format(let f)) = style else { return d.formatted() }
            switch f.kind {
            case .currency(let code):
                var s = Decimal.FormatStyle.Currency(code: code)
                if let r = f.fraction { s = s.precision(.fractionLength(r)) }
                return d.formatted(s)
            case .percent:
                var s = Decimal.FormatStyle.Percent()
                if let r = f.fraction { s = s.precision(.fractionLength(r)) }
                return d.formatted(s)
            default:
                var s = Decimal.FormatStyle().grouping(f.grouping ? .automatic : .never)
                if let r = f.fraction { s = s.precision(.fractionLength(r)) }
                return d.formatted(s)
            }
        }
    }
}
