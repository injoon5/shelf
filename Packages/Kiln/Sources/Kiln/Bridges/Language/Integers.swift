//
//  Integers.swift
//  Bridges: fixed-width integers, SIMD vectors and random number generators
//
//  `UInt8`, `Int8` … `UInt64` and `UInt` are their own types (an `Int` is
//  Kiln's `.int`): their arithmetic traps on overflow as Swift's does, and the
//  `&` operators wrap. A value reads as a number wherever one is read
//  (`Data([b])`, `Int(b)`). `SIMD2`/`SIMD3`/`SIMD4` hold their scalars and
//  their scalar type. Random numbers can come from the app's own
//  `RandomNumberGenerator`, through Swift's own algorithms, so a seeded
//  generator gives what compiled Swift gives.
//

import SwiftUI

/// A fixed-width integer that isn't `Int`: its type and its bits.
struct KFixedInt: Hashable, KNumericBox, KDescribable {
    enum Kind: String, CaseIterable {
        case int8 = "Int8", int16 = "Int16", int32 = "Int32", int64 = "Int64"
        case uint8 = "UInt8", uint16 = "UInt16", uint32 = "UInt32", uint64 = "UInt64", uint = "UInt"
        var signed: Bool { [.int8, .int16, .int32, .int64].contains(self) }
        var width: Int {
            switch self {
            case .int8, .uint8: return 8
            case .int16, .uint16: return 16
            case .int32, .uint32: return 32
            default: return 64
            }
        }
        var mask: UInt64 { width == 64 ? .max : (1 << UInt64(width)) - 1 }
    }
    let kind: Kind
    /// The value's bit pattern, `width` bits wide.
    let bits: UInt64

    init(_ kind: Kind, bits: UInt64) {
        self.kind = kind
        self.bits = bits & kind.mask
    }

    /// The value, sign-extended for a signed type.
    var signedValue: Int64 {
        guard kind.signed else { return Int64(bitPattern: bits) }
        let shift = UInt64(64 - kind.width)
        return Int64(bitPattern: bits << shift) >> Int64(shift)
    }
    var isNegative: Bool { kind.signed && signedValue < 0 }

    var intValue: Int? {
        if kind.signed { return Int(signedValue) }
        return bits <= UInt64(Int.max) ? Int(bits) : nil
    }
    var doubleValue: Double { kind.signed ? Double(signedValue) : Double(bits) }

    func describe(_ interp: KInterpreter) -> String { kind.signed ? String(signedValue) : String(bits) }

    var kv: KV { .native(.boxed(KBoxed(kind.rawValue, self))) }

    /// The value of `v` as this type, if it fits: nil when it doesn't.
    static func exactly(_ kind: Kind, _ v: KV) -> KFixedInt? {
        if case .native(.boxed(let b)) = v, let f = b.value.base as? KFixedInt {
            if f.kind.signed { return exactly(kind, int64: f.signedValue) }
            return exactly(kind, uint64: f.bits)
        }
        if case .int(let i) = v { return exactly(kind, int64: Int64(i)) }
        if case .double(let d) = v, d.isFinite, d == d.rounded() {
            if d < 0 { return Int64(exactly: d).flatMap { exactly(kind, int64: $0) } }
            return UInt64(exactly: d).flatMap { exactly(kind, uint64: $0) }
        }
        return nil
    }

    static func exactly(_ kind: Kind, int64 i: Int64) -> KFixedInt? {
        if kind.signed {
            let lo = kind.width == 64 ? Int64.min : -(Int64(1) << Int64(kind.width - 1)), hi = kind.width == 64 ? Int64.max : (Int64(1) << Int64(kind.width - 1)) - 1
            guard i >= lo, kind.width == 64 || i <= hi else { return nil }
            return KFixedInt(kind, bits: UInt64(bitPattern: i))
        }
        guard i >= 0 else { return nil }
        return exactly(kind, uint64: UInt64(i))
    }

    static func exactly(_ kind: Kind, uint64 u: UInt64) -> KFixedInt? {
        if kind.signed { return u <= UInt64(Int64.max) ? exactly(kind, int64: Int64(u)) : nil }
        guard u & ~kind.mask == 0 else { return nil }
        return KFixedInt(kind, bits: u)
    }

