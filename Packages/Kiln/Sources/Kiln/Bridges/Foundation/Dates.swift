//
//  Dates.swift
//  Bridges: Date, Calendar, DateComponents, TimeZone and the date formatters
//
//  `Calendar` is Foundation's (`Calendar.current` follows the device's, or
//  the time zone the run is given); `DateComponents`, `DateInterval` and
//  `TimeZone` are Foundation's values, printed as Swift prints them.
//

import SwiftUI

/// `.orderedAscending` and its siblings, printed as Swift prints them.
struct KComparison: Hashable, KDescribable {
    let result: ComparisonResult
    func describe(_ interp: KInterpreter) -> String { "NSComparisonResult" }
    var name: String { result == .orderedAscending ? "orderedAscending" : (result == .orderedDescending ? "orderedDescending" : "orderedSame") }
    var kv: KV { .native(.boxed(KBoxed("ComparisonResult", self, caseName: name))) }
    static func kv(_ r: ComparisonResult) -> KV { KComparison(result: r).kv }
}

/// The date values: `DateComponents`, `DateInterval`.
struct KDateValue: Hashable, KDescribable {
    let components: DateComponents?
    let interval: DateInterval?
    func describe(_ interp: KInterpreter) -> String { components.map { String(describing: $0) } ?? interval.map { String(describing: $0) } ?? "" }
}

@MainActor
enum KDates {
    // MARK: Values

    static func comps(_ dc: DateComponents) -> KV { .native(.boxed(KBoxed("DateComponents", KDateValue(components: dc, interval: nil)))) }
    static func interval(_ i: DateInterval) -> KV { .native(.boxed(KBoxed("DateInterval", KDateValue(components: nil, interval: i)))) }

    static func comps(_ v: KV?) -> DateComponents? {
        if case .native(.boxed(let b))? = v, let d = b.value.base as? KDateValue { return d.components }
        if let v { return KDateComponents.native(v) }
        return nil
    }
    static func interval(_ v: KV?) -> DateInterval? {
        if case .native(.boxed(let b))? = v, let d = b.value.base as? KDateValue { return d.interval }
        return nil
    }
    static func date(_ v: KV?) -> Date? { if case .native(.date(let d))? = v { return d }; return nil }

    static func calendarValue(_ c: Calendar) -> KV { .native(.object("Calendar", KRef(c as NSCalendar))) }
    static func calendar(_ v: KV?) -> Calendar? {
        if case .native(.object(_, let ref))? = v { return ref.value as? Calendar }
        return nil
    }
    static func timeZoneValue(_ t: TimeZone) -> KV { .native(.object("TimeZone", KRef(t as NSTimeZone))) }
    static func timeZone(_ v: KV?) -> TimeZone? {
        if case .native(.object(_, let ref))? = v { return ref.value as? TimeZone }
        if case .string(let s)? = v { return TimeZone(identifier: s) }
        return nil
    }

    // MARK: Symbols

    static let componentNames: [(String, Calendar.Component)] = {
        var out: [(String, Calendar.Component)] = [
            ("era", .era), ("year", .year), ("month", .month), ("day", .day), ("hour", .hour), ("minute", .minute), ("second", .second),
            ("weekday", .weekday), ("weekdayOrdinal", .weekdayOrdinal), ("quarter", .quarter), ("weekOfMonth", .weekOfMonth),
            ("weekOfYear", .weekOfYear), ("yearForWeekOfYear", .yearForWeekOfYear), ("nanosecond", .nanosecond),
            ("calendar", .calendar), ("timeZone", .timeZone), ("isLeapMonth", .isLeapMonth),
        ]
        if #available(iOS 18, macOS 15, *) { out.append(("dayOfYear", .dayOfYear)) }
        return out
    }()
    static func component(_ v: KV?) -> Calendar.Component? {
        guard case .native(.implicit(let n, _))? = v else { return nil }
        return componentNames.first { $0.0 == n }?.1
    }
    static func componentSet(_ v: KV?, _ interp: KInterpreter) -> Set<Calendar.Component>? {
        if let one = component(v) { return [one] }
        guard let v, let xs = try? interp.sequence(v) else { return nil }
        return Set(xs.compactMap { component($0) })
    }
    static func identifier(_ v: KV?) -> Calendar.Identifier? {
        guard case .native(.implicit(let n, _))? = v else { return nil }
        let all: [String: Calendar.Identifier] = ["gregorian": .gregorian, "iso8601": .iso8601, "buddhist": .buddhist, "chinese": .chinese,
            "coptic": .coptic, "ethiopicAmeteAlem": .ethiopicAmeteAlem, "ethiopicAmeteMihret": .ethiopicAmeteMihret, "hebrew": .hebrew,
            "indian": .indian, "islamic": .islamic, "islamicCivil": .islamicCivil, "islamicTabular": .islamicTabular,
            "islamicUmmAlQura": .islamicUmmAlQura, "japanese": .japanese, "persian": .persian, "republicOfChina": .republicOfChina]
        return all[n]
    }
    static func identifierName(_ i: Calendar.Identifier) -> String {
        let s = String(describing: i)
        return s
    }
    static func policy(_ v: KV?) -> Calendar.MatchingPolicy {
        guard case .native(.implicit(let n, _))? = v else { return .nextTime }
        switch n {
        case "strict": return .strict
        case "nextTimePreservingSmallerComponents": return .nextTimePreservingSmallerComponents
        case "previousTimePreservingSmallerComponents": return .previousTimePreservingSmallerComponents
        default: return .nextTime
        }
    }
    static func repeated(_ v: KV?) -> Calendar.RepeatedTimePolicy {
        if case .native(.implicit("last", _))? = v { return .last }
        return .first
    }
    static func direction(_ v: KV?) -> Calendar.SearchDirection {
        if case .native(.implicit("backward", _))? = v { return .backward }
        return .forward
    }

    // MARK: DateComponents

