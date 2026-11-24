//
//  Regex.swift
//  Bridges: Regex, from literals, strings and RegexBuilder
//
//  `/\d+/` and `#/…/#` (KELexer), `try Regex("…")` and `Regex { … }`
//  (RegexBuilder, Text/RegexBuilder.swift) are a real `Regex<AnyRegexOutput>`,
//  wrapped in `KRegexBox`. A builder's regex also carries what each capture
//  does with its text (`Capture { … } transform: { Int($0) }`, `TryCapture`,
//  Foundation's `.localizedInteger` and friends) and which `Reference` names
//  it. A match is a `KRegexMatch`: `match.0` is the whole match, `match.1`…
//  the captures (transformed), `match.name` a named capture, `match[ref]` a
//  reference's, `match.output` all of them as a tuple.
//
//  §1.6 made the value and the basics; §3.3 adds the rest of the String and
//  Regex API: `split(separator:)`, `ranges(of:)`, `firstRange(of:)`,
//  `trimmingPrefix`, `starts(with:)`, `replace(_:with:)`, and the options
//  (`ignoresCase`, `anchorsMatchLineEndings`, `dotMatchesNewlines`,
//  `repetitionBehavior`, `wordBoundaryKind`, `asciiOnly…`).
//

import SwiftUI

/// What a builder capture does with the text it matched.
struct KRegexCapture {
    /// `transform: { … }`: the app's closure.
    var transform: KFunction?
    /// Foundation's parsers (`.localizedInteger`): native.
    var parse: ((String) -> KV?)?
    /// `TryCapture`: a nil from the transform fails the match.
    var tries = false
}

/// A compiled regex and the source it came from.
final class KRegexBox {
    let regex: Regex<AnyRegexOutput>
    let source: String
    /// By capture number - 1, for a builder's regex; empty for a literal's.
    var captures: [KRegexCapture] = []
    /// `Reference`s, by identity, to their capture number.
    var references: [ObjectIdentifier: Int] = [:]
    init(_ regex: Regex<AnyRegexOutput>, source: String) {
        self.regex = regex
        self.source = source
    }

    /// The same captures and references, on a regex with other options.
    func with(_ regex: Regex<AnyRegexOutput>) -> KRegexBox {
        let b = KRegexBox(regex, source: source)
        b.captures = captures
        b.references = references
        return b
    }

    var kv: KV { .native(.object("Regex", KRef(self))) }
}

/// One match: the whole text, each capture (nil when it didn't take part), their names.
final class KRegexMatch: KDescribable {
    let whole: String
    var captures: [KV]
    let names: [String?]
    let range: (Int, Int)
    weak var box: KRegexBox?
    /// A `TryCapture` whose transform gave nil: no match.
    var failed = false

    @MainActor init(_ m: Regex<AnyRegexOutput>.Match, in text: String, box: KRegexBox?, interp: KInterpreter?) throws {
        whole = String(text[m.range])
        var caps: [KV] = []
        var names: [String?] = []
        for (i, e) in m.output.enumerated() where i > 0 {
            var v: KV = e.substring.map { .string(String($0)) } ?? .nilValue
            if let box, i - 1 < box.captures.count, let s = e.substring {
                let spec = box.captures[i - 1]
                if let f = spec.transform, let interp {
                    v = try interp.call(f, [.string(String(s))], [nil])
                } else if let parse = spec.parse {
                    v = parse(String(s)) ?? .nilValue
                }
                if spec.tries && v.isNil { failed = true }
            }
            caps.append(v)
            names.append(e.name)
        }
        captures = caps
        self.names = names
        self.box = box
        range = (text.distance(from: text.startIndex, to: m.range.lowerBound), text.distance(from: text.startIndex, to: m.range.upperBound))
    }

    /// `match.output`: the whole match, then each capture, labeled by its name.
    var output: KV {
        if captures.isEmpty { return .string(whole) }
        return .tuple([.string(whole)] + captures, [nil] + names)
    }

    func describe(_ interp: KInterpreter) -> String { interp.describe(output) }
}

extension KBuiltins {
    @MainActor private static var regexCache: [String: KRegexBox] = [:]

