//
//  Coding.swift
//  Bridges: Decoder and Encoder, for an app's own `init(from:)` and `encode(to:)`
//
//  A type that writes `init(from decoder: Decoder)` or `encode(to encoder:
//  Encoder)` is decoded and encoded by them (PLAN.md §1.6), with keyed,
//  unkeyed and single-value containers, nested containers, and `CodingKeys`
//  (their raw values are the JSON keys). Everything else keeps the
//  synthesized mapping in Bridges/Networking/NetworkSupport.swift.
//

import SwiftUI

/// A spot in the JSON being written: filled by a value, an object or an array.
final class KJSONSlot {
    var value: Any?
}

final class KJSONObject {
    var entries: [(String, KJSONSlot)] = []
    func slot(_ key: String) -> KJSONSlot {
        if let s = entries.first(where: { $0.0 == key })?.1 { return s }
        let s = KJSONSlot()
        entries.append((key, s))
        return s
    }
}

final class KJSONArray {
    var items: [KJSONSlot] = []
}

/// A `Decoder`: the JSON being read, where it is, and the decoder's settings.
final class KDecoderNode {
    let json: Any
    let box: KDecoderBox
    let path: [String]
    init(_ json: Any, _ box: KDecoderBox, _ path: [String]) {
        self.json = json
        self.box = box
        self.path = path
    }
}

final class KKeyedDecoding {
    let object: [String: Any]
    let keys: KType?
    let box: KDecoderBox
    let path: [String]
    init(_ object: [String: Any], _ keys: KType?, _ box: KDecoderBox, _ path: [String]) {
        self.object = object
        self.keys = keys
        self.box = box
        self.path = path
    }
}

final class KUnkeyedDecoding {
    let items: [Any]
    var index = 0
    let box: KDecoderBox
    let path: [String]
    init(_ items: [Any], _ box: KDecoderBox, _ path: [String]) {
        self.items = items
        self.box = box
        self.path = path
    }
}

final class KSingleDecoding {
    let json: Any
    let box: KDecoderBox
    let path: [String]
    init(_ json: Any, _ box: KDecoderBox, _ path: [String]) {
        self.json = json
        self.box = box
        self.path = path
    }
}

/// An `Encoder`: the slot it writes into.
final class KEncoderNode {
    let slot: KJSONSlot
    let box: KEncoderBox
    init(_ slot: KJSONSlot, _ box: KEncoderBox) {
        self.slot = slot
        self.box = box
    }
}

final class KKeyedEncoding {
    let object: KJSONObject
    let keys: KType?
    let box: KEncoderBox
    init(_ object: KJSONObject, _ keys: KType?, _ box: KEncoderBox) {
        self.object = object
        self.keys = keys
        self.box = box
    }
}

final class KUnkeyedEncoding {
    let array: KJSONArray
    let box: KEncoderBox
    init(_ array: KJSONArray, _ box: KEncoderBox) {
        self.array = array
        self.box = box
    }
}

final class KSingleEncoding {
    let slot: KJSONSlot
    let box: KEncoderBox
    init(_ slot: KJSONSlot, _ box: KEncoderBox) {
        self.slot = slot
        self.box = box
    }
}

extension KBuiltins {

    // MARK: The hooks NetworkSupport calls

    /// `init(from:)` if the type has one.
    static func customDecodeInit(_ t: KType) -> KEFuncDecl? {
        t.inits.first { $0.params.count == 1 && $0.params[0].label == "from" }
    }

    /// `encode(to:)` if the type has one.
    static func customEncode(_ t: KType) -> KEFuncDecl? {
        t.methods["encode"]?.first { $0.params.count == 1 && $0.params[0].label == "to" }
    }