    /// The low bits of any integer: `UInt8(truncatingIfNeeded:)`.
    static func truncating(_ kind: Kind, _ v: KV) -> KFixedInt? {
        if case .native(.boxed(let b)) = v, let f = b.value.base as? KFixedInt {
            return KFixedInt(kind, bits: f.kind.signed ? UInt64(bitPattern: f.signedValue) : f.bits)
        }
        if case .int(let i) = v { return KFixedInt(kind, bits: UInt64(bitPattern: Int64(i))) }
        return nil
    }

    /// The nearest value this type has: `Int32(clamping:)`.
    static func clamping(_ kind: Kind, _ v: KV) -> KFixedInt? {
        let wide: Double
        if case .native(.boxed(let b)) = v, let f = b.value.base as? KFixedInt { wide = f.doubleValue } else if let d = v.asDouble { wide = d } else { return nil }
        if let exact = exactly(kind, v) { return exact }
        let maxV = max(kind), minV = min(kind)
        return wide < 0 ? minV : maxV
    }

    static func max(_ kind: Kind) -> KFixedInt {
        kind.signed ? KFixedInt(kind, bits: kind.mask >> 1) : KFixedInt(kind, bits: kind.mask)
    }
    static func min(_ kind: Kind) -> KFixedInt {
        kind.signed ? KFixedInt(kind, bits: (kind.mask >> 1) + 1) : KFixedInt(kind, bits: 0)
    }
}

// MARK: - Arithmetic, as Swift's own types do it

@MainActor
enum KIntegerOps {
    /// A binary operator on two values of one fixed-width type; nil for
    /// operands it doesn't take. Overflow is an error, as Swift traps.
    static func binary(_ op: String, _ a: KV, _ b: KV, _ line: Int) throws -> KV? {
        guard let (x, y) = try operands(a, b, op, line) else { return nil }
        switch x.kind {
        case .int8: return try run(Int8.self, op, x, y, line)
        case .int16: return try run(Int16.self, op, x, y, line)
        case .int32: return try run(Int32.self, op, x, y, line)
        case .int64: return try run(Int64.self, op, x, y, line)
        case .uint8: return try run(UInt8.self, op, x, y, line)
        case .uint16: return try run(UInt16.self, op, x, y, line)
        case .uint32: return try run(UInt32.self, op, x, y, line)
        case .uint64: return try run(UInt64.self, op, x, y, line)
        case .uint: return try run(UInt.self, op, x, y, line)
        }
    }

    static func fixed(_ v: KV) -> KFixedInt? {
        if case .native(.boxed(let b)) = v { return b.value.base as? KFixedInt }
        return nil
    }

    /// Both operands as one type: an `Int` literal takes the other's type.
    private static func operands(_ a: KV, _ b: KV, _ op: String, _ line: Int) throws -> (KFixedInt, KFixedInt)? {
        let shift = ["<<", ">>", "&<<", "&>>"].contains(op)
        switch (fixed(a), fixed(b)) {
        case (let x?, let y?):
            if x.kind == y.kind || shift { return (x, shift ? (KFixedInt.truncating(x.kind, .int(y.intValue ?? 0)) ?? y) : y) }
            throw KERuntimeError(message: "Binary operator '\(op)' can't be applied to \(x.kind.rawValue) and \(y.kind.rawValue)", line: line)
        case (let x?, nil):
            if shift, case .int(let n) = b { return (x, KFixedInt(x.kind, bits: UInt64(bitPattern: Int64(n)))) }
            guard case .int = b else { return nil }
            guard let y = KFixedInt.exactly(x.kind, b) else {
                throw KERuntimeError(message: "\(b.asInt.map(String.init) ?? "the value") doesn't fit in a \(x.kind.rawValue)", line: line)
            }
            return (x, y)
        case (nil, let y?):
            guard case .int = a else { return nil }
            guard let x = KFixedInt.exactly(y.kind, a) else {
                throw KERuntimeError(message: "\(a.asInt.map(String.init) ?? "the value") doesn't fit in a \(y.kind.rawValue)", line: line)
            }
            return (x, y)
        default:
            return nil
        }
    }

    private static func value<T: FixedWidthInteger>(_ f: KFixedInt, _: T.Type) -> T {
        f.kind.signed ? T(truncatingIfNeeded: f.signedValue) : T(truncatingIfNeeded: f.bits)
    }

    private static func box<T: FixedWidthInteger>(_ v: T, _ kind: KFixedInt.Kind) -> KV {
        KFixedInt(kind, bits: UInt64(truncatingIfNeeded: v)).kv
    }