    /// A literal's regex, compiled once per pattern.
    @MainActor static func regex(_ pattern: String, _ interp: KInterpreter, _ line: Int) throws -> KV {
        if let box = regexCache[pattern] { return box.kv }
        do {
            let box = KRegexBox(try Regex(pattern), source: pattern)
            regexCache[pattern] = box
            return box.kv
        } catch {
            throw interp.fail("Invalid regex /\(pattern)/: \(error)", line)
        }
    }

    static func regexBox(_ v: KV?) -> KRegexBox? {
        if case .native(.object("Regex", let ref))? = v { return ref.value as? KRegexBox }
        return nil
    }

    /// The matches the app sees: a builder's captures transformed, and a
    /// `TryCapture` that gave nil left out.
    @MainActor static func matches(_ r: KRegexBox, in text: String, _ interp: KInterpreter) throws -> [KRegexMatch] {
        try text.matches(of: r.regex).compactMap { m in
            let x = try KRegexMatch(m, in: text, box: r, interp: interp)
            return x.failed ? nil : x
        }
    }

    @MainActor static func match(_ m: Regex<AnyRegexOutput>.Match?, in text: String, _ r: KRegexBox?, _ interp: KInterpreter) throws -> KV {
        guard let m else { return .nilValue }
        let x = try KRegexMatch(m, in: text, box: r, interp: interp)
        return x.failed ? .nilValue : .native(.object("Regex.Match", KRef(x)))
    }

    @MainActor static func firstMatch(_ r: KRegexBox, in text: String, _ interp: KInterpreter) throws -> KV {
        if r.captures.contains(where: \.tries) {
            return try matches(r, in: text, interp).first.map { .native(.object("Regex.Match", KRef($0))) } ?? .nilValue
        }
        return try match(r.regex.firstMatch(in: text), in: text, r, interp)
    }

    static func offsetRange(_ r: Range<String.Index>, in text: String) -> KV {
        .range(.int(text.distance(from: text.startIndex, to: r.lowerBound)), .int(text.distance(from: text.startIndex, to: r.upperBound)), closed: false)
    }

    /// `text.replacing(regex, with: "…")` or `with: { match in … }`.
    @MainActor static func replacing(_ text: String, _ r: KRegexBox, _ with: KV?, maxReplacements: Int, _ interp: KInterpreter, _ line: Int) throws -> String {
        var out = ""
        var rest = text.startIndex
        var count = 0
        for m in text.matches(of: r.regex) where count < maxReplacements {
            let x = try KRegexMatch(m, in: text, box: r, interp: interp)
            if x.failed { continue }
            out += text[rest..<m.range.lowerBound]
            switch with {
            case .function(let f)?:
                out += interp.describe(try interp.call(f, [.native(.object("Regex.Match", KRef(x)))], [nil]))
            case let v?:
                out += v.asString ?? interp.describe(v)
            case nil:
                break
            }
            rest = m.range.upperBound
            count += 1
        }
        return out + text[rest...]
    }

    /// `text.split(separator: /\s*,\s*/)`.
    @MainActor static func split(_ text: String, _ r: KRegexBox, maxSplits: Int, omittingEmpty: Bool) -> [KV] {
        var out: [String] = []
        var rest = text.startIndex
        for m in text.matches(of: r.regex) where out.count < maxSplits {
            if m.range.isEmpty { continue }
            out.append(String(text[rest..<m.range.lowerBound]))
            rest = m.range.upperBound
        }
        out.append(String(text[rest...]))
        return (omittingEmpty ? out.filter { !$0.isEmpty } : out).map { .string($0) }
    }
}

