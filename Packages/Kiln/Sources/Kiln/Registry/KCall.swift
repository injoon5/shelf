//
//  KCall.swift
//  Kiln's bridge registry
//
//  What a bridge gets: the call's arguments, already evaluated against their
//  parameters' kinds, and helpers that decode and check them so every bridge
//  is a few lines and every error reads the same:
//
//      c.binding("selection", Date.self)          Binding<Date>
//      c.optional("in", ClosedRange<Date>.self)   ClosedRange<Date>?
//      c.content()                                the @ViewBuilder closure, shown
//      c.shapeStyle(0)                            the first unlabeled argument as a ShapeStyle
//      c.double("step") ?? 1
//
//  An argument is named by its label, or by its position among the unlabeled
//  ones (`0` is the first), or `.receiver` for the value a method is called on.
//

import SwiftUI

/// Names an argument: `"isOn"`, `0` (the first unlabeled one), `.receiver`.
enum KArgRef: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, Equatable {
    case label(String)
    case position(Int)
    case receiver

    init(stringLiteral s: String) { self = .label(s) }
    init(integerLiteral i: Int) { self = .position(i) }

    var description: String {
        switch self {
        case .label(let l): return "'\(l)'"
        case .position(let i): return i == 0 ? "the first argument" : "argument \(i + 1)"
        case .receiver: return "the value"
        }
    }
}

@MainActor
struct KCall {
    let interp: KInterpreter
    /// For messages: `Toggle`, `.padding`, `Date.addingTimeInterval`.
    let name: String
    let line: Int
    /// The arguments as written, evaluated, in order.
    let args: [KV]
    let labels: [String?]
    /// The overload picked (nil for calls the engine makes itself).
    let overload: KOverload?
    /// Parameter index → argument index, -1 when the argument was left out.
    let slots: [Int]
    /// What a method or property is called on.
    var receiver: KV = .void
    /// A mutating method's new receiver, written back to where it came from.
    var mutated: KV?
    /// For a modifier: the description of the view it's applied to.
    var base: KView?
    /// How each argument was written (a string literal, a closure), when the
    /// call came from code.
    var syntax: [KArgSyntax] = []

    init(interp: KInterpreter, name: String, line: Int, args: [KV], labels: [String?], overload: KOverload?, slots: [Int],
         receiver: KV = .void, base: KView? = nil) {
        self.interp = interp
        self.name = name
        self.line = line
        self.args = args
        self.labels = labels
        self.overload = overload
        self.slots = slots
        self.receiver = receiver
        self.base = base
    }

    /// A call the engine builds from values (`Image` rendered from a value,
    /// a member read).
    static func values(_ interp: KInterpreter, _ name: String, _ args: [KV] = [], _ labels: [String?] = [], line: Int = 0,
                       receiver: KV = .void) -> KCall {
        KCall(interp: interp, name: name, line: line, args: args, labels: labels.isEmpty ? args.map { _ in nil } : labels,
              overload: nil, slots: [], receiver: receiver)
    }

    /// The renderer, for bridges that show views.
    var r: KRenderer { KRenderer(interp: interp) }

    /// For a modifier: the view it's applied to, shown.
    var view: AnyView { base.map { r.render($0) } ?? AnyView(EmptyView()) }

    /// The arguments as written, for bridges that read them positionally.
    var a: KArgs { KArgs(args: args, labels: labels) }

    // MARK: Finding arguments

    subscript(_ ref: KArgRef) -> KV? {
        switch ref {
        case .receiver: return receiver
        case .label(let l):
            if let o = overload, !o.lenient {
                guard let p = o.params.firstIndex(where: { $0.label == l }), slots[p] >= 0 else { return nil }
                return args[slots[p]]
            }
            return labels.firstIndex(of: l).map { args[$0] }
        case .position(let n):
            if let o = overload, !o.lenient {
                var k = 0
                for (p, param) in o.params.enumerated() where param.label == nil {
                    if k == n { return slots[p] >= 0 ? args[slots[p]] : nil }
                    k += 1
                }
                return nil
            }
            var k = 0
            for (i, l) in labels.enumerated() where l == nil {
                if k == n { return args[i] }
                k += 1
            }
            return nil
        }
    }

