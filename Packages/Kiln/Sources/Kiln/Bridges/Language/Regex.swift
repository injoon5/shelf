//
//  Regex.swift
//  Bridges: Regex, from literals and from strings
//
//  `/\d+/` and `#/…/#` (KELexer) and `try Regex("…")` are a real
//  `Regex<AnyRegexOutput>`, wrapped in `KRegexBox`. A match is a `KRegexMatch`:
//  `match.0` is the whole match, `match.1`… the captures, `match.name` a
//  named capture, `match.output` all of them as a tuple.
//
//  PLAN.md §1.6 makes the value and the basics (`firstMatch`, `wholeMatch`,
//  `contains`, `replacing`, `matches(of:)`, `case /…/:`). §3.3 owns the rest
//  of the API and RegexBuilder, which uses `r.resultBuilder` (KEBuilders).
//

import SwiftUI

/// A compiled regex and the source it came from.
final class KRegexBox {
    let regex: Regex<AnyRegexOutput>
    let source: String
    init(_ regex: Regex<AnyRegexOutput>, source: String) {
        self.regex = regex
        self.source = source
    }
}

/// One match: the whole text, each capture (nil when it didn't take part), their names.
final class KRegexMatch {
    let whole: String
    let captures: [KV]
    let names: [String?]
    let range: (Int, Int)
    init(_ m: Regex<AnyRegexOutput>.Match, in text: String) {
        whole = String(text[m.range])
        var caps: [KV] = []
        var names: [String?] = []
        for (i, e) in m.output.enumerated() where i > 0 {
            caps.append(e.substring.map { .string(String($0)) } ?? .nilValue)
            names.append(e.name)
        }
        captures = caps
        self.names = names
        range = (text.distance(from: text.startIndex, to: m.range.lowerBound), text.distance(from: text.startIndex, to: m.range.upperBound))
    }

    /// `match.output`: the whole match, then each capture, labeled by its name.
    var output: KV {
        if captures.isEmpty { return .string(whole) }
        return .tuple([.string(whole)] + captures, [nil] + names)
    }
}

extension KBuiltins {
    @MainActor private static var regexCache: [String: KRegexBox] = [:]

    /// A literal's regex, compiled once per pattern.
    @MainActor static func regex(_ pattern: String, _ interp: KInterpreter, _ line: Int) throws -> KV {
        if let box = regexCache[pattern] { return .native(.object("Regex", KRef(box))) }
        do {
            let box = KRegexBox(try Regex(pattern), source: pattern)
            regexCache[pattern] = box
            return .native(.object("Regex", KRef(box)))
        } catch {
            throw interp.fail("Invalid regex /\(pattern)/: \(error)", line)
        }
    }

    static func regexBox(_ v: KV?) -> KRegexBox? {
        if case .native(.object("Regex", let ref))? = v { return ref.value as? KRegexBox }
        return nil
    }

    static func match(_ m: Regex<AnyRegexOutput>.Match?, in text: String) -> KV {
        guard let m else { return .nilValue }
        return .native(.object("Regex.Match", KRef(KRegexMatch(m, in: text))))
    }

    /// `text.replacing(regex, with: "…")` or `with: { match in … }`.
    @MainActor static func replacing(_ text: String, _ r: KRegexBox, _ with: KV?, maxReplacements: Int, _ interp: KInterpreter, _ line: Int) throws -> String {
        var out = ""
        var rest = text.startIndex
        var count = 0
        for m in text.matches(of: r.regex) where count < maxReplacements {
            out += text[rest..<m.range.lowerBound]
            switch with {
            case .function(let f)?:
                out += interp.describe(try interp.call(f, [match(m, in: text)], [nil]))
            case let v?:
                out += v.asString ?? interp.describe(v)
            case nil:
                break
            }
            rest = m.range.upperBound
            count += 1
            if m.range.isEmpty { break }
        }
        return out + text[rest...]
    }
}