    private static func run<T: FixedWidthInteger>(_: T.Type, _ op: String, _ x: KFixedInt, _ y: KFixedInt, _ line: Int) throws -> KV? {
        let a = value(x, T.self), b = value(y, T.self), k = x.kind
        func overflow(_ r: (partialValue: T, overflow: Bool)) throws -> KV {
            if r.overflow { throw KERuntimeError(message: "Arithmetic overflow: \(a) \(op) \(b) doesn't fit in a \(k.rawValue) (use &\(op) to wrap around)", line: line) }
            return box(r.partialValue, k)
        }
        switch op {
        case "+": return try overflow(a.addingReportingOverflow(b))
        case "-": return try overflow(a.subtractingReportingOverflow(b))
        case "*": return try overflow(a.multipliedReportingOverflow(by: b))
        case "/", "%":
            if b == 0 { throw KERuntimeError(message: "Division by zero", line: line) }
            return try overflow(op == "/" ? a.dividedReportingOverflow(by: b) : a.remainderReportingOverflow(dividingBy: b))
        case "&+": return box(a &+ b, k)
        case "&-": return box(a &- b, k)
        case "&*": return box(a &* b, k)
        case "&": return box(a & b, k)
        case "|": return box(a | b, k)
        case "^": return box(a ^ b, k)
        case "<<": return box(a << b, k)
        case ">>": return box(a >> b, k)
        case "&<<": return box(a &<< b, k)
        case "&>>": return box(a &>> b, k)
        case "<": return .bool(a < b)
        default: return nil
        }
    }

    /// `-x` and `~x`.
    static func prefix(_ op: String, _ v: KV, _ line: Int) throws -> KV? {
        guard let x = fixed(v) else { return nil }
        if op == "prefix~" { return KFixedInt(x.kind, bits: ~x.bits).kv }
        guard op == "prefix-" else { return nil }
        guard x.kind.signed else { throw KERuntimeError(message: "Unary operator '-' can't be applied to an unsigned \(x.kind.rawValue)", line: line) }
        guard x.bits != KFixedInt.min(x.kind).bits, let r = KFixedInt.exactly(x.kind, int64: -x.signedValue) else {
            throw KERuntimeError(message: "Arithmetic overflow: -(\(x.signedValue)) doesn't fit in a \(x.kind.rawValue)", line: line)
        }
        return r.kv
    }

    /// Swift's integer members, on any width.
    static func property(_ name: String, _ x: KFixedInt) -> KV? {
        func run<T: FixedWidthInteger>(_: T.Type) -> KV? {
            let v = value(x, T.self)
            switch name {
            case "leadingZeroBitCount": return .int(v.leadingZeroBitCount)
            case "trailingZeroBitCount": return .int(v.trailingZeroBitCount)
            case "nonzeroBitCount": return .int(v.nonzeroBitCount)
            case "bitWidth": return .int(T.bitWidth)
            case "byteSwapped": return box(v.byteSwapped, x.kind)
            case "bigEndian": return box(v.bigEndian, x.kind)
            case "littleEndian": return box(v.littleEndian, x.kind)
            case "description": return .string(String(v))
            case "isZero": return .bool(v == 0)
            default: return nil
            }
        }
        switch x.kind {
        case .int8: return run(Int8.self)
        case .int16: return run(Int16.self)
        case .int32: return run(Int32.self)
        case .int64: return run(Int64.self)
        case .uint8: return run(UInt8.self)
        case .uint16: return run(UInt16.self)
        case .uint32: return run(UInt32.self)
        case .uint64: return run(UInt64.self)
        case .uint: return run(UInt.self)
        }
    }

    /// `addingReportingOverflow(_:)` and the others: `(partialValue:overflow:)`.
    static func reporting(_ name: String, _ x: KFixedInt, _ other: KV) -> KV? {
        guard let y = fixed(other) ?? KFixedInt.truncating(x.kind, other) else { return nil }
        func run<T: FixedWidthInteger>(_: T.Type) -> KV? {
            let a = value(x, T.self), b = value(y, T.self)
            let r: (partialValue: T, overflow: Bool)
            switch name {
            case "addingReportingOverflow": r = a.addingReportingOverflow(b)
            case "subtractingReportingOverflow": r = a.subtractingReportingOverflow(b)
            case "multipliedReportingOverflow": r = a.multipliedReportingOverflow(by: b)
            case "dividedReportingOverflow": r = a.dividedReportingOverflow(by: b)
            default: return nil
            }
            return .tuple([box(r.partialValue, x.kind), .bool(r.overflow)], ["partialValue", "overflow"])
        }
        switch x.kind {
        case .int8: return run(Int8.self)
        case .int16: return run(Int16.self)
        case .int32: return run(Int32.self)
        case .int64: return run(Int64.self)
        case .uint8: return run(UInt8.self)
        case .uint16: return run(UInt16.self)
        case .uint32: return run(UInt32.self)
        case .uint64: return run(UInt64.self)
        case .uint: return run(UInt.self)
        }
    }
}