    func has(_ ref: KArgRef) -> Bool { self[ref].map { !$0.isNil } ?? false }

    var first: KV? { args.first }
    var last: KV? { args.last }

    /// The value of the first parameter of a kind (the content closure).
    func param(ofKind kind: KArgKind) -> KV? {
        guard let o = overload, !o.lenient else { return nil }
        for (p, param) in o.params.enumerated() where param.kind == kind && slots[p] >= 0 { return args[slots[p]] }
        return nil
    }

    // MARK: Errors

    /// `Toggle(_:isOn:): …`, with the author's line.
    func fail(_ message: String) -> KERuntimeError {
        KERuntimeError(message: "\(overload?.display(name) ?? name): \(message)", line: line)
    }

    func describe(_ v: KV) -> String { interp.describe(v) }

    // MARK: Plain values

    func string(_ ref: KArgRef) -> String? {
        guard let v = self[ref], !v.isNil else { return nil }
        return r.string(v)
    }

    /// A title: a `Text`'s words, a string, a number.
    func title(_ ref: KArgRef) -> String { string(ref) ?? "" }

    func double(_ ref: KArgRef) -> Double? { self[ref]?.asDouble }
    func cg(_ ref: KArgRef) -> CGFloat? { self[ref]?.cg }
    func int(_ ref: KArgRef) -> Int? { self[ref]?.asInt }
    func bool(_ ref: KArgRef, default d: Bool) -> Bool { self[ref].map { interp.truthy($0) } ?? d }

    func date(_ ref: KArgRef) -> Date? {
        if case .native(.date(let d))? = self[ref] { return d }
        return nil
    }

    func url(_ ref: KArgRef) -> URL? {
        switch self[ref] {
        case .native(.url(let u))?: return u
        case .string(let s)?: return URL(string: s)
        default: return nil
        }
    }

    /// A symbolic SwiftUI value: `.leading` → "leading".
    func symbol(_ ref: KArgRef) -> String? {
        if case .native(.implicit(let n, _))? = self[ref] { return n }
        return nil
    }

    func function(_ ref: KArgRef) -> KFunction? {
        if case .function(let f)? = self[ref] { return f }
        return nil
    }

    // MARK: SwiftUI values

    func color(_ ref: KArgRef) -> Color? { r.color(self[ref]) }
    func shapeStyle(_ ref: KArgRef) -> AnyShapeStyle? { r.shapeStyle(self[ref]) }
    func font(_ ref: KArgRef) -> Font? { r.font(self[ref]) }
    func angle(_ ref: KArgRef) -> Angle { r.angle(self[ref]) }
    func alignment(_ ref: KArgRef) -> Alignment { r.alignment(self[ref]) }
    func horizontalAlignment(_ ref: KArgRef) -> HorizontalAlignment { r.horizontalAlignment(self[ref]) }
    func verticalAlignment(_ ref: KArgRef) -> VerticalAlignment { r.verticalAlignment(self[ref]) }
    func unitPoint(_ ref: KArgRef) -> UnitPoint? { r.unitPoint(self[ref]) }
    func edges(_ ref: KArgRef) -> Edge.Set { r.edges(self[ref]) }
    func animation(_ ref: KArgRef) -> Animation? { r.animation(self[ref]) }

    // MARK: Bindings and typed values

    /// The argument as a SwiftUI binding of `T`. Reads that don't decode give
    /// `T`'s placeholder; writes keep the stored value's kind (an `Int` stays one).
    func binding<T: KBridgeable>(_ ref: KArgRef, _ type: T.Type) -> Binding<T> {
        guard case .binding(let b)? = self[ref] else {
            let v = self[ref].flatMap { T.decode($0, interp) } ?? T.placeholder
            return .constant(v)
        }
        let interp = self.interp
        return Binding(get: { T.decode(b.get(), interp) ?? T.placeholder },
                       set: { b.set($0.encode(like: b.get())) })
    }

    /// The raw binding, when the bridge works with values directly.
    func kbinding(_ ref: KArgRef) -> KBinding? {
        if case .binding(let b)? = self[ref] { return b }
        return nil
    }

