//
//  Collections.swift
//  Bridges: Array, Set, Dictionary, ranges, and Sequence
//
//  `Sequence` holds what every collection has (`map`, `filter`, `sorted` …).
//  Array, Set, Dictionary, String and the ranges fall back to it, each as an
//  array: a set's elements, a dictionary's `(key, value)` pairs sorted by key,
//  a string's characters, a range's numbers.
//

import SwiftUI

extension LanguageBridges {
    static func collections(_ r: KRegistry) {
        sequence(r)
        array(r)
        set(r)
        dictionary(r)
        ranges(r)
        tuples(r)
    }

    // MARK: Sequence

    static func sequence(_ r: KRegistry) {
        r.type("Sequence", .language) { t in
            t.namespace()
            @MainActor func a(_ c: KCall) -> [KV] { c.receiver.asArray ?? [] }
            @MainActor func fn(_ c: KCall, _ i: Int = 0) throws -> (KV) throws -> KV {
                guard i < c.args.count else { throw c.interp.fail("'\(c.memberName)' needs a closure", c.line) }
                return try c.interp.applier(c.args[i], c.line)
            }
            @MainActor func fn2(_ c: KCall, _ i: Int = 0) throws -> (KV, KV) throws -> KV {
                guard i < c.args.count else { throw c.interp.fail("'\(c.memberName)' needs a closure", c.line) }
                let f = c.args[i]
                return { x, y in
                    switch f {
                    case .function(let fun): return try c.interp.call(fun, [x, y], [nil, nil])
                    case .native(.keyPath(let comps)): return try c.interp.member(x, comps.first ?? "self", line: c.line)
                    default: throw c.interp.fail("'\(c.memberName)' needs a closure", c.line)
                    }
                }
            }
            let truthy: @MainActor (KCall, KV) -> Bool = { c, v in c.interp.truthy(v) }

            t.method("map") { c in let f = try fn(c); return .array(try a(c).map(f)) }
            t.method("compactMap") { c in let f = try fn(c); return .array(try a(c).map(f).filter { !$0.isNil }) }
            t.method("flatMap") { c in let f = try fn(c); return .array(try a(c).flatMap { try c.interp.sequence(try f($0)) }) }
            t.method("filter") { c in let f = try fn(c); return .array(try a(c).filter { truthy(c, try f($0)) }) }
            t.method("forEach") { c in let f = try fn(c); for x in a(c) { _ = try f(x) }; return .void }
            t.method("reduce") { c in
                if c.labels.first == "into" {
                    guard c.args.count > 1, case .function(let fun) = c.args[1] else { throw c.interp.fail("reduce(into:) needs a closure", c.line) }
                    let acc = KBox(c.args[0])
                    for x in a(c) {
                        _ = try c.interp.call(fun, [.binding(KBinding(get: { acc.value }, set: { acc.value = $0 })), x], [nil, nil])
                    }
                    return acc.value
                }
                let f = try fn2(c, 1)
                var acc = c.args.first ?? .void
                for x in a(c) { acc = try f(acc, x) }
                return acc
            }
            t.method("sorted") { c in .array(try sortValues(a(c), c)) }
            t.method("reversed") { c in .array(a(c).reversed()) }
            t.method("shuffled") { c in .array(a(c).shuffled(using: &c.interp.rng)) }
            t.method("randomElement") { c in a(c).randomElement(using: &c.interp.rng) ?? .nilValue }
            t.method("contains") { c in
                if c.labels.first == "where" || (c.first.map { if case .function = $0 { return true }; return false } ?? false) {
                    let f = try fn(c); return .bool(try a(c).contains { truthy(c, try f($0)) })
                }
                return .bool(a(c).contains(c.at(0) ?? .void))
            }
            t.method("allSatisfy") { c in let f = try fn(c); return .bool(try a(c).allSatisfy { truthy(c, try f($0)) }) }
            t.method("first") { c in let f = try fn(c); return try a(c).first { truthy(c, try f($0)) } ?? .nilValue }
            t.method("last") { c in let f = try fn(c); return try a(c).last { truthy(c, try f($0)) } ?? .nilValue }
            t.method("firstIndex") { c in
                if let of = c.arg("of") { return a(c).firstIndex(of: of).map { .int($0) } ?? .nilValue }
                let f = try fn(c); return try a(c).firstIndex { truthy(c, try f($0)) }.map { .int($0) } ?? .nilValue
            }
            t.method("lastIndex") { c in
                if let of = c.arg("of") { return a(c).lastIndex(of: of).map { .int($0) } ?? .nilValue }
                let f = try fn(c); return try a(c).lastIndex { truthy(c, try f($0)) }.map { .int($0) } ?? .nilValue
            }
            t.method("count") { c in
                if c.labels.first == "where" { let f = try fn(c); return .int(try a(c).filter { truthy(c, try f($0)) }.count) }
                return .int(a(c).count)
            }
            t.methods(["min", "max"]) { c, name in
                let items = a(c)
                if c.args.isEmpty {
                    var best: KV? = nil
                    for x in items {
                        if let b = best { if try c.interp.compare(name == "min" ? "<" : ">", x, b, c.line) { best = x } } else { best = x }
                    }
                    return best ?? .nilValue
                }
                let f = try fn2(c)
                var best: KV? = nil
                for x in items {
                    guard let b = best else { best = x; continue }
                    if name == "min" { if truthy(c, try f(x, b)) { best = x } } else if truthy(c, try f(b, x)) { best = x }
                }
                return best ?? .nilValue
            }
            t.method("enumerated") { c in .array(a(c).enumerated().map { .tuple([.int($0.offset), $0.element], ["offset", "element"]) }) }
            t.method("prefix") { c in
                if let n = c.first?.asInt { return .array(Array(a(c).prefix(n))) }
                let f = try fn(c); return .array(try Array(a(c).prefix { truthy(c, try f($0)) }))
            }
            t.method("suffix") { c in .array(Array(a(c).suffix(c.first?.asInt ?? 0))) }
            t.method("dropFirst") { c in .array(Array(a(c).dropFirst(c.first?.asInt ?? 1))) }
            t.method("dropLast") { c in .array(Array(a(c).dropLast(c.first?.asInt ?? 1))) }
            t.method("joined") { c in
                let items = a(c)
                let sep = c.arg("separator")?.asString ?? ""
                if items.allSatisfy({ if case .array = $0 { return true }; return false }) { return .array(items.flatMap { $0.asArray ?? [] }) }
                return .string(items.map { c.interp.describe($0) }.joined(separator: sep))
            }
            t.method("split") { c in .array([.array(a(c))]) }
            t.method("elementsEqual") { c in .bool(a(c) == (try c.interp.sequence(c.at(0) ?? .void))) }
            t.method("starts") { c in .bool(a(c).starts(with: try c.interp.sequence(c.arg("with") ?? c.at(0) ?? .void))) }
            t.method("index") { c in
                guard let of = c.arg("of") else { throw c.noMember() }
                return a(c).firstIndex(of: of).map { .int($0) } ?? .nilValue
            }
            t.method("chunked") { c in
                let items = a(c)
                let n = max(1, c.arg("into")?.asInt ?? 1)
                return .array(stride(from: 0, to: items.count, by: n).map { .array(Array(items[$0..<min($0 + n, items.count)])) })
            }
            t.method("sum") { c in a(c).reduce(KV.int(0)) { acc, x in (try? c.interp.arithmetic("+", acc, x, c.line)) ?? acc } }
            t.method("uniqued") { c in var seen = Set<KV>(); return .array(a(c).filter { seen.insert($0).inserted }) }
            t.method("isEmpty") { c in .bool(a(c).isEmpty) }
            t.method("makeIterator") { c in .array(a(c)) }
        }
    }

