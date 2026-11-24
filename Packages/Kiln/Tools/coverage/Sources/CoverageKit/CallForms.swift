// Every SDK initializer and modifier as a call sees it: each parameter's
// label, whether it has a default, and whether a closure can reach it, for
// Kiln's call-forms audit (Packages/Kiln/Tests/KilnTests/CallFormsAuditTests.swift).
//
// The audit writes each declaration the ways models do (required arguments
// only, with optional closures, trailing closures, everything labeled), works
// out where Swift binds each argument, and checks Kiln binds it to the same
// parameter. This file is the SDK half; the binding is Kiln's own code.

import Foundation

/// One parameter of an SDK call.
public struct CallParam: Codable, Equatable, Sendable {
    /// `_` when unlabeled.
    public var label: String
    public var type: String
    /// A letter per property:
    /// - `d`: it has a default, so a call can leave it out;
    /// - `f`: a function type (through optionals): a closure is written for it;
    /// - `t`: an unlabeled trailing closure can bind to it (SE-0286: a
    ///   function, a result builder, or `Any`);
    /// - `b`: a result builder (`@ViewBuilder`);
    /// - `v`: variadic; `i`: `inout`; `a`: `@autoclosure`.
    public var flags: String

    public init(label: String, type: String, flags: String) {
        self.label = label
        self.type = type
        self.flags = flags
    }

