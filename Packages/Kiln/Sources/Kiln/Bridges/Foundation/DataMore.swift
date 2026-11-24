//
//  DataMore.swift
//  Bridges: Data's bytes, JSONSerialization, property lists, CryptoKit's
//  hashes, NSAttributedString, NSString's paths, and Foundation's string
//  comparison and search (Round 2C)
//

import SwiftUI
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

// `Data` is an `NSData` in Kiln: it loops over its bytes and prints as Swift prints it.
extension NSData: KNativeSequence, KDescribable {
    func elements(_ interp: KInterpreter) throws -> [KV] { (self as Data).map { KFixedInt(.uint8, bits: UInt64($0)).kv } }
    func describe(_ interp: KInterpreter) -> String { "\(length) bytes" }
}

/// A CryptoKit digest: its bytes, printed as Swift prints it (`SHA256 digest: …`).
struct KDigest: Hashable, KDescribable, KNativeSequence {
    let name: String
    let bytes: [UInt8]
    var kv: KV { .native(.boxed(KBoxed("Digest", self))) }
    func describe(_ interp: KInterpreter) -> String { "\(name) digest: " + bytes.map { String(format: "%02x", $0) }.joined() }
    func elements(_ interp: KInterpreter) throws -> [KV] { bytes.map { KFixedInt(.uint8, bits: UInt64($0)).kv } }
}

@MainActor
enum KStrings {
    static func options(_ v: KV?, _ interp: KInterpreter) -> String.CompareOptions {
        var o: String.CompareOptions = []
        let items = (v.flatMap { try? interp.sequence($0) }) ?? []
        let names = items.compactMap(KFormatStyles.symbol) + (KFormatStyles.symbol(v).map { [$0] } ?? [])
        for n in names {
            switch n {
            case "caseInsensitive": o.insert(.caseInsensitive)
            case "literal": o.insert(.literal)
            case "backwards": o.insert(.backwards)
            case "anchored": o.insert(.anchored)
            case "numeric": o.insert(.numeric)
            case "diacriticInsensitive": o.insert(.diacriticInsensitive)
            case "widthInsensitive": o.insert(.widthInsensitive)
            case "forcedOrdering": o.insert(.forcedOrdering)
            case "regularExpression": o.insert(.regularExpression)
            default: break
            }
        }
        return o
    }

    /// A range of character offsets, as Kiln's string indices are.
    static func offsets(_ r: Range<String.Index>, in s: String) -> KV {
        .range(.int(s.distance(from: s.startIndex, to: r.lowerBound)), .int(s.distance(from: s.startIndex, to: r.upperBound)), closed: false)
    }
    static func indexRange(_ v: KV?, in s: String) -> Range<String.Index>? {
        guard case .range(let lo, let hi, let closed)? = v else { return nil }
        let l = max(0, min(lo.asInt ?? 0, s.count)), h0 = hi.isNil ? s.count : (hi.asInt ?? s.count)
        let h = max(l, min(closed ? h0 + 1 : h0, s.count))
        return s.index(s.startIndex, offsetBy: l)..<s.index(s.startIndex, offsetBy: h)
    }

    static func attributes(_ v: KV?) -> [NSAttributedString.Key: Any] {
        guard case .dict(let d)? = v else { return [:] }
        var out: [NSAttributedString.Key: Any] = [:]
        let keys: [String: NSAttributedString.Key] = ["font": .font, "foregroundColor": .foregroundColor, "backgroundColor": .backgroundColor,
            "kern": .kern, "underlineStyle": .underlineStyle, "strikethroughStyle": .strikethroughStyle, "link": .link,
            "baselineOffset": .baselineOffset, "tracking": .tracking, "ligature": .ligature, "shadow": .shadow]
        for (k, val) in d {
            guard let name = KFormatStyles.symbol(k), let key = keys[name] else { continue }
            out[key] = KNativeValues.native(from: val) ?? NSNull()
        }
        return out
    }
}

/// `PropertyListEncoder`'s settings.
final class KPlistEncoderBox {
    var format: PropertyListSerialization.PropertyListFormat = .binary
    let json = KEncoderBox()
}