    static let componentFields: [(String, WritableKeyPath<DateComponents, Int?>)] = {
        var out: [(String, WritableKeyPath<DateComponents, Int?>)] = [
            ("era", \.era), ("year", \.year), ("month", \.month), ("day", \.day), ("hour", \.hour), ("minute", \.minute),
            ("second", \.second), ("nanosecond", \.nanosecond), ("weekday", \.weekday), ("weekdayOrdinal", \.weekdayOrdinal),
            ("quarter", \.quarter), ("weekOfMonth", \.weekOfMonth), ("weekOfYear", \.weekOfYear), ("yearForWeekOfYear", \.yearForWeekOfYear),
        ]
        if #available(iOS 18, macOS 15, *) { out.append(("dayOfYear", \.dayOfYear)) }
        return out
    }()

    static func makeComponents(_ c: KCall) -> DateComponents {
        var dc = DateComponents()
        for (i, label) in c.labels.enumerated() {
            guard let label else { continue }
            let v = c.args[i]
            switch label {
            case "calendar": dc.calendar = calendar(v)
            case "timeZone": dc.timeZone = timeZone(v)
            case "isLeapMonth": dc.isLeapMonth = v.asBool
            default:
                if let kp = componentFields.first(where: { $0.0 == label })?.1 { dc[keyPath: kp] = v.asInt }
            }
        }
        return dc
    }
}

extension FoundationBridges {
    static func dates(_ r: KRegistry) {
        r.addContextFree("now") { _, _, _ in .native(.date(Date())) }
        date(r)
        calendar(r)
        dateComponents(r)
        timeZones(r)
        dateFormatters(r)
    }

    // MARK: Date

    static func date(_ r: KRegistry) {
        r.type("Date", .foundation, support: .full) { t in
            t.initializer { c in
                // `try Date("2026-11-24T09:30:00Z", strategy: .iso8601)` (Text/ParseStrategies.swift).
                if c.arg("strategy") != nil { return try KParsing.date(c) }
                if let s = c.arg("timeIntervalSinceNow")?.asDouble { return .native(.date(Date(timeIntervalSinceNow: s))) }
                if let s = c.arg("timeIntervalSince1970")?.asDouble { return .native(.date(Date(timeIntervalSince1970: s))) }
                if let s = c.arg("timeIntervalSinceReferenceDate")?.asDouble { return .native(.date(Date(timeIntervalSinceReferenceDate: s))) }
                if let s = c.arg("timeInterval")?.asDouble, case .native(.date(let d))? = c.arg("since") { return .native(.date(d.addingTimeInterval(s))) }
                return .native(.date(Date()))
            }
            t.staticProperty("now") { _ in .native(.date(Date())) }
            t.staticProperty("distantPast") { _ in .native(.date(.distantPast)) }
            t.staticProperty("distantFuture") { _ in .native(.date(.distantFuture)) }
            t.staticMethod("now") { _ in .native(.date(Date())) }
            t.implicit { name, _, _ in
                switch name {
                case "now": return .native(.date(Date()))
                case "distantPast": return .native(.date(.distantPast))
                case "distantFuture": return .native(.date(.distantFuture))
                default: return nil
                }
            }
            t.property("timeIntervalSinceNow") { c in .double(c.receiverDate.timeIntervalSinceNow) }
            t.property("timeIntervalSince1970") { c in .double(c.receiverDate.timeIntervalSince1970) }
            t.property("timeIntervalSinceReferenceDate") { c in .double(c.receiverDate.timeIntervalSinceReferenceDate) }
            t.property("description") { c in .string(c.receiverDate.description) }
            t.method("addingTimeInterval", "_:number") { c in .native(.date(c.receiverDate.addingTimeInterval(c.double(0) ?? 0))) }
            t.method("advanced", "by:number") { c in .native(.date(c.receiverDate.advanced(by: c.double("by") ?? 0))) }
            t.method("timeIntervalSince", "_:any") { c in
                guard let o = KDates.date(c[0]) else { throw c.fail("needs a Date") }
                return .double(c.receiverDate.timeIntervalSince(o))
            }
            t.method("distance", "to:any") { c in
                guard let o = KDates.date(c["to"]) else { throw c.fail("needs a Date") }
                return .double(c.receiverDate.distance(to: o))
            }
            t.method("compare", "_:any") { c in
                guard let o = KDates.date(c[0]) else { throw c.fail("needs a Date") }
                return KComparison.kv(c.receiverDate.compare(o))
            }
            t.method("formatted", "") { c in .string(c.receiverDate.formatted()) }
            t.method("formatted", "date:any time:any") { c in
                .string(c.receiverDate.formatted(date: dateFormatStyle(c["date"] ?? .nilValue), time: timeFormatStyle(c["time"] ?? .nilValue)))
            }
            t.method("formatted", "_:any") { c in .string(KFormatting.formatted(c.receiver, c.first ?? .nilValue, c.interp)) }
            t.method("ISO8601Format", "_:any?") { c in .string(c.receiverDate.formatted(KFormatStyles.iso8601(c.first, c.interp))) }
        }
    }

    // MARK: Calendar

