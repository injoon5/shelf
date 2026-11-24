//
//  FormatStyles.swift
//  Bridges: format styles, and the formatters that aren't for dates (Round 2C)
//
//  A format style an app writes (`.number.precision(.fractionLength(2)).notation(.compactName)`)
//  is kept as the calls it's made of (`KFormat.steps`), and replayed onto
//  Foundation's own style when a value is formatted, for that value's type:
//  `IntegerFormatStyle` for an `Int`, `FloatingPointFormatStyle` for a
//  `Double`, `Date.FormatStyle`, `ByteCountFormatStyle`, `ListFormatStyle`,
//  `Date.RelativeFormatStyle`, `Date.ISO8601FormatStyle`,
//  `Date.IntervalFormatStyle`, `PersonNameComponents.FormatStyle`,
//  `URL.FormatStyle`. A call Kiln doesn't know is an error, not ignored.
//

import SwiftUI

@MainActor
enum KFormatStyles {
    struct Unsupported: Error { let message: String }

    static func symbol(_ v: KV?) -> String? {
        if case .native(.implicit(let n, _))? = v { return n }
        // `.currency`, `.percent`, `.number` are format styles too (context-free names).
        if case .native(.format(let f))? = v, f.steps.isEmpty {
            switch f.kind {
            case .currency: return "currency"
            case .percent: return "percent"
            case .number: return "decimal"
            default: return nil
            }
        }
        return nil
    }
    static func symbolArgs(_ v: KV?) -> [KV] {
        if case .native(.implicit(_, let a))? = v { return a }
        return []
    }

    /// `value.formatted(style)` for the styles this file knows; nil for others.
    static func format(_ v: KV, _ style: KV, _ interp: KInterpreter) throws -> String? {
        var f: KFormat
        switch style {
        case .native(.format(let x)): f = x
        case .native(.implicit(let name, let args)):
            guard ["byteCount", "list", "iso8601", "relative", "interval", "name", "url", "dateTime", "number", "percent", "currency"].contains(name) else { return nil }
            f = named(name, args, [])
        case .native(.object("Date.FormatStyle", let ref)):
            guard let box = ref.value as? KDateStyleBox, case .native(.date(let d)) = v else { return nil }
            return d.formatted(box.style)
        default: return nil
        }
        // A date range: `(start..<end).formatted(.interval…)`.
        if case .range(.native(.date(let a)), .native(.date(let b)), _) = v {
            return try interval(a..<max(a, b), f)
        }
        if case .native(.date(let d)) = v { return try date(d, f, interp) }
        if case .array(let items) = v { return try list(items, f, interp) }
        if case .native(.url(let u)) = v, f.kind == .named("url") { return try url(u, f) }
        if case .native(.boxed(let b)) = v, let p = b.value.base as? KPersonName { return try name(p.components, f) }
        if f.kind == .named("byteCount"), let n = v.asDouble { return try byteCount(Int64(n), f) }
        switch v {
        case .int(let i): return try integer(i, f)
        case .double(let d): return try floating(d, f)
        case .native(.boxed(let b)) where b.value.base is KNumericBox:
            if let i = v.asInt { return try integer(i, f) }
            return try floating(v.asDouble ?? 0, f)
        default: return nil
        }
    }

    /// A style written by name with its arguments (`.byteCount(style: .file)`).
    static func named(_ name: String, _ args: [KV], _ labels: [String?]) -> KFormat {
        switch name {
        case "number": return KFormat(kind: .number)
        case "percent": return KFormat(kind: .percent)
        case "currency": return KFormat(kind: .currency(args.first?.asString ?? Locale.current.currency?.identifier ?? "USD"))
        case "dateTime": return KFormat(kind: .dateTime)
        default: return KFormat(kind: .named(name), steps: [KFormatStep(name: "init", args: args, labels: labels)])
        }
    }

    static func fail(_ what: String) -> Unsupported { Unsupported(message: what) }

    // MARK: Numbers