extension FoundationBridges {
    static func dataMore(_ r: KRegistry) {
        r.extend("Data") { t in
            @MainActor func d(_ c: KCall) -> Data { c.object(Data.self) ?? Data() }
            t.initializer("base64Encoded:any options:any?", first: true) { c in
                if case .string(let s)? = c["base64Encoded"] { return Data(base64Encoded: s, options: .ignoreUnknownCharacters).map(KBuiltins.data) ?? .nilValue }
                return KBuiltins.dataValue(c["base64Encoded"]).flatMap { Data(base64Encoded: $0) }.map(KBuiltins.data) ?? .nilValue
            }
            t.initializer("repeating:any count:number", first: true) { c in
                KBuiltins.data(Data(repeating: UInt8(truncatingIfNeeded: c["repeating"]?.asInt ?? 0), count: c.int("count") ?? 0))
            }
            t.method("base64EncodedString", "options:any?") { c in
                var o: Data.Base64EncodingOptions = []
                switch KFormatStyles.symbol(c["options"]) {
                case "lineLength64Characters": o = .lineLength64Characters
                case "lineLength76Characters": o = .lineLength76Characters
                default: break
                }
                return .string(d(c).base64EncodedString(options: o))
            }
            t.method("base64EncodedData", "options:any?") { c in KBuiltins.data(d(c).base64EncodedData()) }
            t.method("append", "_:any") { c in
                var data = d(c)
                if let other = KBuiltins.dataValue(c.first) { data.append(other) }
                else if let b = c.first?.asInt { data.append(UInt8(truncatingIfNeeded: b)) }
                c.mutated = KBuiltins.data(data)
                return .void
            }
            t.method("append", "contentsOf:any") { c in
                var data = d(c)
                if let other = KBuiltins.dataValue(c["contentsOf"]) { data.append(other) }
                else { data.append(contentsOf: try c.interp.sequence(c["contentsOf"] ?? .nilValue).map { UInt8(truncatingIfNeeded: $0.asInt ?? 0) }) }
                c.mutated = KBuiltins.data(data)
                return .void
            }
            t.method("subscript", "_:any") { c in
                let data = d(c)
                if case .range(let lo, let hi, let closed)? = c.first {
                    let l = lo.asInt ?? 0, h = (hi.isNil ? data.count : (hi.asInt ?? data.count)) + (closed && !hi.isNil ? 1 : 0)
                    guard l >= 0, h <= data.count, l <= h else { throw c.interp.fail("Range out of bounds", c.line) }
                    return KBuiltins.data(data.subdata(in: l..<h))
                }
                guard let i = c.first?.asInt, i >= 0, i < data.count else { throw c.interp.fail("Index out of range", c.line) }
                return KFixedInt(.uint8, bits: UInt64(data[i])).kv
            }
            t.property("first") { c in d(c).first.map { KFixedInt(.uint8, bits: UInt64($0)).kv } ?? .nilValue }
            t.property("last") { c in d(c).last.map { KFixedInt(.uint8, bits: UInt64($0)).kv } ?? .nilValue }
            t.property("description") { c in .string("\(d(c).count) bytes") }
            t.property("bytes") { c in .array(d(c).map { KFixedInt(.uint8, bits: UInt64($0)).kv }) }
            for name in ["prefix", "suffix", "dropFirst", "dropLast"] {
                t.method(name, "_:number?") { c in
                    let data = d(c), n = c.int(0) ?? (name.hasPrefix("drop") ? 1 : 0)
                    switch name {
                    case "prefix": return KBuiltins.data(Data(data.prefix(n)))
                    case "suffix": return KBuiltins.data(Data(data.suffix(n)))
                    case "dropFirst": return KBuiltins.data(Data(data.dropFirst(n)))
                    default: return KBuiltins.data(Data(data.dropLast(n)))
                    }
                }
            }
            t.method("subdata", "in:any") { c in
                let data = d(c)
                guard case .range(let lo, let hi, let closed)? = c["in"] else { throw c.fail("needs a range") }
                let l = lo.asInt ?? 0, h = (hi.asInt ?? data.count) + (closed ? 1 : 0)
                guard l >= 0, h <= data.count, l <= h else { throw c.interp.fail("Range out of bounds", c.line) }
                return KBuiltins.data(data.subdata(in: l..<h))
            }
            t.fallback("Sequence") { v, interp in .array(try interp.sequence(v)) }
        }

        r.type("JSONSerialization", .foundation, support: .full,
               notes: "`jsonObject(with:options:)` gives Swift arrays and dictionaries (cast with `as? [String: Any]`); `data(withJSONObject:options:)`, `isValidJSONObject`.") { t in
            t.staticMethod("jsonObject", "with:any options:any?") { c in
                guard let data = KBuiltins.dataValue(c["with"]) else { throw c.fail("needs Data") }
                do {
                    return KNativeValues.kv(from: try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
                } catch {
                    throw FoundationBridges.thrown(error, c)
                }
            }
            t.staticMethod("data", "withJSONObject:any options:any?") { c in
                var o: JSONSerialization.WritingOptions = [.fragmentsAllowed]
                let names = ((c["options"]).flatMap { try? c.interp.sequence($0) } ?? []).compactMap(KFormatStyles.symbol) + (c.symbol("options").map { [$0] } ?? [])
                for n in names {
                    switch n {
                    case "prettyPrinted": o.insert(.prettyPrinted)
                    case "sortedKeys": o.insert(.sortedKeys)
                    case "withoutEscapingSlashes": o.insert(.withoutEscapingSlashes)
                    default: break
                    }
                }
                guard let obj = KNativeValues.native(from: c["withJSONObject"] ?? .nilValue), JSONSerialization.isValidJSONObject(obj) || o.contains(.fragmentsAllowed) else {
                    throw c.fail("needs arrays, dictionaries, strings, numbers and Bools")
                }
                do { return KBuiltins.data(try JSONSerialization.data(withJSONObject: obj, options: o)) } catch { throw FoundationBridges.thrown(error, c) }
            }
            t.staticMethod("isValidJSONObject", "_:any") { c in
                .bool(KNativeValues.native(from: c.first ?? .nilValue).map(JSONSerialization.isValidJSONObject) ?? false)
            }
        }

        r.type("PropertyListEncoder", .foundation, support: .full, notes: "Your `Codable` types to a property list (`outputFormat` `.xml` or `.binary`).") { t in
            t.initializer("") { _ in .native(.object("PropertyListEncoder", KRef(KPlistEncoderBox()))) }
            t.property("outputFormat", { _ in .nilValue }, set: { c in
                let box = c.object(KPlistEncoderBox.self)
                switch c.symbol(0) {
                case "xml": box?.format = .xml
                case "openStep": box?.format = .openStep
                default: box?.format = .binary
                }
            })
            t.method("encode", "_:any") { c in
                let box = c.object(KPlistEncoderBox.self) ?? KPlistEncoderBox()
                let any = try KBuiltins.encode(c.first ?? .nilValue, box.json, c.interp, c.line)
                do {
                    return KBuiltins.data(try PropertyListSerialization.data(fromPropertyList: stripNulls(any), format: box.format, options: 0))
                } catch { throw FoundationBridges.thrown(error, c) }
            }
        }
        r.type("PropertyListDecoder", .foundation, support: .full) { t in
            t.initializer("") { _ in .native(.object("PropertyListDecoder", KRef(KDecoderBox()))) }
            t.method("decode", "_:any from:any") { c in
                guard let data = KBuiltins.dataValue(c["from"]) else { throw c.fail("needs Data") }
                let any: Any
                do { any = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) } catch { throw FoundationBridges.thrown(error, c) }
                return try KBuiltins.decode(any, as: KBuiltins.decodeTarget(c.first ?? .nilValue, c.interp), c.object(KDecoderBox.self) ?? KDecoderBox(), c.interp, c.line)
            }
        }
        r.type("PropertyListSerialization", .foundation, support: .full) { t in
            t.staticMethod("data", "fromPropertyList:any format:any options:any") { c in
                guard let obj = KNativeValues.native(from: c["fromPropertyList"] ?? .nilValue) else { throw c.fail("needs a property list") }
                let format: PropertyListSerialization.PropertyListFormat = c.symbol("format") == "xml" ? .xml : .binary
                do { return KBuiltins.data(try PropertyListSerialization.data(fromPropertyList: obj, format: format, options: 0)) } catch { throw FoundationBridges.thrown(error, c) }
            }
            t.staticMethod("propertyList", "from:any options:any? format:any?") { c in
                guard let data = KBuiltins.dataValue(c["from"]) else { throw c.fail("needs Data") }
                do { return fromPlist(try PropertyListSerialization.propertyList(from: data, options: [], format: nil)) } catch { throw FoundationBridges.thrown(error, c) }
            }
        }

        // CryptoKit's hashes.
        r.type("Insecure", .foundation, support: .full) { t in t.namespace() }
        for (name, label) in [("SHA256", "SHA256"), ("SHA384", "SHA384"), ("SHA512", "SHA512"), ("Insecure.MD5", "MD5"), ("Insecure.SHA1", "SHA1")] {
            r.type(name, .foundation, support: .full, notes: name == "SHA256" ? "CryptoKit's `SHA256`, `SHA384`, `SHA512`, `Insecure.MD5` and `Insecure.SHA1`: `hash(data:)`, a digest's bytes and `description`." : nil) { t in
                t.staticMethod("hash", "data:any") { c in
                    guard let data = KBuiltins.dataValue(c["data"]) ?? (c["data"]?.asString.map { Data($0.utf8) }) else { throw c.fail("needs Data") }
                    let bytes: [UInt8]
                    switch label {
                    case "SHA256": bytes = Array(SHA256.hash(data: data))
                    case "SHA384": bytes = Array(SHA384.hash(data: data))
                    case "SHA512": bytes = Array(SHA512.hash(data: data))
                    case "MD5": bytes = Array(Insecure.MD5.hash(data: data))
                    default: bytes = Array(Insecure.SHA1.hash(data: data))
                    }
                    return KDigest(name: label, bytes: bytes).kv
                }
            }
        }
        r.type("Digest", .foundation, support: .full) { t in
            t.internal()
            t.property("description") { c in
                if case .native(.boxed(let b)) = c.receiver, let d = b.value.base as? KDigest { return .string(d.describe(c.interp)) }
                return .string("")
            }
            t.fallback("Sequence") { v, interp in .array(try interp.sequence(v)) }
        }

        // NSAttributedString.
        for name in ["NSAttributedString", "NSMutableAttributedString"] {
            r.type(name, .foundation, support: .partial, notes: name == "NSAttributedString" ? "`string`, `length`, attributes by name (`.font`, `.foregroundColor`, `.kern`…); `NSMutableAttributedString`'s `append`, `addAttribute`; `AttributedString(nsString)` shows it in `Text`." : nil) { t in
                t.initializer("string:string attributes:any?") { c in
                    let s = NSMutableAttributedString(string: c.string("string") ?? "", attributes: KStrings.attributes(c["attributes"]))
                    return .native(.object(name, KRef(name == "NSAttributedString" ? NSAttributedString(attributedString: s) : s)))
                }
                t.initializer("attributedString:any") { c in
                    let base = c.object(NSAttributedString.self) ?? NSAttributedString()
                    if case .native(.object(_, let ref))? = c["attributedString"], let other = ref.value as? NSAttributedString {
                        return .native(.object(name, KRef(name == "NSAttributedString" ? other : NSMutableAttributedString(attributedString: other))))
                    }
                    return .native(.object(name, KRef(base)))
                }
                @MainActor func s(_ c: KCall) -> NSAttributedString { c.object(NSAttributedString.self) ?? NSAttributedString() }
                t.property("string") { c in .string(s(c).string) }
                t.property("length") { c in .int(s(c).length) }
                t.property("description") { c in .string(s(c).description) }
                if name == "NSMutableAttributedString" {
                    @MainActor func m(_ c: KCall) -> NSMutableAttributedString? { c.object(NSMutableAttributedString.self) }
                    t.method("append", "_:any") { c in
                        if case .native(.object(_, let ref))? = c.first, let other = ref.value as? NSAttributedString { m(c)?.append(other) }
                        return .void
                    }
                    t.method("addAttribute", "_:any value:any range:any") { c in
                        let attrs = KStrings.attributes(.dict([c.first ?? .nilValue: c["value"] ?? .nilValue]))
                        let r = KNSRange.from(c["range"]) ?? NSRange(location: 0, length: m(c)?.length ?? 0)
                        for (k, v) in attrs { m(c)?.addAttribute(k, value: v, range: r) }
                        return .void
                    }
                    t.method("addAttributes", "_:any range:any") { c in
                        let r = KNSRange.from(c["range"]) ?? NSRange(location: 0, length: m(c)?.length ?? 0)
                        m(c)?.addAttributes(KStrings.attributes(c.first), range: r)
                        return .void
                    }
                    t.method("replaceCharacters", "in:any with:string") { c in
                        if let r = KNSRange.from(c["in"]) { m(c)?.replaceCharacters(in: r, with: c.string("with") ?? "") }
                        return .void
                    }
                    t.property("mutableString") { c in .string(s(c).string) }
                }
            }
        }

        // NSString's path members, on a String (`(name as NSString).pathExtension`).
        r.extend("String") { t in
            @MainActor func ns(_ c: KCall) -> NSString { (c.receiver.asString ?? "") as NSString }
            t.property("pathExtension") { c in .string(ns(c).pathExtension) }
            t.property("lastPathComponent") { c in .string(ns(c).lastPathComponent) }
            t.property("deletingPathExtension") { c in .string(ns(c).deletingPathExtension) }
            t.property("deletingLastPathComponent") { c in .string(ns(c).deletingLastPathComponent) }
            t.property("pathComponents") { c in .array(ns(c).pathComponents.map { .string($0) }) }
            t.property("expandingTildeInPath") { c in .string(ns(c).expandingTildeInPath) }
            t.property("abbreviatingWithTildeInPath") { c in .string(ns(c).abbreviatingWithTildeInPath) }
            t.method("appendingPathComponent", "_:string") { c in .string(ns(c).appendingPathComponent(c.string(0) ?? "")) }
            t.method("appendingPathExtension", "_:string") { c in ns(c).appendingPathExtension(c.string(0) ?? "").map { .string($0) } ?? .nilValue }

            // Comparing and searching, as Foundation does.
            @MainActor func s(_ c: KCall) -> String { c.receiver.asString ?? "" }
            t.method("compare", "_:string options:any? range:any? locale:any?") { c in
                let str = s(c), other = c.string(0) ?? ""
                let opts = KStrings.options(c["options"], c.interp)
                let range = KStrings.indexRange(c["range"], in: str)
                if let l = locale(c["locale"]) { return KComparison.kv(str.compare(other, options: opts, range: range, locale: l)) }
                return KComparison.kv(str.compare(other, options: opts, range: range))
            }
            t.method("localizedCompare", "_:string") { c in KComparison.kv(s(c).localizedCompare(c.string(0) ?? "")) }
            t.method("localizedCaseInsensitiveCompare", "_:string") { c in KComparison.kv(s(c).localizedCaseInsensitiveCompare(c.string(0) ?? "")) }
            t.method("caseInsensitiveCompare", "_:string") { c in KComparison.kv(s(c).caseInsensitiveCompare(c.string(0) ?? "")) }
            t.method("localizedStandardCompare", "_:string", first: true) { c in KComparison.kv(s(c).localizedStandardCompare(c.string(0) ?? "")) }
            t.method("range", "of:string options:any? range:any? locale:any?", first: true) { c in
                let str = s(c)
                let opts = KStrings.options(c["options"], c.interp)
                let found = str.range(of: c.string("of") ?? "", options: opts, range: KStrings.indexRange(c["range"], in: str), locale: locale(c["locale"]))
                return found.map { KStrings.offsets($0, in: str) } ?? .nilValue
            }
            t.method("replacingOccurrences", "of:string with:string options:any? range:any?", first: true) { c in
                let str = s(c)
                return .string(str.replacingOccurrences(of: c.string("of") ?? "", with: c.string("with") ?? "",
                                                        options: KStrings.options(c["options"], c.interp), range: KStrings.indexRange(c["range"], in: str)))
            }
            t.method("folding", "options:any locale:any?") { c in .string(s(c).folding(options: KStrings.options(c["options"], c.interp), locale: locale(c["locale"]))) }
            t.method("applyingTransform", "_:any reverse:bool") { c in
                let names: [String: StringTransform] = ["toLatin": .toLatin, "latinToHiragana": .latinToHiragana, "latinToKatakana": .latinToKatakana,
                    "hiraganaToKatakana": .hiraganaToKatakana, "fullwidthToHalfwidth": .fullwidthToHalfwidth, "stripDiacritics": .stripDiacritics,
                    "stripCombiningMarks": .stripCombiningMarks, "toUnicodeName": .toUnicodeName, "latinToGreek": .latinToGreek,
                    "latinToCyrillic": .latinToCyrillic, "latinToArabic": .latinToArabic, "latinToHebrew": .latinToHebrew, "mandarinToLatin": .mandarinToLatin]
                guard let tr = c.symbol(0).flatMap({ names[$0] }) else { throw c.fail("needs a StringTransform, as .toLatin") }
                return s(c).applyingTransform(tr, reverse: c.bool("reverse", default: false)).map { .string($0) } ?? .nilValue
            }
            t.method("lengthOfBytes", "using:any") { c in .int(s(c).lengthOfBytes(using: encoding(c["using"]))) }
            t.method("maximumLengthOfBytes", "using:any") { c in .int(s(c).maximumLengthOfBytes(using: encoding(c["using"]))) }
            t.method("data", "using:any allowLossyConversion:bool?", first: true) { c in
                s(c).data(using: encoding(c["using"]), allowLossyConversion: c.bool("allowLossyConversion", default: false)).map(KBuiltins.data) ?? .nilValue
            }
            t.method("enumerateLines", "invoking:closure") { c in
                guard case .function(let f)? = c["invoking"] else { throw c.fail("needs a closure") }
                for line in s(c).components(separatedBy: .newlines) {
                    let stop = KBox(.bool(false))
                    _ = try c.interp.call(f, [.string(line), .binding(KBinding.inOut(get: { stop.value }, set: { stop.value = $0 }))], [nil, nil])
                    if c.interp.truthy(stop.value) { break }
                }
                return .void
            }
            t.method("appendingFormat", "_:string _:any...") { c in .string(s(c) + KFormatting.format(c.string(0) ?? "", Array(c.args.dropFirst()), c.interp)) }
            t.method("appending", "_:any") { c in .string(s(c) + c.interp.describe(c.first ?? .string(""))) }
            t.method("uppercased", "with:any", first: true) { c in .string(s(c).uppercased(with: locale(c["with"]))) }
            t.method("lowercased", "with:any", first: true) { c in .string(s(c).lowercased(with: locale(c["with"]))) }
            t.method("capitalized", "with:any", first: true) { c in .string(s(c).capitalized(with: locale(c["with"]))) }
            t.method("trimmingCharacters", "in:any", first: true) { c in
                guard let set = KCharacterSetBridge.set(c["in"]) else { throw c.fail("needs a CharacterSet") }
                return .string(s(c).trimmingCharacters(in: set))
            }
            t.method("components", "separatedBy:any", first: true) { c in
                if let sep = c["separatedBy"]?.asString { return .array(s(c).components(separatedBy: sep).map { .string($0) }) }
                guard let set = KCharacterSetBridge.set(c["separatedBy"]) else { throw c.fail("needs a String or a CharacterSet") }
                return .array(s(c).components(separatedBy: set).map { .string($0) })
            }
        }
    }

