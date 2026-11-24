//
//  Parsing.swift
//  Bridges: NSRegularExpression, NSDataDetector, Scanner and CharacterSet (PLAN.md §3.3)
//
//      let regex = try NSRegularExpression(pattern: "#(\\w+)")
//      let range = NSRange(text.startIndex..., in: text)
//      for m in regex.matches(in: text, range: range) {
//          if let r = Range(m.range(at: 1), in: text) { tags.append(String(text[r])) }
//      }
//
//      let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
//
//  Each is Foundation's own. Kiln's string indices are character offsets, so
//  an `NSRange` (UTF-16, as Foundation's) converts to and from them with
//  `NSRange(_:in:)` and `Range(_:in:)`, as in compiled Swift.
//

import SwiftUI

/// An `NSRange`, in UTF-16 units as Foundation's.
struct KNSRange: Hashable, KDescribable {
    var r: NSRange
    var kv: KV { .native(.boxed(KBoxed("NSRange", self))) }
    func describe(_ interp: KInterpreter) -> String { "{\(r.location), \(r.length)}" }
    static func from(_ v: KV?) -> NSRange? {
        if case .native(.boxed(let b))? = v { return b.get(KNSRange.self)?.r }
        return nil
    }

    /// Character offsets in `text` → UTF-16.
    static func make(_ lo: Int, _ hi: Int, in text: String) -> NSRange {
        let a = text.index(text.startIndex, offsetBy: min(max(lo, 0), text.count))
        let b = text.index(text.startIndex, offsetBy: min(max(hi, lo), text.count))
        return NSRange(a..<b, in: text)
    }

    /// UTF-16 → character offsets in `text`, or nil when it's outside it.
    @MainActor static func offsets(_ r: NSRange, in text: String) -> KV {
        guard r.location != NSNotFound, let range = Range(r, in: text) else { return .nilValue }
        return KBuiltins.offsetRange(range, in: text)
    }
}

/// An `NSTextCheckingResult`, with the text it was found in.
final class KCheckingResult: KDescribable {
    let result: NSTextCheckingResult
    let text: String
    init(_ r: NSTextCheckingResult, _ text: String) {
        result = r
        self.text = text
    }
    var kv: KV { .native(.object("NSTextCheckingResult", KRef(self))) }
    func describe(_ interp: KInterpreter) -> String { "NSTextCheckingResult" }
}

/// A `CharacterSet`, Foundation's own.
struct KCharacterSet: Hashable {
    var set: CharacterSet
    var kv: KV { .native(.boxed(KBoxed("CharacterSet", self))) }

    static let named: [String: CharacterSet] = [
        "whitespaces": .whitespaces, "whitespacesAndNewlines": .whitespacesAndNewlines, "newlines": .newlines,
        "decimalDigits": .decimalDigits, "letters": .letters, "lowercaseLetters": .lowercaseLetters,
        "uppercaseLetters": .uppercaseLetters, "alphanumerics": .alphanumerics, "punctuationCharacters": .punctuationCharacters,
        "symbols": .symbols, "controlCharacters": .controlCharacters, "illegalCharacters": .illegalCharacters,
        "capitalizedLetters": .capitalizedLetters, "nonBaseCharacters": .nonBaseCharacters, "decomposables": .decomposables,
        "urlQueryAllowed": .urlQueryAllowed, "urlPathAllowed": .urlPathAllowed, "urlHostAllowed": .urlHostAllowed,
        "urlFragmentAllowed": .urlFragmentAllowed, "urlUserAllowed": .urlUserAllowed, "urlPasswordAllowed": .urlPasswordAllowed,
    ]

    /// A set the app named: a value, or `.whitespaces` with no type.
    static func from(_ v: KV?) -> CharacterSet? {
        switch v {
        case .native(.boxed(let b))?: return b.get(KCharacterSet.self)?.set
        case .native(.implicit(let n, let args))? where args.isEmpty: return named[n]
        case .native(.implicit("init", let args))?, .native(.implicit("charactersIn", let args))?:
            return args.first?.asString.map { CharacterSet(charactersIn: $0) }
        default: return nil
        }
    }
}