extension LanguageBridges {
    static func integers(_ r: KRegistry) {
        for kind in KFixedInt.Kind.allCases {
            let name = kind.rawValue
            r.type(name, .language, support: .full,
                   notes: kind == .uint8 ? "Every fixed-width integer (`Int8`…`UInt64`, `UInt`) is its own type: overflow traps, `&+` `&-` `&*` wrap." : nil) { t in
                t.initializer("_:any") { c in
                    // `UInt8("12")`, `UInt8(x)` (traps when it doesn't fit, as Swift does).
                    if case .string(let s)? = c.first {
                        return UInt64(s).flatMap { KFixedInt.exactly(kind, uint64: $0) }?.kv
                            ?? Int64(s).flatMap { KFixedInt.exactly(kind, int64: $0) }?.kv ?? .nilValue
                    }
                    if let d = c.first?.asDouble, case .double = c.first! {
                        guard d.isFinite, let f = KFixedInt.exactly(kind, .double(d.rounded(.towardZero))) else {
                            throw c.interp.fail("\(d) can't be converted to \(name): it's out of its range", c.line)
                        }
                        return f.kv
                    }
                    guard let v = c.first, let f = KFixedInt.exactly(kind, v) else {
                        throw c.interp.fail("Not enough bits to represent \(c.first.map { c.interp.describe($0) } ?? "the value") in a \(name)", c.line)
                    }
                    return f.kv
                }
                t.initializer("_:string radix:number") { c in
                    guard let s = c.string(0), let radix = c.int("radix") else { return .nilValue }
                    return UInt64(s, radix: radix).flatMap { KFixedInt.exactly(kind, uint64: $0) }?.kv
                        ?? Int64(s, radix: radix).flatMap { KFixedInt.exactly(kind, int64: $0) }?.kv ?? .nilValue
                }
                t.initializer("truncatingIfNeeded:any") { c in KFixedInt.truncating(kind, c["truncatingIfNeeded"] ?? .int(0))?.kv ?? .nilValue }
                t.initializer("clamping:any") { c in KFixedInt.clamping(kind, c["clamping"] ?? .int(0))?.kv ?? .nilValue }
                t.initializer("exactly:any") { c in KFixedInt.exactly(kind, c["exactly"] ?? .nilValue)?.kv ?? .nilValue }
                t.initializer("bitPattern:any") { c in KFixedInt.truncating(kind, c["bitPattern"] ?? .int(0))?.kv ?? .nilValue }
                t.staticProperty("max") { _ in KFixedInt.max(kind).kv }
                t.staticProperty("min") { _ in KFixedInt.min(kind).kv }
                t.staticProperty("zero") { _ in KFixedInt(kind, bits: 0).kv }
                t.staticProperty("bitWidth") { _ in .int(kind.width) }
                t.staticProperty("isSigned") { _ in .bool(kind.signed) }
                t.staticProperty("self") { _ in .type(.builtin(name)) }
                t.staticMethod("random", "in:any using:binding?") { c in
                    guard case .range(let lo, let hi, let closed)? = c["in"],
                          let l = KFixedInt.exactly(kind, lo)?.doubleValue, let h = KFixedInt.exactly(kind, hi)?.doubleValue else { return .nilValue }
                    let n = try KRandom.int(c, Int(l), Int(h), closed: closed)
                    return KFixedInt.exactly(kind, .int(n))?.kv ?? .nilValue
                }
                for p in ["leadingZeroBitCount", "trailingZeroBitCount", "nonzeroBitCount", "bitWidth", "byteSwapped", "bigEndian",
                          "littleEndian", "description", "isZero"] {
                    t.property(p) { c in KIntegerOps.fixed(c.receiver).flatMap { KIntegerOps.property(p, $0) } ?? .nilValue }
                }
                t.property("magnitude") { c in
                    guard let x = KIntegerOps.fixed(c.receiver) else { return .nilValue }
                    let unsigned = KFixedInt.Kind(rawValue: "U" + name.replacingOccurrences(of: "UInt", with: "Int")) ?? kind
                    return KFixedInt(kind.signed ? unsigned : kind, bits: UInt64(x.signedValue.magnitude)).kv
                }
                for m in ["addingReportingOverflow", "subtractingReportingOverflow", "multipliedReportingOverflow", "dividedReportingOverflow"] {
                    t.method(m, m == "multipliedReportingOverflow" || m == "dividedReportingOverflow" ? "by:any" : "_:any") { c in
                        guard let x = KIntegerOps.fixed(c.receiver), let other = c.args.first else { return .nilValue }
                        return KIntegerOps.reporting(m, x, other) ?? .nilValue
                    }
                }
                t.method("signum", "") { c in
                    guard let x = KIntegerOps.fixed(c.receiver) else { return .nilValue }
                    return KFixedInt(kind, bits: UInt64(bitPattern: x.signedValue.signum())).kv
                }
                t.method("isMultiple", "of:any") { c in
                    guard let x = KIntegerOps.fixed(c.receiver)?.doubleValue, let y = c["of"]?.asDouble, y != 0 else { return .bool(false) }
                    return .bool(x.truncatingRemainder(dividingBy: y) == 0)
                }
                t.method("formatted", "_:any?") { c in .string(KFormatting.formatted(.int(c.receiver.asInt ?? 0), c.first ?? .nilValue, c.interp)) }
                for op in ["+", "-", "*", "/", "%", "&+", "&-", "&*", "&", "|", "^", "<<", ">>", "&<<", "&>>", "<"] {
                    t.operator(op) { a, b, line in try KIntegerOps.binary(op, a, b, line) }
                }
                for op in ["prefix-", "prefix~"] {
                    t.operator(op) { a, _, line in try KIntegerOps.prefix(op, a, line) }
                }
                t.fallback("Int") { v, _ in .int(v.asInt ?? 0) }
            }
            r.addLiteralCoercion(name) { v, _ in
                if case .int = v { return KFixedInt.exactly(kind, v)?.kv }
                return nil
            }
        }
        r.alias("UnicodeScalarValue", to: "UInt32", engineOnly: true)

        r.extend("Int") { t in
            t.initializer("_:string radix:number", first: true) { c in
                guard let s = c.string(0), let radix = c.int("radix") else { return .nilValue }
                return Int(s, radix: radix).map { .int($0) } ?? .nilValue
            }
            t.initializer("exactly:any", first: true) { c in
                if case .double(let d)? = c["exactly"] { return Int(exactly: d).map { .int($0) } ?? .nilValue }
                return c["exactly"]?.asInt.map { .int($0) } ?? .nilValue
            }
            t.initializer("truncatingIfNeeded:any", first: true) { c in
                if let f = KIntegerOps.fixed(c["truncatingIfNeeded"] ?? .nilValue) {
                    return .int(f.kind.signed ? Int(f.signedValue) : Int(truncatingIfNeeded: f.bits))
                }
                return c["truncatingIfNeeded"]?.asInt.map { .int($0) } ?? .int(0)
            }
            t.initializer("clamping:any", first: true) { c in
                if let f = KIntegerOps.fixed(c["clamping"] ?? .nilValue) {
                    return .int(f.kind.signed ? Int(f.signedValue) : (f.bits > UInt64(Int.max) ? Int.max : Int(f.bits)))
                }
                return c["clamping"]?.asInt.map { .int($0) } ?? .int(0)
            }
            t.initializer("bitPattern:any", first: true) { c in
                if let f = KIntegerOps.fixed(c["bitPattern"] ?? .nilValue) { return .int(Int(truncatingIfNeeded: Int64(bitPattern: f.bits))) }
                return c["bitPattern"]?.asInt.map { .int($0) } ?? .int(0)
            }
            t.staticProperty("bitWidth") { _ in .int(Int.bitWidth) }
            t.staticProperty("isSigned") { _ in .bool(true) }
            @MainActor func i(_ c: KCall) -> Int { c.receiver.asInt ?? 0 }
            t.property("leadingZeroBitCount") { c in .int(i(c).leadingZeroBitCount) }
            t.property("trailingZeroBitCount") { c in .int(i(c).trailingZeroBitCount) }
            t.property("nonzeroBitCount") { c in .int(i(c).nonzeroBitCount) }
            t.property("bitWidth") { _ in .int(Int.bitWidth) }
            t.property("byteSwapped") { c in .int(i(c).byteSwapped) }
            t.method("signum", "") { c in .int(i(c).signum()) }
            for m in ["addingReportingOverflow", "subtractingReportingOverflow", "multipliedReportingOverflow", "dividedReportingOverflow"] {
                t.method(m, m == "multipliedReportingOverflow" || m == "dividedReportingOverflow" ? "by:number" : "_:number") { c in
                    let a = i(c), b = c.args.first?.asInt ?? 0
                    let r: (partialValue: Int, overflow: Bool)
                    switch m {
                    case "addingReportingOverflow": r = a.addingReportingOverflow(b)
                    case "subtractingReportingOverflow": r = a.subtractingReportingOverflow(b)
                    case "multipliedReportingOverflow": r = a.multipliedReportingOverflow(by: b)
                    default: r = a.dividedReportingOverflow(by: b)
                    }
                    return .tuple([.int(r.partialValue), .bool(r.overflow)], ["partialValue", "overflow"])
                }
            }
            // A string index is a character offset in Kiln: its offset in UTF-16.
            t.method("utf16Offset", "in:string") { c in
                let s = c.string("in") ?? ""
                return .int(String(s.prefix(i(c))).utf16.count)
            }
        }
        r.extend("String") { t in
            t.initializer("format:string locale:any _:any...", first: true) { c in
                let rest = zip(c.args, c.labels).filter { $0.1 == nil }.map(\.0)
                let fmt = c.string("format") ?? ""
                guard let locale = FoundationBridges.locale(c["locale"]) else { return .string(KFormatting.format(fmt, rest, c.interp)) }
                return .string(KFormatting.format(fmt, rest, c.interp, locale: locale))
            }
            t.initializer("_:any radix:number uppercase:bool?", first: true) { c in
                let radix = c.int("radix") ?? 10
                let upper = c.bool("uppercase", default: false)
                if let f = KIntegerOps.fixed(c.first ?? .nilValue) {
                    return .string(f.kind.signed ? String(f.signedValue, radix: radix, uppercase: upper) : String(f.bits, radix: radix, uppercase: upper))
                }
                return .string(String(c.first?.asInt ?? 0, radix: radix, uppercase: upper))
            }
        }
        simd(r)
        randomGenerators(r)
    }
}

