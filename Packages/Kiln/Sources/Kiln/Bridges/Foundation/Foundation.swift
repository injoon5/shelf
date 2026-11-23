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
        formatStyles(r)
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
                if let s = c.arg("fileURLWithPath")?.asString { return .native(.url(URL(fileURLWithPath: s))) }
                return .nilValue
            }
            @MainActor func u(_ c: KCall) -> URL? { if case .native(.url(let u)) = c.receiver { return u }; return nil }
            t.property("absoluteString") { c in .string(u(c)?.absoluteString ?? "") }
            t.property("host") { c in u(c)?.host.map { .string($0) } ?? .nilValue }
            t.property("lastPathComponent") { c in .string(u(c)?.lastPathComponent ?? "") }
        }

        r.type("Data", .foundation, notes: "`Data()`, `Data(text.utf8)` and `Data([UInt8])`; `String(data:encoding:)` and `JSONDecoder` read it.") { t in
            t.initializer { c in
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

    static func system(_ r: KRegistry) {
        r.type("UserDefaults", .foundation, notes: "Each key is kept apart from Shelf's own settings.") { t in
            t.staticProperty("standard") { _ in .native(.object("UserDefaults", KRef(UserDefaults.standard))) }
            @MainActor func key(_ c: KCall) -> String { "kiln." + (c.arg("forKey")?.asString ?? "") }
            t.method("set") { c in
                let k = key(c)
                switch c.first ?? .nilValue {
                case .int(let i): UserDefaults.standard.set(i, forKey: k)
                case .double(let d): UserDefaults.standard.set(d, forKey: k)
                case .string(let s): UserDefaults.standard.set(s, forKey: k)
                case .bool(let b): UserDefaults.standard.set(b, forKey: k)
                case let v: UserDefaults.standard.set(c.interp.describe(v), forKey: k)
                }
                return .void
            }
            t.method("integer") { c in .int(UserDefaults.standard.integer(forKey: key(c))) }
            t.method("double") { c in .double(UserDefaults.standard.double(forKey: key(c))) }
            t.method("bool") { c in .bool(UserDefaults.standard.bool(forKey: key(c))) }
            t.method("string") { c in UserDefaults.standard.string(forKey: key(c)).map { .string($0) } ?? .nilValue }
            for name in ["object", "data", "array", "stringArray", "dictionary"] {
                t.method(name, notes: "Always nil: store strings, numbers or Bools.") { _ in .nilValue }
            }
            t.method("removeObject") { c in UserDefaults.standard.removeObject(forKey: key(c)); return .void }
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
            t.methods(["async", "sync"]) { c, _ in
                if case .function(let f)? = c.last {
                    let interp = c.interp
                    DispatchQueue.main.async { MainActor.assumeIsolated { interp.perform(f) } }
                }
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

        r.type("Locale", .foundation, support: .stub) { t in
            t.initializer { _ in .native(.object("Locale", KRef(NSObject()))) }
            t.staticProperty("current") { _ in .native(.object("Locale", KRef(NSObject()))) }
            t.property("identifier") { _ in .string(Locale.current.identifier) }
        }
        r.type("TimeZone", .foundation, support: .stub) { t in
            t.initializer { _ in .native(.object("TimeZone", KRef(NSObject()))) }
            t.staticProperty("current") { _ in .native(.object("TimeZone", KRef(NSObject()))) }
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

        r.type("FormatStyle", .foundation, notes: "`.number`, `.percent`, `.currency(code:)` with `.precision(.fractionLength(n))`, and `.dateTime` with its parts.") { t in
            t.anyProperty { c, name in
                guard case .native(.format(var f)) = c.receiver else { return nil }
                if name == "grouping" { f.grouping = false } else { f.components.append(name) }
                return .native(.format(f))
            }
            t.method("precision") { c in
                guard case .native(.format(var f)) = c.receiver else { return c.receiver }
                if case .native(.implicit(let p, let pa))? = c.first, p == "fractionLength" {
                    if let n = pa.first?.asInt { f.fraction = n...n }
                    else if case .range(let lo, let hi, _)? = pa.first { f.fraction = (lo.asInt ?? 0)...(hi.asInt ?? 2) }
                }
                return .native(.format(f))
            }
            t.method("grouping") { c in
                guard case .native(.format(var f)) = c.receiver else { return c.receiver }
                f.grouping = false
                return .native(.format(f))
            }
            t.anyMethod { c, name in
                guard case .native(.format(var f)) = c.receiver else { return nil }
                f.components.append(name)
                return .native(.format(f))
            }
        }
    }
}
