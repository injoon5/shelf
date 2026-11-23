//
//  JSON.swift
//  Bridges: JSONDecoder and JSONEncoder
//
//  `decode(T.self, from:)` builds the app's own `Decodable` types from their
//  stored properties (CodingKeys, optionals, defaults, nested types, arrays,
//  raw-value enums); `encode` is the same mapping the other way. The mapping
//  itself is in Bridges/Networking/NetworkSupport.swift.
//

import SwiftUI

extension FoundationBridges {
    static func json(_ r: KRegistry) {
        r.type("JSONDecoder", .foundation, notes: "Into your own `Codable` types, with `CodingKeys`, `.convertFromSnakeCase` and `.iso8601` dates.") { t in
            t.initializer { _ in .native(.object("JSONDecoder", KRef(KDecoderBox()))) }
            t.method("decode") { c in
                guard let data = KBuiltins.dataValue(c.arg("from") ?? c.last) else { throw c.interp.fail("decode(_:from:) needs Data", c.line) }
                let json: Any
                do {
                    json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
                } catch {
                    throw KEThrown(value: KBuiltins.errorValue("The data couldn't be read because it isn't in the correct format."))
                }
                let box = c.object(KDecoderBox.self) ?? KDecoderBox()
                return try KBuiltins.decode(json, as: KBuiltins.decodeTarget(c.first ?? .nilValue, c.interp), box, c.interp, c.line)
            }
            t.property("keyDecodingStrategy", { _ in .nilValue }, set: { c in
                if case .native(.implicit(let s, _))? = c.first { c.object(KDecoderBox.self)?.snakeCase = s == "convertFromSnakeCase" }
            })
            t.property("dateDecodingStrategy", { _ in .nilValue }, set: { c in
                if case .native(.implicit(let s, _))? = c.first { c.object(KDecoderBox.self)?.iso8601 = s == "iso8601" }
            })
        }
        r.type("JSONEncoder", .foundation, notes: "Keys are sorted; `.convertToSnakeCase` and `.iso8601` dates.") { t in
            t.initializer { _ in .native(.object("JSONEncoder", KRef(KEncoderBox()))) }
            t.method("encode") { c in
                let box = c.object(KEncoderBox.self) ?? KEncoderBox()
                let json = try KBuiltins.encode(c.first ?? .nilValue, box, c.interp, c.line)
                guard let out = try? JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed, .sortedKeys]) else {
                    throw KEThrown(value: KBuiltins.errorValue("The data couldn't be written because it isn't in the correct format."))
                }
                return KBuiltins.data(out)
            }
            t.property("keyEncodingStrategy", { _ in .nilValue }, set: { c in
                if case .native(.implicit(let s, _))? = c.first { c.object(KEncoderBox.self)?.snakeCase = s == "convertToSnakeCase" }
            })
            t.property("dateEncodingStrategy", { _ in .nilValue }, set: { c in
                if case .native(.implicit(let s, _))? = c.first { c.object(KEncoderBox.self)?.iso8601 = s == "iso8601" }
            })
            // Keys are always sorted; the rest is whitespace.
            t.property("outputFormatting", { _ in .nilValue }, set: { _ in })
        }
    }
}