    /// `sorted()`, `sorted(by:)`, `sorted(using: \.key)` and `sort` alike.
    static func sortValues(_ a: [KV], _ c: KCall) throws -> [KV] {
        let interp = c.interp, line = c.line
        var err: Error?
        if let f = c.first {
            let sorted = a.sorted { x, y in
                if err != nil { return false }
                do {
                    switch f {
                    case .function(let fun): return interp.truthy(try interp.call(fun, [x, y], [nil, nil]))
                    case .native(.keyPath(let comps)):
                        var vx = x, vy = y
                        for k in comps where k != "self" { vx = try interp.member(vx, k, line: line); vy = try interp.member(vy, k, line: line) }
                        return try interp.compare("<", vx, vy, line)
                    default: return false
                    }
                } catch { err = error; return false }
            }
            if let err { throw err }
            return sorted
        }
        let sorted = a.sorted { x, y in
            do { return try interp.compare("<", x, y, line) } catch { err = error; return false }
        }
        if let err { throw err }
        return sorted
    }

    // MARK: Array

    static func array(_ r: KRegistry) {
        r.type("Array", .language) { t in
            t.initializer { c in
                if let rep = c.arg("repeating") { return .array(Array(repeating: rep, count: c.arg("count")?.asInt ?? 0)) }
                if let f = c.first { return .array(try c.interp.sequence(f)) }
                return .array([])
            }
            @MainActor func a(_ c: KCall) -> [KV] { c.receiver.asArray ?? [] }
            t.property("count") { c in .int(a(c).count) }
            t.property("isEmpty") { c in .bool(a(c).isEmpty) }
            t.property("first") { c in a(c).first ?? .nilValue }
            t.property("last") { c in a(c).last ?? .nilValue }
            t.property("indices") { c in .range(.int(0), .int(a(c).count), closed: false) }
            t.property("startIndex") { _ in .int(0) }
            t.property("endIndex") { c in .int(a(c).count) }
            t.property("description") { c in .string(c.interp.describe(c.receiver)) }
            t.property("lazy") { c in c.receiver }

            // Mutating.
            t.method("append") { c in
                var arr = a(c)
                if let more = c.arg("contentsOf") { arr.append(contentsOf: try c.interp.sequence(more)) } else if let x = c.first { arr.append(x) }
                c.mutated = .array(arr)
                return .void
            }
            t.method("insert") { c in
                var arr = a(c)
                let at = c.arg("at")?.asInt ?? 0
                if let more = c.arg("contentsOf") { arr.insert(contentsOf: try c.interp.sequence(more), at: min(max(at, 0), arr.count)) }
                else if let x = c.first { arr.insert(x, at: min(max(at, 0), arr.count)) }
                c.mutated = .array(arr)
                return .void
            }
            t.method("remove") { c in
                var arr = a(c)
                if let offs = c.arg("atOffsets"), case .native(.indexSet(let set)) = offs {
                    for i in set.sorted(by: >) where i < arr.count { arr.remove(at: i) }
                    c.mutated = .array(arr)
                    return .void
                }
                guard let i = (c.arg("at") ?? c.first)?.asInt, i >= 0, i < arr.count else {
                    throw c.interp.fail("Index out of range in remove(at:)", c.line)
                }
                let removed = arr.remove(at: i)
                c.mutated = .array(arr)
                return removed
            }
            t.method("removeFirst") { c in
                var arr = a(c)
                guard !arr.isEmpty else { throw c.interp.fail("Can't remove the first element from an empty array", c.line) }
                if let n = c.first?.asInt { arr.removeFirst(min(n, arr.count)); c.mutated = .array(arr); return .void }
                let x = arr.removeFirst()
                c.mutated = .array(arr)
                return x
            }
            t.method("removeLast") { c in
                var arr = a(c)
                guard !arr.isEmpty else { throw c.interp.fail("Can't remove the last element from an empty array", c.line) }
                if let n = c.first?.asInt { arr.removeLast(min(n, arr.count)); c.mutated = .array(arr); return .void }
                let x = arr.removeLast()
                c.mutated = .array(arr)
                return x
            }
            t.method("popLast") { c in
                var arr = a(c)
                let x = arr.popLast() ?? .nilValue
                c.mutated = .array(arr)
                return x
            }
            t.method("removeAll") { c in
                var arr = a(c)
                if let f = c.first {
                    let test = try c.interp.applier(f, c.line)
                    arr = try arr.filter { !c.interp.truthy(try test($0)) }
                } else { arr.removeAll() }
                c.mutated = .array(arr)
                return .void
            }
            t.method("removeSubrange") { c in
                var arr = a(c)
                if case .range(let lo, let hi, let closed)? = c.first, let l = lo.asInt, let h = hi.asInt {
                    arr.removeSubrange(l..<min(closed ? h + 1 : h, arr.count))
                }
                c.mutated = .array(arr)
                return .void
            }
            t.method("move") { c in
                var arr = a(c)
                if case .native(.indexSet(let from))? = c.arg("fromOffsets"), let to = c.arg("toOffset")?.asInt {
                    arr.move(fromOffsets: from, toOffset: to)
                }
                c.mutated = .array(arr)
                return .void
            }
            t.method("swapAt") { c in
                var arr = a(c)
                if let i = c.at(0)?.asInt, let j = c.at(1)?.asInt, i < arr.count, j < arr.count { arr.swapAt(i, j) }
                c.mutated = .array(arr)
                return .void
            }
            t.method("sort") { c in
                c.mutated = .array(try sortValues(a(c), c))
                return .void
            }
            t.method("reverse") { c in
                c.mutated = .array(a(c).reversed())
                return .void
            }
            t.method("shuffle") { c in
                var arr = a(c)
                arr.shuffle(using: &c.interp.rng)
                c.mutated = .array(arr)
                return .void
            }
            t.fallback("Sequence") { v, _ in v }
        }
        for alias in ["ContiguousArray", "ArraySlice"] { r.alias(alias, to: "Array") }
    }

