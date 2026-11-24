//
//  Stdlib.swift
//  Bridges: the rest of the standard library (Round 2C)
//
//  `Optional`, `Unicode.Scalar` and what a `Character` knows, the string
//  APIs that take indices, collections' `difference`, `merging`,
//  `sorted(using:)` with `KeyPathComparator` and `SortDescriptor`, `split`,
//  `partition`, `Mirror`, `sequence(first:next:)`. `Result` and
//  `AnyIterator` are Swift, in `KSwiftPrelude`.
//

import SwiftUI

/// A `Unicode.Scalar`: `"a".unicodeScalars.first!.value`.
struct KScalar: Hashable, KDescribable {
    let scalar: Unicode.Scalar
    func describe(_ interp: KInterpreter) -> String { String(scalar) }
    var kv: KV { .native(.boxed(KBoxed("Unicode.Scalar", self))) }

    /// A scalar, or the first of a one-character string.
    static func from(_ v: KV?) -> Unicode.Scalar? {
        if case .native(.boxed(let b))? = v, let s = b.value.base as? KScalar { return s.scalar }
        return v?.asString?.unicodeScalars.first
    }
}

/// What `scalar.properties` answers.
struct KScalarProperties: Hashable {
    let scalar: Unicode.Scalar
}

/// `KeyPathComparator(\.age, order: .reverse)` and `SortDescriptor(\.name)`.
struct KComparator: Hashable {
    var path: [String]
    var reverse: Bool
    var localized: Bool = false
    var kv: KV { .native(.boxed(KBoxed("KeyPathComparator", self))) }
}

/// `sequence(first:next:)`: an `UnfoldSequence`, made as far as it goes (or 10,000 elements).
struct KUnfold: Hashable, KNativeSequence {
    let values: [KV]
    func elements(_ interp: KInterpreter) throws -> [KV] { values }
}

extension LanguageBridges {
    static func stdlib(_ r: KRegistry) {
        optionals(r)
        scalars(r)
        stringIndices(r)
        collectionsMore(r)
        reflection(r)
    }

    // MARK: Optional

    static func optionals(_ r: KRegistry) {
        r.type("Optional", .language, support: .full,
               notes: "`Optional(x)`, `.some(x)`, `.none`, `map` and `flatMap`; printed as `Optional(5)` where Swift prints that.") { t in
            t.initializer("_:any") { c in c.first ?? .nilValue }
            t.staticProperty("none") { _ in .nilValue }
            t.staticMethod("some", "_:any") { c in c.first ?? .nilValue }
            t.implicit { name, args, _ in
                switch name {
                case "none": return args.isEmpty ? .nilValue : nil
                case "some": return args.first
                default: return nil
                }
            }
        }
        r.protocolBridge("IteratorProtocol", .language, requirements: ["next()"], support: .full,
                         notes: "Your own iterators and sequences (`next()`, `makeIterator()`) loop with `for in` and have every `Sequence` method.")
        r.protocolBridge("Sequence", .language, requirements: ["makeIterator()?"], support: .full)
    }

    // MARK: Unicode scalars and characters