/// `NSTextCheckingResult.CheckingType`'s values.
enum KCheckingTypes {
    static let all: [String: NSTextCheckingResult.CheckingType] = [
        "orthography": .orthography, "spelling": .spelling, "grammar": .grammar, "date": .date, "address": .address,
        "link": .link, "quote": .quote, "dash": .dash, "replacement": .replacement, "correction": .correction,
        "regularExpression": .regularExpression, "phoneNumber": .phoneNumber, "transitInformation": .transitInformation,
    ]
    static func name(_ t: NSTextCheckingResult.CheckingType) -> String { all.first { $0.value == t }?.key ?? "regularExpression" }

    /// `.link.rawValue | .date.rawValue`, `[.link, .date]`, or one type.
    static func types(_ v: KV?) -> NSTextCheckingResult.CheckingType {
        switch v {
        case .int(let i)?: return NSTextCheckingResult.CheckingType(rawValue: UInt64(max(i, 0)))
        case .native(.implicit(let n, _))?: return all[n] ?? []
        case .array(let a)?: return a.reduce([]) { $0.union(types($1)) }
        default: return []
        }
    }
}

extension KTextBridges {
    static func parsing(_ r: KRegistry) {
        ranges(r)
        regularExpressions(r)
        scanner(r)
        characterSets(r)
    }

    // MARK: NSRange

    static func ranges(_ r: KRegistry) {
        r.type("NSRange", .text, support: .full, notes: "`NSRange(text.startIndex..., in: text)`, `NSRange(location:length:)`; `Range(nsRange, in: text)` back.") { t in
            t.initializer("location:number length:number") { c in KNSRange(r: NSRange(location: c.int("location") ?? 0, length: c.int("length") ?? 0)).kv }
            t.initializer("_:any in:string") { c in
                let text = c.string("in") ?? ""
                guard case .range(let lo, let hi, let closed)? = c[0] else { throw c.fail("needs a range of the string") }
                let l = lo.asInt ?? 0
                let h = hi.isNil ? text.count : (hi.asInt ?? 0) + (closed ? 1 : 0)
                return KNSRange(r: KNSRange.make(l, h, in: text)).kv
            }
            @MainActor func me(_ c: KCall) -> NSRange { KNSRange.from(c.receiver) ?? NSRange(location: NSNotFound, length: 0) }
            t.property("location") { c in .int(me(c).location) }
            t.property("length") { c in .int(me(c).length) }
            t.property("lowerBound") { c in .int(me(c).lowerBound) }
            t.property("upperBound") { c in .int(me(c).upperBound) }
        }
        r.function("NSMakeRange", .text, "_:number _:number", owner: "Foundation") { c in
            KNSRange(r: NSMakeRange(c.int(0) ?? 0, c.int(1) ?? 0)).kv
        }
        r.addConstant("NSNotFound") { _ in .int(NSNotFound) }
    }