    static func precision(_ v: KV?) throws -> NumberFormatStyleConfiguration.Precision {
        guard case .native(.implicit(let n, let a))? = v else { throw fail(".precision needs .fractionLength(n), .significantDigits(n) or .integerLength(n)") }
        func range(_ x: KV?) -> ClosedRange<Int>? {
            if let i = x?.asInt { return i...i }
            if case .range(let lo, let hi, let closed)? = x { let l = lo.asInt ?? 0; let h = hi.asInt ?? 20; return l...(closed ? h : max(l, h - 1)) }
            return nil
        }
        switch n {
        case "fractionLength": guard let r = range(a.first) else { break }; return .fractionLength(r)
        case "significantDigits": guard let r = range(a.first) else { break }; return .significantDigits(r)
        case "integerLength": guard let r = range(a.first) else { break }; return .integerLength(r)
        case "integerAndFractionLength":
            if a.count >= 2, let i = a[0].asInt, let f = a[1].asInt { return .integerAndFractionLength(integer: i, fraction: f) }
        default: break
        }
        throw fail("Kiln doesn't have the .\(n) precision")
    }
    static func grouping(_ v: KV?) -> NumberFormatStyleConfiguration.Grouping { symbol(v) == "never" ? .never : .automatic }
    static func notation(_ v: KV?) throws -> NumberFormatStyleConfiguration.Notation {
        switch symbol(v) {
        case "compactName": return .compactName
        case "scientific": return .scientific
        case "automatic": return .automatic
        default: throw fail("Kiln doesn't have that notation; it has .compactName, .scientific and .automatic")
        }
    }
    static func sign(_ v: KV?) -> NumberFormatStyleConfiguration.SignDisplayStrategy {
        switch symbol(v) {
        case "always": return .always(includingZero: symbolArgs(v).first?.asBool ?? true)
        case "never": return .never
        default: return .automatic
        }
    }
    static func rule(_ v: KV?) -> FloatingPointRoundingRule {
        switch symbol(v) {
        case "up": return .up
        case "down": return .down
        case "towardZero": return .towardZero
        case "awayFromZero": return .awayFromZero
        case "toNearestOrEven": return .toNearestOrEven
        default: return .toNearestOrAwayFromZero
        }
    }
    static func decimalSeparator(_ v: KV?) -> NumberFormatStyleConfiguration.DecimalSeparatorDisplayStrategy { symbol(v) == "always" ? .always : .automatic }

    static func integer(_ x: Int, _ f: KFormat) throws -> String {
        switch f.kind {
        case .percent:
            var s = IntegerFormatStyle<Int>.Percent()
            for step in f.steps {
                switch step.name {
                case "precision": s = s.precision(try precision(step.args.first))
                case "grouping": s = s.grouping(grouping(step.args.first))
                case "notation": s = s.notation(try notation(step.args.first))
                case "sign": s = s.sign(strategy: sign(step.args.first))
                case "rounded": s = s.rounded(rule: rule(step.arg("rule") ?? step.args.first), increment: step.arg("increment")?.asInt)
                case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
                case "scale": s = s.scale(step.args.first?.asDouble ?? 1)
                case "decimalSeparator": s = s.decimalSeparator(strategy: decimalSeparator(step.args.first))
                default: throw fail("Kiln doesn't have .\(step.name) on a percent style")
                }
            }
            return x.formatted(s)
        case .currency(let code):
            var s = IntegerFormatStyle<Int>.Currency(code: code)
            for step in f.steps {
                switch step.name {
                case "precision": s = s.precision(try precision(step.args.first))
                case "grouping": s = s.grouping(grouping(step.args.first))
                case "rounded": s = s.rounded(rule: rule(step.arg("rule") ?? step.args.first), increment: step.arg("increment")?.asInt)
                case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
                case "presentation": s = s.presentation(currencyPresentation(step.args.first))
                case "sign": s = s.sign(strategy: currencySign(step.args.first))
                case "scale": s = s.scale(step.args.first?.asDouble ?? 1)
                case "decimalSeparator": s = s.decimalSeparator(strategy: decimalSeparator(step.args.first))
                default: throw fail("Kiln doesn't have .\(step.name) on a currency style")
                }
            }
            return x.formatted(s)
        case .number, .dateTime:
            var s = IntegerFormatStyle<Int>()
            if !f.grouping { s = s.grouping(.never) }
            for step in f.steps {
                switch step.name {
                case "precision": s = s.precision(try precision(step.args.first))
                case "grouping": s = s.grouping(grouping(step.args.first))
                case "notation": s = s.notation(try notation(step.args.first))
                case "sign": s = s.sign(strategy: sign(step.args.first))
                case "rounded": s = s.rounded(rule: rule(step.arg("rule") ?? step.args.first), increment: step.arg("increment")?.asInt)
                case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
                case "scale": s = s.scale(step.args.first?.asDouble ?? 1)
                case "decimalSeparator": s = s.decimalSeparator(strategy: decimalSeparator(step.args.first))
                default: throw fail("Kiln doesn't have .\(step.name) on a number style")
                }
            }
            return x.formatted(s)
        default:
            return try floating(Double(x), f)
        }
    }