    // MARK: Set

    static func set(_ r: KRegistry) {
        r.type("Set", .language) { t in
            t.initializer { c in
                if let f = c.first { return .set(Set(try c.interp.sequence(f))) }
                return .set([])
            }
            @MainActor func s(_ c: KCall) -> Set<KV> { if case .set(let s) = c.receiver { return s }; return [] }
            t.property("count") { c in .int(s(c).count) }
            t.property("isEmpty") { c in .bool(s(c).isEmpty) }
            t.property("first") { c in s(c).first ?? .nilValue }

            t.method("insert") { c in
                var set = s(c)
                let x = c.at(0) ?? .void
                let (inserted, _) = set.insert(x)
                c.mutated = .set(set)
                return .tuple([.bool(inserted), x], ["inserted", "memberAfterInsert"])
            }
            t.method("remove") { c in
                var set = s(c)
                let removed = set.remove(c.at(0) ?? .void) ?? .nilValue
                c.mutated = .set(set)
                return removed
            }
            t.method("removeAll") { c in c.mutated = .set([]); return .void }
            t.method("formUnion") { c in var set = s(c); set.formUnion(try c.interp.sequence(c.at(0) ?? .void)); c.mutated = .set(set); return .void }
            t.method("formIntersection") { c in var set = s(c); set.formIntersection(try c.interp.sequence(c.at(0) ?? .void)); c.mutated = .set(set); return .void }
            t.method("subtract") { c in var set = s(c); set.subtract(try c.interp.sequence(c.at(0) ?? .void)); c.mutated = .set(set); return .void }
            t.method("contains") { c in
                if c.labels.first == "where" {
                    let f = try c.interp.applier(c.first ?? .void, c.line)
                    return .bool(try s(c).contains { c.interp.truthy(try f($0)) })
                }
                return .bool(s(c).contains(c.at(0) ?? .void))
            }
            t.method("union") { c in .set(s(c).union(try c.interp.sequence(c.at(0) ?? .void))) }
            t.method("intersection") { c in .set(s(c).intersection(try c.interp.sequence(c.at(0) ?? .void))) }
            t.method("subtracting") { c in .set(s(c).subtracting(try c.interp.sequence(c.at(0) ?? .void))) }
            t.method("symmetricDifference") { c in .set(s(c).symmetricDifference(try c.interp.sequence(c.at(0) ?? .void))) }
            t.method("isSubset") { c in .bool(s(c).isSubset(of: try c.interp.sequence(c.at(0) ?? .void))) }
            t.method("isSuperset") { c in .bool(s(c).isSuperset(of: try c.interp.sequence(c.at(0) ?? .void))) }
            t.method("isDisjoint") { c in .bool(s(c).isDisjoint(with: try c.interp.sequence(c.at(0) ?? .void))) }
            t.fallback("Sequence") { v, _ in .array(Array(v.asArray ?? [])) }
        }
    }