    /// `Range(nsRange, in: text)`, `text.utf16`, `(text as NSString).substring(with:)`: on other families' types.
    static func parsingExtensions(_ r: KRegistry) {
        r.extend("Range") { t in
            t.initializer("_:any in:string") { c in
                guard let ns = KNSRange.from(c[0]) else { throw c.fail("needs an NSRange") }
                return KNSRange.offsets(ns, in: c.string("in") ?? "")
            }
        }
        // `url.host()` (iOS 16), which detected links are read with.
        r.extend("URL") { t in
            t.method("host", "percentEncoded:bool?") { c in
                guard case .native(.url(let u)) = c.receiver else { throw c.noMember() }
                return u.host(percentEncoded: c.bool("percentEncoded", default: true)).map { .string($0) } ?? .nilValue
            }
        }
        r.extend("String") { t in
            @MainActor func s(_ c: KCall) -> String { c.receiver.asString ?? "" }
            t.property("utf16") { c in .array(s(c).utf16.map { .int(Int($0)) }) }
            t.property("length") { c in .int(s(c).utf16.count) }
            t.method("substring", "with:any") { c in
                guard let ns = KNSRange.from(c["with"]) else { throw c.fail("needs an NSRange") }
                return .string((s(c) as NSString).substring(with: ns))
            }
            t.method("rangeOfCharacter", "from:any") { c in
                let str = s(c)
                guard let set = KCharacterSet.from(c["from"]) else { throw c.fail("needs a CharacterSet") }
                return str.rangeOfCharacter(from: set).map { KBuiltins.offsetRange($0, in: str) } ?? .nilValue
            }
            t.method("addingPercentEncoding", "withAllowedCharacters:any") { c in
                guard let set = KCharacterSet.from(c["withAllowedCharacters"]) else { throw c.fail("needs a CharacterSet") }
                return s(c).addingPercentEncoding(withAllowedCharacters: set).map { .string($0) } ?? .nilValue
            }
            t.property("removingPercentEncoding") { c in s(c).removingPercentEncoding.map { .string($0) } ?? .nilValue }
        }
    }

    // MARK: NSRegularExpression and NSDataDetector