    static func scalars(_ r: KRegistry) {
        r.type("Unicode", .language, support: .full) { t in t.namespace() }
        r.type("Unicode.Scalar", .language, support: .full,
               notes: "`text.unicodeScalars`: each scalar's `value`, `properties` (`isEmoji`, `isAlphabetic`…) and `isASCII`; `Unicode.Scalar(n)`.") { t in
            t.initializer("_:any") { c in
                if case .string(let s)? = c.first, let u = s.unicodeScalars.first { return KScalar(scalar: u).kv }
                guard let n = c.first?.asInt, n >= 0, let u = Unicode.Scalar(UInt32(truncatingIfNeeded: n)) else { return .nilValue }
                return KScalar(scalar: u).kv
            }
            @MainActor func u(_ c: KCall) -> Unicode.Scalar? { KScalar.from(c.receiver) }
            t.property("value") { c in u(c).map { KFixedInt(.uint32, bits: UInt64($0.value)).kv } ?? .nilValue }
            t.property("isASCII") { c in .bool(u(c)?.isASCII ?? false) }
            t.property("description") { c in u(c).map { .string(String($0)) } ?? .nilValue }
            t.property("properties") { c in u(c).map { .native(.boxed(KBoxed("Unicode.Scalar.Properties", KScalarProperties(scalar: $0)))) } ?? .nilValue }
            t.method("escaped", "asASCII:bool") { c in u(c).map { .string($0.escaped(asASCII: c.bool("asASCII", default: false))) } ?? .nilValue }
            t.operator("<") { a, b, _ in
                guard let x = KScalar.from(a), let y = KScalar.from(b) else { return nil }
                return .bool(x < y)
            }
        }
        r.alias("UnicodeScalar", to: "Unicode.Scalar")
        r.type("Unicode.Scalar.Properties", .language, support: .full) { t in
            @MainActor func p(_ c: KCall) -> Unicode.Scalar.Properties? {
                if case .native(.boxed(let b)) = c.receiver { return (b.value.base as? KScalarProperties)?.scalar.properties }
                return nil
            }
            let flags: [String: (Unicode.Scalar.Properties) -> Bool] = [
                "isEmoji": \.isEmoji, "isEmojiPresentation": \.isEmojiPresentation, "isAlphabetic": \.isAlphabetic,
                "isWhitespace": \.isWhitespace, "isUppercase": \.isUppercase, "isLowercase": \.isLowercase,
                "isMath": \.isMath, "isDiacritic": \.isDiacritic, "isIdeographic": \.isIdeographic, "isDash": \.isDash,
            ]
            for (name, f) in flags { t.property(name) { c in .bool(p(c).map(f) ?? false) } }
            t.property("name") { c in p(c)?.name.map { .string($0) } ?? .nilValue }
            t.property("numericValue") { c in p(c)?.numericValue.map { .double($0) } ?? .nilValue }
            t.property("uppercaseMapping") { c in p(c).map { .string($0.uppercaseMapping) } ?? .nilValue }
            t.property("lowercaseMapping") { c in p(c).map { .string($0.lowercaseMapping) } ?? .nilValue }
        }

        // A Character is a one-character String in Kiln: what Swift's Character knows.
        r.extend("String") { t in
            @MainActor func ch(_ c: KCall) -> Character? { c.receiver.asString?.first }
            t.property("asciiValue") { c in ch(c)?.asciiValue.map { KFixedInt(.uint8, bits: UInt64($0)).kv } ?? .nilValue }
            t.property("isASCII") { c in .bool(c.receiver.asString?.allSatisfy(\.isASCII) ?? false) }
            t.property("isHexDigit") { c in .bool(ch(c)?.isHexDigit ?? false) }
            t.property("hexDigitValue") { c in ch(c)?.hexDigitValue.map { .int($0) } ?? .nilValue }
            t.property("isSymbol") { c in .bool(ch(c)?.isSymbol ?? false) }
            t.property("isMathSymbol") { c in .bool(ch(c)?.isMathSymbol ?? false) }
            t.property("isCurrencySymbol") { c in .bool(ch(c)?.isCurrencySymbol ?? false) }
            t.property("isNewline") { c in .bool(ch(c)?.isNewline ?? false) }
            t.property("isCased") { c in .bool(ch(c)?.isCased ?? false) }
            t.property("isWholeNumber") { c in .bool(ch(c)?.isWholeNumber ?? false) }
            t.property("unicodeScalars") { c in .array((c.receiver.asString ?? "").unicodeScalars.map { KScalar(scalar: $0).kv }) }
            t.property("utf8CString") { c in .array((c.receiver.asString ?? "").utf8CString.map { KFixedInt(.int8, bits: UInt64(bitPattern: Int64($0))).kv }) }
        }
    }

    // MARK: Strings, by index