    static func encoding(_ v: KV?) -> String.Encoding {
        switch KFormatStyles.symbol(v) {
        case "ascii": return .ascii
        case "utf16": return .utf16
        case "utf16BigEndian": return .utf16BigEndian
        case "utf16LittleEndian": return .utf16LittleEndian
        case "utf32": return .utf32
        case "isoLatin1": return .isoLatin1
        case "unicode": return .unicode
        case "nonLossyASCII": return .nonLossyASCII
        case "macOSRoman": return .macOSRoman
        case "windowsCP1252": return .windowsCP1252
        default: return .utf8
        }
    }

    /// A property list can't hold `NSNull` (an encoded nil): it's left out.
    static func stripNulls(_ v: Any) -> Any {
        if let d = v as? [String: Any] { return d.filter { !($0.value is NSNull) }.mapValues(stripNulls) }
        if let a = v as? [Any] { return a.filter { !($0 is NSNull) }.map(stripNulls) }
        return v
    }

    /// The second pass: types later families declare.
    static func extendLater(_ r: KRegistry) {
        // Decimal (Text's type): negation, `Decimal(sign:exponent:significand:)`, `NSDecimalRound`.
        r.extend("Decimal") { t in
            t.operator("prefix-") { a, _, _ in KDecimal.from(a).map { KDecimal(-$0).kv } }
            t.initializer("sign:any exponent:number significand:any", first: true) { c in
                let sign: FloatingPointSign = c.symbol("sign") == "minus" ? .minus : .plus
                return KDecimal(Decimal(sign: sign, exponent: c.int("exponent") ?? 0, significand: KDecimal.from(c["significand"]) ?? 0)).kv
            }
            t.property("exponent") { c in .int(KDecimal.from(c.receiver)?.exponent ?? 0) }
            t.property("sign") { c in .native(.implicit(KDecimal.from(c.receiver)?.sign == .minus ? "minus" : "plus", [])) }
            t.property("isNaN") { c in .bool(KDecimal.from(c.receiver)?.isNaN ?? false) }
            t.property("description") { c in .string(KDecimal.from(c.receiver)?.description ?? "0") }
        }
        r.function("NSDecimalRound", .foundation, "_:binding _:binding _:number _:any", owner: "Foundation") { c in
            guard case .binding(let out)? = c.at(0), case .binding(let input)? = c.at(1) else { throw c.fail("needs &result, &value") }
            var x = KDecimal.from(input.get()) ?? 0, r = Decimal()
            let mode: NSDecimalNumber.RoundingMode = ["down": .down, "up": .up, "bankers": .bankers][c.symbol(3) ?? ""] ?? .plain
            NSDecimalRound(&r, &x, c.at(2)?.asInt ?? 0, mode)
            out.set(KDecimal(r).kv)
            return .void
        }
        // `Date.FormatStyle(date:time:).format(date)` (Text's type).
        r.extend("Date.FormatStyle") { t in
            t.method("format", "_:any") { c in
                guard case .native(.object(_, let ref)) = c.receiver, let box = ref.value as? KDateStyleBox, let d = KDates.date(c.first) else { throw c.fail("needs a Date") }
                return .string(d.formatted(box.style))
            }
        }
        // `AttributedString(nsAttributedString)`: Text's type, from Foundation's.
        r.extend("AttributedString") { t in
            t.initializer("_:any", first: true) { c in
                guard case .native(.object(_, let ref))? = c.first, let ns = ref.value as? NSAttributedString else {
                    return KAttributed.kv(AttributedString(c.first.map { c.interp.describe($0) } ?? ""))
                }
                return KAttributed.kv((try? AttributedString(ns, including: \.foundation)) ?? AttributedString(ns.string))
            }
        }
    }
}

/// A `CharacterSet` argument, whether a value or a name (`.whitespaces`).
@MainActor
enum KCharacterSetBridge {
    static func set(_ v: KV?) -> CharacterSet? {
        if let s = KCharacterSet.from(v) { return s }
        if case .native(.implicit(let n, _))? = v { return KCharacterSet.named[n] }
        return nil
    }
}