extension LanguageBridges {
    static func regex(_ r: KRegistry) {
        r.type("Regex", .language, notes: "From `/…/`, `#/…/#` or `try Regex(\"…\")`. §1.6 has the basics: `firstMatch`, `wholeMatch`, `contains`, `replacing`, `matches(of:)`, `case /…/:`.") { t in
            t.initializer("_:string") { c in
                let pattern = c.string(0) ?? ""
                do {
                    return .native(.object("Regex", KRef(KRegexBox(try Regex(pattern), source: pattern))))
                } catch {
                    throw KEThrown(value: KBuiltins.errorValue("Invalid regex \(pattern): \(error)"))
                }
            }
            @MainActor func box(_ c: KCall) -> KRegexBox? { c.object(KRegexBox.self) }
            t.method("ignoresCase", "_:bool?") { c in
                guard let b = box(c) else { return .nilValue }
                return .native(.object("Regex", KRef(KRegexBox(b.regex.ignoresCase(c.bool(0, default: true)), source: b.source))))
            }
            t.method("wholeMatch", "in:string") { c in
                let s = c.string("in") ?? ""
                return KBuiltins.match(try box(c)?.regex.wholeMatch(in: s), in: s)
            }
            t.method("firstMatch", "in:string") { c in
                let s = c.string("in") ?? ""
                return KBuiltins.match(try box(c)?.regex.firstMatch(in: s), in: s)
            }
            t.method("prefixMatch", "in:string") { c in
                let s = c.string("in") ?? ""
                return KBuiltins.match(try box(c)?.regex.prefixMatch(in: s), in: s)
            }
        }

        r.type("Regex.Match", .language, notes: "`match.0`, `match.1`, `match.name`, `match.output`, `match.range` (character offsets).") { t in
            @MainActor func m(_ c: KCall) -> KRegexMatch? { c.object(KRegexMatch.self) }
            t.property("output") { c in m(c)?.output ?? .nilValue }
            t.property("range") { c in
                guard let x = m(c) else { return .nilValue }
                return .range(.int(x.range.0), .int(x.range.1), closed: false)
            }
            t.anyProperty { c, name in
                guard let x = m(c) else { return nil }
                if let i = Int(name) { return i == 0 ? .string(x.whole) : (i - 1 < x.captures.count ? x.captures[i - 1] : nil) }
                if let i = x.names.firstIndex(of: name) { return x.captures[i] }
                return nil
            }
        }

        r.extend("String") { t in
            @MainActor func text(_ c: KCall) -> String { c.receiver.asString ?? "" }
            t.method("firstMatch", "of:any") { c in
                guard let r = KBuiltins.regexBox(c.first) else { throw c.fail("needs a Regex, such as /\\d+/") }
                return KBuiltins.match(try r.regex.firstMatch(in: text(c)), in: text(c))
            }
            t.method("wholeMatch", "of:any") { c in
                guard let r = KBuiltins.regexBox(c.first) else { throw c.fail("needs a Regex, such as /\\d+/") }
                return KBuiltins.match(try r.regex.wholeMatch(in: text(c)), in: text(c))
            }
            t.method("prefixMatch", "of:any") { c in
                guard let r = KBuiltins.regexBox(c.first) else { throw c.fail("needs a Regex, such as /\\d+/") }
                return KBuiltins.match(try r.regex.prefixMatch(in: text(c)), in: text(c))
            }
            t.method("matches", "of:any") { c in
                guard let r = KBuiltins.regexBox(c.first) else { throw c.fail("needs a Regex, such as /\\d+/") }
                let s = text(c)
                return .array(s.matches(of: r.regex).map { KBuiltins.match($0, in: s) })
            }
            t.method("replacing", "_:any maxReplacements:number? with:closure") { c in
                guard let r = KBuiltins.regexBox(c.first) else { throw c.fail("needs a Regex, such as /\\d+/") }
                return .string(try KBuiltins.replacing(text(c), r, c["with"], maxReplacements: c.int("maxReplacements") ?? .max, c.interp, c.line))
            }
            t.method("replacing", "_:any with:any maxReplacements:number?") { c in
                let s = text(c)
                let limit = c.int("maxReplacements") ?? .max
                if let r = KBuiltins.regexBox(c.first) {
                    return .string(try KBuiltins.replacing(s, r, c["with"], maxReplacements: limit, c.interp, c.line))
                }
                let target = c.string(0) ?? ""
                let with = c.string("with") ?? ""
                return .string(s.replacing(target, with: with, maxReplacements: limit))
            }
        }
    }
}