    /// A string index is a character offset in Kiln.
    static func stringIndices(_ r: KRegistry) {
        r.extend("String") { t in
            @MainActor func s(_ c: KCall) -> String { c.receiver.asString ?? "" }
            @MainActor func idx(_ str: String, _ v: KV?, _ c: KCall) throws -> String.Index {
                guard let i = v?.asInt, i >= 0, i <= str.count else {
                    throw c.interp.fail("String index \(v.map { c.interp.describe($0) } ?? "?") is out of bounds", c.line)
                }
                return str.index(str.startIndex, offsetBy: i)
            }
            @MainActor func range(_ str: String, _ v: KV?, _ c: KCall) throws -> Range<String.Index> {
                guard case .range(let lo, let hi, let closed)? = v else { throw c.fail("needs a range of indices") }
                let l = try idx(str, lo.isNil ? .int(0) : lo, c)
                var h = try idx(str, hi.isNil ? .int(str.count) : hi, c)
                if closed, !hi.isNil { h = str.index(after: h) }
                return l..<h
            }
            t.method("remove", "at:any", first: true) { c in
                var str = s(c)
                let i = try idx(str, c["at"], c)
                guard i < str.endIndex else { throw c.interp.fail("Can't remove at the end of a string", c.line) }
                let ch = str.remove(at: i)
                c.mutated = .string(str)
                return .string(String(ch))
            }
            t.method("replaceSubrange", "_:any with:any", first: true) { c in
                var str = s(c)
                str.replaceSubrange(try range(str, c.first, c), with: c.interp.describe(c["with"] ?? .string("")))
                c.mutated = .string(str)
                return .void
            }
            t.method("removeSubrange", "_:any") { c in
                var str = s(c)
                str.removeSubrange(try range(str, c.first, c))
                c.mutated = .string(str)
                return .void
            }
            t.method("removeFirst", "_:number?", first: true) { c in
                var str = s(c)
                let n = c.first?.asInt ?? 1
                guard str.count >= n, !str.isEmpty || n == 0 else { throw c.interp.fail("Can't remove \(n) from a string of \(str.count)", c.line) }
                if c.args.isEmpty { let ch = str.removeFirst(); c.mutated = .string(str); return .string(String(ch)) }
                str.removeFirst(n)
                c.mutated = .string(str)
                return .void
            }
            t.method("removeLast", "_:number?", first: true) { c in
                var str = s(c)
                let n = c.first?.asInt ?? 1
                guard str.count >= n, !str.isEmpty || n == 0 else { throw c.interp.fail("Can't remove \(n) from a string of \(str.count)", c.line) }
                if c.args.isEmpty { let ch = str.removeLast(); c.mutated = .string(str); return .string(String(ch)) }
                str.removeLast(n)
                c.mutated = .string(str)
                return .void
            }
            t.method("firstIndex", "where:closure", first: true) { c in
                let test = try c.interp.applier(c.first ?? .void, c.line)
                return try s(c).enumerated().first { c.interp.truthy(try test(.string(String($0.element)))) }.map { .int($0.offset) } ?? .nilValue
            }
            t.method("firstIndex", "of:any", first: true) { c in
                let str = s(c)
                guard let ch = c["of"]?.asString?.first, let i = str.firstIndex(of: ch) else { return .nilValue }
                return .int(str.distance(from: str.startIndex, to: i))
            }
            t.method("lastIndex", "of:any", first: true) { c in
                let str = s(c)
                guard let ch = c["of"]?.asString?.first, let i = str.lastIndex(of: ch) else { return .nilValue }
                return .int(str.distance(from: str.startIndex, to: i))
            }
            t.method("lastIndex", "where:closure", first: true) { c in
                let test = try c.interp.applier(c.first ?? .void, c.line)
                return try s(c).enumerated().reversed().first { c.interp.truthy(try test(.string(String($0.element)))) }.map { .int($0.offset) } ?? .nilValue
            }
            t.method("drop", "while:closure") { c in
                let test = try c.interp.applier(c.first ?? .void, c.line)
                return .string(String(try s(c).drop { c.interp.truthy(try test(.string(String($0)))) }))
            }
            t.method("trimmingPrefix", "while:closure") { c in
                let test = try c.interp.applier(c.first ?? .void, c.line)
                return .string(String(try s(c).trimmingPrefix { c.interp.truthy(try test(.string(String($0)))) }))
            }
            t.method("split", "maxSplits:number? omittingEmptySubsequences:bool? whereSeparator:closure", first: true) { c in
                let test = try c.interp.applier(c["whereSeparator"] ?? .void, c.line)
                var err: Error?
                let parts = s(c).split(maxSplits: c.int("maxSplits") ?? .max, omittingEmptySubsequences: c.bool("omittingEmptySubsequences", default: true)) { ch in
                    do { return c.interp.truthy(try test(.string(String(ch)))) } catch { err = error; return false }
                }
                if let err { throw err }
                return .array(parts.map { .string(String($0)) })
            }
            t.initializer("utf16CodeUnits:any count:number", first: true) { c in
                let units = ((try? c.interp.sequence(c.arg("utf16CodeUnits") ?? .nilValue)) ?? []).compactMap { $0.asInt }.map { UInt16(truncatingIfNeeded: $0) }
                return .string(String(decoding: units.prefix(c.int("count") ?? units.count), as: UTF16.self))
            }
            t.initializer("cString:any", first: true) { c in
                let bytes = ((try? c.interp.sequence(c["cString"] ?? .nilValue)) ?? []).compactMap { $0.asInt }.prefix { $0 != 0 }
                return .string(String(decoding: bytes.map { UInt8(truncatingIfNeeded: $0) }, as: UTF8.self))
            }
        }
    }

