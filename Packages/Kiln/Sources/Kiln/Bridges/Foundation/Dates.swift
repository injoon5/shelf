//
//  Dates.swift
//  Bridges: Date, Calendar and the formatters
//

import SwiftUI

extension FoundationBridges {
    static func dates(_ r: KRegistry) {
        r.addContextFree("now") { _, _, _ in .native(.date(Date())) }

        r.type("Date", .foundation) { t in
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
            t.method("addingTimeInterval") { c in .native(.date(c.receiverDate.addingTimeInterval(c.first?.asDouble ?? 0))) }
            t.method("timeIntervalSince") { c in
                guard case .native(.date(let o))? = c.first else { throw c.noMember() }
                return .double(c.receiverDate.timeIntervalSince(o))
            }
            t.method("distance") { c in
                guard case .native(.date(let o))? = c.first else { throw c.noMember() }
                return .double(c.receiverDate.distance(to: o))
            }
            t.method("formatted") { c in
                let d = c.receiverDate
                if let ds = c.arg("date"), let ts = c.arg("time") {
                    return .string(d.formatted(date: dateFormatStyle(ds), time: timeFormatStyle(ts)))
                }
                if let style = c.first { return .string(KFormatting.formatted(.native(.date(d)), style, c.interp)) }
                return .string(d.formatted())
            }
            t.method("compare") { c in
                guard case .native(.date(let o))? = c.first else { throw c.noMember() }
                let d = c.receiverDate
                return .native(.implicit(d < o ? "orderedAscending" : (d > o ? "orderedDescending" : "orderedSame"), []))
            }
        }

        r.type("DateFormatter", .foundation, notes: "`dateStyle`, `timeStyle` and `dateFormat`; other settings are ignored.") { t in
            t.initializer { _ in .native(.object("DateFormatter", KRef(DateFormatter()))) }
            t.staticMethod("localizedString") { c in
                guard case .native(.date(let d))? = c.arg("from") ?? c.first else { return .string("") }
                return .string(DateFormatter.localizedString(from: d, dateStyle: c.arg("dateStyle").map(dateStyle) ?? .none,
                                                             timeStyle: c.arg("timeStyle").map(dateStyle) ?? .none))
            }
            t.property("dateFormat", { c in .string(c.object(DateFormatter.self)?.dateFormat ?? "") },
                       set: { c in c.object(DateFormatter.self)?.dateFormat = c.first?.asString })
            t.property("dateStyle", { _ in .nilValue }, set: { c in c.object(DateFormatter.self)?.dateStyle = dateStyle(c.first ?? .nilValue) })
            t.property("timeStyle", { _ in .nilValue }, set: { c in c.object(DateFormatter.self)?.timeStyle = dateStyle(c.first ?? .nilValue) })
            t.anySetter { _, _ in true }
            t.method("string") { c in
                guard case .native(.date(let d))? = c.arg("from") ?? c.first else { return .string("") }
                return .string(c.object(DateFormatter.self)?.string(from: d) ?? "")
            }
            t.method("date") { c in
                if let s = (c.arg("from") ?? c.first)?.asString, let d = c.object(DateFormatter.self)?.date(from: s) { return .native(.date(d)) }
                return .nilValue
            }
        }

        r.type("NumberFormatter", .foundation, notes: "`numberStyle`, the fraction digits and `currencyCode`; other settings are ignored.") { t in
            t.initializer { _ in .native(.object("NumberFormatter", KRef(NumberFormatter()))) }
            t.staticMethod("localizedString") { c in
                let f = NumberFormatter()
                if case .native(.implicit(let s, _))? = c.arg("number") { f.numberStyle = numberStyle(s) }
                return .string(f.string(from: NSNumber(value: (c.arg("from") ?? c.first)?.asDouble ?? 0)) ?? "")
            }
            t.property("numberStyle", { _ in .nilValue }, set: { c in
                if case .native(.implicit(let s, _))? = c.first { c.object(NumberFormatter.self)?.numberStyle = numberStyle(s) }
            })
            t.property("maximumFractionDigits", { c in .int(c.object(NumberFormatter.self)?.maximumFractionDigits ?? 0) },
                       set: { c in c.object(NumberFormatter.self)?.maximumFractionDigits = c.first?.asInt ?? 2 })
            t.property("minimumFractionDigits", { c in .int(c.object(NumberFormatter.self)?.minimumFractionDigits ?? 0) },
                       set: { c in c.object(NumberFormatter.self)?.minimumFractionDigits = c.first?.asInt ?? 0 })
            t.property("currencyCode", { c in .string(c.object(NumberFormatter.self)?.currencyCode ?? "") },
                       set: { c in c.object(NumberFormatter.self)?.currencyCode = c.first?.asString })
            t.anySetter { _, _ in true }
            t.method("string") { c in
                let v = (c.arg("from") ?? c.first)?.asDouble ?? 0
                return c.object(NumberFormatter.self)?.string(from: NSNumber(value: v)).map { .string($0) } ?? .nilValue
            }
        }

        r.type("RelativeDateTimeFormatter", .foundation) { t in
            t.initializer { _ in .native(.object("RelativeDateTimeFormatter", KRef(RelativeDateTimeFormatter()))) }
            t.anySetter { _, _ in true }
            t.method("localizedString") { c in
                guard case .native(.date(let d))? = c.arg("for") ?? c.first else { return .string("") }
                return .string(c.object(RelativeDateTimeFormatter.self)?.localizedString(for: d, relativeTo: Date()) ?? "")
            }
        }

        r.type("DateComponents", .foundation, notes: "Its labelled values, as a tuple: `.day`, `.hour`, `.minute`, `.second`.") { t in
            t.initializer { c in .tuple(c.args, c.labels) }
        }

        r.type("Calendar", .foundation, notes: "The current calendar.") { t in
            t.initializer { _ in .native(.object("Calendar", KRef(Calendar.current as NSCalendar))) }
            for name in ["current", "autoupdatingCurrent"] {
                t.staticProperty(name) { _ in .native(.object("Calendar", KRef(Calendar.current as NSCalendar))) }
            }
            @MainActor func date(_ v: KV?) -> Date? { if case .native(.date(let d))? = v { return d }; return nil }
            @MainActor func component(_ v: KV?) -> Calendar.Component? {
                guard case .native(.implicit(let n, _))? = v else { return nil }
                let map: [String: Calendar.Component] = ["year": .year, "month": .month, "day": .day, "hour": .hour, "minute": .minute,
                    "second": .second, "weekday": .weekday, "weekOfYear": .weekOfYear, "weekOfMonth": .weekOfMonth]
                return map[n]
            }
            let cal = Calendar.current
            @MainActor func unsupported(_ c: KCall) -> KERuntimeError { c.interp.fail("Calendar.\(c.memberName) isn't supported in Kiln", c.line) }
            t.method("component") { c in
                guard let comp = component(c.first), let d = date(c.arg("from")) else { throw unsupported(c) }
                return .int(cal.component(comp, from: d))
            }
            t.method("isDateInToday") { c in guard let d = date(c.first) else { throw unsupported(c) }; return .bool(cal.isDateInToday(d)) }
            t.method("isDateInYesterday") { c in guard let d = date(c.first) else { throw unsupported(c) }; return .bool(cal.isDateInYesterday(d)) }
            t.method("isDateInTomorrow") { c in guard let d = date(c.first) else { throw unsupported(c) }; return .bool(cal.isDateInTomorrow(d)) }
            t.method("isDateInWeekend") { c in guard let d = date(c.first) else { throw unsupported(c) }; return .bool(cal.isDateInWeekend(d)) }
            t.method("isDate") { c in
                guard let a = date(c.first), let b = date(c.arg("inSameDayAs")) else { throw unsupported(c) }
                return .bool(cal.isDate(a, inSameDayAs: b))
            }
            t.method("startOfDay") { c in
                guard let d = date(c.arg("for") ?? c.first) else { throw unsupported(c) }
                return .native(.date(cal.startOfDay(for: d)))
            }
            t.method("date") { c in
                guard let comp = component(c.arg("byAdding")), let v = c.arg("value")?.asInt, let d = date(c.arg("to")) else { throw unsupported(c) }
                return cal.date(byAdding: comp, value: v, to: d).map { .native(.date($0)) } ?? .nilValue
            }
            t.method("dateComponents") { c in
                guard let from = date(c.arg("from")), let to = date(c.arg("to")) else { throw unsupported(c) }
                let comps = cal.dateComponents([.day, .hour, .minute, .second], from: from, to: to)
                return .tuple([.int(comps.day ?? 0), .int(comps.hour ?? 0), .int(comps.minute ?? 0), .int(comps.second ?? 0)], ["day", "hour", "minute", "second"])
            }
            t.anyMethod { c, _ in throw unsupported(c) }
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
        s == "currency" ? .currency : (s == "percent" ? .percent : (s == "decimal" ? .decimal : .none))
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