    static func floating(_ x: Double, _ f: KFormat) throws -> String {
        switch f.kind {
        case .percent:
            var s = FloatingPointFormatStyle<Double>.Percent()
            if let r = f.fraction, f.steps.isEmpty { s = s.precision(.fractionLength(r)) }
            for step in f.steps {
                switch step.name {
                case "precision": s = s.precision(try precision(step.args.first))
                case "grouping": s = s.grouping(grouping(step.args.first))
                case "notation": s = s.notation(try notation(step.args.first))
                case "sign": s = s.sign(strategy: sign(step.args.first))
                case "rounded": s = s.rounded(rule: rule(step.arg("rule") ?? step.args.first), increment: step.arg("increment")?.asDouble)
                case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
                case "scale": s = s.scale(step.args.first?.asDouble ?? 1)
                case "decimalSeparator": s = s.decimalSeparator(strategy: decimalSeparator(step.args.first))
                default: throw fail("Kiln doesn't have .\(step.name) on a percent style")
                }
            }
            return x.formatted(s)
        case .currency(let code):
            var s = FloatingPointFormatStyle<Double>.Currency(code: code)
            if let r = f.fraction, f.steps.isEmpty { s = s.precision(.fractionLength(r)) }
            for step in f.steps {
                switch step.name {
                case "precision": s = s.precision(try precision(step.args.first))
                case "grouping": s = s.grouping(grouping(step.args.first))
                case "rounded": s = s.rounded(rule: rule(step.arg("rule") ?? step.args.first), increment: step.arg("increment")?.asDouble)
                case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
                case "presentation": s = s.presentation(currencyPresentation(step.args.first))
                case "sign": s = s.sign(strategy: currencySign(step.args.first))
                case "scale": s = s.scale(step.args.first?.asDouble ?? 1)
                case "decimalSeparator": s = s.decimalSeparator(strategy: decimalSeparator(step.args.first))
                default: throw fail("Kiln doesn't have .\(step.name) on a currency style")
                }
            }
            return x.formatted(s)
        case .number, .dateTime:
            var s = FloatingPointFormatStyle<Double>()
            if !f.grouping { s = s.grouping(.never) }
            if let r = f.fraction, f.steps.isEmpty { s = s.precision(.fractionLength(r)) }
            for step in f.steps {
                switch step.name {
                case "precision": s = s.precision(try precision(step.args.first))
                case "grouping": s = s.grouping(grouping(step.args.first))
                case "notation": s = s.notation(try notation(step.args.first))
                case "sign": s = s.sign(strategy: sign(step.args.first))
                case "rounded": s = s.rounded(rule: rule(step.arg("rule") ?? step.args.first), increment: step.arg("increment")?.asDouble)
                case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
                case "scale": s = s.scale(step.args.first?.asDouble ?? 1)
                case "decimalSeparator": s = s.decimalSeparator(strategy: decimalSeparator(step.args.first))
                default: throw fail("Kiln doesn't have .\(step.name) on a number style")
                }
            }
            return x.formatted(s)
        case .named("byteCount"):
            return try byteCount(Int64(x), f)
        default:
            throw fail("That format style isn't for numbers")
        }
    }

    static func currencyPresentation(_ v: KV?) -> CurrencyFormatStyleConfiguration.Presentation {
        switch symbol(v) {
        case "narrow": return .narrow
        case "isoCode": return .isoCode
        case "fullName": return .fullName
        default: return .standard
        }
    }
    static func currencySign(_ v: KV?) -> CurrencyFormatStyleConfiguration.SignDisplayStrategy {
        switch symbol(v) {
        case "always": return .always(showZero: symbolArgs(v).first?.asBool ?? true)
        case "never": return .never
        case "accounting": return .accounting
        default: return .automatic
        }
    }

    // MARK: Byte counts and lists

    static func byteStyle(_ v: KV?) -> ByteCountFormatStyle.Style {
        switch symbol(v) {
        case "memory": return .memory
        case "decimal": return .decimal
        case "binary": return .binary
        default: return .file
        }
    }

    static func byteCount(_ n: Int64, _ f: KFormat) throws -> String {
        let initial = f.steps.first { $0.name == "init" }
        var s = ByteCountFormatStyle(style: byteStyle(initial?.arg("style") ?? initial?.args.first))
        if let u = initial?.arg("allowedUnits") { s.allowedUnits = byteUnits(u) }
        if let z = initial?.arg("spellsOutZero")?.asBool { s.spellsOutZero = z }
        if let a = initial?.arg("includesActualByteCount")?.asBool { s.includesActualByteCount = a }
        for step in f.steps where step.name != "init" {
            switch step.name {
            case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
            default: throw fail("Kiln doesn't have .\(step.name) on a byte count style")
            }
        }
        return n.formatted(s)
    }