    // MARK: Dictionary

    static func dictionary(_ r: KRegistry) {
        r.type("Dictionary", .language) { t in
            t.initializer { c in
                if let g = c.arg("grouping"), case .function(let by)? = c.arg("by") {
                    var d: [KV: KV] = [:]
                    for item in try c.interp.sequence(g) {
                        let k = try c.interp.call(by, [item], [nil])
                        if d[k] == nil { d[k] = .array([]) }
                        if case .array(var a)? = d[k] { a.append(item); d[k] = .array(a) }
                    }
                    return .dict(d)
                }
                if let u = c.arg("uniqueKeysWithValues") ?? c.first {
                    var d: [KV: KV] = [:]
                    for pair in try c.interp.sequence(u) { if case .tuple(let tv, _) = pair, tv.count == 2 { d[tv[0]] = tv[1] } }
                    return .dict(d)
                }
                return .dict([:])
            }
            @MainActor func d(_ c: KCall) -> [KV: KV] { if case .dict(let d) = c.receiver { return d }; return [:] }
            @MainActor func sortedKeys(_ c: KCall) -> [KV] { d(c).keys.sorted { c.interp.describe($0) < c.interp.describe($1) } }
            t.property("count") { c in .int(d(c).count) }
            t.property("isEmpty") { c in .bool(d(c).isEmpty) }
            t.property("keys") { c in .array(sortedKeys(c)) }
            t.property("values") { c in let dict = d(c); return .array(sortedKeys(c).map { dict[$0]! }) }
            t.property("first") { c in d(c).first.map { .tuple([$0.key, $0.value], ["key", "value"]) } ?? .nilValue }

            t.method("removeValue") { c in
                var dict = d(c)
                let removed = dict.removeValue(forKey: c.arg("forKey") ?? c.at(0) ?? .void) ?? .nilValue
                c.mutated = .dict(dict)
                return removed
            }
            t.method("updateValue") { c in
                var dict = d(c)
                let old = dict.updateValue(c.at(0) ?? .void, forKey: c.arg("forKey") ?? c.at(1) ?? .void) ?? .nilValue
                c.mutated = .dict(dict)
                return old
            }
            t.method("removeAll") { c in c.mutated = .dict([:]); return .void }
            t.method("merge") { c in
                var dict = d(c)
                if case .dict(let other)? = c.at(0) {
                    for (k, v) in other {
                        if let existing = dict[k], c.args.count > 1, case .function(let f) = c.args[1] {
                            dict[k] = try c.interp.call(f, [existing, v], [nil, nil])
                        } else { dict[k] = v }
                    }
                }
                c.mutated = .dict(dict)
                return .void
            }
            t.method("mapValues") { c in
                let f = try c.interp.applier(c.first ?? .void, c.line)
                var out: [KV: KV] = [:]
                for (k, v) in d(c) { out[k] = try f(v) }
                return .dict(out)
            }
            t.method("compactMapValues") { c in
                let f = try c.interp.applier(c.first ?? .void, c.line)
                var out: [KV: KV] = [:]
                for (k, v) in d(c) { let x = try f(v); if !x.isNil { out[k] = x } }
                return .dict(out)
            }
            t.method("filter") { c in
                let f = try c.interp.applier(c.first ?? .void, c.line)
                var out: [KV: KV] = [:]
                for (k, v) in d(c) where c.interp.truthy(try f(.tuple([k, v], ["key", "value"]))) { out[k] = v }
                return .dict(out)
            }
            t.fallback("Sequence") { v, interp in
                guard case .dict(let dict) = v else { return .array([]) }
                return .array(dict.keys.sorted { interp.describe($0) < interp.describe($1) }.map { .tuple([$0, dict[$0]!], ["key", "value"]) })
            }
        }
    }