    // MARK: Collections

    static func collectionsMore(_ r: KRegistry) {
        r.type("KeyPathComparator", .language, support: .full,
               notes: "`sorted(using: KeyPathComparator(\\.name))`, with `order: .reverse`, or an array of them.") { t in
            t.initializer("_:any order:any?") { c in
                guard case .native(.keyPath(let p))? = c.first else { throw c.fail("needs a key path") }
                return KComparator(path: p, reverse: c.symbol("order") == "reverse").kv
            }
            t.initializer("_:any comparator:any order:any?") { c in
                guard case .native(.keyPath(let p))? = c.first else { throw c.fail("needs a key path") }
                return KComparator(path: p, reverse: c.symbol("order") == "reverse", localized: true).kv
            }
            t.property("order") { c in
                guard case .native(.boxed(let b)) = c.receiver, let k = b.value.base as? KComparator else { return .nilValue }
                return .native(.implicit(k.reverse ? "reverse" : "forward", []))
            }
            t.property("reversed") { c in
                guard case .native(.boxed(let b)) = c.receiver, var k = b.value.base as? KComparator else { return .nilValue }
                k.reverse.toggle()
                return k.kv
            }
        }
        r.type("SortDescriptor", .language, support: .full, notes: "`SortDescriptor(\\.name, order: .reverse)` with `sorted(using:)`.") { t in
            t.initializer("_:any order:any?") { c in
                guard case .native(.keyPath(let p))? = c.first else { throw c.fail("needs a key path") }
                return KComparator(path: p, reverse: c.symbol("order") == "reverse").kv
            }
            t.initializer("_:any comparator:any order:any?") { c in
                guard case .native(.keyPath(let p))? = c.first else { throw c.fail("needs a key path") }
                return KComparator(path: p, reverse: c.symbol("order") == "reverse", localized: true).kv
            }
        }
        r.alias("SortOrder", to: "KeyPathComparator", engineOnly: true)

        r.extend("Sequence") { t in
            t.method("sorted", "using:any", first: true) { c in .array(try sortedUsing(c.receiver.asArray ?? [], c["using"], c)) }
            t.method("split", "separator:any maxSplits:number? omittingEmptySubsequences:bool?", first: true) { c in
                let sep = c["separator"] ?? .nilValue
                let parts = (c.receiver.asArray ?? []).split(separator: sep, maxSplits: c.int("maxSplits") ?? .max,
                                                             omittingEmptySubsequences: c.bool("omittingEmptySubsequences", default: true))
                return .array(parts.map { .array(Array($0)) })
            }
            t.method("split", "maxSplits:number? omittingEmptySubsequences:bool? whereSeparator:closure", first: true) { c in
                let test = try c.interp.applier(c["whereSeparator"] ?? .void, c.line)
                var err: Error?
                let parts = (c.receiver.asArray ?? []).split(maxSplits: c.int("maxSplits") ?? .max,
                                                             omittingEmptySubsequences: c.bool("omittingEmptySubsequences", default: true)) { x in
                    do { return c.interp.truthy(try test(x)) } catch { err = error; return false }
                }
                if let err { throw err }
                return .array(parts.map { .array(Array($0)) })
            }
            t.method("shuffled", "using:binding", first: true) { c in
                let xs = c.receiver.asArray ?? []
                return .array(try KRandom.with(c) { g in xs.shuffled(using: &g) })
            }
            t.method("randomElement", "using:binding", first: true) { c in
                let xs = c.receiver.asArray ?? []
                return try KRandom.with(c) { g in xs.randomElement(using: &g) } ?? .nilValue
            }
            t.method("difference", "from:any") { c in
                let new = c.receiver.asArray ?? [], old = try c.interp.sequence(c["from"] ?? .nilValue)
                return .native(.boxed(KBoxed("CollectionDifference", KDifference(diff: new.difference(from: old)))))
            }
        }
        r.type("CollectionDifference", .language, support: .full, notes: "`difference(from:)`: `insertions`, `removals`, `count`, and `applying(_:)`.") { t in
            @MainActor func d(_ c: KCall) -> CollectionDifference<KV>? {
                if case .native(.boxed(let b)) = c.receiver { return (b.value.base as? KDifference)?.diff }
                return nil
            }
            t.property("count") { c in .int(d(c)?.count ?? 0) }
            t.property("isEmpty") { c in .bool(d(c)?.isEmpty ?? true) }
            t.property("insertions") { c in .array((d(c)?.insertions ?? []).map(KDifference.change)) }
            t.property("removals") { c in .array((d(c)?.removals ?? []).map(KDifference.change)) }
            t.method("inverse", "") { c in d(c).map { .native(.boxed(KBoxed("CollectionDifference", KDifference(diff: $0.inverse())))) } ?? .nilValue }
            t.fallback("Sequence") { v, _ in
                if case .native(.boxed(let b)) = v, let diff = (b.value.base as? KDifference)?.diff { return .array(diff.map(KDifference.change)) }
                return .array([])
            }
        }
        r.extend("Array") { t in
            t.method("applying", "_:any") { c in
                guard case .native(.boxed(let b))? = c.first, let diff = (b.value.base as? KDifference)?.diff else { throw c.fail("needs a CollectionDifference") }
                return (c.receiver.asArray ?? []).applying(diff).map { .array($0) } ?? .nilValue
            }
            t.method("replaceSubrange", "_:any with:any", first: true) { c in
                var xs = c.receiver.asArray ?? []
                guard case .range(let lo, let hi, let closed)? = c.first else { throw c.fail("needs a range") }
                let l = lo.asInt ?? 0, h = (hi.asInt ?? xs.count) + (closed && !hi.isNil ? 1 : 0)
                guard l >= 0, h <= xs.count, l <= h else { throw c.interp.fail("Range out of bounds", c.line) }
                xs.replaceSubrange(l..<h, with: try c.interp.sequence(c["with"] ?? .array([])))
                c.mutated = .array(xs)
                return .void
            }
            t.method("remove", "atOffsets:any", first: true) { c in
                var xs = c.receiver.asArray ?? []
                guard case .native(.indexSet(let set))? = c["atOffsets"] else { throw c.fail("needs an IndexSet") }
                for i in set.sorted(by: >) where i < xs.count { xs.remove(at: i) }
                c.mutated = .array(xs)
                return .void
            }
            t.method("partition", "by:closure") { c in
                var xs = c.receiver.asArray ?? []
                let test = try c.interp.applier(c.first ?? .void, c.line)
                var err: Error?
                let p = xs.partition { x in do { return c.interp.truthy(try test(x)) } catch { err = error; return false } }
                if let err { throw err }
                c.mutated = .array(xs)
                return .int(p)
            }
            t.method("sort", "using:any", first: true) { c in
                c.mutated = .array(try sortedUsing(c.receiver.asArray ?? [], c["using"], c))
                return .void
            }
            t.method("shuffle", "using:binding", first: true) { c in
                var xs = c.receiver.asArray ?? []
                try KRandom.with(c) { g in xs.shuffle(using: &g) }
                c.mutated = .array(xs)
                return .void
            }
        }
        r.extend("Dictionary") { t in
            t.method("merging", "_:any uniquingKeysWith:closure") { c in
                guard case .dict(var d) = c.receiver else { return c.receiver }
                let pairs = try mergePairs(c.first, c)
                guard case .function(let f)? = c["uniquingKeysWith"] else { throw c.fail("needs a closure") }
                for (k, v) in pairs { d[k] = try d[k].map { try c.interp.call(f, [$0, v], [nil, nil]) } ?? v }
                return .dict(d)
            }
        }
        r.extend("Range") { t in
            t.method("overlaps", "_:any") { c in
                guard case .range(let a, let b, let ca) = c.receiver, case .range(let x, let y, let cx)? = c.first,
                      let lo1 = a.asDouble, let hi1 = b.asDouble, let lo2 = x.asDouble, let hi2 = y.asDouble else { return .bool(false) }
                let end1 = ca ? hi1 : hi1 - 0.5, end2 = cx ? hi2 : hi2 - 0.5
                if (!ca && lo1 == hi1) || (!cx && lo2 == hi2) { return .bool(false) }
                return .bool(lo1 <= end2 && lo2 <= end1)
            }
            t.method("clamped", "to:any", first: true) { c in
                guard case .range(let a, let b, let closed) = c.receiver, case .range(let x, let y, _)? = c["to"] else { return c.receiver }
                func clamp(_ v: KV) -> KV {
                    guard let d = v.asDouble, let lo = x.asDouble, let hi = y.asDouble else { return v }
                    let r = min(max(d, lo), hi)
                    if case .int = v { return .int(Int(r)) }
                    return .double(r)
                }
                return .range(clamp(a), clamp(b), closed: closed)
            }
        }
        r.extend("Dictionary") { t in
            t.initializer("_:any uniquingKeysWith:closure", first: true) { c in
                guard case .function(let f)? = c["uniquingKeysWith"] else { throw c.fail("needs a closure") }
                var d: [KV: KV] = [:]
                for (k, v) in try mergePairs(c.first, c) { d[k] = try d[k].map { try c.interp.call(f, [$0, v], [nil, nil]) } ?? v }
                return .dict(d)
            }
        }

        r.type("KeyPath", .language, support: .full, notes: "`\\.name`, `\\Type.a.b`, `\\.self`; `value[keyPath:]` reads and writes; `appending(path:)`.") { t in
            t.method("appending", "path:any") { c in
                guard case .native(.keyPath(let a)) = c.receiver, case .native(.keyPath(let b))? = c["path"] else { throw c.fail("needs a key path") }
                return .native(.keyPath(a.filter { $0 != "self" } + b.filter { $0 != "self" }))
            }
        }
        r.function("sequence", .language, "first:any next:closure") { c in
            guard case .function(let f)? = c["next"] else { throw c.fail("needs a closure") }
            var out: [KV] = []
            var cur = c["first"] ?? .nilValue
            while !cur.isNil, out.count < 10_000 {
                out.append(cur)
                cur = try c.interp.call(f, [cur], [nil])
            }
            return .native(.boxed(KBoxed("UnfoldSequence", KUnfold(values: out))))
        }
        r.type("UnfoldSequence", .language, support: .full, notes: "`sequence(first:next:)`, made up to 10,000 elements.") { t in
            t.fallback("Sequence") { v, _ in
                if case .native(.boxed(let b)) = v, let u = b.value.base as? KUnfold { return .array(u.values) }
                return .array([])
            }
        }
    }