    static func regularExpressions(_ r: KRegistry) {
        @MainActor func options(_ v: KV?) -> NSRegularExpression.Options {
            let names: [String: NSRegularExpression.Options] = [
                "caseInsensitive": .caseInsensitive, "allowCommentsAndWhitespace": .allowCommentsAndWhitespace,
                "ignoreMetacharacters": .ignoreMetacharacters, "dotMatchesLineSeparators": .dotMatchesLineSeparators,
                "anchorsMatchLines": .anchorsMatchLines, "useUnixLineSeparators": .useUnixLineSeparators,
                "useUnicodeWordBoundaries": .useUnicodeWordBoundaries,
            ]
            switch v {
            case .native(.implicit(let n, _))?: return names[n] ?? []
            case .array(let a)?: return a.reduce([]) { $0.union(options($1)) }
            default: return []
            }
        }
        @MainActor func text(_ c: KCall) -> String { c.string("in") ?? "" }
        @MainActor func range(_ c: KCall) -> NSRange {
            KNSRange.from(c["range"]) ?? NSRange(text(c).startIndex..., in: text(c))
        }
        @MainActor func matchMembers(_ t: KTypeBuilder) {
            @MainActor func re(_ c: KCall) throws -> NSRegularExpression {
                guard let x = c.object(NSRegularExpression.self) else { throw c.noMember() }
                return x
            }
            let rest = "options:any? range:any?"
            t.method("firstMatch", "in:string \(rest)") { c in
                try re(c).firstMatch(in: text(c), options: [], range: range(c)).map { KCheckingResult($0, text(c)).kv } ?? .nilValue
            }
            t.method("matches", "in:string \(rest)") { c in
                .array(try re(c).matches(in: text(c), options: [], range: range(c)).map { KCheckingResult($0, text(c)).kv })
            }
            t.method("numberOfMatches", "in:string \(rest)") { c in .int(try re(c).numberOfMatches(in: text(c), options: [], range: range(c))) }
            t.method("rangeOfFirstMatch", "in:string \(rest)") { c in KNSRange(r: try re(c).rangeOfFirstMatch(in: text(c), options: [], range: range(c))).kv }
            t.method("enumerateMatches", "in:string \(rest) using:closure") { c in
                guard let f = c.function("using") else { throw c.fail("needs a closure") }
                let s = text(c)
                for m in try re(c).matches(in: s, options: [], range: range(c)) {
                    let stop = KStopFlag()
                    _ = try c.interp.call(f, [KCheckingResult(m, s).kv, .array([]), .native(.object("UnsafeMutablePointer", KRef(stop)))], [nil, nil, nil])
                    if stop.stop { break }
                }
                return .void
            }
        }

        r.type("NSRegularExpression", .text, support: .full,
               notes: "`try NSRegularExpression(pattern:options:)`: `matches(in:range:)`, `firstMatch`, `numberOfMatches`, `stringByReplacingMatches(in:range:withTemplate:)`; results' `range(at:)` and `range(withName:)` are `NSRange`s.") { t in
            t.initializer("pattern:string options:any?") { c in
                do {
                    return .native(.object("NSRegularExpression", KRef(try NSRegularExpression(pattern: c.string("pattern") ?? "", options: options(c["options"])))))
                } catch {
                    throw FoundationBridges.thrown(error, c)
                }
            }
            t.staticMethod("escapedPattern", "for:string") { c in .string(NSRegularExpression.escapedPattern(for: c.string("for") ?? "")) }
            t.staticMethod("escapedTemplate", "for:string") { c in .string(NSRegularExpression.escapedTemplate(for: c.string("for") ?? "")) }
            t.property("pattern") { c in .string(c.object(NSRegularExpression.self)?.pattern ?? "") }
            t.property("numberOfCaptureGroups") { c in .int(c.object(NSRegularExpression.self)?.numberOfCaptureGroups ?? 0) }
            matchMembers(t)
            t.method("stringByReplacingMatches", "in:string options:any? range:any? withTemplate:string") { c in
                guard let x = c.object(NSRegularExpression.self) else { throw c.noMember() }
                return .string(x.stringByReplacingMatches(in: text(c), options: [], range: range(c), withTemplate: c.string("withTemplate") ?? ""))
            }
        }
        r.type("NSRegularExpression.Options", .text, support: .full) { t in
            for n in ["caseInsensitive", "allowCommentsAndWhitespace", "ignoreMetacharacters", "dotMatchesLineSeparators", "anchorsMatchLines",
                      "useUnixLineSeparators", "useUnicodeWordBoundaries"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }

        r.type("NSDataDetector", .text, support: .full,
               notes: "`try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | …)`: links, dates, phone numbers, addresses and transit information; results' `url`, `date`, `duration`, `phoneNumber`, `addressComponents`.") { t in
            t.initializer("types:any") { c in
                do {
                    return .native(.object("NSRegularExpression", KRef(try NSDataDetector(types: KCheckingTypes.types(c["types"]).rawValue))))
                } catch {
                    throw FoundationBridges.thrown(error, c)
                }
            }
        }

        r.type("NSTextCheckingResult", .text, support: .full) { t in
            @MainActor func me(_ c: KCall) throws -> KCheckingResult {
                guard let x = c.object(KCheckingResult.self) else { throw c.noMember() }
                return x
            }
            t.property("range") { c in KNSRange(r: try me(c).result.range).kv }
            t.property("numberOfRanges") { c in .int(try me(c).result.numberOfRanges) }
            t.method("range", "at:number") { c in KNSRange(r: try me(c).result.range(at: c.int("at") ?? 0)).kv }
            t.method("range", "withName:string") { c in KNSRange(r: try me(c).result.range(withName: c.string("withName") ?? "")).kv }
            t.property("resultType") { c in .native(.implicit(KCheckingTypes.name(try me(c).result.resultType), [])) }
            t.property("url") { c in try me(c).result.url.map { .native(.url($0)) } ?? .nilValue }
            t.property("date") { c in try me(c).result.date.map { .native(.date($0)) } ?? .nilValue }
            t.property("duration") { c in .double(try me(c).result.duration) }
            t.property("timeZone") { c in try me(c).result.timeZone.map { .string($0.identifier) } ?? .nilValue }
            t.property("phoneNumber") { c in try me(c).result.phoneNumber.map { .string($0) } ?? .nilValue }
            t.property("addressComponents") { c in
                guard let comps = try me(c).result.addressComponents else { return .nilValue }
                var d: [KV: KV] = [:]
                for (k, v) in comps { d[.native(.implicit(k.rawValue.prefix(1).lowercased() + k.rawValue.dropFirst(), []))] = .string(v) }
                return .dict(d)
            }
            t.property("components") { c in
                guard let comps = try me(c).result.components else { return .nilValue }
                var d: [KV: KV] = [:]
                for (k, v) in comps { d[.native(.implicit(k.rawValue.prefix(1).lowercased() + k.rawValue.dropFirst(), []))] = .string(v) }
                return .dict(d)
            }
        }
        r.type("NSTextCheckingResult.CheckingType", .text, support: .full) { t in
            for (n, v) in KCheckingTypes.all {
                t.staticProperty(n) { _ in .native(.implicit(n, [])) }
                _ = v
            }
            t.staticProperty("allTypes") { _ in .int(Int(NSTextCheckingAllTypes)) }
        }
        r.type("NSTextCheckingKey", .text, support: .full) { t in
            for n in ["name", "jobTitle", "organization", "street", "city", "state", "zip", "country", "phone", "airline", "flight"] {
                t.staticProperty(n) { _ in .native(.implicit(n, [])) }
            }
        }
        // `.link.rawValue`: a checking type's bits.
        r.implicitProperties["rawValue"] = { name, args in
            guard args.isEmpty, let t = KCheckingTypes.all[name] else { return nil }
            return .int(Int(t.rawValue))
        }
        r.type("UnsafeMutablePointer", .text) { t in
            t.internal()
            t.property("pointee", { c in .bool(c.object(KStopFlag.self)?.stop ?? false) }, set: { c in
                c.object(KStopFlag.self)?.stop = c.args.first.map { c.interp.truthy($0) } ?? false
            })
        }
    }

    // MARK: Scanner

    static func scanner(_ r: KRegistry) {
        r.type("Scanner", .text, support: .full,
               notes: "`Scanner(string:)`: `scanInt()`, `scanDouble()`, `scanDecimal()`, `scanString(_:)`, `scanUpToString(_:)`, `scanCharacters(from:)`, `scanUpToCharacters(from:)`, `scanCharacter()`, `isAtEnd`, `currentIndex` (a character offset), `charactersToBeSkipped`, `caseSensitive`.") { t in
            t.initializer("string:string") { c in .native(.object("Scanner", KRef(Scanner(string: c.string("string") ?? "")))) }
            @MainActor func sc(_ c: KCall) throws -> Scanner {
                guard let s = c.object(Scanner.self) else { throw c.noMember() }
                return s
            }
            t.property("string") { c in .string(try sc(c).string) }
            t.property("isAtEnd") { c in .bool(try sc(c).isAtEnd) }
            t.property("currentIndex", { c in
                let s = try sc(c)
                return .int(s.string.distance(from: s.string.startIndex, to: s.currentIndex))
            }, set: { c in
                let s = try sc(c)
                s.currentIndex = s.string.index(s.string.startIndex, offsetBy: min(max(c.int(0) ?? 0, 0), s.string.count))
            })
            t.property("charactersToBeSkipped", { c in try sc(c).charactersToBeSkipped.map { KCharacterSet(set: $0).kv } ?? .nilValue }, set: { c in
                try sc(c).charactersToBeSkipped = KCharacterSet.from(c.args.first)
            })
            t.property("caseSensitive", { c in .bool(try sc(c).caseSensitive) }, set: { c in
                try sc(c).caseSensitive = c.args.first.map { c.interp.truthy($0) } ?? false
            })
            t.method("scanInt", "representation:any?") { c in
                let s = try sc(c)
                if c.symbol("representation") == "hexadecimal" { return s.scanInt(representation: .hexadecimal).map { .int($0) } ?? .nilValue }
                return s.scanInt().map { .int($0) } ?? .nilValue
            }
            t.method("scanDouble", "representation:any?") { c in try sc(c).scanDouble().map { .double($0) } ?? .nilValue }
            t.method("scanFloat", "representation:any?") { c in try sc(c).scanFloat().map { .double(Double($0)) } ?? .nilValue }
            t.method("scanDecimal", "") { c in try sc(c).scanDecimal().map { KDecimal($0).kv } ?? .nilValue }
            t.method("scanString", "_:string") { c in try sc(c).scanString(c.string(0) ?? "").map { .string($0) } ?? .nilValue }
            t.method("scanUpToString", "_:string") { c in try sc(c).scanUpToString(c.string(0) ?? "").map { .string($0) } ?? .nilValue }
            t.method("scanCharacter", "") { c in try sc(c).scanCharacter().map { .string(String($0)) } ?? .nilValue }
            t.method("scanCharacters", "from:any") { c in
                guard let set = KCharacterSet.from(c["from"]) else { throw c.fail("needs a CharacterSet") }
                return try sc(c).scanCharacters(from: set).map { .string($0) } ?? .nilValue
            }
            t.method("scanUpToCharacters", "from:any") { c in
                guard let set = KCharacterSet.from(c["from"]) else { throw c.fail("needs a CharacterSet") }
                return try sc(c).scanUpToCharacters(from: set).map { .string($0) } ?? .nilValue
            }
        }
    }

    // MARK: CharacterSet

    static func characterSets(_ r: KRegistry) {
        r.type("CharacterSet", .text, support: .full,
               notes: "Foundation's sets (`.whitespaces`, `.decimalDigits`, `.letters`, `.alphanumerics`, `.punctuationCharacters`, `.urlQueryAllowed`…), `CharacterSet(charactersIn:)`, `inverted`, `union`, `subtracting`, `contains`.") { t in
            for (n, s) in KCharacterSet.named { t.staticProperty(n) { _ in KCharacterSet(set: s).kv } }
            t.implicit { name, args, labels in
                if name == "init" || labels.first == "charactersIn" { return args.first?.asString.map { KCharacterSet(set: CharacterSet(charactersIn: $0)).kv } }
                return args.isEmpty ? KCharacterSet.named[name].map { KCharacterSet(set: $0).kv } : nil
            }
            t.initializer("charactersIn:string") { c in KCharacterSet(set: CharacterSet(charactersIn: c.string("charactersIn") ?? "")).kv }
            t.initializer("") { _ in KCharacterSet(set: CharacterSet()).kv }
            @MainActor func me(_ c: KCall) throws -> CharacterSet {
                guard let s = KCharacterSet.from(c.receiver) else { throw c.noMember() }
                return s
            }
            @MainActor func other(_ c: KCall) throws -> CharacterSet {
                guard let s = KCharacterSet.from(c[0]) else { throw c.fail("needs a CharacterSet") }
                return s
            }
            t.property("inverted") { c in KCharacterSet(set: try me(c).inverted).kv }
            t.method("union", "_:any") { c in KCharacterSet(set: try me(c).union(try other(c))).kv }
            t.method("intersection", "_:any") { c in KCharacterSet(set: try me(c).intersection(try other(c))).kv }
            t.method("subtracting", "_:any") { c in KCharacterSet(set: try me(c).subtracting(try other(c))).kv }
            t.method("isSuperset", "of:any") { c in .bool(try me(c).isSuperset(of: KCharacterSet.from(c["of"]) ?? CharacterSet())) }
            t.method("contains", "_:any") { c in
                let set = try me(c)
                guard let scalar = KScalar.from(c[0]) else { return .bool(false) }
                return .bool(set.contains(scalar))
            }
            t.method("insert", "charactersIn:string") { c in
                var set = try me(c)
                set.insert(charactersIn: c.string("charactersIn") ?? "")
                c.mutated = KCharacterSet(set: set).kv
                return .void
            }
            t.method("remove", "charactersIn:string") { c in
                var set = try me(c)
                set.remove(charactersIn: c.string("charactersIn") ?? "")
                c.mutated = KCharacterSet(set: set).kv
                return .void
            }
            t.method("formUnion", "_:any") { c in
                c.mutated = KCharacterSet(set: try me(c).union(try other(c))).kv
                return .void
            }
        }
    }
}

/// `stop.pointee = true` in `enumerateMatches`.
final class KStopFlag { var stop = false }