    /// The argument as `T`, or nil when it's absent or isn't one.
    func optional<T: KBridgeable>(_ ref: KArgRef, _ type: T.Type) -> T? {
        guard let v = self[ref], !v.isNil else { return nil }
        if case .binding(let b) = v { return T.decode(b.get(), interp) }
        return T.decode(v, interp)
    }

    /// The argument as `T`; a missing or mistyped one is an error.
    func required<T: KBridgeable>(_ ref: KArgRef, _ type: T.Type) throws -> T {
        guard let v = self[ref] else { throw fail("\(ref.description) is missing") }
        guard let t = optional(ref, type) else { throw fail("\(ref.description) should be \(T.kilnTypeName), not \(v.typeName)") }
        return t
    }

    // MARK: Closures

    /// The views a `@ViewBuilder` argument makes, shown. Without a reference:
    /// the first `content` parameter, else the last closure.
    func content(_ ref: KArgRef? = nil, _ closureArgs: [KV] = []) -> AnyView {
        r.renderContent(contentValue(ref), closureArgs)
    }

    /// The views it makes, as descriptions.
    func views(_ ref: KArgRef? = nil, _ closureArgs: [KV] = []) -> [KView] {
        r.content(contentValue(ref), closureArgs)
    }

    func contentValue(_ ref: KArgRef?) -> KV? {
        if let ref { return self[ref] }
        return param(ofKind: .content) ?? a.lastFunction
    }

    /// Runs the closure on an event, with its own step budget.
    func action(_ ref: KArgRef) -> () -> Void { r.action(self[ref]) }

    /// Calls the closure now and returns its result.
    func call(_ ref: KArgRef, _ args: [KV] = []) throws -> KV {
        guard case .function(let f)? = self[ref] else { throw fail("\(ref.description) should be a closure") }
        return try interp.call(f, args, args.map { _ in nil })
    }
}

/// A Swift type a bridge can read from an argument and write to a binding.
@MainActor
protocol KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> Self?
    /// What a binding reads when the stored value doesn't decode.
    static var placeholder: Self { get }
    /// The value to store, given what was stored before.
    func encode(like old: KV) -> KV
    static var kilnTypeName: String { get }
}

extension Bool: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> Bool? { interp.truthy(v) }
    static var placeholder: Bool { false }
    func encode(like old: KV) -> KV { .bool(self) }
    static var kilnTypeName: String { "Bool" }
}

extension String: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> String? { v.asString ?? (v.isNil ? "" : interp.describe(v)) }
    static var placeholder: String { "" }
    func encode(like old: KV) -> KV { .string(self) }
    static var kilnTypeName: String { "String" }
}

extension Double: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> Double? { v.asDouble }
    static var placeholder: Double { 0 }
    /// A `Slider` on an `Int` writes whole numbers back.
    func encode(like old: KV) -> KV {
        if case .int = old { return .int(Int(self.rounded())) }
        return .double(self)
    }
    static var kilnTypeName: String { "Double" }
}

extension Int: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> Int? { v.asInt }
    static var placeholder: Int { 0 }
    func encode(like old: KV) -> KV { .int(self) }
    static var kilnTypeName: String { "Int" }
}

extension CGFloat: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> CGFloat? { v.cg }
    static var placeholder: CGFloat { 0 }
    func encode(like old: KV) -> KV { .double(Double(self)) }
    static var kilnTypeName: String { "CGFloat" }
}

extension Date: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> Date? {
        if case .native(.date(let d)) = v { return d }
        return nil
    }
    static var placeholder: Date { Date() }
    func encode(like old: KV) -> KV { .native(.date(self)) }
    static var kilnTypeName: String { "Date" }
}

extension Color: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> Color? { KRenderer(interp: interp).color(v) }
    static var placeholder: Color { .blue }
    func encode(like old: KV) -> KV { .native(.color(self)) }
    static var kilnTypeName: String { "Color" }
}