    static func calendar(_ r: KRegistry) {
        r.type("Calendar", .foundation, support: .full,
               notes: "Foundation's: every component, `date(byAdding:…)`, `date(from:)`, `date(bySettingHour:…)`, `dateComponents(_:from:)` and `(_:from:to:)`, `range(of:in:for:)`, `nextDate`, `enumerateDates`, `dateInterval(of:for:)`, the symbols, `firstWeekday`, `Calendar(identifier:)`.") { t in
            t.initializer("identifier:any") { c in
                guard let id = KDates.identifier(c["identifier"]) else { throw c.fail("needs a calendar identifier, as .gregorian") }
                return KDates.calendarValue(Calendar(identifier: id))
            }
            t.initializer("_:any") { c in
                guard let id = KDates.identifier(c[0]) else { throw c.fail("needs a calendar identifier, as .gregorian") }
                return KDates.calendarValue(Calendar(identifier: id))
            }
            for name in ["current", "autoupdatingCurrent"] {
                t.staticProperty(name) { _ in KDates.calendarValue(Calendar.current) }
            }
            t.implicit { name, args, _ in
                switch name {
                case "current", "autoupdatingCurrent": return KDates.calendarValue(.current)
                case "init": return args.first.flatMap { KDates.identifier($0) }.map { KDates.calendarValue(Calendar(identifier: $0)) }
                default: return nil
                }
            }
            @MainActor func cal(_ c: KCall) -> Calendar { KDates.calendar(c.receiver) ?? .current }
            @MainActor func date(_ c: KCall, _ ref: KArgRef) throws -> Date {
                guard let d = KDates.date(c[ref]) else { throw c.fail("needs a Date") }
                return d
            }
            @MainActor func comp(_ c: KCall, _ ref: KArgRef) throws -> Calendar.Component {
                guard let k = KDates.component(c[ref]) else { throw c.fail("needs a Calendar.Component, as .day") }
                return k
            }
            @MainActor func set(_ c: KCall, _ ref: KArgRef) throws -> Set<Calendar.Component> {
                guard let s = KDates.componentSet(c[ref], c.interp) else { throw c.fail("needs a set of components, as [.year, .month]") }
                return s
            }
            @MainActor func optDate(_ d: Date?) -> KV { d.map { .native(.date($0)) } ?? .nilValue }
            @MainActor func mutate(_ c: inout KCall, _ f: (inout Calendar) -> Void) {
                var copy = cal(c)
                f(&copy)
                c.mutated = KDates.calendarValue(copy)
            }

            // Settings.
            t.property("identifier") { c in .native(.implicit(KDates.identifierName(cal(c).identifier), [])) }
            t.property("timeZone", { c in KDates.timeZoneValue(cal(c).timeZone) }, set: { c in
                if let tz = KDates.timeZone(c.first) { mutate(&c) { $0.timeZone = tz } }
            })
            t.property("locale", { c in cal(c).locale.map { localeValue($0) } ?? .nilValue }, set: { c in
                let l = locale(c.first)
                mutate(&c) { $0.locale = l }
            })
            t.property("firstWeekday", { c in .int(cal(c).firstWeekday) }, set: { c in
                if let n = c.first?.asInt { mutate(&c) { $0.firstWeekday = n } }
            })
            t.property("minimumDaysInFirstWeek", { c in .int(cal(c).minimumDaysInFirstWeek) }, set: { c in
                if let n = c.first?.asInt { mutate(&c) { $0.minimumDaysInFirstWeek = n } }
            })
            let symbols: [String: KeyPath<Calendar, [String]>] = [
                "monthSymbols": \.monthSymbols, "shortMonthSymbols": \.shortMonthSymbols, "veryShortMonthSymbols": \.veryShortMonthSymbols,
                "standaloneMonthSymbols": \.standaloneMonthSymbols, "shortStandaloneMonthSymbols": \.shortStandaloneMonthSymbols,
                "veryShortStandaloneMonthSymbols": \.veryShortStandaloneMonthSymbols, "weekdaySymbols": \.weekdaySymbols,
                "shortWeekdaySymbols": \.shortWeekdaySymbols, "veryShortWeekdaySymbols": \.veryShortWeekdaySymbols,
                "standaloneWeekdaySymbols": \.standaloneWeekdaySymbols, "shortStandaloneWeekdaySymbols": \.shortStandaloneWeekdaySymbols,
                "veryShortStandaloneWeekdaySymbols": \.veryShortStandaloneWeekdaySymbols, "quarterSymbols": \.quarterSymbols,
                "shortQuarterSymbols": \.shortQuarterSymbols, "standaloneQuarterSymbols": \.standaloneQuarterSymbols,
                "eraSymbols": \.eraSymbols, "longEraSymbols": \.longEraSymbols,
            ]
            for (name, kp) in symbols { t.property(name) { c in .array(cal(c)[keyPath: kp].map { .string($0) }) } }
            t.property("amSymbol") { c in .string(cal(c).amSymbol) }
            t.property("pmSymbol") { c in .string(cal(c).pmSymbol) }

            // Components.
            t.method("component", "_:any from:any") { c in .int(cal(c).component(try comp(c, 0), from: try date(c, "from"))) }
            t.method("dateComponents", "_:any from:any") { c in KDates.comps(cal(c).dateComponents(try set(c, 0), from: try date(c, "from"))) }
            t.method("dateComponents", "_:any from:any to:any") { c in
                let s = try set(c, 0)
                if let a = KDates.date(c["from"]), let b = KDates.date(c["to"]) { return KDates.comps(cal(c).dateComponents(s, from: a, to: b)) }
                guard let a = KDates.comps(c["from"]), let b = KDates.comps(c["to"]) else { throw c.fail("needs two dates, or two DateComponents") }
                return KDates.comps(cal(c).dateComponents(s, from: a, to: b))
            }
            t.method("dateComponents", "in:any from:any") { c in
                guard let tz = KDates.timeZone(c["in"]) else { throw c.fail("needs a TimeZone") }
                return KDates.comps(cal(c).dateComponents(in: tz, from: try date(c, "from")))
            }
            t.method("ordinality", "of:any in:any for:any") { c in
                cal(c).ordinality(of: try comp(c, "of"), in: try comp(c, "in"), for: try date(c, "for")).map { .int($0) } ?? .nilValue
            }
            t.method("range", "of:any in:any for:any") { c in
                cal(c).range(of: try comp(c, "of"), in: try comp(c, "in"), for: try date(c, "for")).map { .range(.int($0.lowerBound), .int($0.upperBound), closed: false) } ?? .nilValue
            }
            t.method("minimumRange", "of:any") { c in cal(c).minimumRange(of: try comp(c, "of")).map { .range(.int($0.lowerBound), .int($0.upperBound), closed: false) } ?? .nilValue }
            t.method("maximumRange", "of:any") { c in cal(c).maximumRange(of: try comp(c, "of")).map { .range(.int($0.lowerBound), .int($0.upperBound), closed: false) } ?? .nilValue }

            // Making dates.
            t.method("date", "from:any") { c in
                guard let dc = KDates.comps(c["from"]) else { throw c.fail("needs DateComponents") }
                return optDate(cal(c).date(from: dc))
            }
            t.method("date", "byAdding:any value:number to:any wrappingComponents:bool?") { c in
                optDate(cal(c).date(byAdding: try comp(c, "byAdding"), value: c.int("value") ?? 0, to: try date(c, "to"),
                                    wrappingComponents: c.bool("wrappingComponents", default: false)))
            }
            t.method("date", "byAdding:any to:any wrappingComponents:bool?") { c in
                guard let dc = KDates.comps(c["byAdding"]) else { throw c.fail("needs DateComponents") }
                return optDate(cal(c).date(byAdding: dc, to: try date(c, "to"), wrappingComponents: c.bool("wrappingComponents", default: false)))
            }
            t.method("date", "bySettingHour:number minute:number second:number of:any matchingPolicy:any? repeatedTimePolicy:any? direction:any?") { c in
                optDate(cal(c).date(bySettingHour: c.int("bySettingHour") ?? 0, minute: c.int("minute") ?? 0, second: c.int("second") ?? 0,
                                    of: try date(c, "of"), matchingPolicy: KDates.policy(c["matchingPolicy"]),
                                    repeatedTimePolicy: KDates.repeated(c["repeatedTimePolicy"]), direction: KDates.direction(c["direction"])))
            }
            t.method("date", "bySetting:any value:number of:any") { c in
                optDate(cal(c).date(bySetting: try comp(c, "bySetting"), value: c.int("value") ?? 0, of: try date(c, "of")))
            }
            t.method("date", "_:any matchesComponents:any") { c in
                guard let dc = KDates.comps(c["matchesComponents"]) else { throw c.fail("needs DateComponents") }
                return .bool(cal(c).date(try date(c, 0), matchesComponents: dc))
            }
            t.method("startOfDay", "for:any") { c in .native(.date(cal(c).startOfDay(for: try date(c, "for")))) }
            t.method("nextDate", "after:any matching:any matchingPolicy:any repeatedTimePolicy:any? direction:any?") { c in
                guard let dc = KDates.comps(c["matching"]) else { throw c.fail("needs DateComponents") }
                return optDate(cal(c).nextDate(after: try date(c, "after"), matching: dc, matchingPolicy: KDates.policy(c["matchingPolicy"]),
                                               repeatedTimePolicy: KDates.repeated(c["repeatedTimePolicy"]), direction: KDates.direction(c["direction"])))
            }
            t.method("enumerateDates", "startingAfter:any matching:any matchingPolicy:any repeatedTimePolicy:any? direction:any? using:closure") { c in
                guard let dc = KDates.comps(c["matching"]), case .function(let f)? = c["using"] else { throw c.fail("needs DateComponents and a closure") }
                let interp = c.interp
                var failure: Error?
                var count = 0
                cal(c).enumerateDates(startingAfter: try date(c, "startingAfter"), matching: dc, matchingPolicy: KDates.policy(c["matchingPolicy"]),
                                      repeatedTimePolicy: KDates.repeated(c["repeatedTimePolicy"]), direction: KDates.direction(c["direction"])) { d, exact, stop in
                    count += 1
                    let flag = KBox(.bool(false))
                    do {
                        _ = try interp.call(f, [d.map { .native(.date($0)) } ?? .nilValue, .bool(exact),
                                                .binding(KBinding.inOut(get: { flag.value }, set: { flag.value = $0 }))], [nil, nil, nil])
                    } catch { failure = error; stop = true; return }
                    if interp.truthy(flag.value) || count > 100_000 { stop = true }
                }
                if let failure { throw failure }
                return .void
            }
            t.method("dateInterval", "of:any for:any") { c in
                cal(c).dateInterval(of: try comp(c, "of"), for: try date(c, "for")).map { KDates.interval($0) } ?? .nilValue
            }
            t.method("dateIntervalOfWeekend", "containing:any") { c in
                cal(c).dateIntervalOfWeekend(containing: try date(c, "containing")).map { KDates.interval($0) } ?? .nilValue
            }
            t.method("nextWeekend", "startingAfter:any direction:any?") { c in
                cal(c).nextWeekend(startingAfter: try date(c, "startingAfter"), direction: KDates.direction(c["direction"])).map { KDates.interval($0) } ?? .nilValue
            }

            // Comparing.
            t.method("isDate", "_:any inSameDayAs:any") { c in .bool(cal(c).isDate(try date(c, 0), inSameDayAs: try date(c, "inSameDayAs"))) }
            t.method("isDate", "_:any equalTo:any toGranularity:any") { c in
                .bool(cal(c).isDate(try date(c, 0), equalTo: try date(c, "equalTo"), toGranularity: try comp(c, "toGranularity")))
            }
            t.method("compare", "_:any to:any toGranularity:any") { c in
                KComparison.kv(cal(c).compare(try date(c, 0), to: try date(c, "to"), toGranularity: try comp(c, "toGranularity")))
            }
            for name in ["isDateInToday", "isDateInYesterday", "isDateInTomorrow", "isDateInWeekend"] {
                t.method(name, "_:any") { c in
                    let d = try date(c, 0), k = cal(c)
                    switch name {
                    case "isDateInToday": return .bool(k.isDateInToday(d))
                    case "isDateInYesterday": return .bool(k.isDateInYesterday(d))
                    case "isDateInTomorrow": return .bool(k.isDateInTomorrow(d))
                    default: return .bool(k.isDateInWeekend(d))
                    }
                }
            }
        }
        for (name, cases) in [("Calendar.Component", KDates.componentNames.map(\.0)),
                              ("Calendar.MatchingPolicy", ["nextTime", "strict", "nextTimePreservingSmallerComponents", "previousTimePreservingSmallerComponents"]),
                              ("Calendar.RepeatedTimePolicy", ["first", "last"]), ("Calendar.SearchDirection", ["forward", "backward"]),
                              ("Calendar.Identifier", ["gregorian", "iso8601", "buddhist", "chinese", "coptic", "hebrew", "indian", "islamic",
                                                       "islamicCivil", "islamicTabular", "islamicUmmAlQura", "japanese", "persian", "republicOfChina"])] {
            r.type(name, .foundation, support: .full) { t in
                for n in cases { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
            }
        }
    }

    // MARK: DateComponents and DateInterval

    static func dateComponents(_ r: KRegistry) {
        r.type("DateComponents", .foundation, support: .full, notes: "A value: every component, `calendar`, `timeZone`, `date`, `isValidDate`, `value(for:)`, `setValue(_:for:)`.") { t in
            t.initializer("calendar:any? timeZone:any? era:number? year:number? month:number? day:number? hour:number? minute:number? second:number? nanosecond:number? weekday:number? weekdayOrdinal:number? quarter:number? weekOfMonth:number? weekOfYear:number? yearForWeekOfYear:number? dayOfYear:number?") { c in
                KDates.comps(KDates.makeComponents(c))
            }
            @MainActor func dc(_ c: KCall) -> DateComponents { KDates.comps(c.receiver) ?? DateComponents() }
            for (name, kp) in KDates.componentFields {
                t.property(name, { c in dc(c)[keyPath: kp].map { .int($0) } ?? .nilValue }, set: { c in
                    var d = dc(c)
                    d[keyPath: kp] = c.first?.asInt
                    c.mutated = KDates.comps(d)
                })
            }
            t.property("isLeapMonth", { c in dc(c).isLeapMonth.map { .bool($0) } ?? .nilValue }, set: { c in
                var d = dc(c); d.isLeapMonth = c.first?.asBool; c.mutated = KDates.comps(d)
            })
            t.property("calendar", { c in dc(c).calendar.map { KDates.calendarValue($0) } ?? .nilValue }, set: { c in
                var d = dc(c); d.calendar = KDates.calendar(c.first); c.mutated = KDates.comps(d)
            })
            t.property("timeZone", { c in dc(c).timeZone.map { KDates.timeZoneValue($0) } ?? .nilValue }, set: { c in
                var d = dc(c); d.timeZone = KDates.timeZone(c.first); c.mutated = KDates.comps(d)
            })
            t.property("date") { c in dc(c).date.map { .native(.date($0)) } ?? .nilValue }
            t.property("isValidDate") { c in .bool(dc(c).isValidDate) }
            t.property("description") { c in .string(String(describing: dc(c))) }
            t.method("value", "for:any") { c in
                guard let k = KDates.component(c["for"]) else { throw c.fail("needs a component") }
                return dc(c).value(for: k).map { .int($0) } ?? .nilValue
            }
            t.method("setValue", "_:any for:any") { c in
                guard let k = KDates.component(c["for"]) else { throw c.fail("needs a component") }
                var d = dc(c)
                d.setValue(c[0]?.asInt, for: k)
                c.mutated = KDates.comps(d)
                return .void
            }
            t.method("isValidDate", "in:any") { c in .bool(dc(c).isValidDate(in: KDates.calendar(c["in"]) ?? .current)) }
        }
        r.type("DateInterval", .foundation, support: .full, notes: "`start`, `end`, `duration`, `contains`, `intersects`, `intersection(with:)`.") { t in
            t.initializer("start:any end:any") { c in
                guard let s = KDates.date(c["start"]), let e = KDates.date(c["end"]), e >= s else { throw c.fail("needs a start no later than its end") }
                return KDates.interval(DateInterval(start: s, end: e))
            }
            t.initializer("start:any duration:number") { c in
                guard let s = KDates.date(c["start"]) else { throw c.fail("needs a start Date") }
                return KDates.interval(DateInterval(start: s, duration: c.double("duration") ?? 0))
            }
            t.initializer("") { _ in KDates.interval(DateInterval()) }
            @MainActor func i(_ c: KCall) -> DateInterval { KDates.interval(c.receiver) ?? DateInterval() }
            t.property("start") { c in .native(.date(i(c).start)) }
            t.property("end") { c in .native(.date(i(c).end)) }
            t.property("duration") { c in .double(i(c).duration) }
            t.property("description") { c in .string(String(describing: i(c))) }
            t.method("contains", "_:any") { c in
                guard let d = KDates.date(c[0]) else { throw c.fail("needs a Date") }
                return .bool(i(c).contains(d))
            }
            t.method("intersects", "_:any") { c in
                guard let o = KDates.interval(c[0]) else { throw c.fail("needs a DateInterval") }
                return .bool(i(c).intersects(o))
            }
            t.method("intersection", "with:any") { c in
                guard let o = KDates.interval(c["with"]) else { throw c.fail("needs a DateInterval") }
                return i(c).intersection(with: o).map { KDates.interval($0) } ?? .nilValue
            }
            t.operator("<") { a, b, _ in
                guard let x = KDates.interval(a), let y = KDates.interval(b) else { return nil }
                return .bool(x < y)
            }
        }
    }

    // MARK: TimeZone

    static func timeZones(_ r: KRegistry) {
        r.type("TimeZone", .foundation, support: .full,
               notes: "`TimeZone.current`, `TimeZone(identifier:)`, `(secondsFromGMT:)`, `(abbreviation:)`: `identifier`, `secondsFromGMT(for:)`, `abbreviation(for:)`, `isDaylightSavingTime(for:)`.") { t in
            t.initializer("identifier:string") { c in TimeZone(identifier: c.string("identifier") ?? "").map { KDates.timeZoneValue($0) } ?? .nilValue }
            t.initializer("secondsFromGMT:number") { c in TimeZone(secondsFromGMT: c.int("secondsFromGMT") ?? 0).map { KDates.timeZoneValue($0) } ?? .nilValue }
            t.initializer("abbreviation:string") { c in TimeZone(abbreviation: c.string("abbreviation") ?? "").map { KDates.timeZoneValue($0) } ?? .nilValue }
            for name in ["current", "autoupdatingCurrent"] { t.staticProperty(name) { _ in KDates.timeZoneValue(.current) } }
            t.staticProperty("gmt") { _ in KDates.timeZoneValue(TimeZone(secondsFromGMT: 0)!) }
            t.staticProperty("knownTimeZoneIdentifiers") { _ in .array(TimeZone.knownTimeZoneIdentifiers.map { .string($0) }) }
            t.implicit { name, _, _ in
                switch name {
                case "current", "autoupdatingCurrent": return KDates.timeZoneValue(.current)
                case "gmt": return KDates.timeZoneValue(TimeZone(secondsFromGMT: 0)!)
                default: return nil
                }
            }
            @MainActor func tz(_ c: KCall) -> TimeZone { KDates.timeZone(c.receiver) ?? .current }
            t.property("identifier") { c in .string(tz(c).identifier) }
            t.property("description") { c in .string(tz(c).description) }
            t.method("secondsFromGMT", "for:any?") { c in .int(tz(c).secondsFromGMT(for: KDates.date(c["for"]) ?? Date())) }
            t.method("abbreviation", "for:any?") { c in tz(c).abbreviation(for: KDates.date(c["for"]) ?? Date()).map { .string($0) } ?? .nilValue }
            t.method("isDaylightSavingTime", "for:any?") { c in .bool(tz(c).isDaylightSavingTime(for: KDates.date(c["for"]) ?? Date())) }
            t.method("daylightSavingTimeOffset", "for:any?") { c in .double(tz(c).daylightSavingTimeOffset(for: KDates.date(c["for"]) ?? Date())) }
            t.method("localizedName", "for:any locale:any?") { c in
                let style: NSTimeZone.NameStyle
                switch c.symbol("for") {
                case "standard": style = .standard
                case "shortStandard": style = .shortStandard
                case "daylightSaving": style = .daylightSaving
                case "shortDaylightSaving": style = .shortDaylightSaving
                case "shortGeneric": style = .shortGeneric
                default: style = .generic
                }
                return tz(c).localizedName(for: style, locale: locale(c["locale"]) ?? .current).map { .string($0) } ?? .nilValue
            }
            t.operator("<") { _, _, _ in nil }
        }
    }

    // MARK: Formatters

    static func dateFormatters(_ r: KRegistry) {
        r.type("DateFormatter", .foundation, support: .full,
               notes: "`dateFormat`, `dateStyle`, `timeStyle`, `locale`, `timeZone`, `calendar`, `setLocalizedDateFormatFromTemplate`, the symbols.") { t in
            t.initializer("") { _ in .native(.object("DateFormatter", KRef(DateFormatter()))) }
            t.staticMethod("localizedString", "from:any dateStyle:any timeStyle:any") { c in
                guard let d = KDates.date(c["from"]) else { throw c.fail("needs a Date") }
                return .string(DateFormatter.localizedString(from: d, dateStyle: dateStyle(c["dateStyle"] ?? .nilValue), timeStyle: dateStyle(c["timeStyle"] ?? .nilValue)))
            }
            t.staticMethod("dateFormat", "fromTemplate:string options:number locale:any?") { c in
                DateFormatter.dateFormat(fromTemplate: c.string("fromTemplate") ?? "", options: 0, locale: locale(c["locale"]) ?? .current).map { .string($0) } ?? .nilValue
            }
            @MainActor func f(_ c: KCall) -> DateFormatter? { c.object(DateFormatter.self) }
            t.property("dateFormat", { c in .string(f(c)?.dateFormat ?? "") }, set: { c in f(c)?.dateFormat = c.first?.asString })
            t.property("dateStyle", { c in .native(.implicit(styleName(f(c)?.dateStyle ?? .none), [])) }, set: { c in f(c)?.dateStyle = dateStyle(c.first ?? .nilValue) })
            t.property("timeStyle", { c in .native(.implicit(styleName(f(c)?.timeStyle ?? .none), [])) }, set: { c in f(c)?.timeStyle = dateStyle(c.first ?? .nilValue) })
            t.property("locale", { c in f(c).map { localeValue($0.locale) } ?? .nilValue }, set: { c in f(c)?.locale = locale(c.first) })
            t.property("timeZone", { c in f(c).map { KDates.timeZoneValue($0.timeZone) } ?? .nilValue }, set: { c in f(c)?.timeZone = KDates.timeZone(c.first) })
            t.property("calendar", { c in f(c).map { KDates.calendarValue($0.calendar) } ?? .nilValue }, set: { c in f(c)?.calendar = KDates.calendar(c.first) })
            t.property("doesRelativeDateFormatting", { c in .bool(f(c)?.doesRelativeDateFormatting ?? false) },
                       set: { c in f(c)?.doesRelativeDateFormatting = c.first?.asBool ?? false })
            t.property("isLenient", { c in .bool(f(c)?.isLenient ?? false) }, set: { c in f(c)?.isLenient = c.first?.asBool ?? false })
            t.property("amSymbol", { c in .string(f(c)?.amSymbol ?? "AM") }, set: { c in f(c)?.amSymbol = c.first?.asString })
            t.property("pmSymbol", { c in .string(f(c)?.pmSymbol ?? "PM") }, set: { c in f(c)?.pmSymbol = c.first?.asString })
            let symbols: [String: KeyPath<DateFormatter, [String]?>] = [
                "monthSymbols": \.monthSymbols, "shortMonthSymbols": \.shortMonthSymbols, "veryShortMonthSymbols": \.veryShortMonthSymbols,
                "standaloneMonthSymbols": \.standaloneMonthSymbols, "weekdaySymbols": \.weekdaySymbols,
                "shortWeekdaySymbols": \.shortWeekdaySymbols, "veryShortWeekdaySymbols": \.veryShortWeekdaySymbols,
                "standaloneWeekdaySymbols": \.standaloneWeekdaySymbols, "shortStandaloneWeekdaySymbols": \.shortStandaloneWeekdaySymbols,
                "quarterSymbols": \.quarterSymbols, "eraSymbols": \.eraSymbols,
            ]
            for (name, kp) in symbols { t.property(name) { c in .array((f(c)?[keyPath: kp] ?? []).map { .string($0) }) } }
            t.method("setLocalizedDateFormatFromTemplate", "_:string") { c in f(c)?.setLocalizedDateFormatFromTemplate(c.string(0) ?? ""); return .void }
            t.method("string", "from:any") { c in
                guard let d = KDates.date(c["from"]) else { throw c.fail("needs a Date") }
                return .string(f(c)?.string(from: d) ?? "")
            }
            t.method("date", "from:string") { c in
                if let s = c.string("from"), let d = f(c)?.date(from: s) { return .native(.date(d)) }
                return .nilValue
            }
        }

        r.type("ISO8601DateFormatter", .foundation, support: .full, notes: "`string(from:)`, `date(from:)`, `formatOptions`, `timeZone`.") { t in
            t.initializer("") { _ in .native(.object("ISO8601DateFormatter", KRef(ISO8601DateFormatter()))) }
            t.staticMethod("string", "from:any timeZone:any formatOptions:any") { c in
                guard let d = KDates.date(c["from"]) else { throw c.fail("needs a Date") }
                return .string(ISO8601DateFormatter.string(from: d, timeZone: KDates.timeZone(c["timeZone"]) ?? TimeZone(secondsFromGMT: 0)!,
                                                           formatOptions: isoOptions(c["formatOptions"], c.interp)))
            }
            @MainActor func f(_ c: KCall) -> ISO8601DateFormatter? { c.object(ISO8601DateFormatter.self) }
            t.property("formatOptions", { c in isoOptionsValue(f(c)?.formatOptions ?? []) }, set: { c in f(c)?.formatOptions = isoOptions(c.first, c.interp) })
            t.property("timeZone", { c in f(c).map { KDates.timeZoneValue($0.timeZone) } ?? .nilValue }, set: { c in f(c)?.timeZone = KDates.timeZone(c.first) })
            t.method("string", "from:any") { c in
                guard let d = KDates.date(c["from"]) else { throw c.fail("needs a Date") }
                return .string(f(c)?.string(from: d) ?? "")
            }
            t.method("date", "from:string") { c in
                if let s = c.string("from"), let d = f(c)?.date(from: s) { return .native(.date(d)) }
                return .nilValue
            }
        }

        r.type("RelativeDateTimeFormatter", .foundation, support: .full,
               notes: "`localizedString(for:relativeTo:)`, `localizedString(fromTimeInterval:)`, `unitsStyle`, `dateTimeStyle`, `locale`.") { t in
            t.initializer("") { _ in .native(.object("RelativeDateTimeFormatter", KRef(RelativeDateTimeFormatter()))) }
            @MainActor func f(_ c: KCall) -> RelativeDateTimeFormatter? { c.object(RelativeDateTimeFormatter.self) }
            t.property("unitsStyle", { _ in .nilValue }, set: { c in
                switch c.symbol(0) {
                case "full": f(c)?.unitsStyle = .full
                case "short": f(c)?.unitsStyle = .short
                case "spellOut": f(c)?.unitsStyle = .spellOut
                default: f(c)?.unitsStyle = .abbreviated
                }
            })
            t.property("dateTimeStyle", { _ in .nilValue }, set: { c in f(c)?.dateTimeStyle = c.symbol(0) == "named" ? .named : .numeric })
            t.property("locale", { c in f(c).map { localeValue($0.locale) } ?? .nilValue }, set: { c in f(c)?.locale = locale(c.first) })
            t.property("calendar", { c in f(c).map { KDates.calendarValue($0.calendar) } ?? .nilValue }, set: { c in f(c)?.calendar = KDates.calendar(c.first) })
            t.method("localizedString", "for:any relativeTo:any?") { c in
                guard let d = KDates.date(c["for"]) else { throw c.fail("needs a Date") }
                return .string(f(c)?.localizedString(for: d, relativeTo: KDates.date(c["relativeTo"]) ?? Date()) ?? "")
            }
            t.method("localizedString", "fromTimeInterval:number") { c in .string(f(c)?.localizedString(fromTimeInterval: c.double("fromTimeInterval") ?? 0) ?? "") }
            t.method("localizedString", "from:any") { c in
                guard let dc = KDates.comps(c["from"]) else { throw c.fail("needs DateComponents") }
                return .string(f(c)?.localizedString(from: dc) ?? "")
            }
        }

        r.type("DateComponentsFormatter", .foundation, support: .full,
               notes: "`string(from:)` a number of seconds, two dates or `DateComponents`; `unitsStyle`, `allowedUnits`, `zeroFormattingBehavior`, `maximumUnitCount`.") { t in
            t.initializer("") { _ in .native(.object("DateComponentsFormatter", KRef(DateComponentsFormatter()))) }
            t.staticMethod("localizedString", "from:any unitsStyle:any") { c in
                guard let dc = KDates.comps(c["from"]) else { throw c.fail("needs DateComponents") }
                return DateComponentsFormatter.localizedString(from: dc, unitsStyle: unitsStyle(c.symbol("unitsStyle"))).map { .string($0) } ?? .nilValue
            }
            @MainActor func f(_ c: KCall) -> DateComponentsFormatter? { c.object(DateComponentsFormatter.self) }
            t.property("unitsStyle", { _ in .nilValue }, set: { c in f(c)?.unitsStyle = unitsStyle(c.symbol(0)) })
            t.property("allowedUnits", { _ in .nilValue }, set: { c in
                var units: NSCalendar.Unit = []
                for k in KDates.componentSet(c.first, c.interp) ?? [] {
                    switch k {
                    case .year: units.insert(.year)
                    case .month: units.insert(.month)
                    case .weekOfMonth, .weekOfYear: units.insert(.weekOfMonth)
                    case .day: units.insert(.day)
                    case .hour: units.insert(.hour)
                    case .minute: units.insert(.minute)
                    case .second: units.insert(.second)
                    default: break
                    }
                }
                f(c)?.allowedUnits = units
            })
            t.property("zeroFormattingBehavior", { _ in .nilValue }, set: { c in
                var b: DateComponentsFormatter.ZeroFormattingBehavior = []
                let names: [KV] = (c.first?.asArray) ?? (c.first.map { [$0] } ?? [])
                for n in names {
                    switch n {
                    case .native(.implicit("pad", _)): b.insert(.pad)
                    case .native(.implicit("dropLeading", _)): b.insert(.dropLeading)
                    case .native(.implicit("dropMiddle", _)): b.insert(.dropMiddle)
                    case .native(.implicit("dropTrailing", _)): b.insert(.dropTrailing)
                    case .native(.implicit("dropAll", _)): b.insert(.dropAll)
                    default: b.insert(.default)
                    }
                }
                f(c)?.zeroFormattingBehavior = b
            })
            t.property("maximumUnitCount", { c in .int(f(c)?.maximumUnitCount ?? 0) }, set: { c in f(c)?.maximumUnitCount = c.first?.asInt ?? 0 })
            t.property("includesApproximationPhrase", { _ in .nilValue }, set: { c in f(c)?.includesApproximationPhrase = c.first?.asBool ?? false })
            t.property("includesTimeRemainingPhrase", { _ in .nilValue }, set: { c in f(c)?.includesTimeRemainingPhrase = c.first?.asBool ?? false })
            t.property("collapsesLargestUnit", { _ in .nilValue }, set: { c in f(c)?.collapsesLargestUnit = c.first?.asBool ?? false })
            t.property("allowsFractionalUnits", { _ in .nilValue }, set: { c in f(c)?.allowsFractionalUnits = c.first?.asBool ?? false })
            t.method("string", "from:any") { c in
                if let s = c["from"]?.asDouble { return f(c)?.string(from: s).map { .string($0) } ?? .nilValue }
                if let dc = KDates.comps(c["from"]) { return f(c)?.string(from: dc).map { .string($0) } ?? .nilValue }
                throw c.fail("needs a number of seconds or DateComponents")
            }
            t.method("string", "from:any to:any") { c in
                guard let a = KDates.date(c["from"]), let b = KDates.date(c["to"]) else { throw c.fail("needs two dates") }
                return f(c)?.string(from: a, to: b).map { .string($0) } ?? .nilValue
            }
        }
    }

    static func unitsStyle(_ s: String?) -> DateComponentsFormatter.UnitsStyle {
        switch s {
        case "abbreviated": return .abbreviated
        case "short": return .short
        case "full": return .full
        case "spellOut": return .spellOut
        case "brief": return .brief
        default: return .positional
        }
    }

    static let isoOptionNames: [(String, ISO8601DateFormatter.Options)] = [
        ("withYear", .withYear), ("withMonth", .withMonth), ("withWeekOfYear", .withWeekOfYear), ("withDay", .withDay),
        ("withTime", .withTime), ("withTimeZone", .withTimeZone), ("withSpaceBetweenDateAndTime", .withSpaceBetweenDateAndTime),
        ("withDashSeparatorInDate", .withDashSeparatorInDate), ("withColonSeparatorInTime", .withColonSeparatorInTime),
        ("withColonSeparatorInTimeZone", .withColonSeparatorInTimeZone), ("withFractionalSeconds", .withFractionalSeconds),
        ("withFullDate", .withFullDate), ("withFullTime", .withFullTime), ("withInternetDateTime", .withInternetDateTime),
    ]
    @MainActor static func isoOptions(_ v: KV?, _ interp: KInterpreter) -> ISO8601DateFormatter.Options {
        var o: ISO8601DateFormatter.Options = []
        let items = (v.flatMap { try? interp.sequence($0) }) ?? (v.map { [$0] } ?? [])
        for x in items { if case .native(.implicit(let n, _)) = x, let opt = isoOptionNames.first(where: { $0.0 == n })?.1 { o.insert(opt) } }
        if case .native(.implicit(let n, _))? = v, let opt = isoOptionNames.first(where: { $0.0 == n })?.1 { o.insert(opt) }
        return o
    }
    static func isoOptionsValue(_ o: ISO8601DateFormatter.Options) -> KV {
        .array(isoOptionNames.filter { o.contains($0.1) }.map { .native(.implicit($0.0, [])) })
    }

    static func styleName(_ s: DateFormatter.Style) -> String {
        switch s {
        case .short: return "short"
        case .medium: return "medium"
        case .long: return "long"
        case .full: return "full"
        default: return "none"
        }
    }

    static func dateStyle(_ v: KV) -> DateFormatter.Style {
        guard case .native(.implicit(let s, _)) = v else { return .none }
        switch s {
        case "short": return .short
        case "medium": return .medium
        case "long": return .long
        case "full": return .full
        default: return .none
        }
    }

    static func numberStyle(_ s: String) -> NumberFormatter.Style {
        switch s {
        case "currency": return .currency
        case "percent": return .percent
        case "decimal": return .decimal
        case "spellOut": return .spellOut
        case "ordinal": return .ordinal
        case "scientific": return .scientific
        case "currencyAccounting": return .currencyAccounting
        case "currencyISOCode": return .currencyISOCode
        case "currencyPlural": return .currencyPlural
        default: return .none
        }
    }

    static func dateFormatStyle(_ v: KV) -> Date.FormatStyle.DateStyle {
        guard case .native(.implicit(let s, _)) = v else { return .abbreviated }
        switch s {
        case "omitted": return .omitted
        case "numeric": return .numeric
        case "long": return .long
        case "complete": return .complete
        default: return .abbreviated
        }
    }

    static func timeFormatStyle(_ v: KV) -> Date.FormatStyle.TimeStyle {
        guard case .native(.implicit(let s, _)) = v else { return .shortened }
        switch s {
        case "omitted": return .omitted
        case "complete": return .complete
        case "standard": return .standard
        default: return .shortened
        }
    }
}