    /// The app's type, built by its own `init(from:)`.
    @MainActor static func decodeCustom(_ json: Any, _ t: KType, _ box: KDecoderBox, _ path: [String], _ interp: KInterpreter, _ line: Int) throws -> KV {
        let decoder = KV.native(.object("Decoder", KRef(KDecoderNode(json, box, path))))
        return try interp.instantiate(t, args: [decoder], labels: ["from"], line: line)
    }

    /// The app's value, written by its own `encode(to:)`.
    @MainActor static func encodeCustom(_ v: KV, _ t: KType, _ m: KEFuncDecl, _ box: KEncoderBox, _ interp: KInterpreter) throws -> Any {
        let slot = KJSONSlot()
        let encoder = KV.native(.object("Encoder", KRef(KEncoderNode(slot, box))))
        _ = try interp.invoke(m, args: [encoder], labels: ["to"], selfContext: KSelfContext(type: t, location: .box(KBox(v))), parent: interp.globalEnv)
        return materialize(slot.value)
    }

    /// The JSON objects a tree of slots stands for.
    static func materialize(_ v: Any?) -> Any {
        switch v {
        case nil: return [String: Any]()   // an encode(to:) that wrote nothing is an empty object
        case let o as KJSONObject:
            var out: [String: Any] = [:]
            for (k, s) in o.entries { out[k] = materialize(s.value ?? NSNull()) }
            return out
        case let a as KJSONArray: return a.items.map { materialize($0.value ?? NSNull()) }
        case let s as KJSONSlot: return materialize(s.value)
        default: return v!
        }
    }

    /// A conformance the type must declare to be read or written as JSON.
    @MainActor static func requireCoding(_ t: KType, _ proto: String, _ interp: KInterpreter, _ line: Int) throws {
        guard !t.conformances.contains(proto), !t.conformances.contains("Codable") else { return }
        let verb = proto == "Encodable" ? "written" : "read"
        let error = interp.fail("'\(t.name)' isn't \(proto), so it can't be \(verb) as JSON: add `: Codable` to its declaration", line)
        interp.report(error)
        throw KEThrown(value: errorValue(error.message))
    }

    // MARK: Keys

    /// The JSON key a `CodingKeys` value (or `.name`) stands for.
    @MainActor static func codingKey(_ v: KV?, _ keys: KType?, _ interp: KInterpreter) -> String {
        switch v {
        case .enumV(let e)?:
            // `.name` may have resolved to another enum with that case: the container's keys decide.
            if let k = keys, e.type !== k, k.enumCase(e.caseName) != nil { return codingKey(.native(.implicit(e.caseName, [])), k, interp) }
            if let raw = try? interp.rawValue(e), case .string(let s) = raw { return s }
            return e.caseName
        case .native(.implicit(let n, _))?:
            if let k = keys, let c = k.enumCase(n),
               let raw = try? interp.rawValue(KEnumValue(type: k, caseName: c.name, payload: [])), case .string(let s) = raw { return s }
            return n
        case .string(let s)?: return s
        case let other?: return interp.describe(other)
        case nil: return ""
        }
    }

