//
//  KENetwork.swift
//  Kiln engine 2
//
//  URLSession and JSONDecoder for interpreted code.
//  - `try await URLSession.shared.data(from:)` (or `for: URLRequest`) fetches
//    and returns `(Data, URLResponse)`. The task waits (KEAsync); the main
//    thread doesn't.
//  - `URLSession.shared.dataTask(with:) { data, response, error in … }.resume()`
//    fetches in the background and calls back on the main thread.
//  - `JSONDecoder().decode(T.self, from:)` builds your own Decodable types
//    from the JSON by their stored properties: CodingKeys, optionals, default
//    values, nested types, arrays, raw-value enums, `.convertFromSnakeCase`
//    and `.iso8601` dates.
//  - `JSONEncoder().encode(value)` is the same mapping the other way, so what
//    it writes is what `decode` reads: stored properties (through CodingKeys),
//    nil optionals left out, raw-value enums, `.convertToSnakeCase` and
//    `.iso8601` dates.
//

import Foundation

/// A JSONDecoder's settings.
final class KDecoderBox {
    var snakeCase = false
    var iso8601 = false
}

/// A JSONEncoder's settings.
final class KEncoderBox {
    var snakeCase = false
    var iso8601 = false
}

/// `URLSession.shared.dataTask(with:completionHandler:)`, until `resume()`.
final class KDataTask {
    let request: URLRequest
    let completion: KFunction?
    var task: URLSessionDataTask?
    init(request: URLRequest, completion: KFunction?) {
        self.request = request
        self.completion = completion
    }
}

extension KBuiltins {
    static func data(_ d: Data) -> KV { .native(.object("Data", KRef(d as NSData))) }

    static func dataValue(_ v: KV?) -> Data? {
        if case .native(.object("Data", let ref))? = v { return ref.value as? Data }
        if case .string(let s)? = v { return Data(s.utf8) }
        return nil
    }

    static func request(_ v: KV?) -> URLRequest? {
        switch v {
        case .native(.url(let u))?: return URLRequest(url: u)
        case .native(.object("URLRequest", let ref))?: return (ref.value as? NSURLRequest).map { $0 as URLRequest }
        case .string(let s)?: return URL(string: s).map { URLRequest(url: $0) }
        default: return nil
        }
    }

    static func errorValue(_ message: String) -> KV {
        .native(.object("Error", KRef(NSError(domain: "Kiln", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))))
    }

    /// `try await URLSession.shared.data(from: url)` (or `for:`): a
    /// suspension the calling task waits on, so the main thread never blocks.
    /// A request the host answers itself (`Kiln.hostRequestHandler`, Shelf's
    /// `db://`) comes back at once, without waiting, even where code can't wait.
    /// A headless run (`validate`) never touches the network: the request
    /// fails at once, as it would offline.
    @MainActor static func fetch(_ request: URLRequest, _ interp: KInterpreter, _ line: Int) throws -> KV {
        if let handler = Kiln.hostRequestHandler, let reply = handler(request) {
            let url = request.url ?? URL(string: "about:blank")!
            let response = HTTPURLResponse(url: url, statusCode: reply.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)
            return fetched(reply.body ?? Data(), response ?? URLResponse())
        }
        let req = KUnsafeSendable(request)
        return .suspension(KSuspension.async(headless: {
            throw KEThrown(value: errorValue(URLError(.notConnectedToInternet).localizedDescription))
        }) {
            let (data, response) = try await URLSession.shared.data(for: req.value)
            return fetched(data, response)
        })
    }

    static func fetched(_ data: Data, _ response: URLResponse) -> KV {
        .tuple([KBuiltins.data(data), .native(.object("HTTPURLResponse", KRef(response)))], [nil, nil])
    }

    // MARK: Encoding