    static func byteUnits(_ v: KV?) -> ByteCountFormatStyle.Units {
        var u: ByteCountFormatStyle.Units = []
        let names = (v?.asArray ?? []).compactMap(symbol) + (symbol(v).map { [$0] } ?? [])
        for n in names {
            switch n {
            case "bytes": u.insert(.bytes)
            case "kb": u.insert(.kb)
            case "mb": u.insert(.mb)
            case "gb": u.insert(.gb)
            case "tb": u.insert(.tb)
            case "all": u.insert(.all)
            case "default": u.insert(.default)
            default: break
            }
        }
        return u.isEmpty ? .all : u
    }

    static func list(_ items: [KV], _ f: KFormat, _ interp: KInterpreter) throws -> String {
        let initial = f.steps.first { $0.name == "init" }
        var type: ListFormatStyle<StringStyle, [String]>.ListType = .and
        var width: ListFormatStyle<StringStyle, [String]>.Width = .standard
        var member: KV?
        for (i, a) in (initial?.args ?? []).enumerated() {
            let label = initial.flatMap { i < $0.labels.count ? $0.labels[i] : nil }
            if label == "memberStyle" { member = a; continue }
            switch symbol(a) {
            case "or": type = .or
            case "and": type = .and
            case "short": width = .short
            case "narrow": width = .narrow
            case "standard": width = .standard
            default: if label == nil, f.kind == .named("list"), member == nil, symbol(a) == nil { member = a }
            }
        }
        let strings = try items.map { x -> String in
            if let member { return try format(x, member, interp) ?? interp.describe(x) }
            return interp.describe(x)
        }
        var s = ListFormatStyle<StringStyle, [String]>.list(type: type, width: width)
        for step in f.steps where step.name != "init" {
            if step.name == "locale" { s = s.locale(FoundationBridges.locale(step.args.first) ?? .current) }
            else { throw fail("Kiln doesn't have .\(step.name) on a list style") }
        }
        return strings.formatted(s)
    }

    // MARK: Dates