    init(_ p: Param) {
        label = p.label ?? "_"
        let raw = p.type.trimmingCharacters(in: .whitespaces)
        var t = raw
        var isInout = false, isAuto = false
        // Attributes and ownership in the type: `@escaping @Sendable () -> Void`, `inout`, `sending`.
        while true {
            if t.hasPrefix("@") {
                let name = t.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
                if name.hasSuffix("autoclosure") { isAuto = true }
                t = String(t.dropFirst(1 + name.count))
                if t.hasPrefix("(") { t = String(t.dropFirst(CallParam.balanced(t))) }
                t = t.trimmingCharacters(in: .whitespaces)
                continue
            }
            var stripped = false
            for w in ["inout ", "__owned ", "__shared ", "sending ", "borrowing ", "consuming "] where t.hasPrefix(w) {
                if w == "inout " { isInout = true }
                t = String(t.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
                stripped = true
            }
            if !stripped { break }
        }
        type = t
        let variadic = t.hasSuffix("...")
        let builder = p.attributes.contains { $0.hasSuffix("Builder") }
        let function = !isAuto && CallParam.isFunction(t)
        // A bare `Any` could be a function too. (Swift also lets the scan stop
        // at a bare type parameter, `T` or `some P`; when one there can't be a
        // function, `Slider(value:in:) { editing in … }`'s `step: V.Stride`,
        // the call only type-checks with the closure on the function after
        // it, so a type parameter doesn't count here.)
        let generic = t == "Any" || t == "AnyObject"
        var f = ""
        if p.hasDefault { f += "d" }
        if function { f += "f" }
        if !isInout && (function || builder || generic) { f += "t" }
        if builder { f += "b" }
        if variadic { f += "v" }
        if isInout { f += "i" }
        if isAuto { f += "a" }
        flags = f
    }

    public var hasDefault: Bool { flags.contains("d") }
    public var isFunction: Bool { flags.contains("f") }
    public var takesTrailingClosure: Bool { flags.contains("t") }
    public var isBuilder: Bool { flags.contains("b") }
    public var isVariadic: Bool { flags.contains("v") }
    /// Swift needs an argument for it: no default, not variadic.
    public var isRequired: Bool { !hasDefault && !isVariadic }

    // MARK: Types

    /// The length of the balanced (), [] or <> group at the start of `s`
    /// (the `>` of an arrow doesn't close one).
    static func balanced(_ s: String) -> Int {
        var depth = 0
        var n = 0
        var previous: Character = " "
        for ch in s {
            n += 1
            if "([<".contains(ch) { depth += 1 }
            if ")]".contains(ch) || (ch == ">" && previous != "-") { depth -= 1; if depth == 0 { return n } }
            previous = ch
        }
        return n
    }

    /// `(() -> Void)?` → `() -> Void`; `Optional<T>` → `T`.
    static func unwrapOptional(_ t: String) -> String {
        var t = t.trimmingCharacters(in: .whitespaces)
        while true {
            if t.hasSuffix("?") || t.hasSuffix("!") { t.removeLast(); t = t.trimmingCharacters(in: .whitespaces); continue }
            if t.hasPrefix("Optional<"), t.hasSuffix(">") { t = String(t.dropFirst("Optional<".count).dropLast()); continue }
            if t.hasPrefix("("), balanced(t) == t.count, !topLevelComma(String(t.dropFirst().dropLast())) {
                t = String(t.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            return t
        }
    }

    static func topLevelComma(_ s: String) -> Bool {
        var depth = 0
        var previous: Character = " "
        for ch in s {
            if "([<".contains(ch) { depth += 1 } else if ")]".contains(ch) || (ch == ">" && previous != "-") { depth -= 1 } else if ch == ",", depth == 0 { return true }
            previous = ch
        }
        return false
    }

    /// A function type, through optionals and attributes: `@escaping (A) -> B`, `((A) async throws -> B)?`.
    static func isFunction(_ t: String) -> Bool {
        var s = unwrapOptional(t)
        while s.hasPrefix("@") {
            let name = s.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
            s = String(s.dropFirst(1 + name.count))
            // `@isolated(any)`: arguments right after the name, with no space.
            if s.hasPrefix("(") { s = String(s.dropFirst(balanced(s))) }
            s = s.trimmingCharacters(in: .whitespaces)
        }
        guard s.hasPrefix("(") else { return false }
        // `(A, B) -> C`: an arrow at depth 0 after the parameter list.
        let chars = Array(s)
        var depth = 0
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "(" || ch == "[" || ch == "<" { depth += 1 }
            else if ch == ")" || ch == "]" || (ch == ">" && (i == 0 || chars[i - 1] != "-")) { depth -= 1 }
            else if ch == "-", i + 1 < chars.count, chars[i + 1] == ">", depth == 0 { return true }
            i += 1
        }
        return false
    }
}

/// One SDK call the audit writes forms of.
public struct CallForm: Codable, Equatable, Sendable {
    /// The coverage id: `view:ShareLink`, `modifier:sheet`, `modifier:ChartContent.foregroundStyle`.
    public var id: String
    /// What it's called on, for a modifier (`View`, `Shape`, `ChartContent`).
    public var receiver: String?
    public var introduced: String?
    public var deprecated: Bool
    public var signature: String
    public var params: [CallParam]
}

public enum CallForms {
    /// The kinds whose calls are audited: views, content, gestures and modifiers.
    static let kinds: Set<SymbolKind> = [.view, .content, .gesture, .modifier]

    public static func forms(_ catalog: Catalog) -> [CallForm] {
        var out: [CallForm] = []
        for s in catalog.symbols where kinds.contains(s.kind) {
            for o in s.overloads {
                // Views', content's and gestures' overloads are their initializers.
                if s.kind != .modifier && !o.signature.hasPrefix("init") { continue }
                out.append(CallForm(id: s.id, receiver: o.receiver, introduced: o.introduced, deprecated: o.deprecated,
                                    signature: o.signature, params: o.call))
            }
        }
        return out
    }

    /// One form per line, so a new SDK reads as a small diff.
    public static func json(_ forms: [CallForm], sdk: String) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var lines: [String] = []
        for f in forms { lines.append(String(decoding: try e.encode(f), as: UTF8.self)) }
        let header = String(decoding: try e.encode(["sdk": sdk, "about": "Written by Tools/coverage.sh; read by CallFormsAuditTests. See CoverageKit/CallForms.swift."]), as: UTF8.self)
        return Data(("{\"header\":" + header + ",\n\"forms\":[\n" + lines.joined(separator: ",\n") + "\n]}\n").utf8)
    }
}