// MARK: - SIMD

/// `SIMD2<Double>(1, 2)`: its scalars and their type.
struct KSIMD: Hashable, KDescribable, KNativeSequence {
    let scalar: String
    var values: [Double]
    var isInteger: Bool { !["Double", "Float", "CGFloat", "Float16", "Float32", "Float64"].contains(scalar) }
    var typeName: String { "SIMD\(values.count)" }

    func element(_ x: Double) -> KV { isInteger ? .int(Int(x)) : .double(x) }
    var kv: KV { .native(.boxed(KBoxed(typeName, self))) }

    func describe(_ interp: KInterpreter) -> String {
        "\(typeName)<\(scalar)>(" + values.map { isInteger ? String(Int($0)) : String(describing: $0) }.joined(separator: ", ") + ")"
    }
    func elements(_ interp: KInterpreter) throws -> [KV] { values.map(element) }

    static let names = ["x", "y", "z", "w"]
}

extension LanguageBridges {
    static func simd(_ r: KRegistry) {
        for n in [2, 3, 4] {
            let name = "SIMD\(n)"
            r.type(name, .language, support: .full, notes: n == 2 ? "`SIMD2`, `SIMD3` and `SIMD4` of numbers: `x`…`w`, subscripts, `+ - * /` with vectors and scalars, `sum()`, `min()`, `max()`." : nil) { t in
                @MainActor func make(_ c: KCall, _ values: [Double]) -> KV {
                    var scalar = c.interp.constructingGenerics.first?.name
                    if scalar == nil { scalar = c.args.allSatisfy({ if case .int = $0 { return true }; return false }) ? "Int" : "Double" }
                    return KSIMD(scalar: scalar!, values: values).kv
                }
                t.initializer(Array(repeating: "_:any", count: n).joined(separator: " ")) { c in make(c, c.args.map { $0.asDouble ?? 0 }) }
                t.initializer("repeating:any") { c in make(c, Array(repeating: c["repeating"]?.asDouble ?? 0, count: n)) }
                t.initializer("") { c in make(c, Array(repeating: 0, count: n)) }
                t.initializer("_:[any]") { c in make(c, ((try? c.interp.sequence(c.first ?? .nilValue)) ?? []).map { $0.asDouble ?? 0 }) }
                t.staticProperty("zero") { c in make(c, Array(repeating: 0, count: n)) }
                t.staticProperty("one") { c in make(c, Array(repeating: 1, count: n)) }
                t.staticProperty("scalarCount") { _ in .int(n) }
                @MainActor func v(_ c: KCall) -> KSIMD? { if case .native(.boxed(let b)) = c.receiver { return b.value.base as? KSIMD }; return nil }
                for (i, comp) in KSIMD.names.prefix(n).enumerated() {
                    t.property(comp, { c in v(c).map { $0.element($0.values[i]) } ?? .nilValue }, set: { c in
                        guard var s = v(c), let x = c.first?.asDouble else { return }
                        s.values[i] = x
                        c.mutated = s.kv
                    })
                }
                t.property("scalarCount") { _ in .int(n) }
                t.property("indices") { _ in .range(.int(0), .int(n), closed: false) }
                t.method("sum", "") { c in v(c).map { $0.element($0.values.reduce(0, +)) } ?? .nilValue }
                t.method("min", "") { c in v(c).map { $0.element($0.values.min() ?? 0) } ?? .nilValue }
                t.method("max", "") { c in v(c).map { $0.element($0.values.max() ?? 0) } ?? .nilValue }
                t.method("subscript", "_:number") { c in
                    guard let s = v(c), let i = c.int(0), i >= 0, i < n else { throw c.interp.fail("Index out of range", c.line) }
                    return s.element(s.values[i])
                }
                t.method("replacing", "with:any where:any") { c in c.receiver }
                let ops: [(String, (Double, Double) -> Double)] = [("+", { $0 + $1 }), ("-", { $0 - $1 }), ("*", { $0 * $1 }), ("/", { $0 / $1 })]
                for (op, f) in ops {
                    t.operator(op) { a, b, _ in
                        func vec(_ x: KV) -> KSIMD? { if case .native(.boxed(let bx)) = x { return bx.value.base as? KSIMD }; return nil }
                        switch (vec(a), vec(b)) {
                        case (let x?, let y?) where x.values.count == y.values.count:
                            return KSIMD(scalar: x.scalar, values: zip(x.values, y.values).map(f)).kv
                        case (let x?, nil): guard let s = b.asDouble else { return nil }; return KSIMD(scalar: x.scalar, values: x.values.map { f($0, s) }).kv
                        case (nil, let y?): guard let s = a.asDouble else { return nil }; return KSIMD(scalar: y.scalar, values: y.values.map { f(s, $0) }).kv
                        default: return nil
                        }
                    }
                }
                t.operator("prefix-") { a, _, _ in
                    guard case .native(.boxed(let bx)) = a, let x = bx.value.base as? KSIMD else { return nil }
                    return KSIMD(scalar: x.scalar, values: x.values.map { -$0 }).kv
                }
            }
            r.addLiteralCoercion(name) { v, t in
                guard case .array(let xs) = v, xs.count == n else { return nil }
                var scalar = "Double"
                if case .named(_, let g) = t.core, let s = g.first?.name { scalar = s }
                return KSIMD(scalar: scalar, values: xs.map { $0.asDouble ?? 0 }).kv
            }
        }
        @MainActor func simdArgs(_ c: KCall) -> (KSIMD, KSIMD)? {
            guard case .native(.boxed(let a))? = c.at(0), let x = a.value.base as? KSIMD,
                  case .native(.boxed(let b))? = c.at(1), let y = b.value.base as? KSIMD, x.values.count == y.values.count else { return nil }
            return (x, y)
        }
        @MainActor func simdArg(_ c: KCall) -> KSIMD? {
            guard case .native(.boxed(let a))? = c.at(0) else { return nil }
            return a.value.base as? KSIMD
        }
        for (name, f) in [("pointwiseMin", { (a: Double, b: Double) in min(a, b) }), ("pointwiseMax", { (a: Double, b: Double) in max(a, b) })] {
            r.function(name, .language, "_:any _:any") { c in
                guard let (x, y) = simdArgs(c) else { throw c.fail("needs two SIMD vectors of one size") }
                return KSIMD(scalar: x.scalar, values: zip(x.values, y.values).map(f)).kv
            }
        }
        for name in ["simd_length", "length"] {
            r.function(name, .language, "_:any", owner: "simd") { c in
                guard let x = simdArg(c) else { throw c.fail("needs a SIMD vector") }
                return .double(x.values.map { $0 * $0 }.reduce(0, +).squareRoot())
            }
        }
        for name in ["simd_distance", "distance"] {
            r.function(name, .language, "_:any _:any", owner: "simd") { c in
                guard let (x, y) = simdArgs(c) else { throw c.fail("needs two SIMD vectors of one size") }
                return .double(zip(x.values, y.values).map { ($0 - $1) * ($0 - $1) }.reduce(0, +).squareRoot())
            }
        }
        for name in ["simd_dot", "dot"] {
            r.function(name, .language, "_:any _:any", owner: "simd") { c in
                guard let (x, y) = simdArgs(c) else { throw c.fail("needs two SIMD vectors of one size") }
                return x.element(zip(x.values, y.values).map(*).reduce(0, +))
            }
        }
        for name in ["simd_normalize", "normalize"] {
            r.function(name, .language, "_:any", owner: "simd") { c in
                guard let x = simdArg(c) else { throw c.fail("needs a SIMD vector") }
                let len = x.values.map { $0 * $0 }.reduce(0, +).squareRoot()
                return KSIMD(scalar: x.scalar, values: x.values.map { len == 0 ? 0 : $0 / len }).kv
            }
        }
        r.function("simd_mix", .language, "_:any _:any _:any", owner: "simd") { c in
            guard let (x, y) = simdArgs(c), case .native(.boxed(let tb))? = c.at(2), let tt = tb.value.base as? KSIMD else { throw c.fail("needs three SIMD vectors") }
            return KSIMD(scalar: x.scalar, values: (0..<x.values.count).map { x.values[$0] + (y.values[$0] - x.values[$0]) * tt.values[$0] }).kv
        }
    }
}

