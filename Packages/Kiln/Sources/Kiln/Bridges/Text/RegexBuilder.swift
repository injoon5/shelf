//
//  RegexBuilder.swift
//  Bridges: RegexBuilder (PLAN.md §3.3)
//
//      let date = Regex {
//          Capture { OneOrMore(.digit) } transform: { Int($0) }
//          "/"
//          TryCapture { Repeat(.digit, count: 2) } transform: { Int($0) }
//          Optionally { ChoiceOf { "am"; "pm" } }
//      }
//
//  Each component is a node (`KRx`); `Regex { … }` runs its block through
//  `RegexComponentBuilder` (KEBuilders) and compiles the nodes into one
//  pattern for Swift's own `Regex`, numbering captures as Swift does (in the
//  order they open). What a capture does with its text (a `transform:`, a
//  `TryCapture`, Foundation's `.localizedInteger`…) rides along in the
//  `KRegexBox` and is applied to each match (Language/Regex.swift).
//
//  Character classes and anchors are the same symbols RegexBuilder has
//  (`.digit`, `.word.inverted`, `.anyOf("+-")`, `"a"..."f"`,
//  `Anchor.wordBoundary`); a regex literal works inside a builder too.
//

import SwiftUI

/// `Reference(Substring.self)`: names a capture, read with `match[ref]`.
final class KRegexReference: KDescribable {
    func describe(_ interp: KInterpreter) -> String { "Reference" }
}

/// A RegexBuilder component.
indirect enum KRx {
    /// Text to match as is.
    case literal(String)
    /// A pattern in regex syntax (a literal, a character class, an anchor), with its own captures.
    case raw(String, captures: Int)
    case seq([KRx])
    case alt([KRx])
    case capture(KRx, KRegexCapture, KRegexReference?)
    case quant(KRx, min: Int, max: Int?, behavior: String?)
    case look(KRx, negative: Bool)
    case local(KRx)
    /// Foundation's parsers: a pattern, and how the matched text becomes a value.
    case parser(String, (String) -> KV?)

    var kv: KV { .native(.object("RegexComponent", KRef(KRxBox(self)))) }
}

final class KRxBox { let node: KRx; init(_ n: KRx) { node = n } }

@MainActor
enum KRegexBuilding {
    /// `Regex { … }`.
    static func regex(fromBlock f: KFunction, _ interp: KInterpreter, _ line: Int) throws -> KV {
        let node = try block(.function(f), interp, line)
        return try compile(node, line).kv
    }

    /// A builder block's components, as one sequence.
    static func block(_ v: KV, _ interp: KInterpreter, _ line: Int) throws -> KRx {
        guard let builder = interp.builder([KEAttribute(name: "RegexComponentBuilder", args: [])]) else { throw interp.fail("RegexBuilder isn't available", line) }
        let g = interp.builderClosure(v, builder)
        guard case .function(let fn) = g else { return try node(v, line) }
        return try node(try interp.call(fn, [], []), line)
    }

    /// Any value a component takes: a component, a string, a regex, a character class, a range of characters.
    static func node(_ v: KV, _ line: Int) throws -> KRx {
        switch v {
        case .native(.object("RegexComponent", let ref)): return (ref.value as! KRxBox).node
        case .native(.object("Regex", let ref)):
            let b = ref.value as! KRegexBox
            return .raw(b.source, captures: captureCount(b.source))
        case .string(let s): return .literal(s)
        case .array(let parts): return .seq(try parts.map { try node($0, line) })
        case .range(.string(let lo), .string(let hi), _):
            return .raw("[" + classEscape(lo) + "-" + classEscape(hi) + "]", captures: 0)
        case .native(.implicit(let name, let args)):
            if let p = characterClass(name, args) { return .raw(p, captures: 0) }
            if let p = anchor(name) { return .raw(p, captures: 0) }
            if let p = parser(name, args) { return p }
            throw KERuntimeError(message: "'.\(name)' isn't a RegexBuilder component", line: line)
        case .void:
            return .seq([])
        default:
            throw KERuntimeError(message: "\(v.typeName) isn't a RegexBuilder component", line: line)
        }
    }

    // MARK: Character classes and anchors