    /// Key-value pairs from a dictionary or a sequence of pairs.
    @MainActor static func mergePairs(_ v: KV?, _ c: KCall) throws -> [(KV, KV)] {
        if case .dict(let d)? = v { return d.sorted { c.interp.describe($0.key) < c.interp.describe($1.key) }.map { ($0.key, $0.value) } }
        return try c.interp.sequence(v ?? .nilValue).compactMap { if case .tuple(let p, _) = $0, p.count == 2 { return (p[0], p[1]) }; return nil }
    }

    /// `sorted(using:)` with one comparator or several (`KeyPathComparator`, `SortDescriptor`).
    @MainActor static func sortedUsing(_ xs: [KV], _ using: KV?, _ c: KCall) throws -> [KV] {
        var comparators: [KComparator] = []
        func add(_ v: KV) {
            if case .native(.boxed(let b)) = v, let k = b.value.base as? KComparator { comparators.append(k) }
            if case .native(.keyPath(let p)) = v { comparators.append(KComparator(path: p, reverse: false)) }
        }
        if case .array(let many)? = using { many.forEach(add) } else if let u = using { add(u) }
        guard !comparators.isEmpty else { throw c.fail("needs a KeyPathComparator or SortDescriptor") }
        var err: Error?
        let interp = c.interp, line = c.line
        func key(_ v: KV, _ k: KComparator) throws -> KV {
            var x = v
            for p in k.path where p != "self" { x = try interp.member(x, p, line: line) }
            return x
        }
        // A stable sort, as Swift's.
        let indexed = Array(xs.enumerated())
        let sorted = indexed.sorted { a, b in
            if err != nil { return false }
            do {
                for k in comparators {
                    let x = try key(a.element, k), y = try key(b.element, k)
                    if k.localized, let s = x.asString, let t = y.asString {
                        let r = s.localizedStandardCompare(t)
                        if r == .orderedSame { continue }
                        return (r == .orderedAscending) != k.reverse
                    }
                    if try interp.compare("<", x, y, line) { return !k.reverse }
                    if try interp.compare("<", y, x, line) { return k.reverse }
                }
                return a.offset < b.offset
            } catch { err = error; return false }
        }
        if let err { throw err }
        return sorted.map(\.element)
    }