    static func date(_ d: Date, _ f: KFormat, _ interp: KInterpreter) throws -> String {
        switch f.kind {
        case .named("iso8601"): return d.formatted(iso8601(.native(.format(f)), interp))
        case .named("relative"):
            let initial = f.steps.first { $0.name == "init" }
            var presentation: Date.RelativeFormatStyle.Presentation = .numeric
            var units: Date.RelativeFormatStyle.UnitsStyle = .wide
            for a in initial?.args ?? [] {
                switch symbol(a) {
                case "named": presentation = .named
                case "numeric": presentation = .numeric
                case "abbreviated": units = .abbreviated
                case "narrow": units = .narrow
                case "spellOut": units = .spellOut
                case "wide": units = .wide
                default: break
                }
            }
            return d.formatted(.relative(presentation: presentation, unitsStyle: units))
        case .dateTime, .number:
            var s = Date.FormatStyle.dateTime
            var plain = true
            for step in f.steps {
                switch step.name {
                case "dateTimeInit": break
                case "year":
                    plain = false
                    switch symbol(step.args.first) {
                    case "twoDigits": s = s.year(.twoDigits)
                    case "padded": s = s.year(.padded(symbolArgs(step.args.first).first?.asInt ?? 4))
                    default: s = s.year()
                    }
                case "month":
                    plain = false
                    switch symbol(step.args.first) {
                    case "wide": s = s.month(.wide)
                    case "narrow": s = s.month(.narrow)
                    case "twoDigits": s = s.month(.twoDigits)
                    case "defaultDigits": s = s.month(.defaultDigits)
                    case "abbreviated": s = s.month(.abbreviated)
                    default: s = s.month()
                    }
                case "day":
                    plain = false
                    switch symbol(step.args.first) {
                    case "twoDigits": s = s.day(.twoDigits)
                    case "ordinalOfDayInMonth": s = s.day(.ordinalOfDayInMonth)
                    default: s = s.day()
                    }
                case "weekday":
                    plain = false
                    switch symbol(step.args.first) {
                    case "wide": s = s.weekday(.wide)
                    case "narrow": s = s.weekday(.narrow)
                    case "short": s = s.weekday(.short)
                    case "oneDigit": s = s.weekday(.oneDigit)
                    case "twoDigits": s = s.weekday(.twoDigits)
                    default: s = s.weekday()
                    }
                case "hour":
                    plain = false
                    let amPM: Date.FormatStyle.Symbol.Hour.AMPMStyle
                    switch symbol(symbolArgs(step.args.first).first) {
                    case "omitted": amPM = .omitted
                    case "narrow": amPM = .narrow
                    case "wide": amPM = .wide
                    default: amPM = .abbreviated
                    }
                    switch symbol(step.args.first) {
                    case "twoDigits": s = s.hour(.twoDigits(amPM: amPM))
                    case "conversationalDefaultDigits": s = s.hour(.conversationalDefaultDigits(amPM: amPM))
                    case "defaultDigits": s = s.hour(.defaultDigits(amPM: amPM))
                    default: s = s.hour()
                    }
                case "minute": plain = false; s = symbol(step.args.first) == "twoDigits" ? s.minute(.twoDigits) : s.minute()
                case "second": plain = false; s = symbol(step.args.first) == "twoDigits" ? s.second(.twoDigits) : s.second()
                case "secondFraction": plain = false; s = s.secondFraction(.fractional(symbolArgs(step.args.first).first?.asInt ?? 3))
                case "era": plain = false; s = s.era()
                case "quarter": plain = false; s = s.quarter()
                case "week": plain = false; s = s.week()
                case "dayOfYear": plain = false; s = s.dayOfYear()
                case "timeZone": plain = false; s = s.timeZone()
                case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
                default: throw fail("Kiln doesn't have .\(step.name) on a date style")
                }
            }
            // `Date.FormatStyle(date: .long, time: .omitted)`.
            if let initial = f.steps.first(where: { $0.name == "dateTimeInit" }) {
                let ds = initial.arg("date").map(FoundationBridges.dateFormatStyle)
                let ts = initial.arg("time").map(FoundationBridges.timeFormatStyle)
                var fs = Date.FormatStyle(date: ds, time: ts)
                if let l = FoundationBridges.locale(initial.arg("locale")) { fs = fs.locale(l) }
                return d.formatted(fs)
            }
            // The legacy components list (`components`, from before steps).
            if plain && !f.components.isEmpty {
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
            return d.formatted(s)
        default:
            throw fail("That format style isn't for dates")
        }
    }

    /// `.iso8601`, with `.year()`, `.month()`… or `.iso8601(timeZone:…)`.
    static func iso8601(_ v: KV?, _ interp: KInterpreter) -> Date.ISO8601FormatStyle {
        var s = Date.ISO8601FormatStyle()
        guard case .native(.format(let f))? = v else { return s }
        var parts = false
        var withTime = false
        for step in f.steps {
            switch step.name {
            case "year": parts = true; s = s.year()
            case "month": parts = true; s = s.month()
            case "day": parts = true; s = s.day()
            case "weekOfYear": parts = true; s = s.weekOfYear()
            case "time": parts = true; withTime = true; s = s.time(includingFractionalSeconds: step.arg("includingFractionalSeconds")?.asBool ?? false)
            case "timeZone": parts = true; s = s.timeZone(separator: .omitted)
            case "dateSeparator": s = s.dateSeparator(symbol(step.args.first) == "omitted" ? .omitted : .dash)
            case "timeSeparator": s = s.timeSeparator(symbol(step.args.first) == "omitted" ? .omitted : .colon)
            case "dateTimeSeparator": s = s.dateTimeSeparator(symbol(step.args.first) == "space" ? .space : .standard)
            default: break
            }
        }
        _ = parts; _ = withTime
        return s
    }

    static func interval(_ r: Range<Date>, _ f: KFormat) throws -> String {
        var s = Date.IntervalFormatStyle()
        for step in f.steps where step.name != "init" {
            switch step.name {
            case "year": s = s.year()
            case "month": s = symbol(step.args.first) == "wide" ? s.month(.wide) : s.month()
            case "day": s = s.day()
            case "weekday": s = s.weekday()
            case "hour": s = s.hour()
            case "minute": s = s.minute()
            case "second": s = s.second()
            case "locale": s = s.locale(FoundationBridges.locale(step.args.first) ?? .current)
            default: throw fail("Kiln doesn't have .\(step.name) on an interval style")
            }
        }
        return r.formatted(s)
    }

    static func name(_ p: PersonNameComponents, _ f: KFormat) throws -> String {
        let initial = f.steps.first { $0.name == "init" }
        let style: PersonNameComponents.FormatStyle.Style
        switch symbol(initial?.arg("style") ?? initial?.args.first) {
        case "short": style = .short
        case "long": style = .long
        case "abbreviated": style = .abbreviated
        default: style = .medium
        }
        return p.formatted(.name(style: style))
    }

    static func url(_ u: URL, _ f: KFormat) throws -> String {
        var s = URL.FormatStyle()
        func component(_ v: KV?) -> URL.FormatStyle.ComponentDisplayOption {
            switch symbol(v) {
            case "never": return .never
            case "always": return .always
            default: return .omitIfHTTPFamily
            }
        }
        for step in f.steps where step.name != "init" {
            switch step.name {
            case "scheme": s = s.scheme(component(step.args.first))
            case "host": s = s.host(component(step.args.first) == .never ? .never : .always)
            case "path": s = s.path(component(step.args.first) == .never ? .never : .always)
            case "query": s = s.query(component(step.args.first) == .never ? .never : .always)
            case "fragment": s = s.fragment(component(step.args.first) == .never ? .never : .always)
            case "port": s = s.port(component(step.args.first) == .never ? .never : .always)
            case "user", "password": break
            default: throw fail("Kiln doesn't have .\(step.name) on a URL style")
            }
        }
        return u.formatted(s)
    }
}

/// `PersonNameComponents`, as a value.
struct KPersonName: Hashable {
    var components: PersonNameComponents
    var kv: KV { .native(.boxed(KBoxed("PersonNameComponents", self))) }
    static func from(_ v: KV?) -> PersonNameComponents? {
        if case .native(.boxed(let b))? = v { return (b.value.base as? KPersonName)?.components }
        return nil
    }
}

extension FoundationBridges {
    static func formatters(_ r: KRegistry) {
        // Only names nothing else reads as a symbol (`.iso8601`, `.relative`, `.list` stay symbols: the formatter reads them as written).
        for name in ["byteCount", "interval", "url"] {
            r.addContextFree(name) { args, labels, _ in .native(.format(KFormatStyles.named(name, args, labels))) }
        }

        r.type("NumberFormatter", .foundation, support: .full,
               notes: "`numberStyle` (`.decimal`, `.currency`, `.percent`, `.spellOut`, `.ordinal`…), fraction digits, `currencyCode`, `locale`, `string(from:)`, `number(from:)`.") { t in
            t.initializer("") { _ in .native(.object("NumberFormatter", KRef(NumberFormatter()))) }
            t.staticMethod("localizedString", "from:any number:any") { c in
                let n = NSNumber(value: c["from"]?.asDouble ?? 0)
                return .string(NumberFormatter.localizedString(from: n, number: numberStyle(KFormatStyles.symbol(c["number"]) ?? "")))
            }
            @MainActor func f(_ c: KCall) -> NumberFormatter? { c.object(NumberFormatter.self) }
            t.property("numberStyle", { _ in .nilValue }, set: { c in if let s = KFormatStyles.symbol(c.first) { f(c)?.numberStyle = numberStyle(s) } })
            let ints: [String: ReferenceWritableKeyPath<NumberFormatter, Int>] = [
                "maximumFractionDigits": \.maximumFractionDigits, "minimumFractionDigits": \.minimumFractionDigits,
                "maximumIntegerDigits": \.maximumIntegerDigits, "minimumIntegerDigits": \.minimumIntegerDigits,
                "maximumSignificantDigits": \.maximumSignificantDigits, "minimumSignificantDigits": \.minimumSignificantDigits,
                "groupingSize": \.groupingSize,
            ]
            for (name, kp) in ints {
                t.property(name, { c in .int(f(c)?[keyPath: kp] ?? 0) }, set: { c in if let n = c.first?.asInt { f(c)?[keyPath: kp] = n } })
            }
            let bools: [String: ReferenceWritableKeyPath<NumberFormatter, Bool>] = [
                "usesGroupingSeparator": \.usesGroupingSeparator, "usesSignificantDigits": \.usesSignificantDigits,
                "alwaysShowsDecimalSeparator": \.alwaysShowsDecimalSeparator, "isLenient": \.isLenient,
            ]
            for (name, kp) in bools {
                t.property(name, { c in .bool(f(c)?[keyPath: kp] ?? false) }, set: { c in if let b = c.first?.asBool { f(c)?[keyPath: kp] = b } })
            }
            let strings: [String: ReferenceWritableKeyPath<NumberFormatter, String?>] = [
                "currencyCode": \.currencyCode, "currencySymbol": \.currencySymbol, "positivePrefix": \.positivePrefix,
                "negativePrefix": \.negativePrefix, "positiveSuffix": \.positiveSuffix, "negativeSuffix": \.negativeSuffix,
                "decimalSeparator": \.decimalSeparator, "groupingSeparator": \.groupingSeparator, "zeroSymbol": \.zeroSymbol,
            ]
            for (name, kp) in strings {
                t.property(name, { c in f(c)?[keyPath: kp].map { .string($0) } ?? .nilValue }, set: { c in f(c)?[keyPath: kp] = c.first?.asString })
            }
            t.property("locale", { c in f(c).map { localeValue($0.locale) } ?? .nilValue }, set: { c in f(c)?.locale = locale(c.first) })
            t.property("roundingMode", { _ in .nilValue }, set: { c in
                let modes: [String: NumberFormatter.RoundingMode] = ["up": .up, "down": .down, "halfUp": .halfUp, "halfDown": .halfDown,
                                                                    "halfEven": .halfEven, "ceiling": .ceiling, "floor": .floor]
                if let m = c.symbol(0).flatMap({ modes[$0] }) { f(c)?.roundingMode = m }
            })
            t.property("multiplier", { _ in .nilValue }, set: { c in f(c)?.multiplier = c.first?.asDouble.map { NSNumber(value: $0) } })
            t.method("string", "from:any") { c in
                guard let v = c["from"] else { return .nilValue }
                let n: NSNumber
                if let d = KDecimal.from(v), case .native = v { n = NSDecimalNumber(decimal: d) }
                else if case .int(let i) = v { n = NSNumber(value: i) }
                else if let i = KIntegerOps.fixed(v)?.intValue { n = NSNumber(value: i) }
                else if case .native(.object(_, let ref)) = v, let num = ref.value as? NSNumber { n = num }
                else { n = NSNumber(value: v.asDouble ?? 0) }
                return f(c)?.string(from: n).map { .string($0) } ?? .nilValue
            }
            t.method("number", "from:string") { c in
                guard let s = c.string("from"), let n = f(c)?.number(from: s) else { return .nilValue }
                return .native(.object("NSNumber", KRef(n)))
            }
            t.method("string", "for:any") { c in
                f(c)?.string(for: KNativeValues.native(from: c["for"] ?? .nilValue)).map { .string($0) } ?? .nilValue
            }
        }
        r.type("NSNumber", .foundation, support: .full) { t in
            t.initializer("value:any") { c in
                switch c["value"] {
                case .int(let i)?: return .native(.object("NSNumber", KRef(NSNumber(value: i))))
                case .bool(let b)?: return .native(.object("NSNumber", KRef(NSNumber(value: b))))
                default: return .native(.object("NSNumber", KRef(NSNumber(value: c["value"]?.asDouble ?? 0))))
                }
            }
            @MainActor func n(_ c: KCall) -> NSNumber { c.object(NSNumber.self) ?? 0 }
            t.property("doubleValue") { c in .double(n(c).doubleValue) }
            t.property("intValue") { c in .int(n(c).intValue) }
            t.property("floatValue") { c in .double(Double(n(c).floatValue)) }
            t.property("boolValue") { c in .bool(n(c).boolValue) }
            t.property("stringValue") { c in .string(n(c).stringValue) }
            t.property("decimalValue") { c in KDecimal(n(c).decimalValue).kv }
        }
        r.addLiteralCoercion("NSNumber") { v, _ in
            switch v {
            case .int(let i): return .native(.object("NSNumber", KRef(NSNumber(value: i))))
            case .double(let d): return .native(.object("NSNumber", KRef(NSNumber(value: d))))
            default: return nil
            }
        }

        r.type("ByteCountFormatter", .foundation, support: .full, notes: "`string(fromByteCount:countStyle:)`, `allowedUnits`, `countStyle`.") { t in
            t.initializer("") { _ in .native(.object("ByteCountFormatter", KRef(ByteCountFormatter()))) }
            t.staticMethod("string", "fromByteCount:any countStyle:any") { c in
                .string(ByteCountFormatter.string(fromByteCount: Int64(c["fromByteCount"]?.asDouble ?? 0), countStyle: countStyle(c.symbol("countStyle"))))
            }
            @MainActor func f(_ c: KCall) -> ByteCountFormatter? { c.object(ByteCountFormatter.self) }
            t.property("countStyle", { _ in .nilValue }, set: { c in f(c)?.countStyle = countStyle(c.symbol(0)) })
            t.property("allowedUnits", { _ in .nilValue }, set: { c in
                var u: ByteCountFormatter.Units = []
                let names = (c.first?.asArray ?? []).compactMap(KFormatStyles.symbol) + (c.symbol(0).map { [$0] } ?? [])
                for n in names {
                    switch n {
                    case "useBytes": u.insert(.useBytes)
                    case "useKB": u.insert(.useKB)
                    case "useMB": u.insert(.useMB)
                    case "useGB": u.insert(.useGB)
                    case "useTB": u.insert(.useTB)
                    default: u.insert(.useAll)
                    }
                }
                f(c)?.allowedUnits = u
            })
            for name in ["includesUnit", "includesCount", "isAdaptive", "allowsNonnumericFormatting", "includesActualByteCount", "zeroPadsFractionDigits"] {
                t.property(name, { _ in .nilValue }, set: { c in
                    guard let b = c.first?.asBool, let fmt = f(c) else { return }
                    switch name {
                    case "includesUnit": fmt.includesUnit = b
                    case "includesCount": fmt.includesCount = b
                    case "isAdaptive": fmt.isAdaptive = b
                    case "allowsNonnumericFormatting": fmt.allowsNonnumericFormatting = b
                    case "includesActualByteCount": fmt.includesActualByteCount = b
                    default: fmt.zeroPadsFractionDigits = b
                    }
                })
            }
            t.method("string", "fromByteCount:any") { c in .string(f(c)?.string(fromByteCount: Int64(c["fromByteCount"]?.asDouble ?? 0)) ?? "") }
        }

        r.type("ListFormatter", .foundation, support: .full) { t in
            t.initializer("") { _ in .native(.object("ListFormatter", KRef(ListFormatter()))) }
            t.staticMethod("localizedString", "byJoining:any") { c in
                .string(ListFormatter.localizedString(byJoining: ((try? c.interp.sequence(c["byJoining"] ?? .nilValue)) ?? []).map { c.interp.describe($0) }))
            }
            t.method("string", "from:any") { c in
                .string(c.object(ListFormatter.self)?.string(from: ((try? c.interp.sequence(c["from"] ?? .nilValue)) ?? []).map { c.interp.describe($0) }) ?? "")
            }
        }

        r.type("PersonNameComponents", .foundation, support: .full, notes: "`givenName`, `familyName` and the rest, `formatted(.name(style:))`.") { t in
            t.initializer("namePrefix:string? givenName:string? middleName:string? familyName:string? nameSuffix:string? nickname:string?") { c in
                var p = PersonNameComponents()
                p.namePrefix = c.string("namePrefix"); p.givenName = c.string("givenName"); p.middleName = c.string("middleName")
                p.familyName = c.string("familyName"); p.nameSuffix = c.string("nameSuffix"); p.nickname = c.string("nickname")
                return KPersonName(components: p).kv
            }
            let fields: [String: WritableKeyPath<PersonNameComponents, String?>] = [
                "namePrefix": \.namePrefix, "givenName": \.givenName, "middleName": \.middleName, "familyName": \.familyName,
                "nameSuffix": \.nameSuffix, "nickname": \.nickname,
            ]
            for (name, kp) in fields {
                t.property(name, { c in KPersonName.from(c.receiver)?[keyPath: kp].map { .string($0) } ?? .nilValue }, set: { c in
                    var p = KPersonName.from(c.receiver) ?? PersonNameComponents()
                    p[keyPath: kp] = c.first?.asString
                    c.mutated = KPersonName(components: p).kv
                })
            }
            t.method("formatted", "") { c in .string((KPersonName.from(c.receiver) ?? PersonNameComponents()).formatted()) }
            t.method("formatted", "_:any") { c in .string(KFormatting.formatted(c.receiver, c.first ?? .nilValue, c.interp)) }
        }
        r.type("PersonNameComponentsFormatter", .foundation, support: .full) { t in
            t.initializer("") { _ in .native(.object("PersonNameComponentsFormatter", KRef(PersonNameComponentsFormatter()))) }
            t.property("style", { _ in .nilValue }, set: { c in
                let f = c.object(PersonNameComponentsFormatter.self)
                switch c.symbol(0) {
                case "short": f?.style = .short
                case "long": f?.style = .long
                case "abbreviated": f?.style = .abbreviated
                default: f?.style = .medium
                }
            })
            t.method("string", "from:any") { c in
                .string(c.object(PersonNameComponentsFormatter.self)?.string(from: KPersonName.from(c["from"]) ?? PersonNameComponents()) ?? "")
            }
            t.method("personNameComponents", "from:string") { c in
                c.object(PersonNameComponentsFormatter.self)?.personNameComponents(from: c.string("from") ?? "").map { KPersonName(components: $0).kv } ?? .nilValue
            }
        }

        // `[…].formatted()`, `.formatted(.list(type:))`; `(a..<b).formatted(.interval…)`; `url.formatted(…)`.
        r.extend("Sequence") { t in
            t.method("formatted", "") { c in .string(try KFormatStyles.list(c.receiver.asArray ?? [], KFormat(kind: .named("list")), c.interp)) }
            t.method("formatted", "_:any") { c in
                guard let s = try KFormatStyles.format(.array(c.receiver.asArray ?? []), c.first ?? .nilValue, c.interp) else { throw c.fail("Kiln can't format a list with that style") }
                return .string(s)
            }
        }
        r.extend("Range") { t in
            t.method("formatted", "_:any") { c in
                guard let s = try KFormatStyles.format(c.receiver, c.first ?? .nilValue, c.interp) else { throw c.fail("Kiln can't format a range with that style") }
                return .string(s)
            }
        }
        r.extend("URL") { t in
            t.method("formatted", "_:any?") { c in
                guard case .native(.url(let u)) = c.receiver else { return .string("") }
                guard let style = c.first else { return .string(u.formatted()) }
                return .string(try KFormatStyles.format(c.receiver, style, c.interp) ?? u.absoluteString)
            }
        }
    }

    static func countStyle(_ s: String?) -> ByteCountFormatter.CountStyle {
        switch s {
        case "memory": return .memory
        case "decimal": return .decimal
        case "binary": return .binary
        default: return .file
        }
    }
}