    static func characterClass(_ name: String, _ args: [KV]) -> String? {
        switch name {
        case "digit": return "\\d"
        case "word": return "\\w"
        case "whitespace": return "\\s"
        case "any": return "(?s:.)"
        case "anyNonNewline": return "[^\\n\\r]"
        case "anyGrapheme": return "\\X"
        case "horizontalWhitespace": return "\\h"
        case "verticalWhitespace": return "\\v"
        case "newlineSequence": return "\\R"
        case "hexDigit": return "[0-9A-Fa-f]"
        case "anyOf": return args.first?.asString.map { "[" + $0.map { classEscape(String($0)) }.joined() + "]" }
        case "noneOf": return args.first?.asString.map { "[^" + $0.map { classEscape(String($0)) }.joined() + "]" }
        case "inverted": return nil
        default: return nil
        }
    }

    static func anchor(_ name: String) -> String? {
        switch name {
        case "startOfSubject": return "\\A"
        case "endOfSubject": return "\\z"
        case "endOfSubjectBeforeNewline": return "\\Z"
        case "startOfLine": return "(?m:^)"
        case "endOfLine": return "(?m:$)"
        case "wordBoundary": return "\\b"
        case "firstMatchingPositionInSubject": return "\\G"
        case "textSegmentBoundary": return "\\y"
        default: return nil
        }
    }

    /// `.digit.inverted`, `Anchor.wordBoundary.inverted`.
    static func inverted(_ p: String) -> String {
        switch p {
        case "\\d": return "\\D"
        case "\\w": return "\\W"
        case "\\s": return "\\S"
        case "\\h": return "\\H"
        case "\\v": return "\\V"
        case "\\b": return "\\B"
        default:
            if p.hasPrefix("[^") { return "[" + p.dropFirst(2) }
            if p.hasPrefix("[") { return "[^" + p.dropFirst() }
            return "[^" + p + "]"
        }
    }

    /// The pattern of a class (`[...]` or `\d`) without its brackets, for a union.
    static func classBody(_ p: String) -> String {
        if p.hasPrefix("[") && !p.hasPrefix("[^") && p.hasSuffix("]") { return String(p.dropFirst().dropLast()) }
        return p
    }

    // MARK: Foundation's parsers

    static func parser(_ name: String, _ args: [KV]) -> KRx? {
        switch name {
        case "localizedInteger":
            return .parser("[-+]?\\d{1,3}(?:,\\d{3})+|[-+]?\\d+") { s in Int(s.replacingOccurrences(of: ",", with: "")).map { .int($0) } }
        case "localizedDouble":
            return .parser("[-+]?(?:\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.\\d+)?") { s in Double(s.replacingOccurrences(of: ",", with: "")).map { .double($0) } }
        case "localizedCurrency":
            return .parser("[-+]?[$€£¥]?\\s?(?:\\d{1,3}(?:,\\d{3})+|\\d+)(?:\\.\\d+)?") { s in
                let digits = s.filter { $0.isNumber || $0 == "." || $0 == "-" }
                return Decimal(string: digits).map { KDecimal($0).kv }
            }
        case "iso8601":
            return .parser("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:?\\d{2})") { s in
                (try? Date(s, strategy: .iso8601)).map { .native(.date($0)) }
            }
        case "date" where args.first.flatMap(KFeedback.sym) == "iso8601":
            return parser("iso8601", [])
        default:
            return nil
        }
    }

    // MARK: Compiling

