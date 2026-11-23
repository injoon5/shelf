//
//  KilnBridgeAPI.swift
//  Kiln's bridge registry: the public half
//
//  How the app hosting Kiln adds its own bridges (PLAN.md §1.4's host
//  bridges): Shelf registers `DB` here in §1.7, and later the permission
//  gate. The same registry, the same overload rules and the same errors as
//  Kiln's own bridges; only the values are wrapped (`KilnValue`), so the host
//  doesn't see Kiln's internals.
//
//      Kiln.registerType("DB") { t in
//          t.staticMethod("load", "_:string") { call in
//              KilnValue(string: store[try call.string(0)] ?? "")
//          }
//      }
//
//  Signatures are written as Kiln's own (`Docs/bridges.md`): `label:kind`
//  pairs, `_` for no label, `?` for a default. A nil signature takes any
//  labels and the bridge reads them itself.
//

import SwiftUI

extension Kiln {
    /// Adds a native type the app's code can name: its static members,
    /// initializers, and the methods and properties of its values. Registering
    /// a host type again replaces it.
    @MainActor
    public static func registerType(_ name: String, family: KilnFamily = .host, notes: String? = nil,
                                    _ build: @MainActor (KilnTypeBuilder) -> Void) {
        let r = KRegistry.shared
        let b = KTypeBridge(name: name, family: family, support: .full, introduced: nil, notes: notes, source: "host")
        build(KilnTypeBuilder(bridge: b))
        r.replace(b)
    }

    /// Adds a global function the app's code can call.
    @MainActor
    public static func registerFunction(_ name: String, signature: String? = nil, family: KilnFamily = .host, notes: String? = nil,
                                        _ run: @escaping @MainActor (KilnCall) throws -> KilnValue) {
        let r = KRegistry.shared
        let b = KFunctionBridge(name: name, family: family, support: .full, introduced: nil, notes: notes, source: "host")
        b.owner = "Host"
        b.forms = [.init(overload: KTypeBuilder.overload(signature, introduced: nil, notes: notes), run: KilnTypeBuilder.wrap(run))]
        r.replace(b)
    }

    /// `kiln-manifest.json`'s contents: every bridge, Kiln's and the host's.
    @MainActor
    public static func manifestJSON() throws -> Data {
        try KRegistry.shared.manifest().encoded()
    }
}

extension KRegistry {
    /// A host bridge: registered at run time, so registering it again replaces it.
    func replace(_ b: KTypeBridge) {
        removeClaim("type:" + b.name)
        add(b)
    }

    func replace(_ b: KFunctionBridge) {
        removeClaim("function:" + b.name)
        add(b)
    }
}

/// Declares a host type's members.
@MainActor
public struct KilnTypeBuilder {
    let bridge: KTypeBridge

    static func wrap(_ run: @escaping @MainActor (KilnCall) throws -> KilnValue) -> KTypeBridge.Fn {
        { c in
            let call = KilnCall(c: c)
            let v = try run(call)
            c.mutated = call.mutated?.kv
            return v.kv
        }
    }

    /// `Type(…)`.
    public func initializer(_ signature: String? = nil, notes: String? = nil, _ run: @escaping @MainActor (KilnCall) throws -> KilnValue) {
        bridge.inits.append(.init(overload: KTypeBuilder.overload(signature, introduced: nil, notes: notes), run: Self.wrap(run)))
    }

    /// `Type.name`.
    public func staticProperty(_ name: String, notes: String? = nil, _ get: @escaping @MainActor (KilnCall) throws -> KilnValue) {
        bridge.staticProperties[name] = .init(get: Self.wrap(get), set: nil, notes: notes, support: .full)
    }

    /// `Type.name(…)`.
    public func staticMethod(_ name: String, _ signature: String? = nil, notes: String? = nil,
                             _ run: @escaping @MainActor (KilnCall) throws -> KilnValue) {
        bridge.staticMethods[name, default: []].append(.init(overload: KTypeBuilder.overload(signature, introduced: nil, notes: notes), run: Self.wrap(run)))
    }

    /// `value.name`, and `value.name = x` when `set` is given (`call.receiver`
    /// is the value, `call.value(0)` the new one).
    public func property(_ name: String, notes: String? = nil, _ get: @escaping @MainActor (KilnCall) throws -> KilnValue,
                         set: (@MainActor (KilnCall) throws -> Void)? = nil) {
        bridge.properties[name] = .init(get: Self.wrap(get), set: set.map { s in { c in try s(KilnCall(c: c)) } }, notes: notes, support: .full)
    }

    /// `value.name(…)`.
    public func method(_ name: String, _ signature: String? = nil, notes: String? = nil,
                       _ run: @escaping @MainActor (KilnCall) throws -> KilnValue) {
        bridge.methods[name, default: []].append(.init(overload: KTypeBuilder.overload(signature, introduced: nil, notes: notes), run: Self.wrap(run)))
    }
}

/// A call to a host bridge: its arguments, by label or by position among the
/// unlabeled ones.
@MainActor
public final class KilnCall {
    let c: KCall
    var mutated: KilnValue?

    init(c: KCall) { self.c = c }

    /// The line in the app's code, for errors.
    public var line: Int { c.line }

    /// What a method or property was called on.
    public var receiver: KilnValue { KilnValue(c.receiver) }