extension LanguageBridges {
    static func regex(_ r: KRegistry) {
        r.type("Regex", .language,
               notes: "From `/…/`, `#/…/#`, `try Regex(\"…\")` or RegexBuilder's `Regex { … }`. Captures are `match.1`…, named ones `match.name`, a `Reference`'s `match[ref]`.") { t in
            for sig in ["_:string", "_:string as:any"] {
                t.initializer(sig) { c in
                    let pattern = c.string(0) ?? ""
                    do {
                        return KRegexBox(try Regex(pattern), source: pattern).kv
                    } catch {
                        throw KEThrown(value: KBuiltins.errorValue("Invalid regex \(pattern): \(error)"))
                    }
                }
            }
            t.initializer("verbatim:string") { c in
                let s = c.string("verbatim") ?? ""
                return KRegexBox(Regex<AnyRegexOutput>(Regex<Substring>(verbatim: s)), source: s).kv
            }
            // RegexBuilder: `Regex { "id-"; Capture { OneOrMore(.digit) } }` (Text/RegexBuilder.swift).
            t.initializer("_:closure") { c in
                guard let f = c.function(0) else { throw c.fail("needs a RegexBuilder block") }
                return try KRegexBuilding.regex(fromBlock: f, c.interp, c.line)
            }
            @MainActor func box(_ c: KCall) throws -> KRegexBox {
                guard let b = c.object(KRegexBox.self) else { throw c.noMember() }
                return b
            }
            t.method("ignoresCase", "_:bool?") { c in let b = try box(c); return b.with(b.regex.ignoresCase(c.bool(0, default: true))).kv }
            t.method("anchorsMatchLineEndings", "_:bool?") { c in let b = try box(c); return b.with(b.regex.anchorsMatchLineEndings(c.bool(0, default: true))).kv }
            t.method("dotMatchesNewlines", "_:bool?") { c in let b = try box(c); return b.with(b.regex.dotMatchesNewlines(c.bool(0, default: true))).kv }
            t.method("asciiOnlyDigits", "_:bool?") { c in let b = try box(c); return b.with(b.regex.asciiOnlyDigits(c.bool(0, default: true))).kv }
            t.method("asciiOnlyWhitespace", "_:bool?") { c in let b = try box(c); return b.with(b.regex.asciiOnlyWhitespace(c.bool(0, default: true))).kv }
            t.method("asciiOnlyWordCharacters", "_:bool?") { c in let b = try box(c); return b.with(b.regex.asciiOnlyWordCharacters(c.bool(0, default: true))).kv }
            t.method("asciiOnlyCharacterClasses", "_:bool?") { c in let b = try box(c); return b.with(b.regex.asciiOnlyCharacterClasses(c.bool(0, default: true))).kv }
            t.method("repetitionBehavior", "_:any") { c in
                let b = try box(c)
                let k: RegexRepetitionBehavior = c.symbol(0) == "reluctant" ? .reluctant : (c.symbol(0) == "possessive" ? .possessive : .eager)
                return b.with(b.regex.repetitionBehavior(k)).kv
            }
            t.method("wordBoundaryKind", "_:any") { c in
                let b = try box(c)
                return b.with(b.regex.wordBoundaryKind(c.symbol(0) == "simple" ? .simple : .default)).kv
            }
            t.method("wholeMatch", "in:string") { c in
                let s = c.string("in") ?? "", b = try box(c)
                return try KBuiltins.match(b.regex.wholeMatch(in: s), in: s, b, c.interp)
            }
            t.method("firstMatch", "in:string") { c in try KBuiltins.firstMatch(try box(c), in: c.string("in") ?? "", c.interp) }
            t.method("prefixMatch", "in:string") { c in
                let s = c.string("in") ?? "", b = try box(c)
                return try KBuiltins.match(b.regex.prefixMatch(in: s), in: s, b, c.interp)
            }
            t.method("matches", "in:string") { c in
                let s = c.string("in") ?? ""
                return .array(try KBuiltins.matches(try box(c), in: s, c.interp).map { .native(.object("Regex.Match", KRef($0))) })
            }
        }

        r.type("Regex.Match", .language, notes: "`match.0`, `match.1`, `match.name`, `match[ref]`, `match.output`, `match.range` (character offsets).") { t in
            @MainActor func m(_ c: KCall) -> KRegexMatch? { c.object(KRegexMatch.self) }
            t.property("output") { c in m(c)?.output ?? .nilValue }
            t.property("range") { c in
                guard let x = m(c) else { return .nilValue }
                return .range(.int(x.range.0), .int(x.range.1), closed: false)
            }
            t.method("subscript", "_:any") { c in
                guard let x = m(c) else { return .nilValue }
                if let ref = KCall.objectValue(c[0]) as? KRegexReference, let i = x.box?.references[ObjectIdentifier(ref)], i - 1 < x.captures.count {
                    return x.captures[i - 1]
                }
                throw c.fail("this Reference isn't captured in the regex")
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
            @MainActor func rx(_ c: KCall) throws -> KRegexBox {
                guard let r = KBuiltins.regexBox(c.first) else { throw c.fail("needs a Regex, such as /\\d+/") }
                return r
            }
            t.method("firstMatch", "of:any") { c in try KBuiltins.firstMatch(try rx(c), in: text(c), c.interp) }
            t.method("wholeMatch", "of:any") { c in
                let r = try rx(c)
                return try KBuiltins.match(r.regex.wholeMatch(in: text(c)), in: text(c), r, c.interp)
            }
            t.method("prefixMatch", "of:any") { c in
                let r = try rx(c)
                return try KBuiltins.match(r.regex.prefixMatch(in: text(c)), in: text(c), r, c.interp)
            }
            t.method("matches", "of:any") { c in
                .array(try KBuiltins.matches(try rx(c), in: text(c), c.interp).map { .native(.object("Regex.Match", KRef($0))) })
            }
            t.method("replacing", "_:any maxReplacements:number? with:closure") { c in
                .string(try KBuiltins.replacing(text(c), try rx(c), c["with"], maxReplacements: c.int("maxReplacements") ?? .max, c.interp, c.line))
            }
            t.method("replacing", "_:any with:any maxReplacements:number?") { c in
                let s = text(c)
                let limit = c.int("maxReplacements") ?? .max
                if let r = KBuiltins.regexBox(c.first) {
                    return .string(try KBuiltins.replacing(s, r, c["with"], maxReplacements: limit, c.interp, c.line))
                }
                return .string(s.replacing(c.string(0) ?? "", with: c.string("with") ?? "", maxReplacements: limit))
            }
            // `text.replace(/\s+/, with: " ")`, in place.
            t.method("replace", "_:any with:any maxReplacements:number?") { c in
                let s = text(c)
                let limit = c.int("maxReplacements") ?? .max
                if let r = KBuiltins.regexBox(c.first) {
                    c.mutated = .string(try KBuiltins.replacing(s, r, c["with"], maxReplacements: limit, c.interp, c.line))
                } else {
                    c.mutated = .string(s.replacing(c.string(0) ?? "", with: c.string("with") ?? "", maxReplacements: limit))
                }
                return .void
            }
            t.method("ranges", "of:any") { c in
                let s = text(c)
                if let r = KBuiltins.regexBox(c.first) {
                    return .array(try KBuiltins.matches(r, in: s, c.interp).map { .range(.int($0.range.0), .int($0.range.1), closed: false) })
                }
                return .array(s.ranges(of: c.string("of") ?? "").map { KBuiltins.offsetRange($0, in: s) })
            }
            t.method("firstRange", "of:any") { c in
                let s = text(c)
                if let r = KBuiltins.regexBox(c.first) {
                    return try KBuiltins.matches(r, in: s, c.interp).first.map { .range(.int($0.range.0), .int($0.range.1), closed: false) } ?? .nilValue
                }
                return s.firstRange(of: c.string("of") ?? "").map { KBuiltins.offsetRange($0, in: s) } ?? .nilValue
            }
            t.method("trimmingPrefix", "_:any") { c in
                let s = text(c)
                if let r = KBuiltins.regexBox(c.first) { return .string(String(s.trimmingPrefix(r.regex))) }
                return .string(String(s.trimmingPrefix(c.string(0) ?? "")))
            }
            t.method("trimPrefix", "_:any") { c in
                var s = text(c)
                if let r = KBuiltins.regexBox(c.first) { s.trimPrefix(r.regex) } else { s.trimPrefix(c.string(0) ?? "") }
                c.mutated = .string(s)
                return .void
            }
            t.method("starts", "with:any") { c in
                let s = text(c)
                if let r = KBuiltins.regexBox(c.first) { return .bool(s.starts(with: r.regex)) }
                return .bool(s.hasPrefix(c.string("with") ?? ""))
            }
        }
    }
}