extension URL: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> URL? {
        if case .native(.url(let u)) = v { return u }
        return v.asString.flatMap { URL(string: $0) }
    }
    static var placeholder: URL { URL(string: "about:blank")! }
    func encode(like old: KV) -> KV { .native(.url(self)) }
    static var kilnTypeName: String { "URL" }
}

extension Angle: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> Angle? { KRenderer(interp: interp).angle(v) }
    static var placeholder: Angle { .zero }
    func encode(like old: KV) -> KV { .native(.angle(degrees)) }
    static var kilnTypeName: String { "Angle" }
}

extension KV: KBridgeable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> KV? { v }
    static var placeholder: KV { .nilValue }
    func encode(like old: KV) -> KV { self }
    static var kilnTypeName: String { "Any" }
}

extension ClosedRange: KBridgeable where Bound: KBridgeable & Comparable {
    static func decode(_ v: KV, _ interp: KInterpreter) -> ClosedRange<Bound>? {
        guard case .range(let lo, let hi, let closed) = v, let l = Bound.decode(lo, interp), var h = Bound.decode(hi, interp) else { return nil }
        // `0..<10` over Ints is `0...9`.
        if !closed, case .int(let i) = hi, let below = Bound.decode(.int(i - 1), interp) { h = below }
        return l...Swift.max(l, h)
    }
    static var placeholder: ClosedRange<Bound> { Bound.placeholder...Bound.placeholder }
    func encode(like old: KV) -> KV { .range(lowerBound.encode(like: .void), upperBound.encode(like: .void), closed: true) }
    static var kilnTypeName: String { "ClosedRange<\(Bound.kilnTypeName)>" }
}

extension KCall {
    /// The member's own name: `count` in `String.count`.
    var memberName: String { name.split(separator: ".").last.map(String.init) ?? name }

    /// "Value of type 'Range' has no member 'count'": for a member that
    /// doesn't apply to this value.
    func noMember() -> KERuntimeError {
        KERuntimeError(message: "Value of type '\(receiver.typeName)' has no member '\(memberName)'", line: line)
    }

    /// The `n`th argument as written (labels ignored), or nil.
    func at(_ n: Int) -> KV? { n < args.count ? args[n] : nil }

    /// The argument with this label as written, or nil (for lenient overloads
    /// that also take it unlabeled: `arg("of") ?? at(0)`).
    func arg(_ label: String) -> KV? { labels.firstIndex(of: label).map { args[$0] } }
}

extension KInterpreter {
    /// A closure argument as something to call on each element: a closure, a
    /// key path (`\.name`), an initializer (`String.init`), a type.
    func applier(_ f: KV, _ line: Int) throws -> (KV) throws -> KV {
        switch f {
        case .function(let fun): return { [unowned self] x in try self.call(fun, [x], [nil]) }
        case .native(.keyPath(let comps)):
            return { [unowned self] x in
                var v = x
                for c in comps where c != "self" { v = try self.member(v, c, line: line) }
                return v
            }
        case .type(.user(let t)):
            return { [unowned self] x in try self.instantiate(t, args: [x], labels: [nil], line: line) }
        case .type(.builtin(let n)):
            return { [unowned self] x in try self.callNamedValues(n, [x], [nil], line) }
        default:
            throw fail("Expected a closure, found \(describe(f))", line)
        }
    }

    /// `Name(values…)` for a native type or function, with values in hand.
    func callNamedValues(_ name: String, _ args: [KV], _ labels: [String?], _ line: Int) throws -> KV {
        if let f = registry.function(name) { return try runBridge(f.forms, name, values: args, labels: labels, line: line).0 }
        if let t = registry.type(name), !t.inits.isEmpty { return try runBridge(t.inits, name, values: args, labels: labels, line: line).0 }
        if let style = Self.styleName(name) { return .native(.implicit(style, args)) }
        throw fail("Cannot find '\(name)' in scope", line)
    }
}

extension KCall {
    /// The native object a method or property is called on.
    func object<T>(_ type: T.Type) -> T? {
        if case .native(.object(_, let ref)) = receiver { return ref.value as? T }
        return nil
    }

    /// The date a method is called on.
    var receiverDate: Date {
        if case .native(.date(let d)) = receiver { return d }
        return Date()
    }
}