    /// An argument by label (`"forKey"`) or position (`0`), or nil.
    public func value(_ label: String) -> KilnValue? { c[.label(label)].map(KilnValue.init) }
    public func value(_ position: Int) -> KilnValue? { c[.position(position)].map(KilnValue.init) }

    public func string(_ label: String) throws -> String { try required(.label(label), String.self) }
    public func string(_ position: Int) throws -> String { try required(.position(position), String.self) }
    public func int(_ label: String) throws -> Int { try required(.label(label), Int.self) }
    public func int(_ position: Int) throws -> Int { try required(.position(position), Int.self) }
    public func double(_ label: String) throws -> Double { try required(.label(label), Double.self) }
    public func double(_ position: Int) throws -> Double { try required(.position(position), Double.self) }
    public func bool(_ label: String) throws -> Bool { try required(.label(label), Bool.self) }
    public func bool(_ position: Int) throws -> Bool { try required(.position(position), Bool.self) }

    private func required<T: KBridgeable>(_ ref: KArgRef, _ t: T.Type) throws -> T {
        guard let v = c[ref], !v.isNil else { throw c.fail("\(ref.description) is missing") }
        switch (v, t) {
        case (.string, is String.Type), (.int, is Int.Type), (.int, is Double.Type), (.double, is Double.Type), (.bool, is Bool.Type):
            return T.decode(v, c.interp)!
        default:
            throw c.fail("\(ref.description) should be \(T.kilnTypeName), not \(v.typeName)")
        }
    }

    /// An app value (a struct of the app's own, an array) as JSON, encoded as
    /// `JSONEncoder` would in the app's code.
    public func json(_ position: Int) throws -> Data {
        guard let v = c[.position(position)] else { throw c.fail("\(KArgRef.position(position).description) is missing") }
        return try KilnValue(v).json(c)
    }

    /// The type named by an argument written `T.self`, for `decode`.
    public func type(_ label: String) -> KilnValue? { value(label) }

    /// JSON decoded into the app's type, as `JSONDecoder().decode(T.self, from:)`.
    public func decode(_ data: Data, as type: KilnValue) throws -> KilnValue {
        let decoder = KV.native(.object("JSONDecoder", KRef(KDecoderBox())))
        var call = KCall.values(c.interp, "JSONDecoder.decode", [type.kv, KBuiltins.data(data)], [nil, "from"], line: c.line, receiver: decoder)
        guard let decode = KRegistry.shared.type("JSONDecoder")?.methods["decode"]?.first else {
            throw c.fail("JSONDecoder isn't available")
        }
        return KilnValue(try decode.run(&call))
    }

    /// A mutating method's new value for its receiver.
    public func setReceiver(_ v: KilnValue) { mutated = v }

    /// An error the app's code sees with its line: `Line 12: DB.load(_:): …`.
    public func error(_ message: String) -> Error { c.fail(message) }
}

/// A value going into or out of the app's code.
@MainActor
public struct KilnValue {
    let kv: KV
    init(_ kv: KV) { self.kv = kv }

    public static let void = KilnValue(.void)
    public static let `nil` = KilnValue(.nilValue)
    public init(string: String) { kv = .string(string) }
    public init(int: Int) { kv = .int(int) }
    public init(double: Double) { kv = .double(double) }
    public init(bool: Bool) { kv = .bool(bool) }
    public init(date: Date) { kv = .native(.date(date)) }
    public init(url: URL) { kv = .native(.url(url)) }
    public init(data: Data) { kv = KBuiltins.data(data) }
    public init(array: [KilnValue]) { kv = .array(array.map(\.kv)) }
    public init(dictionary: [String: KilnValue]) {
        kv = .dict(Dictionary(uniqueKeysWithValues: dictionary.map { (KV.string($0.key), $0.value.kv) }))
    }

    /// A native object whose members are the type bridge `type`'s methods and
    /// properties (`call.receiver.object` gets it back).
    public init(object: AnyObject, type: String) { kv = .native(.object(type, KRef(object))) }

    /// What `await` waits on: Swift `async` work, run on the main actor.
    /// Cancelling the app's task cancels it. In `Kiln.validate`, `headless`
    /// answers instead (nil: the check stops following the task there).
    public static func async(headless: (@MainActor () throws -> KilnValue)? = nil,
                             _ work: @escaping @MainActor () async throws -> KilnValue) -> KilnValue {
        KilnValue(.suspension(KSuspension.async(headless: headless.map { h in { try h().kv } }) { try await work().kv }))
    }

    public var string: String? { kv.asString }
    public var int: Int? { kv.asInt }
    public var double: Double? { kv.asDouble }
    public var bool: Bool? { kv.asBool }
    public var isNil: Bool { kv.isNil }
    public var object: AnyObject? {
        if case .native(.object(_, let ref)) = kv { return ref.value }
        return nil
    }
    public var data: Data? { KBuiltins.dataValue(kv) }

    func json(_ c: KCall) throws -> Data {
        let encoder = KV.native(.object("JSONEncoder", KRef(KEncoderBox())))
        var call = KCall.values(c.interp, "JSONEncoder.encode", [kv], line: c.line, receiver: encoder)
        guard let encode = KRegistry.shared.type("JSONEncoder")?.methods["encode"]?.first else {
            throw c.fail("JSONEncoder isn't available")
        }
        return KBuiltins.dataValue(try encode.run(&call)) ?? Data()
    }
}
