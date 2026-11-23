//
//  Strings.swift
//  Bridges: String
//
//  A string is also a sequence of one-character strings, so what isn't here
//  (`map`, `filter`, `contains(where:)` …) comes from `Sequence`.
//

import SwiftUI

extension LanguageBridges {
    static func strings(_ r: KRegistry) {
        r.type("String", .language) { t in
            t.initializer { c in
                if let f = c.arg("format")?.asString {
                    return .string(KFormatting.format(f, Array(c.args.dropFirst()), c.interp))
                }
                if let rep = c.arg("repeating") {
                    return .string(String(repeating: c.interp.describe(rep), count: c.arg("count")?.asInt ?? 0))
                }
                if let d = c.arg("describing") { return .string(c.interp.describe(d)) }
                if c.has("contentsOf") || c.has("contentsOfFile") { return try FoundationBridges.stringContents(c) }
                if let d = c.arg("data") { return KBuiltins.dataValue(d).flatMap { String(data: $0, encoding: .utf8) }.map { .string($0) } ?? .nilValue }
                if case .array(let chars)? = c.first { return .string(chars.map { c.interp.describe($0) }.joined()) }
                return .string(c.first.map { c.interp.describe($0) } ?? "")
            }
            t.staticProperty("self") { _ in .type(.builtin("String")) }

            @MainActor func s(_ c: KCall) -> String { c.receiver.asString ?? "" }
            t.property("count") { c in .int(s(c).count) }
            t.property("isEmpty") { c in .bool(s(c).isEmpty) }
            t.property("first") { c in s(c).first.map { .string(String($0)) } ?? .nilValue }
            t.property("last") { c in s(c).last.map { .string(String($0)) } ?? .nilValue }
            t.property("capitalized") { c in .string(s(c).capitalized) }
            t.property("localizedCapitalized") { c in .string(s(c).localizedCapitalized) }
            t.property("uppercased") { c in .string(s(c).uppercased()) }
            t.property("lowercased") { c in .string(s(c).lowercased()) }
            t.property("description") { c in .string(s(c)) }
            t.property("isNumber") { c in .bool(s(c).allSatisfy(\.isNumber)) }
            t.property("isLetter") { c in .bool(s(c).allSatisfy(\.isLetter)) }
            t.property("isUppercase") { c in .bool(s(c).allSatisfy(\.isUppercase)) }
            t.property("isLowercase") { c in .bool(s(c).allSatisfy(\.isLowercase)) }
            t.property("isWhitespace") { c in .bool(s(c).allSatisfy(\.isWhitespace)) }
            t.property("isPunctuation") { c in .bool(s(c).allSatisfy(\.isPunctuation)) }
            t.property("wholeNumberValue") { c in s(c).first?.wholeNumberValue.map { .int($0) } ?? .nilValue }
            t.property("utf8") { c in .array(s(c).utf8.map { .int(Int($0)) }) }
            t.property("unicodeScalars") { c in .array(s(c).unicodeScalars.map { .string(String($0)) }) }
            t.property("startIndex") { _ in .int(0) }
            t.property("endIndex") { c in .int(s(c).count) }
            t.property("indices") { c in .array((0..<s(c).count).map { .int($0) }) }

            // Mutating.
            t.method("append") { c in
                c.mutated = .string(s(c) + (c.first.map { c.interp.describe($0) } ?? ""))
                return .void
            }
            t.method("removeLast") { c in
                var str = s(c)
                guard !str.isEmpty else { throw c.interp.fail("Can't remove from an empty string", c.line) }
                let ch = str.removeLast()
                c.mutated = .string(str)
                return .string(String(ch))
            }
            t.method("removeFirst") { c in
                var str = s(c)
                guard !str.isEmpty else { throw c.interp.fail("Can't remove from an empty string", c.line) }
                let ch = str.removeFirst()
                c.mutated = .string(str)
                return .string(String(ch))
            }
            t.method("removeAll") { c in
                var str = s(c)
                if let f = c.first {
                    let test = try c.interp.applier(f, c.line)
                    str = String(try str.filter { !c.interp.truthy(try test(.string(String($0)))) })
                } else { str = "" }
                c.mutated = .string(str)
                return .void
            }
            t.method("insert") { c in
                var str = s(c)
                if let ch = c.first, let at = c.arg("at")?.asInt {
                    let idx = str.index(str.startIndex, offsetBy: min(max(at, 0), str.count))
                    str.insert(contentsOf: c.interp.describe(ch), at: idx)
                }
                c.mutated = .string(str)
                return .void
            }

            t.method("uppercased") { c in .string(s(c).uppercased()) }
            t.method("lowercased") { c in .string(s(c).lowercased()) }
            t.method("capitalized") { c in .string(s(c).capitalized) }
            t.method("hasPrefix") { c in .bool(s(c).hasPrefix(c.at(0)?.asString ?? "")) }
            t.method("hasSuffix") { c in .bool(s(c).hasSuffix(c.at(0)?.asString ?? "")) }
            t.method("contains") { c in
                if let r = KBuiltins.regexBox(c.first) { return .bool(try r.regex.firstMatch(in: s(c)) != nil) }
                if c.labels.first == "where" {
                    let test = try c.interp.applier(c.first ?? .void, c.line)
                    return .bool(try s(c).contains { c.interp.truthy(try test(.string(String($0)))) })
                }
                return .bool(s(c).contains(c.at(0)?.asString ?? ""))
            }
            t.methods(["localizedCaseInsensitiveContains", "localizedStandardContains"]) { c, _ in
                .bool(s(c).localizedCaseInsensitiveContains(c.at(0)?.asString ?? ""))
            }
            t.method("lowercasedContains") { c in .bool(s(c).lowercased().contains(c.at(0)?.asString?.lowercased() ?? "")) }
            t.method("split") { c in
                let str = s(c)
                let sep = c.arg("separator")?.asString ?? c.first?.asString ?? " "
                let maxSplits = c.arg("maxSplits")?.asInt ?? Int.max
                let omit = c.arg("omittingEmptySubsequences").map { c.interp.truthy($0) } ?? true
                if let ch = sep.first, sep.count == 1 {
                    return .array(str.split(separator: ch, maxSplits: maxSplits, omittingEmptySubsequences: omit).map { .string(String($0)) })
                }
                return .array(str.components(separatedBy: sep).filter { !omit || !$0.isEmpty }.map { .string($0) })
            }
            t.method("components") { c in
                if let sep = c.arg("separatedBy")?.asString { return .array(s(c).components(separatedBy: sep).map { .string($0) }) }
                return .array(s(c).components(separatedBy: .whitespaces).map { .string($0) })
            }
            t.method("trimmingCharacters") { c in
                var set: CharacterSet = .whitespacesAndNewlines
                if case .native(.implicit(let n, _))? = c.first {
                    switch n {
                    case "whitespaces": set = .whitespaces
                    case "newlines": set = .newlines
                    case "punctuationCharacters": set = .punctuationCharacters
                    case "decimalDigits": set = .decimalDigits
                    default: break
                    }
                }
                return .string(s(c).trimmingCharacters(in: set))
            }
            t.method("replacingOccurrences") { c in
                .string(s(c).replacingOccurrences(of: c.arg("of")?.asString ?? "", with: c.arg("with")?.asString ?? ""))
            }
            t.method("prefix") { c in
                if let n = c.first?.asInt { return .string(String(s(c).prefix(n))) }
                if c.labels.first == "while" {
                    let test = try c.interp.applier(c.first ?? .void, c.line)
                    return .string(String(try s(c).prefix { c.interp.truthy(try test(.string(String($0)))) }))
                }
                return try sequenceMethod(c, "prefix")
            }
            t.method("suffix") { c in
                if let n = c.first?.asInt { return .string(String(s(c).suffix(n))) }
                return try sequenceMethod(c, "suffix")
            }
            t.method("dropFirst") { c in .string(String(s(c).dropFirst(c.first?.asInt ?? 1))) }
            t.method("dropLast") { c in .string(String(s(c).dropLast(c.first?.asInt ?? 1))) }
            t.method("reversed") { c in .string(String(s(c).reversed())) }
            t.method("padding") { c in
                let str = s(c)
                return .string(str.padding(toLength: c.arg("toLength")?.asInt ?? str.count, withPad: c.arg("withPad")?.asString ?? " ", startingAt: 0))
            }
            t.method("isEmpty") { c in .bool(s(c).isEmpty) }
            t.method("starts") { c in .bool(s(c).hasPrefix(c.arg("with")?.asString ?? "")) }
            t.methods(["index", "firstIndex"]) { c, _ in
                let str = s(c)
                if let ch = c.first?.asString, let first = ch.first, let i = str.firstIndex(of: first) {
                    return .int(str.distance(from: str.startIndex, to: i))
                }
                return .nilValue
            }
            t.method("range") { c in
                let str = s(c)
                if let sub = c.arg("of")?.asString, let rg = str.range(of: sub, options: .caseInsensitive) {
                    return .range(.int(str.distance(from: str.startIndex, to: rg.lowerBound)),
                                  .int(str.distance(from: str.startIndex, to: rg.upperBound)), closed: false)
                }
                return .nilValue
            }
            t.method("formatted") { c in .string(s(c)) }
            t.method("data") { c in .native(.object("Data", KRef(Data(s(c).utf8) as NSData))) }

            t.fallback("Sequence") { v, _ in .array((v.asString ?? "").map { .string(String($0)) }) }
        }
        for alias in ["Substring", "Character"] { r.alias(alias, to: "String") }
    }

    /// A `Sequence` method on a string's characters, for a form the string's
    /// own method doesn't take.
    static func sequenceMethod(_ c: KCall, _ name: String) throws -> KV {
        guard let ms = c.interp.registry.type("Sequence")?.methods[name] else { throw c.noMember() }
        let chars = KV.array((c.receiver.asString ?? "").map { .string(String($0)) })
        return try c.interp.runBridge(ms, "Sequence.\(name)", values: c.args, labels: c.labels, line: c.line, receiver: chars).0
    }
}