    // MARK: Mirror

    static func reflection(_ r: KRegistry) {
        r.type("Mirror", .language, support: .full,
               notes: "`Mirror(reflecting:)`: `children` (each with `label` and `value`), `displayStyle` and `subjectType`.") { t in
            t.initializer("reflecting:any") { c in .native(.boxed(KBoxed("Mirror", KMirror.make(c["reflecting"] ?? .nilValue, c.interp)))) }
            @MainActor func m(_ c: KCall) -> KMirror? { if case .native(.boxed(let b)) = c.receiver { return b.value.base as? KMirror }; return nil }
            t.property("children") { c in .array((m(c)?.children ?? []).map { .tuple([$0.0.map { .string($0) } ?? .nilValue, $0.1], ["label", "value"]) }) }
            t.property("displayStyle") { c in m(c)?.style.map { .native(.implicit($0, [])) } ?? .nilValue }
            t.property("subjectType") { c in m(c).map { .type(.builtin($0.subjectType)) } ?? .nilValue }
            t.property("description") { c in .string("Mirror for \(m(c)?.subjectType ?? "Any")") }
        }
    }
}

/// `difference(from:)`, kept as Swift's.
struct KDifference: Hashable {
    let diff: CollectionDifference<KV>
    static func change(_ ch: CollectionDifference<KV>.Change) -> KV {
        switch ch {
        case .insert(let offset, let element, let assoc):
            return .enumV(KEnumValue(type: changeType, caseName: "insert", payload: [.int(offset), element, assoc.map { .int($0) } ?? .nilValue],
                                     payloadLabels: ["offset", "element", "associatedWith"]))
        case .remove(let offset, let element, let assoc):
            return .enumV(KEnumValue(type: changeType, caseName: "remove", payload: [.int(offset), element, assoc.map { .int($0) } ?? .nilValue],
                                     payloadLabels: ["offset", "element", "associatedWith"]))
        }
    }
    nonisolated(unsafe) static let changeType: KType = {
        let t = KType(name: "CollectionDifference.Change", kind: .enumType)
        let assoc: [(String?, KETypeRef)] = [("offset", .named("Int", [])), ("element", .named("Any", [])), ("associatedWith", .optional(.named("Int", [])))]
        t.cases = [KEEnumCase(name: "insert", associated: assoc, rawValue: nil), KEEnumCase(name: "remove", associated: assoc, rawValue: nil)]
        return t
    }()
}