// MARK: - Random numbers from a generator

/// `using: &generator`: the system's, or the app's own `RandomNumberGenerator`
/// (its `next()` runs, and Swift's algorithms use what it returns).
@MainActor
enum KRandom {
    struct AppGenerator: RandomNumberGenerator {
        let interp: KInterpreter
        let binding: KBinding
        let nextDecl: KEFuncDecl
        let type: KType
        var failure: Error?
        mutating func next() -> UInt64 {
            let (value, error): (UInt64, Error?) = MainActor.assumeIsolated {
                let box = KBox(binding.get())
                do {
                    let r = try interp.invoke(nextDecl, args: [], labels: [], selfContext: KSelfContext(type: type, location: .box(box)), parent: interp.globalEnv)
                    binding.set(box.value)
                    if let f = KIntegerOps.fixed(r) { return (f.bits, nil) }
                    return (UInt64(bitPattern: Int64(r.asInt ?? 0)), nil)
                } catch { return (0, error) }
            }
            if let error, failure == nil { failure = error }
            return value
        }
    }

    /// Runs `body` with the generator `using:` names (or the run's own, seeded by `Kiln.randomSeed`).
    static func with<T>(_ c: KCall, _ body: (inout any RandomNumberGenerator) throws -> T) throws -> T {
        guard case .binding(let b)? = c["using"] else {
            var g: any RandomNumberGenerator = c.interp.rng
            defer { if let kg = g as? KilnRandom { c.interp.rng = kg } }
            return try body(&g)
        }
        let v = b.get()
        if let t = v.userType, let next = t.methods["next"]?.first(where: { $0.params.isEmpty }) {
            var g: any RandomNumberGenerator = AppGenerator(interp: c.interp, binding: b, nextDecl: next, type: t)
            let r = try body(&g)
            if let failure = (g as? AppGenerator)?.failure { throw failure }
            return r
        }
        var g: any RandomNumberGenerator = SystemRandomNumberGenerator()
        return try body(&g)
    }

    static func int(_ c: KCall, _ lo: Int, _ hi: Int, closed: Bool) throws -> Int {
        if closed ? lo > hi : lo >= hi { throw c.interp.fail("random(in:) needs a non-empty range", c.line) }
        return try with(c) { g in closed ? Int.random(in: lo...hi, using: &g) : Int.random(in: lo..<hi, using: &g) }
    }
}

extension LanguageBridges {
    static func randomGenerators(_ r: KRegistry) {
        r.type("SystemRandomNumberGenerator", .language, support: .full) { t in
            t.initializer("") { _ in .native(.object("SystemRandomNumberGenerator", KRef(NSObject()))) }
            t.method("next", "") { _ in
                var g = SystemRandomNumberGenerator()
                return KFixedInt(.uint64, bits: g.next()).kv
            }
        }
        r.protocolBridge("RandomNumberGenerator", .language, requirements: ["next()"], support: .full,
                         notes: "Your own generator (a seeded one) works with `random(in:using:)`, `shuffled(using:)` and `randomElement(using:)`, through Swift's own algorithms.")
    }
}