    static func camelCase(_ key: String) -> String {
        let parts = key.split(separator: "_", omittingEmptySubsequences: true)
        guard let first = parts.first else { return key }
        return String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// The keyed-by type a container was asked for: `CodingKeys.self`.
    static func keysType(_ v: KV?) -> KType? {
        if case .type(.user(let t))? = v { return t }
        return nil
    }

    // MARK: Errors, as JSONDecoder words them

    static func keyNotFound(_ key: String, _ path: [String]) -> KEThrown {
        KEThrown(value: errorValue("The data couldn't be read because it is missing. (No value associated with key \"\(key)\"\(path.isEmpty ? "" : " at " + path.joined(separator: ".")).)"))
    }

    static func valueNotFound(_ what: String, _ path: [String]) -> KEThrown {
        KEThrown(value: errorValue("The data couldn't be read because it is missing. (Expected \(what) but found null\(path.isEmpty ? "" : " at " + path.joined(separator: ".")).)"))
    }
}

extension FoundationBridges {
    static func coding(_ r: KRegistry) {
        let decodingNote = "In your own `init(from:)`: keyed, unkeyed and single-value containers."
        r.type("Decoder", .foundation, notes: decodingNote) { t in
            t.method("container", "keyedBy:any") { c in
                guard let d = c.object(KDecoderNode.self) else { return .nilValue }
                guard let o = d.json as? [String: Any] else { throw KBuiltins.mismatch("an object", c.line, c.interp) }
                return .native(.object("KeyedDecodingContainer", KRef(KKeyedDecoding(o, KBuiltins.keysType(c.first), d.box, d.path))))
            }
            t.method("unkeyedContainer", "") { c in
                guard let d = c.object(KDecoderNode.self) else { return .nilValue }
                guard let a = d.json as? [Any] else { throw KBuiltins.mismatch("an array", c.line, c.interp) }
                return .native(.object("UnkeyedDecodingContainer", KRef(KUnkeyedDecoding(a, d.box, d.path))))
            }
            t.method("singleValueContainer", "") { c in
                guard let d = c.object(KDecoderNode.self) else { return .nilValue }
                return .native(.object("SingleValueDecodingContainer", KRef(KSingleDecoding(d.json, d.box, d.path))))
            }
            t.property("codingPath") { c in .array((c.object(KDecoderNode.self)?.path ?? []).map { .string($0) }) }
        }

        r.type("KeyedDecodingContainer", .foundation, notes: decodingNote) { t in
            @MainActor func value(_ c: KCall, _ k: KKeyedDecoding) -> (String, Any?) {
                let key = KBuiltins.codingKey(c.arg("forKey"), k.keys, c.interp)
                if let v = k.object[key] { return (key, v) }
                if k.box.snakeCase, let (_, v) = k.object.first(where: { KBuiltins.camelCase($0.key) == key }) { return (key, v) }
                return (key, nil)
            }
            t.method("decode", "_:any forKey:any") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .nilValue }
                let (key, json) = value(c, k)
                guard let json else { throw KBuiltins.keyNotFound(key, k.path) }
                let type = KBuiltins.decodeTarget(c.first ?? .nilValue, c.interp)
                if json is NSNull, type?.isOptional != true { throw KBuiltins.valueNotFound(type?.description ?? "a value", k.path + [key]) }
                return try KBuiltins.decode(json, as: type, k.box, c.interp, c.line)
            }
            t.method("decodeIfPresent", "_:any forKey:any") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .nilValue }
                let (key, json) = value(c, k)
                guard let json, !(json is NSNull) else { return .nilValue }
                return try KBuiltins.decode(json, as: KBuiltins.decodeTarget(c.first ?? .nilValue, c.interp), k.box, c.interp, c.line)
            }
            t.method("contains", "_:any") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .bool(false) }
                return .bool(k.object[KBuiltins.codingKey(c.first, k.keys, c.interp)] != nil)
            }
            t.method("decodeNil", "forKey:any") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .bool(true) }
                let v = k.object[KBuiltins.codingKey(c.arg("forKey"), k.keys, c.interp)]
                return .bool(v == nil || v is NSNull)
            }
            t.property("allKeys") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .array([]) }
                return .array(k.object.keys.sorted().compactMap { key in
                    guard let ck = k.keys else { return .string(key) }
                    for kc in ck.cases where KBuiltins.codingKey(.enumV(KEnumValue(type: ck, caseName: kc.name, payload: [])), ck, c.interp) == key {
                        return .enumV(KEnumValue(type: ck, caseName: kc.name, payload: []))
                    }
                    return nil
                })
            }
            t.method("nestedContainer", "keyedBy:any forKey:any") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .nilValue }
                let (key, json) = value(c, k)
                guard let o = json as? [String: Any] else { throw json == nil ? KBuiltins.keyNotFound(key, k.path) : KBuiltins.mismatch("an object", c.line, c.interp) }
                return .native(.object("KeyedDecodingContainer", KRef(KKeyedDecoding(o, KBuiltins.keysType(c.first), k.box, k.path + [key]))))
            }
            t.method("nestedUnkeyedContainer", "forKey:any") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .nilValue }
                let (key, json) = value(c, k)
                guard let a = json as? [Any] else { throw json == nil ? KBuiltins.keyNotFound(key, k.path) : KBuiltins.mismatch("an array", c.line, c.interp) }
                return .native(.object("UnkeyedDecodingContainer", KRef(KUnkeyedDecoding(a, k.box, k.path + [key]))))
            }
            t.method("superDecoder", "") { c in
                guard let k = c.object(KKeyedDecoding.self) else { return .nilValue }
                return .native(.object("Decoder", KRef(KDecoderNode(k.object, k.box, k.path))))
            }
            t.property("codingPath") { c in .array((c.object(KKeyedDecoding.self)?.path ?? []).map { .string($0) }) }
        }

        r.type("UnkeyedDecodingContainer", .foundation, notes: decodingNote) { t in
            t.method("decode", "_:any") { c in
                guard let u = c.object(KUnkeyedDecoding.self) else { return .nilValue }
                guard u.index < u.items.count else {
                    throw KEThrown(value: KBuiltins.errorValue("The data couldn't be read because it is missing. (Unkeyed container is at end.)"))
                }
                let json = u.items[u.index]
                let type = KBuiltins.decodeTarget(c.first ?? .nilValue, c.interp)
                if json is NSNull, type?.isOptional != true { throw KBuiltins.valueNotFound(type?.description ?? "a value", u.path + ["\(u.index)"]) }
                let v = try KBuiltins.decode(json, as: type, u.box, c.interp, c.line)
                u.index += 1
                return v
            }
            t.method("decodeIfPresent", "_:any") { c in
                guard let u = c.object(KUnkeyedDecoding.self), u.index < u.items.count else { return .nilValue }
                let json = u.items[u.index]
                u.index += 1
                if json is NSNull { return .nilValue }
                return try KBuiltins.decode(json, as: KBuiltins.decodeTarget(c.first ?? .nilValue, c.interp), u.box, c.interp, c.line)
            }
            t.method("decodeNil", "") { c in
                guard let u = c.object(KUnkeyedDecoding.self), u.index < u.items.count else { return .bool(false) }
                if u.items[u.index] is NSNull { u.index += 1; return .bool(true) }
                return .bool(false)
            }
            t.property("isAtEnd") { c in .bool(c.object(KUnkeyedDecoding.self).map { $0.index >= $0.items.count } ?? true) }
            t.property("count") { c in c.object(KUnkeyedDecoding.self).map { .int($0.items.count) } ?? .nilValue }
            t.property("currentIndex") { c in .int(c.object(KUnkeyedDecoding.self)?.index ?? 0) }
            t.method("nestedContainer", "keyedBy:any") { c in
                guard let u = c.object(KUnkeyedDecoding.self), u.index < u.items.count else { return .nilValue }
                guard let o = u.items[u.index] as? [String: Any] else { throw KBuiltins.mismatch("an object", c.line, c.interp) }
                u.index += 1
                return .native(.object("KeyedDecodingContainer", KRef(KKeyedDecoding(o, KBuiltins.keysType(c.first), u.box, u.path + ["\(u.index - 1)"]))))
            }
            t.method("nestedUnkeyedContainer", "") { c in
                guard let u = c.object(KUnkeyedDecoding.self), u.index < u.items.count else { return .nilValue }
                guard let a = u.items[u.index] as? [Any] else { throw KBuiltins.mismatch("an array", c.line, c.interp) }
                u.index += 1
                return .native(.object("UnkeyedDecodingContainer", KRef(KUnkeyedDecoding(a, u.box, u.path + ["\(u.index - 1)"]))))
            }
        }

        r.type("SingleValueDecodingContainer", .foundation, notes: decodingNote) { t in
            t.method("decode", "_:any") { c in
                guard let s = c.object(KSingleDecoding.self) else { return .nilValue }
                let type = KBuiltins.decodeTarget(c.first ?? .nilValue, c.interp)
                if s.json is NSNull, type?.isOptional != true { throw KBuiltins.valueNotFound(type?.description ?? "a value", s.path) }
                return try KBuiltins.decode(s.json, as: type, s.box, c.interp, c.line)
            }
            t.method("decodeNil", "") { c in .bool(c.object(KSingleDecoding.self)?.json is NSNull) }
        }

        let encodingNote = "In your own `encode(to:)`: keyed, unkeyed and single-value containers."
        r.type("Encoder", .foundation, notes: encodingNote) { t in
            t.method("container", "keyedBy:any") { c in
                guard let e = c.object(KEncoderNode.self) else { return .nilValue }
                let o = (e.slot.value as? KJSONObject) ?? KJSONObject()
                e.slot.value = o
                return .native(.object("KeyedEncodingContainer", KRef(KKeyedEncoding(o, KBuiltins.keysType(c.first), e.box))))
            }
            t.method("unkeyedContainer", "") { c in
                guard let e = c.object(KEncoderNode.self) else { return .nilValue }
                let a = (e.slot.value as? KJSONArray) ?? KJSONArray()
                e.slot.value = a
                return .native(.object("UnkeyedEncodingContainer", KRef(KUnkeyedEncoding(a, e.box))))
            }
            t.method("singleValueContainer", "") { c in
                guard let e = c.object(KEncoderNode.self) else { return .nilValue }
                return .native(.object("SingleValueEncodingContainer", KRef(KSingleEncoding(e.slot, e.box))))
            }
            t.property("codingPath") { _ in .array([]) }
        }

        r.type("KeyedEncodingContainer", .foundation, notes: encodingNote) { t in
            @MainActor func key(_ c: KCall, _ k: KKeyedEncoding) -> String {
                let key = KBuiltins.codingKey(c.arg("forKey"), k.keys, c.interp)
                return k.box.snakeCase ? KBuiltins.snakeCase(key) : key
            }
            t.method("encode", "_:any forKey:any") { c in
                guard let k = c.object(KKeyedEncoding.self) else { return .void }
                k.object.slot(key(c, k)).value = try KBuiltins.encode(c.first ?? .nilValue, k.box, c.interp, c.line)
                return .void
            }
            t.method("encodeIfPresent", "_:any forKey:any") { c in
                guard let k = c.object(KKeyedEncoding.self), let v = c.first, !v.isNil else { return .void }
                k.object.slot(key(c, k)).value = try KBuiltins.encode(v, k.box, c.interp, c.line)
                return .void
            }
            t.method("encodeNil", "forKey:any") { c in
                guard let k = c.object(KKeyedEncoding.self) else { return .void }
                k.object.slot(key(c, k)).value = NSNull()
                return .void
            }
            t.method("nestedContainer", "keyedBy:any forKey:any") { c in
                guard let k = c.object(KKeyedEncoding.self) else { return .nilValue }
                let slot = k.object.slot(key(c, k))
                let o = (slot.value as? KJSONObject) ?? KJSONObject()
                slot.value = o
                return .native(.object("KeyedEncodingContainer", KRef(KKeyedEncoding(o, KBuiltins.keysType(c.first), k.box))))
            }
            t.method("nestedUnkeyedContainer", "forKey:any") { c in
                guard let k = c.object(KKeyedEncoding.self) else { return .nilValue }
                let slot = k.object.slot(key(c, k))
                let a = (slot.value as? KJSONArray) ?? KJSONArray()
                slot.value = a
                return .native(.object("UnkeyedEncodingContainer", KRef(KUnkeyedEncoding(a, k.box))))
            }
            t.method("superEncoder", "") { c in
                guard let k = c.object(KKeyedEncoding.self) else { return .nilValue }
                let slot = KJSONSlot()
                slot.value = k.object
                return .native(.object("Encoder", KRef(KEncoderNode(slot, k.box))))
            }
        }

        r.type("UnkeyedEncodingContainer", .foundation, notes: encodingNote) { t in
            @MainActor func append(_ u: KUnkeyedEncoding, _ v: Any) {
                let s = KJSONSlot()
                s.value = v
                u.array.items.append(s)
            }
            t.method("encode", "_:any") { c in
                guard let u = c.object(KUnkeyedEncoding.self) else { return .void }
                append(u, try KBuiltins.encode(c.first ?? .nilValue, u.box, c.interp, c.line))
                return .void
            }
            t.method("encode", "contentsOf:any") { c in
                guard let u = c.object(KUnkeyedEncoding.self) else { return .void }
                for v in try c.interp.sequence(c.first ?? .array([])) { append(u, try KBuiltins.encode(v, u.box, c.interp, c.line)) }
                return .void
            }
            t.method("encodeNil", "") { c in
                if let u = c.object(KUnkeyedEncoding.self) { append(u, NSNull()) }
                return .void
            }
            t.method("nestedContainer", "keyedBy:any") { c in
                guard let u = c.object(KUnkeyedEncoding.self) else { return .nilValue }
                let o = KJSONObject()
                append(u, o)
                return .native(.object("KeyedEncodingContainer", KRef(KKeyedEncoding(o, KBuiltins.keysType(c.first), u.box))))
            }
            t.method("nestedUnkeyedContainer", "") { c in
                guard let u = c.object(KUnkeyedEncoding.self) else { return .nilValue }
                let a = KJSONArray()
                append(u, a)
                return .native(.object("UnkeyedEncodingContainer", KRef(KUnkeyedEncoding(a, u.box))))
            }
            t.property("count") { c in .int(c.object(KUnkeyedEncoding.self)?.array.items.count ?? 0) }
        }

        r.type("SingleValueEncodingContainer", .foundation, notes: encodingNote) { t in
            t.method("encode", "_:any") { c in
                guard let s = c.object(KSingleEncoding.self) else { return .void }
                s.slot.value = try KBuiltins.encode(c.first ?? .nilValue, s.box, c.interp, c.line)
                return .void
            }
            t.method("encodeNil", "") { c in
                c.object(KSingleEncoding.self)?.slot.value = NSNull()
                return .void
            }
        }

        // `throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "…")`.
        r.type("DecodingError", .foundation, notes: "Thrown from your own `init(from:)`.") { t in
            t.staticMethod("dataCorruptedError") { c in
                KBuiltins.errorValue("The data couldn't be read because it isn't in the correct format. (\(c.arg("debugDescription")?.asString ?? ""))")
            }
            for name in ["dataCorrupted", "keyNotFound", "typeMismatch", "valueNotFound"] {
                t.staticMethod(name) { c in
                    var detail = ""
                    for a in c.args {
                        if case .native(.implicit(_, let args)) = a, let d = args.last?.asString { detail = d }
                    }
                    return KBuiltins.errorValue("The data couldn't be read because \(name == "keyNotFound" || name == "valueNotFound" ? "it is missing" : "it isn't in the correct format").\(detail.isEmpty ? "" : " (\(detail))")")
                }
            }
        }
        r.type("EncodingError", .foundation, notes: "Thrown from your own `encode(to:)`.") { t in
            t.staticMethod("invalidValue") { c in
                var detail = ""
                for a in c.args {
                    if case .native(.implicit(_, let args)) = a, let d = args.last?.asString { detail = d }
                }
                return KBuiltins.errorValue("The data couldn't be written because it isn't in the correct format.\(detail.isEmpty ? "" : " (\(detail))")")
            }
        }
    }
}