    // MARK: Ranges

    static func ranges(_ r: KRegistry) {
        r.type("Range", .language) { t in
            t.initializer { c in
                // `Range(nsRange, in: text)` (Text/Parsing.swift).
                if let text = c.arg("in")?.asString, let ns = KNSRange.from(c.first) { return KNSRange.offsets(ns, in: text) }
                return c.first ?? .nilValue
            }
            @MainActor func bounds(_ c: KCall) -> (KV, KV, Bool) {
                if case .range(let lo, let hi, let closed) = c.receiver { return (lo, hi, closed) }
                return (.nilValue, .nilValue, false)
            }
            t.property("lowerBound") { c in bounds(c).0 }
            t.property("upperBound") { c in bounds(c).1 }
            t.property("count") { c in
                let (lo, hi, closed) = bounds(c)
                guard let l = lo.asInt, let h = hi.asInt else { throw c.noMember() }
                return .int(max(0, (closed ? h + 1 : h) - l))
            }
            t.property("isEmpty") { c in
                let (lo, hi, closed) = bounds(c)
                guard let l = lo.asInt, let h = hi.asInt else { throw c.noMember() }
                return .bool(closed ? h < l : h <= l)
            }
            t.property("first") { c in bounds(c).0 }
            t.property("last") { c in
                let (_, hi, closed) = bounds(c)
                guard let h = hi.asInt else { throw c.noMember() }
                return .int(closed ? h : h - 1)
            }
            t.method("contains") { c in
                if c.labels.first == "where" { return try sequenceOf(c, "contains") }
                return .bool(c.interp.rangeContains(c.receiver, c.at(0) ?? .void))
            }
            t.method("clamped") { c in c.receiver }
            t.fallback("Sequence") { v, interp in .array(try interp.sequence(v)) }
        }
        r.alias("ClosedRange", to: "Range")
    }

    /// A `Sequence` method on a range's elements.
    static func sequenceOf(_ c: KCall, _ name: String) throws -> KV {
        guard let ms = c.interp.registry.type("Sequence")?.methods[name] else { throw c.noMember() }
        return try c.interp.runBridge(ms, "Sequence.\(name)", values: c.args, labels: c.labels, line: c.line,
                                      receiver: .array(try c.interp.sequence(c.receiver))).0
    }
}

extension LanguageBridges {
    /// A tuple maps like the array of its elements.
    static func tuples(_ r: KRegistry) {
        r.type("Tuple", .language) { t in
            t.internal()
            t.method("map") { c in
                guard case .tuple(let vals, _) = c.receiver else { return .nilValue }
                let f = try c.interp.applier(c.first ?? .void, c.line)
                return .array(try vals.map(f))
            }
        }
    }
}