/// `Mirror(reflecting:)` of an app value, a tuple or a collection.
struct KMirror: Hashable {
    var children: [(String?, KV)]
    var style: String?
    var subjectType: String

    static func == (a: KMirror, b: KMirror) -> Bool { a.subjectType == b.subjectType && a.children.map(\.1) == b.children.map(\.1) }
    func hash(into h: inout Hasher) { h.combine(subjectType) }

    @MainActor static func make(_ v: KV, _ interp: KInterpreter) -> KMirror {
        switch v {
        case .structV(let s):
            return KMirror(children: s.type.stored.compactMap { d in s.fields[d.name].map { (d.name, $0) } }, style: "struct", subjectType: s.type.name)
        case .object(let o):
            return KMirror(children: o.type.stored.compactMap { d in o.fields[d.name].map { (d.name, $0) } }, style: "class", subjectType: o.type.name)
        case .enumV(let e):
            let payload: KV = e.payload.count == 1 ? e.payload[0] : .tuple(e.payload, e.payloadLabels)
            return KMirror(children: e.payload.isEmpty ? [] : [(e.caseName, payload)], style: "enum", subjectType: e.type.name)
        case .tuple(let xs, let labels):
            return KMirror(children: xs.enumerated().map { i, x in ((i < labels.count ? labels[i] : nil) ?? ".\(i)", x) }, style: "tuple", subjectType: "Tuple")
        case .array(let xs): return KMirror(children: xs.map { (nil, $0) }, style: "collection", subjectType: "Array")
        case .set(let xs): return KMirror(children: xs.map { (nil, $0) }, style: "set", subjectType: "Set")
        case .dict(let d): return KMirror(children: d.map { (nil, .tuple([$0.key, $0.value], ["key", "value"])) }, style: "dictionary", subjectType: "Dictionary")
        case .nilValue: return KMirror(children: [], style: "optional", subjectType: "Optional")
        default: return KMirror(children: [], style: nil, subjectType: KRegistry.typeName(of: v))
        }
    }
}

