//
//  Foundation.swift
//  Bridges: Foundation
//
//  Dates, UUIDs, URLs and Data; formatters and calendars (Dates.swift); JSON
//  (JSON.swift); `UserDefaults`, `DispatchQueue`, `Timer`, `IndexSet`, format
//  styles, errors, and the few UIKit objects models reach for.
//

import SwiftUI

@objc(KilnBridges_Foundation)
final class FoundationBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        values(r)
        dates(r)
        json(r)
        coding(r)
        system(r)
        fileSystem(r)
        formatStyles(r)
        formatters(r)
        systemMore(r)
        dataMore(r)
    }

    /// The second pass: types later families declare (`AttributedString`).
    override class func extend(into r: KRegistry) {
        extendLater(r)
    }

    // MARK: Values

    static func values(_ r: KRegistry) {
        r.type("UUID", .foundation, support: .full) { t in
            t.initializer { c in
                if let s = c.arg("uuidString")?.asString { return UUID(uuidString: s).map { .native(.uuid($0)) } ?? .nilValue }
                return .native(.uuid(UUID()))
            }
            t.properties(["uuidString", "description"]) { c, _ in
                if case .native(.uuid(let u)) = c.receiver { return .string(u.uuidString) }
                return .string("")
            }
            t.property("hashValue") { c in
                if case .native(.uuid(let u)) = c.receiver { return .int(u.hashValue) }
                return .int(0)
            }
        }

        r.type("URL", .foundation) { t in
            t.initializer { c in
                if let s = c.arg("string")?.asString { return URL(string: s).map { .native(.url($0)) } ?? .nilValue }
                if let s = (c.arg("fileURLWithPath") ?? c.arg("filePath"))?.asString { return .native(.url(URL(fileURLWithPath: s))) }
                return .nilValue
            }
            @MainActor func u(_ c: KCall) -> URL? { if case .native(.url(let u)) = c.receiver { return u }; return nil }
            t.property("absoluteString") { c in .string(u(c)?.absoluteString ?? "") }
            t.property("host") { c in u(c)?.host.map { .string($0) } ?? .nilValue }
            t.property("lastPathComponent") { c in .string(u(c)?.lastPathComponent ?? "") }
        }

        r.type("Data", .foundation, notes: "`Data()`, `Data(text.utf8)` and `Data([UInt8])`; `String(data:encoding:)` and `JSONDecoder` read it.") { t in
            t.initializer { c in
                if c.has("contentsOf") { return try dataContents(c) }
                // `Data(text.utf8)` and `Data([0x48, 0x69])`: bytes; `Data(other)`: a copy.
                switch c.first {
                case .array(let bytes)?: return KBuiltins.data(Data(bytes.map { UInt8(truncatingIfNeeded: $0.asInt ?? 0) }))
                case .string(let s)?: return KBuiltins.data(Data(s.utf8))
                case .native(.object("Data", let ref))?: return KBuiltins.data((ref.value as? Data) ?? Data())
                default:
                    if let n = c.arg("count")?.asInt { return KBuiltins.data(Data(count: n)) }
                    return .native(.object("Data", KRef(NSData())))
                }
            }
            t.property("count") { c in .int(c.object(Data.self)?.count ?? 0) }
            t.property("isEmpty") { c in .bool(c.object(Data.self)?.isEmpty ?? true) }
        }

        r.type("Error", .foundation) { t in
            t.properties(["localizedDescription", "description"]) { c, _ in
                .string(c.object(NSError.self)?.localizedDescription ?? "Error")
            }
        }

        r.type("IndexSet", .foundation, support: .full) { t in
            t.initializer { c in
                if let i = c.first?.asInt { return .native(.indexSet(IndexSet(integer: i))) }
                if let xs = c.first.flatMap({ try? c.interp.sequence($0) }) { return .native(.indexSet(IndexSet(xs.compactMap(\.asInt)))) }
                return .native(.indexSet(IndexSet()))
            }
            @MainActor func s(_ c: KCall) -> IndexSet { if case .native(.indexSet(let s)) = c.receiver { return s }; return [] }
            t.property("first") { c in s(c).first.map { .int($0) } ?? .nilValue }
            t.property("count") { c in .int(s(c).count) }
            t.method("contains") { c in .bool(s(c).contains(c.first?.asInt ?? -1)) }
            t.method("map") { c in
                let f = try c.interp.applier(c.at(0) ?? .void, c.line)
                return .array(try s(c).map { try f(.int($0)) })
            }
        }
    }

    // MARK: The system

    /// An app value as a property list, for `UserDefaults`.
    @MainActor static func plist(_ v: KV, _ interp: KInterpreter) -> Any? {
        switch v {
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .native(.date(let d)): return d
        case .native(.url(let u)): return u.absoluteString
        case .array(let xs): return xs.compactMap { plist($0, interp) }
        case .dict(let pairs):
            var out: [String: Any] = [:]
            for (k, x) in pairs { if let k = k.asString, let p = plist(x, interp) { out[k] = p } }
            return out
        default: return KBuiltins.dataValue(v)
        }
    }

    /// A property list read back as an app value.
    @MainActor static func fromPlist(_ any: Any) -> KV {
        switch any {
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            if CFNumberIsFloatType(n) { return .double(n.doubleValue) }
            return .int(n.intValue)
        case let s as String: return .string(s)
        case let d as Date: return .native(.date(d))
        case let d as Data: return KBuiltins.data(d)
        case let xs as [Any]: return .array(xs.map(fromPlist))
        case let m as [String: Any]:
            return .dict(Dictionary(uniqueKeysWithValues: m.map { (KV.string($0.key), fromPlist($0.value)) }))
        default: return .nilValue
        }
    }

    static func system(_ r: KRegistry) {
        r.type("UserDefaults", .foundation, notes: "The app's own settings: `standard` is the app's suite, which its `@AppStorage` shares.") { t in
            // The run's defaults (§1.7): each app has its own suite.
            t.staticProperty("standard") { c in .native(.object("UserDefaults", KRef(c.context.defaults))) }
            @MainActor func d(_ c: KCall) -> UserDefaults { c.object(UserDefaults.self) ?? c.context.defaults }
            @MainActor func key(_ c: KCall) -> String { c.arg("forKey")?.asString ?? "" }
            t.method("set") { c in
                let k = key(c), defaults = d(c)
                switch c.first ?? .nilValue {
                case .nilValue: defaults.removeObject(forKey: k)
                case .int(let i): defaults.set(i, forKey: k)
                case .double(let v): defaults.set(v, forKey: k)
                case .string(let s): defaults.set(s, forKey: k)
                case .bool(let b): defaults.set(b, forKey: k)
                case let v:
                    if let data = KBuiltins.dataValue(v) { defaults.set(data, forKey: k) }
                    else if let plist = plist(v, c.interp) { defaults.set(plist, forKey: k) }
                    else { defaults.set(c.interp.describe(v), forKey: k) }
                }
                return .void
            }
            t.method("integer") { c in .int(d(c).integer(forKey: key(c))) }
            t.method("double") { c in .double(d(c).double(forKey: key(c))) }
            t.method("float") { c in .double(Double(d(c).float(forKey: key(c)))) }
            t.method("bool") { c in .bool(d(c).bool(forKey: key(c))) }
            t.method("string") { c in d(c).string(forKey: key(c)).map { .string($0) } ?? .nilValue }
            t.method("data") { c in d(c).data(forKey: key(c)).map { KBuiltins.data($0) } ?? .nilValue }
            t.method("url") { c in d(c).url(forKey: key(c)).map { .native(.url($0)) } ?? .nilValue }
            for name in ["object", "array", "stringArray", "dictionary"] {
                t.method(name, notes: "Strings, numbers, Bools, dates, Data, and arrays and dictionaries of them.") { c in
                    d(c).object(forKey: key(c)).map { fromPlist($0) } ?? .nilValue
                }
            }
            t.method("removeObject") { c in d(c).removeObject(forKey: key(c)); return .void }
            t.method("register") { c in
                guard case .dict(let pairs)? = c.arg("defaults") ?? c.first else { return .void }
                var values: [String: Any] = [:]
                for (k, v) in pairs { if let k = k.asString, let p = plist(v, c.interp) { values[k] = p } }
                d(c).register(defaults: values)
                return .void
            }
            t.method("dictionaryRepresentation") { c in fromPlist(d(c).dictionaryRepresentation()) }
        }

        r.type("DispatchQueue", .foundation, notes: "Everything runs on the main queue.") { t in
            t.staticProperty("main") { _ in .native(.object("DispatchQueue", KRef(DispatchQueue.main))) }
            t.staticMethod("global") { _ in .native(.object("DispatchQueue", KRef(DispatchQueue.main))) }
            t.method("asyncAfter") { c in
                var delay = 0.0
                if case .native(.date(let when))? = c.arg("deadline") ?? c.first { delay = max(0, when.timeIntervalSinceNow) }
                else if let s = (c.arg("deadline") ?? c.first)?.asDouble { delay = s }
                if case .function(let f)? = c.last {
                    let interp = c.interp
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { interp.perform(f) } }
                }
                return .void
            }
            t.methods(["async", "sync"]) { c, name in
                guard case .function(let f)? = c.last else { return .void }
                // `sync` runs the work now and returns what it returns.
                if name == "sync" { return try c.interp.call(f, [], []) }
                let interp = c.interp
                DispatchQueue.main.async { MainActor.assumeIsolated { interp.perform(f) } }
                return .void
            }
        }

        r.type("Timer", .foundation) { t in
            t.initializer { _ in .native(.timer(KRef(KTimerBox()))) }
            t.staticMethod("publish", notes: "With `.onReceive`; `.autoconnect()` is accepted.") { c in
                .native(.publisher(c.arg("every")?.asDouble ?? 1))
            }
            t.staticMethod("scheduledTimer") { c in
                let interval = c.arg("withTimeInterval")?.asDouble ?? c.arg("timeInterval")?.asDouble ?? 1
                let repeats = c.arg("repeats").map { c.interp.truthy($0) } ?? false
                let box = KTimerBox()
                if case .function(let block)? = c.last {
                    let timerValue = KV.native(.timer(KRef(box)))
                    let interp = c.interp
                    box.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
                        MainActor.assumeIsolated { interp.perform(block, [timerValue]) }
                    }
                    interp.runtime.timers.append(box)
                }
                return .native(.timer(KRef(box)))
            }
            @MainActor func box(_ c: KCall) -> KTimerBox? { if case .native(.timer(let t)) = c.receiver { return t.value }; return nil }
            t.property("isValid") { c in .bool(box(c)?.timer?.isValid ?? false) }
            t.method("invalidate") { c in box(c)?.invalidate(); return .void }
            t.method("fire") { c in box(c)?.timer?.fire(); return .void }
        }
        r.type("Timer.TimerPublisher", .foundation) { t in
            t.internal()
            t.methods(["autoconnect", "receive", "eraseToAnyPublisher"]) { c, _ in c.receiver }
        }

        r.type("Locale", .foundation, support: .full,
               notes: "`Locale.current`, `Locale(identifier:)`: `identifier`, `measurementSystem` (`.metric`, `.us`, `.uk`), `usesMetricSystem`, `region`, `language`, `currency`, `decimalSeparator`.") { t in
            t.initializer("identifier:string") { c in localeValue(Locale(identifier: c.string("identifier") ?? "")) }
            t.initializer("_:string") { c in localeValue(Locale(identifier: c.string(0) ?? "")) }
            t.staticProperty("current") { _ in localeValue(.current) }
            t.staticProperty("autoupdatingCurrent") { _ in localeValue(.autoupdatingCurrent) }
            @MainActor func me(_ c: KCall) -> Locale { locale(c.receiver) ?? .current }
            t.property("identifier") { c in .string(me(c).identifier) }
            t.property("measurementSystem") { c in
                let m = me(c).measurementSystem
                return .native(.implicit(m == .us ? "us" : (m == .uk ? "uk" : "metric"), []))
            }
            t.property("usesMetricSystem") { c in .bool((me(c) as NSLocale).usesMetricSystem) }
            t.property("region") { c in me(c).region.map { .tuple([.string($0.identifier)], ["identifier"]) } ?? .nilValue }
            t.property("language") { c in
                let l = me(c).language
                return .tuple([l.languageCode.map { .tuple([.string($0.identifier)], ["identifier"]) } ?? .nilValue], ["languageCode"])
            }
            t.property("currency") { c in me(c).currency.map { .tuple([.string($0.identifier)], ["identifier"]) } ?? .nilValue }
            t.property("decimalSeparator") { c in me(c).decimalSeparator.map { .string($0) } ?? .nilValue }
            t.property("groupingSeparator") { c in me(c).groupingSeparator.map { .string($0) } ?? .nilValue }
            t.method("localizedString", "forIdentifier:string") { c in me(c).localizedString(forIdentifier: c.string("forIdentifier") ?? "").map { .string($0) } ?? .nilValue }
            t.method("localizedString", "forRegionCode:string") { c in me(c).localizedString(forRegionCode: c.string("forRegionCode") ?? "").map { .string($0) } ?? .nilValue }
            t.method("localizedString", "forLanguageCode:string") { c in me(c).localizedString(forLanguageCode: c.string("forLanguageCode") ?? "").map { .string($0) } ?? .nilValue }
            t.method("localizedString", "forCurrencyCode:string") { c in me(c).localizedString(forCurrencyCode: c.string("forCurrencyCode") ?? "").map { .string($0) } ?? .nilValue }
            t.staticProperty("preferredLanguages") { _ in .array(Locale.preferredLanguages.map { .string($0) }) }
            t.staticProperty("availableIdentifiers") { _ in .array(Locale.availableIdentifiers.map { .string($0) }) }
            t.property("currencySymbol") { c in me(c).currencySymbol.map { .string($0) } ?? .nilValue }
            t.property("calendar") { c in KDates.calendarValue(me(c).calendar) }
        }
        r.type("Locale.MeasurementSystem", .foundation, support: .full) { t in
            for n in ["metric", "us", "uk"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }

        r.type("UIScreen", .foundation, notes: "`UIScreen.main.bounds` is an iPhone's screen; prefer GeometryReader.") { t in
            t.staticProperty("main") { _ in .native(.object("UIScreen", KRef(NSObject()))) }
            t.property("bounds") { _ in .tuple([.double(0), .double(0), .double(402), .double(874)], ["x", "y", "width", "height"]) }
            t.property("main") { c in c.receiver }
        }
        r.type("UIApplication", .foundation, support: .stub) { t in
            t.anyStatic { _, _ in .native(.object("UIApplication", KRef(NSObject()))) }
            t.anyMethod { _, _ in .void }
        }
    }

    // MARK: Locale

    /// A `Locale` value (`Locale.current`, `\.locale`), as an object the app passes around.
    static func localeValue(_ l: Locale) -> KV { .native(.object("Locale", KRef(l as NSLocale))) }

    /// The `Locale` an argument names: a locale value, or an identifier.
    static func locale(_ v: KV?) -> Locale? {
        switch v {
        case .native(.object("Locale", let ref))?: return (ref.value as? NSLocale).map { $0 as Locale }
        case .string(let s)?: return Locale(identifier: s)
        default: return nil
        }
    }

    // MARK: Format styles

    static func formatStyles(_ r: KRegistry) {
        // `.currency(code:)`, `.number`, `.percent`, `.dateTime` anywhere a
        // format is written.
        r.addContextFree("currency") { args, _, _ in
            .native(.format(KFormat(kind: .currency(args.first?.asString ?? Locale.current.currency?.identifier ?? "USD"))))
        }
        r.addContextFree("number") { _, _, _ in .native(.format(KFormat(kind: .number))) }
        r.addContextFree("percent") { _, _, _ in .native(.format(KFormat(kind: .percent))) }
        r.addContextFree("dateTime") { _, _, _ in .native(.format(KFormat(kind: .dateTime))) }

        r.type("FormatStyle", .foundation, support: .full) { t in
            // Each call is kept (`steps`) and replayed onto Foundation's style (FormatStyles.swift).
            t.anyProperty { c, name in
                guard case .native(.format(var f)) = c.receiver else { return nil }
                if name == "grouping" { f.grouping = false } else { f.components.append(name) }
                f.steps.append(KFormatStep(name: name, args: [], labels: []))
                return .native(.format(f))
            }
            t.method("precision") { c in
                guard case .native(.format(var f)) = c.receiver else { return c.receiver }
                if case .native(.implicit(let p, let pa))? = c.first, p == "fractionLength" {
                    if let n = pa.first?.asInt { f.fraction = n...n }
                    else if case .range(let lo, let hi, _)? = pa.first { f.fraction = (lo.asInt ?? 0)...(hi.asInt ?? 2) }
                }
                f.steps.append(KFormatStep(name: "precision", args: c.args, labels: c.labels))
                return .native(.format(f))
            }
            t.method("grouping") { c in
                guard case .native(.format(var f)) = c.receiver else { return c.receiver }
                if KFormatStyles.symbol(c.first) != "automatic" { f.grouping = false }
                f.steps.append(KFormatStep(name: "grouping", args: c.args, labels: c.labels))
                return .native(.format(f))
            }
            t.method("format", "_:any") { c in .string(KFormatting.formatted(c.first ?? .nilValue, c.receiver, c.interp)) }
            t.anyMethod { c, name in
                guard case .native(.format(var f)) = c.receiver else { return nil }
                f.components.append(name)
                f.steps.append(KFormatStep(name: name, args: c.args, labels: c.labels))
                return .native(.format(f))
            }
        }
    }
}