    /// A value as JSONSerialization objects: the inverse of `decode`.
    @MainActor static func encode(_ v: KV, _ box: KEncoderBox, _ interp: KInterpreter, _ line: Int) throws -> Any {
        switch v {
        case .nilValue, .void: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d):
            guard d.isFinite else { throw KEThrown(value: errorValue("The data couldn't be written because \(d) isn't a JSON number.")) }
            return d
        case .string(let s): return s
        case .array(let items): return try items.map { try encode($0, box, interp, line) }
        case .set(let items): return try items.map { try encode($0, box, interp, line) }
        case .tuple(let items, _): return try items.map { try encode($0, box, interp, line) }
        case .dict(let d):
            var out: [String: Any] = [:]
            for (k, item) in d { out[k.asString ?? interp.describe(k)] = try encode(item, box, interp, line) }
            return out
        case .structV(let s): return try encodeFields(s.fields, s.type, box, interp, line)
        case .object(let o): return try encodeFields(o.fields, o.type, box, interp, line)
        case .enumV(let e):
            guard e.payload.isEmpty else {
                throw KEThrown(value: errorValue("The data couldn't be written because \(e.type.name).\(e.caseName) has associated values."))
            }
            return try encode(try interp.rawValue(e), box, interp, line)
        case .binding(let b): return try encode(b.get(), box, interp, line)
        case .native(.uuid(let u)): return u.uuidString
        case .native(.url(let u)): return u.absoluteString
        case .native(.date(let d)):
            return box.iso8601 ? ISO8601DateFormatter().string(from: d) as Any : d.timeIntervalSinceReferenceDate
        case .native(.object("Data", let ref)): return ((ref.value as? Data) ?? Data()).base64EncodedString()
        default:
            throw KEThrown(value: errorValue("The data couldn't be written because \(interp.describe(v)) isn't Encodable."))
        }
    }

    @MainActor static func encodeFields(_ fields: [String: KV], _ t: KType, _ box: KEncoderBox, _ interp: KInterpreter, _ line: Int) throws -> Any {
        var keys: [String: String] = [:]
        if let ck = t.nested["CodingKeys"] {
            for c in ck.cases {
                let raw = try interp.rawValue(KEnumValue(type: ck, caseName: c.name, payload: []))
                keys[c.name] = raw.asString ?? c.name
            }
        }
        var out: [String: Any] = [:]
        for p in t.stored {
            let key: String
            if let k = keys[p.name] { key = k }
            else if !keys.isEmpty { continue }   // not coded
            else { key = box.snakeCase ? snakeCase(p.name) : p.name }
            // A nil optional is left out, as `encodeIfPresent` does; `decode` reads a missing key as nil.
            // A wrapped property (`@Clamped var x`) is its wrapped value.
            let stored = fields[p.name] ?? (interp.customWrapper(p) != nil ? fields["_" + p.name].flatMap { try? interp.member($0, "wrappedValue", line: line) } : nil)
            guard let value = stored, !value.isNil else { continue }
            if case .void = value { continue }
            out[key] = try encode(value, box, interp, line)
        }
        return out
    }

    // MARK: Decoding

    /// What `T.self` names: a type, or `[T].self` (an array literal of one type).
    static func decodeTarget(_ v: KV, _ interp: KInterpreter) -> KETypeRef? {
        switch v {
        case .type(let t): return .named(t.name, [])
        case .array(let items) where items.count == 1: return decodeTarget(items[0], interp).map { .array($0) }
        case .dict(let d) where d.count == 1:
            if let (k, val) = d.first, let kt = decodeTarget(k, interp), let vt = decodeTarget(val, interp) { return .dictionary(kt, vt) }
            return nil
        default: return nil
        }
    }

    @MainActor static func decode(_ json: Any, as type: KETypeRef?, _ box: KDecoderBox, _ interp: KInterpreter, _ line: Int) throws -> KV {
        guard let type else { return plain(json) }
        switch type {
        case .optional(let w):
            return json is NSNull ? .nilValue : try decode(json, as: w, box, interp, line)
        case .array(let e):
            guard let items = json as? [Any] else { throw mismatch("an array", line, interp) }
            return .array(try items.map { try decode($0, as: e, box, interp, line) })
        case .dictionary(_, let v):
            guard let d = json as? [String: Any] else { throw mismatch("a dictionary", line, interp) }
            var out: [KV: KV] = [:]
            for (k, item) in d { out[.string(k)] = try decode(item, as: v, box, interp, line) }
            return .dict(out)
        case .named(let n, let gen):
            switch n {
            case "String":
                if let s = json as? String { return .string(s) }
                throw mismatch("a string", line, interp)
            case "Int", "Int64", "Int32", "UInt":
                if let num = json as? NSNumber { return .int(num.intValue) }
                throw mismatch("a number", line, interp)
            case "Double", "Float", "CGFloat":
                if let num = json as? NSNumber { return .double(num.doubleValue) }
                throw mismatch("a number", line, interp)
            case "Bool":
                if let num = json as? NSNumber { return .bool(num.boolValue) }
                throw mismatch("true or false", line, interp)
            case "URL":
                if let s = json as? String, let u = URL(string: s) { return .native(.url(u)) }
                throw mismatch("a URL", line, interp)
            case "UUID":
                if let s = json as? String, let u = UUID(uuidString: s) { return .native(.uuid(u)) }
                throw mismatch("a UUID", line, interp)
            case "Date":
                if box.iso8601, let s = json as? String, let d = ISO8601DateFormatter().date(from: s) { return .native(.date(d)) }
                if let num = json as? NSNumber { return .native(.date(Date(timeIntervalSinceReferenceDate: num.doubleValue))) }
                throw mismatch("a date", line, interp)
            case "Array" where gen.count == 1:
                return try decode(json, as: .array(gen[0]), box, interp, line)
            case "Optional" where gen.count == 1:
                return try decode(json, as: .optional(gen[0]), box, interp, line)
            default:
                guard let t = interp.type(named: n) else { return plain(json) }
                return try decodeUser(json, t, box, interp, line)
            }
        default:
            return plain(json)
        }
    }

    /// JSON read as the kind of value `like` is, for a property whose type is inferred.
    @MainActor static func decode(_ json: Any, like: KV, _ box: KDecoderBox, _ interp: KInterpreter, _ line: Int) throws -> KV {
        switch like {
        case .double: return try decode(json, as: .named("Double", []), box, interp, line)
        case .native(.uuid): return try decode(json, as: .named("UUID", []), box, interp, line)
        case .native(.date): return try decode(json, as: .named("Date", []), box, interp, line)
        case .native(.url): return try decode(json, as: .named("URL", []), box, interp, line)
        case .structV(let s): return try decodeUser(json, s.type, box, interp, line)
        case .enumV(let e): return try decodeUser(json, e.type, box, interp, line)
        case .array(let items):
            guard let first = items.first, let list = json as? [Any] else { return plain(json) }
            return .array(try list.map { try decode($0, like: first, box, interp, line) })
        default: return plain(json)
        }
    }

    @MainActor static func decodeUser(_ json: Any, _ t: KType, _ box: KDecoderBox, _ interp: KInterpreter, _ line: Int) throws -> KV {
        if t.isEnum {
            for c in t.cases {
                let raw = try interp.rawValue(KEnumValue(type: t, caseName: c.name, payload: []))
                if raw == plain(json) || (json as? String) == interp.describe(raw) && raw.asString != nil {
                    return .enumV(KEnumValue(type: t, caseName: c.name, payload: []))
                }
            }
            throw KEThrown(value: errorValue("Cannot initialize \(t.name) from invalid value \(json)"))
        }
        guard let object = json as? [String: Any] else { throw mismatch("an object for \(t.name)", line, interp) }
        // CodingKeys: `case authorName = "author_name"`.
        var keys: [String: String] = [:]
        if let ck = t.nested["CodingKeys"] {
            for c in ck.cases {
                let raw = try interp.rawValue(KEnumValue(type: ck, caseName: c.name, payload: []))
                keys[c.name] = raw.asString ?? c.name
            }
        }
        let defaults = try interp.defaultFields(t)
        var fields: [String: KV] = [:]
        for p in t.stored {
            let key: String
            if let k = keys[p.name] { key = k }
            else if !keys.isEmpty { fields[p.name] = defaults[p.name] ?? .nilValue; continue }   // not coded
            else { key = box.snakeCase ? snakeCase(p.name) : p.name }
            if let value = object[key], !(value is NSNull) {
                // `var id = UUID()` declares no type; its default value says what the JSON holds.
                if p.type == nil, let like = defaults[p.name] {
                    fields[p.name] = try decode(value, like: like, box, interp, line)
                } else {
                    fields[p.name] = try decode(value, as: p.type, box, interp, line)
                }
            } else if let d = defaults[p.name] {
                fields[p.name] = d
            } else if defaults["_" + p.name] != nil {
                continue   // a wrapped property keeps its wrapper's default
            } else if p.type?.isOptional == true || object[key] is NSNull {
                fields[p.name] = .nilValue
            } else {
                throw KEThrown(value: errorValue("The data couldn't be read because \"\(key)\" is missing (decoding \(t.name))."))
            }
        }
        // Wrapped properties get their wrapper back, built with the decoded value.
        for p in t.stored {
            guard let w = interp.customWrapper(p) else { continue }
            if let v = fields.removeValue(forKey: p.name) {
                fields["_" + p.name] = try interp.makeWrapper(w, wrappedValue: v, env: KEnv(parent: interp.globalEnv), line: line)
            } else if let d = defaults["_" + p.name] {
                fields["_" + p.name] = d
            }
        }
        if t.isClass { return .object(KObject(type: t, fields: fields)) }
        return .structV(KStructValue(type: t, fields: fields))
    }

    static func snakeCase(_ name: String) -> String {
        var out = ""
        for ch in name {
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
        return out
    }

    /// JSON as plain values: objects become `[String: Any]` dictionaries.
    static func plain(_ json: Any) -> KV {
        switch json {
        case let s as String: return .string(s)
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return CFNumberIsFloatType(n) ? .double(n.doubleValue) : .int(n.intValue)
        case let a as [Any]: return .array(a.map(plain))
        case let d as [String: Any]:
            var out: [KV: KV] = [:]
            for (k, v) in d { out[.string(k)] = plain(v) }
            return .dict(out)
        default: return .nilValue
        }
    }

    @MainActor static func mismatch(_ expected: String, _ line: Int, _ interp: KInterpreter) -> KEThrown {
        KEThrown(value: errorValue("The data couldn't be read because it isn't in the correct format (expected \(expected))."))
    }
}