// MARK: - Swift the standard library writes in Swift

/// Standard-library types Kiln writes in Swift, added to an app that names
/// them (and doesn't declare its own): `Result` and `AnyIterator`. The
/// engine runs them as the app's own types, and `Kiln.check` reads them so.
enum KSwiftPrelude {
    static let parts: [(name: String, source: String)] = [
        ("Result", """
        enum Result<Success, Failure: Error>: Equatable {
            case success(Success)
            case failure(Failure)
            init(catching body: () throws -> Success) {
                do { self = .success(try body()) } catch { self = .failure(error) }
            }
            func get() throws -> Success {
                switch self {
                case .success(let value): return value
                case .failure(let error): throw error
                }
            }
            func map<NewSuccess>(_ transform: (Success) -> NewSuccess) -> Result<NewSuccess, Failure> {
                switch self {
                case .success(let value): return .success(transform(value))
                case .failure(let error): return .failure(error)
                }
            }
            func mapError<NewFailure>(_ transform: (Failure) -> NewFailure) -> Result<Success, NewFailure> {
                switch self {
                case .success(let value): return .success(value)
                case .failure(let error): return .failure(transform(error))
                }
            }
            func flatMap<NewSuccess>(_ transform: (Success) -> Result<NewSuccess, Failure>) -> Result<NewSuccess, Failure> {
                switch self {
                case .success(let value): return transform(value)
                case .failure(let error): return .failure(error)
                }
            }
        }
        """),
        ("AnyIterator", """
        struct AnyIterator<Element>: IteratorProtocol, Sequence {
            let body: () -> Element?
            init(_ body: @escaping () -> Element?) { self.body = body }
            func next() -> Element? { body() }
        }
        """),
    ]

    /// Bridges that hand the app a `Result` it may never name (a file
    /// picker's completion, `loadTransferable`'s handler): their names bring
    /// the prelude's `Result` in too, so `try result.get()` works.
    static let alsoNeeded: [String: [String]] = [
        "Result": ["fileImporter", "fileExporter", "fileMover", "loadTransferable", "photosReferenceImageViewer"],
    ]

    /// The prelude's declarations an app's code needs: those it names and doesn't declare.
    static func types(for source: String, declared: Set<String>) -> [KETypeDecl] {
        var out: [KETypeDecl] = []
        for (name, _) in parts where !declared.contains(name) && (mentions(source, name) || (alsoNeeded[name] ?? []).contains { mentions(source, $0) }) {
            if let decls = parsed[name] { out.append(contentsOf: decls) }
        }
        return out
    }

    /// Whether `source` has `name` in it: a byte search (Foundation's
    /// `contains` compares Unicode-aware, and costs a fifth of a small app's run).
    static func mentions(_ source: String, _ name: String) -> Bool {
        let needle = Array(name.utf8)
        guard let first = needle.first else { return true }
        var source = source
        return source.withUTF8 { bytes in
            let n = needle.count
            guard bytes.count >= n else { return false }
            var i = 0
            while i <= bytes.count - n {
                if bytes[i] == first {
                    var j = 1
                    while j < n, bytes[i + j] == needle[j] { j += 1 }
                    if j == n { return true }
                }
                i += 1
            }
            return false
        }
    }

    nonisolated(unsafe) private static let parsed: [String: [KETypeDecl]] = {
        var out: [String: [KETypeDecl]] = [:]
        for (name, src) in parts {
            if case .success(let p) = KilnParsedSource(src).program { out[name] = p.types }
        }
        return out
    }()
}