    /// Swift's regex syntax for a literal: every ASCII punctuation mark escaped.
    static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            if ch.isASCII, ch.isPunctuation || ch.isSymbol { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    static func classEscape(_ s: String) -> String {
        s.map { ch in "\\[]^-".contains(ch) ? "\\" + String(ch) : String(ch) }.joined()
    }

    /// Capture groups in a pattern: `(` not escaped, not in a class, and not `(?:`, `(?=`… (but `(?<name>` counts).
    static func captureCount(_ p: String) -> Int {
        var n = 0, inClass = false, escaped = false
        let chars = Array(p)
        for (i, ch) in chars.enumerated() {
            if escaped { escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if inClass { if ch == "]" { inClass = false }; continue }
            if ch == "[" { inClass = true; continue }
            guard ch == "(" else { continue }
            if i + 1 < chars.count, chars[i + 1] == "?" {
                if i + 2 < chars.count, chars[i + 2] == "<" || chars[i + 2] == "'" || chars[i + 2] == "P",
                   i + 3 < chars.count, chars[i + 3] != "=" && chars[i + 3] != "!" { n += 1 }
                continue
            }
            if i + 1 < chars.count, chars[i + 1] == "*" { continue }
            n += 1
        }
        return n
    }

    static func compile(_ node: KRx, _ line: Int) throws -> KRegexBox {
        var pattern = ""
        var caps: [KRegexCapture] = []
        var refs: [ObjectIdentifier: Int] = [:]
        emit(node, &pattern, &caps, &refs)
        do {
            let b = KRegexBox(try Regex(pattern), source: pattern)
            b.captures = caps
            b.references = refs
            return b
        } catch {
            throw KERuntimeError(message: "This RegexBuilder block doesn't make a valid regex (\(pattern)): \(error)", line: line)
        }
    }

    static func emit(_ node: KRx, _ out: inout String, _ caps: inout [KRegexCapture], _ refs: inout [ObjectIdentifier: Int]) {
        switch node {
        case .literal(let s):
            out += escape(s)
        case .raw(let p, let n):
            out += "(?:" + p + ")"
            caps += Array(repeating: KRegexCapture(), count: n)
        case .seq(let parts):
            for p in parts { emit(p, &out, &caps, &refs) }
        case .alt(let options):
            out += "(?:"
            for (i, o) in options.enumerated() {
                if i > 0 { out += "|" }
                emit(o, &out, &caps, &refs)
            }
            out += ")"
        case .capture(let inner, var spec, let ref):
            if spec.transform == nil, spec.parse == nil, case .parser(_, let parse) = unwrapped(inner) { spec.parse = parse }
            caps.append(spec)
            if let ref { refs[ObjectIdentifier(ref)] = caps.count }
            out += "("
            emit(inner, &out, &caps, &refs)
            out += ")"
        case .quant(let inner, let lo, let hi, let behavior):
            out += "(?:"
            emit(inner, &out, &caps, &refs)
            out += ")"
            switch (lo, hi) {
            case (0, nil): out += "*"
            case (1, nil): out += "+"
            case (0, 1?): out += "?"
            case (let l, nil): out += "{\(l),}"
            case (let l, let h?) where l == h: out += "{\(l)}"
            case (let l, let h?): out += "{\(l),\(h)}"
            }
            if behavior == "reluctant" { out += "?" } else if behavior == "possessive" { out += "+" }
        case .look(let inner, let negative):
            out += negative ? "(?!" : "(?="
            emit(inner, &out, &caps, &refs)
            out += ")"
        case .local(let inner):
            out += "(?>"
            emit(inner, &out, &caps, &refs)
            out += ")"
        case .parser(let p, _):
            out += "(?:" + p + ")"
        }
    }

    static func unwrapped(_ n: KRx) -> KRx {
        if case .seq(let parts) = n, parts.count == 1 { return unwrapped(parts[0]) }
        return n
    }
}

extension KTextBridges {
    static func regexBuilder(_ r: KRegistry) {
        r.resultBuilder("RegexComponentBuilder", .text) { b in
            b.method("buildBlock") { parts, _, _ in KRx.seq(try parts.map { try KRegexBuilding.node($0, 0) }).kv }
            b.method("buildPartialBlock") { parts, _, _ in KRx.seq(try parts.map { try KRegexBuilding.node($0, 0) }).kv }
            b.method("buildExpression") { args, _, _ in try KRegexBuilding.node(args.first ?? .void, 0).kv }
            b.method("buildOptional") { args, _, _ in
                guard let v = args.first, !v.isNil else { return KRx.seq([]).kv }
                return v
            }
            b.method("buildEither") { args, _, _ in args.first ?? KRx.seq([]).kv }
            b.method("buildArray") { args, _, _ in KRx.seq(try (args.first?.asArray ?? []).map { try KRegexBuilding.node($0, 0) }).kv }
            b.method("buildLimitedAvailability") { args, _, _ in args.first ?? KRx.seq([]).kv }
        }

        let note = "RegexBuilder: inside `Regex { … }`."
        @MainActor func content(_ c: KCall) throws -> KRx {
            if let f = c["content"] {
                if case .function = f { return try KRegexBuilding.block(f, c.interp, c.line) }
                return try KRegexBuilding.node(f, c.line)
            }
            guard let v = c[0] else { throw c.fail("needs a component or a block") }
            return try KRegexBuilding.node(v, c.line)
        }
        @MainActor func behavior(_ c: KCall) -> String? { c.symbol(1) ?? c.symbol("behavior") }

        r.type("Capture", .text, support: .full, notes: note) { t in
            for sig in ["content:closure", "as:any content:closure", "content:closure transform:closure", "as:any content:closure transform:closure",
                        "_:RegexComponent", "_:RegexComponent as:any", "_:RegexComponent transform:closure", "_:RegexComponent as:any transform:closure"] {
                t.initializer(sig, kinds: [:]) { c in
                    var spec = KRegexCapture()
                    spec.transform = c.function("transform")
                    return KRx.capture(try content(c), spec, KCall.objectValue(c["as"]) as? KRegexReference).kv
                }
            }
        }
        r.type("TryCapture", .text, support: .full, notes: note) { t in
            for sig in ["content:closure transform:closure", "as:any content:closure transform:closure", "_:RegexComponent transform:closure",
                        "_:RegexComponent as:any transform:closure"] {
                t.initializer(sig) { c in
                    var spec = KRegexCapture()
                    spec.transform = c.function("transform")
                    spec.tries = true
                    return KRx.capture(try content(c), spec, KCall.objectValue(c["as"]) as? KRegexReference).kv
                }
            }
        }
        for (name, lo, hi) in [("OneOrMore", 1, Int?.none), ("ZeroOrMore", 0, nil), ("Optionally", 0, 1)] {
            r.type(name, .text, support: .full, notes: note) { t in
                for sig in ["content:closure", "_:RegexRepetitionBehavior content:closure", "_:RegexComponent", "_:RegexComponent _:RegexRepetitionBehavior"] {
                    t.initializer(sig) { c in
                        // `OneOrMore(.reluctant) { … }`: the behavior first, then the block.
                        if c.has("content"), let b = c.symbol(0) {
                            return KRx.quant(try content(c), min: lo, max: hi, behavior: b).kv
                        }
                        return KRx.quant(try content(c), min: lo, max: hi, behavior: behavior(c)).kv
                    }
                }
            }
        }
        r.type("Repeat", .text, support: .full, notes: note) { t in
            for sig in ["count:number content:closure", "_:any _:RegexRepetitionBehavior? content:closure", "_:RegexComponent count:number",
                        "_:RegexComponent _:any _:RegexRepetitionBehavior?"] {
                t.initializer(sig) { c in
                    if let n = c.int("count") {
                        let inner: KRx = c.has("content") ? try content(c) : try KRegexBuilding.node(c[0] ?? .void, c.line)
                        return KRx.quant(inner, min: n, max: n, behavior: nil).kv
                    }
                    // `Repeat(x, 2...4)`, `Repeat(2...4) { … }`, `Repeat(.digit, 1..., .reluctant)`.
                    let rangeArg = c.has("content") ? c[0] : c[1]
                    guard case .range(let lo, let hi, let closed)? = rangeArg else { throw c.fail("needs count: or a range") }
                    let l = lo.asInt ?? 0
                    let h = hi.asInt.map { closed ? $0 : $0 - 1 }
                    let inner: KRx = c.has("content") ? try content(c) : try KRegexBuilding.node(c[0] ?? .void, c.line)
                    let b = c.has("content") ? c.symbol(1) : c.symbol(2)
                    return KRx.quant(inner, min: l, max: h, behavior: b).kv
                }
            }
        }
        r.type("ChoiceOf", .text, support: .full, notes: note) { t in
            t.initializer("content:closure") { c in
                guard case .seq(let options) = KRegexBuilding.unwrappedSeq(try content(c)) else { return KRx.alt([try content(c)]).kv }
                return KRx.alt(options).kv
            }
        }
        r.type("One", .text, support: .full, notes: note) { t in
            t.initializer("_:RegexComponent") { c in try KRegexBuilding.node(c[0] ?? .void, c.line).kv }
        }
        r.type("Lookahead", .text, support: .full, notes: note) { t in
            for sig in ["content:closure", "_:RegexComponent"] { t.initializer(sig) { c in KRx.look(try content(c), negative: false).kv } }
        }
        r.type("NegativeLookahead", .text, support: .full, notes: note) { t in
            for sig in ["content:closure", "_:RegexComponent"] { t.initializer(sig) { c in KRx.look(try content(c), negative: true).kv } }
        }
        r.type("Local", .text, support: .full, notes: note) { t in
            for sig in ["content:closure", "_:RegexComponent"] { t.initializer(sig) { c in KRx.local(try content(c)).kv } }
        }
        r.type("RegexRepetitionBehavior", .text, support: .full) { t in
            for n in ["eager", "reluctant", "possessive"] { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
        }
        r.type("Reference", .text, support: .full, notes: "`let ref = Reference(Substring.self)`; `Capture(as: ref) { … }`; `match[ref]`.") { t in
            for sig in ["", "_:any"] { t.initializer(sig) { _ in .native(.object("Reference", KRef(KRegexReference()))) } }
        }
        r.type("CharacterClass", .text, support: .full, notes: note) { t in
            for n in ["digit", "word", "whitespace", "any", "anyNonNewline", "anyGrapheme", "horizontalWhitespace", "verticalWhitespace",
                      "newlineSequence", "hexDigit"] {
                t.staticProperty(n) { _ in KRx.raw(KRegexBuilding.characterClass(n, [])!, captures: 0).kv }
            }
            t.staticMethod("anyOf", "_:string") { c in KRx.raw(KRegexBuilding.characterClass("anyOf", [c[0] ?? .void]) ?? "", captures: 0).kv }
            t.staticMethod("noneOf", "_:string") { c in KRx.raw(KRegexBuilding.characterClass("noneOf", [c[0] ?? .void]) ?? "", captures: 0).kv }
            t.initializer("_:any") { c in try KRegexBuilding.node(c[0] ?? .void, c.line).kv }
        }
        r.type("Anchor", .text, support: .full, notes: note) { t in
            for n in ["startOfSubject", "endOfSubject", "endOfSubjectBeforeNewline", "startOfLine", "endOfLine", "wordBoundary",
                      "firstMatchingPositionInSubject", "textSegmentBoundary"] {
                t.staticProperty(n) { _ in KRx.raw(KRegexBuilding.anchor(n)!, captures: 0).kv }
            }
        }
        r.type("RegexComponent", .text) { t in
            t.internal()
            @MainActor func pattern(_ c: KCall) -> String? {
                if case .raw(let p, 0)? = (KCall.objectValue(c.receiver) as? KRxBox)?.node { return p }
                return nil
            }
            t.property("inverted") { c in
                guard let p = pattern(c) else { throw c.fail("only a character class or an anchor can be inverted") }
                return KRx.raw(KRegexBuilding.inverted(p), captures: 0).kv
            }
            t.method("union", "_:any") { c in
                guard let p = pattern(c), case .raw(let q, 0) = try KRegexBuilding.node(c[0] ?? .void, c.line) else { throw c.fail("needs a character class") }
                return KRx.raw("[" + KRegexBuilding.classBody(p) + KRegexBuilding.classBody(q) + "]", captures: 0).kv
            }
            t.method("subtracting", "_:any") { c in
                guard let p = pattern(c), case .raw(let q, 0) = try KRegexBuilding.node(c[0] ?? .void, c.line) else { throw c.fail("needs a character class") }
                return KRx.raw("[" + KRegexBuilding.classBody(p) + "--" + KRegexBuilding.classBody(q) + "]", captures: 0).kv
            }
            t.method("intersection", "_:any") { c in
                guard let p = pattern(c), case .raw(let q, 0) = try KRegexBuilding.node(c[0] ?? .void, c.line) else { throw c.fail("needs a character class") }
                return KRx.raw("[" + KRegexBuilding.classBody(p) + "&&" + KRegexBuilding.classBody(q) + "]", captures: 0).kv
            }
        }
        // `.digit.inverted` before it's a component (an implicit member with no type).
        r.implicitProperties["inverted"] = { name, args in
            if let p = KRegexBuilding.characterClass(name, args) ?? KRegexBuilding.anchor(name) {
                return KRx.raw(KRegexBuilding.inverted(p), captures: 0).kv
            }
            return nil
        }
    }
}

extension KRegexBuilding {
    /// A block of several components is a sequence; one component is itself.
    static func unwrappedSeq(_ n: KRx) -> KRx {
        if case .seq(let parts) = n, parts.count == 1, case .seq = parts[0] { return unwrappedSeq(parts[0]) }
        return n
    }
}
