//
//  KEBuilders.swift
//  Kiln's engine
//
//  Result builders (PLAN.md §1.6). SwiftUI's `@ViewBuilder` (and its
//  toolbar, chart and scene siblings) is the engine's own `evalBuilder`,
//  which keeps `if` and `switch` branches apart for SwiftUI's identity. Any
//  other builder is a `KBuilder`: one the app declares with `@resultBuilder`,
//  or one a bridge registers (RegexBuilder's, §3.3). The transform is Swift's:
//
//      buildExpression    each expression statement, when the builder has it
//      buildBlock         the statements of a block (or buildPartialBlock)
//      buildOptional      `if` without `else`
//      buildEither        `if`/`else`, `else if` and `switch`, as a balanced tree
//      buildArray         `for … in`
//      buildLimitedAvailability   `if #available`
//      buildFinalResult   the whole body
//
//  It applies to functions, methods and computed properties marked with the
//  builder's attribute, to closures passed to a parameter marked with it, and
//  to closures that a memberwise initializer stores into a marked property.
//

import SwiftUI

/// A result builder's static methods, however they're implemented.
@MainActor
protocol KBuilder: AnyObject {
    var name: String { get }
    func has(_ method: String) -> Bool
    /// `buildEither(first:)` is `call("buildEither", ["first"], [v])`.
    func call(_ method: String, _ labels: [String?], _ args: [KV], line: Int) throws -> KV
}

/// Which builder a declaration or parameter names.
enum KBuilderRef {
    /// `@ViewBuilder` and SwiftUI's other content builders.
    case view
    case custom(KBuilder)
}

/// One the app declares: `@resultBuilder struct ListBuilder { static func buildBlock(…) }`.
final class KUserBuilder: KBuilder {
    let type: KType
    unowned let interp: KInterpreter
    init(_ type: KType, _ interp: KInterpreter) {
        self.type = type
        self.interp = interp
    }
    var name: String { type.name }
    func has(_ method: String) -> Bool { type.staticMethods[method] != nil }

    func call(_ method: String, _ labels: [String?], _ args: [KV], line: Int) throws -> KV {
        let candidates = (type.staticMethods[method] ?? []).filter { KInterpreter.labelsFit($0.params, labels) }
        // Overloads by type (`buildExpression(_: String)`, `buildExpression(_: Int)`): the one the value fits.
        let decl = candidates.first { d in
            zip(d.params, args).allSatisfy { p, v in p.type.map { interp.fits(v, $0) } ?? true }
        } ?? candidates.first
        guard let decl else {
            throw interp.fail("Result builder '\(type.name)' has no \(method)(\(labels.map { ($0 ?? "_") + ":" }.joined()))", line)
        }
        let ctx = KSelfContext(type: type, location: .box(KBox(.type(.user(type)))), isStatic: true)
        return try interp.invoke(decl, args: args, labels: labels, selfContext: ctx, parent: interp.globalEnv)
    }
}

/// One a bridge registers (`r.resultBuilder("RegexComponentBuilder") { b in … }`).
final class KNativeBuilder: KBuilder {
    typealias Method = @MainActor (_ args: [KV], _ labels: [String?], _ interp: KInterpreter) throws -> KV
    let name: String
    let family: KilnFamily
    var methods: [String: Method] = [:]
    weak var interp: KInterpreter?
    init(name: String, family: KilnFamily) {
        self.name = name
        self.family = family
    }
    func has(_ method: String) -> Bool { methods[method] != nil }
    func call(_ method: String, _ labels: [String?], _ args: [KV], line: Int) throws -> KV {
        guard let f = methods[method], let interp else { throw KERuntimeError(message: "\(name) has no \(method)", line: line) }
        return try f(args, labels, interp)
    }

    /// Declares one of the builder's static methods: `"buildBlock"`, `"buildEither"`…
    func method(_ name: String, _ f: @escaping Method) { methods[name] = f }
}

extension KInterpreter {

    /// The builder an attribute list names, if any.
    func builder(_ attrs: [KEAttribute]) -> KBuilderRef? {
        for a in attrs {
            if Self.viewBuilders.contains(a.name) { return .view }
            if let t = types[a.name], t.attributes.contains(where: { $0.name == "resultBuilder" }) {
                if t.userBuilder == nil { t.userBuilder = KUserBuilder(t, self) }
                return .custom(t.userBuilder!)
            }
            if let b = registry.resultBuilders[a.name] {
                b.interp = self
                return .custom(b)
            }
        }
        return nil
    }

    nonisolated static let viewBuilders: Set<String> = ["ViewBuilder", "ToolbarContentBuilder", "ChartContentBuilder", "SceneBuilder",
                                                        "CommandsBuilder", "TableRowBuilder", "TableColumnBuilder", "TabContentBuilder",
                                                        "AccessibilityRotorContentBuilder"]

    /// A closure that runs as a builder when it's called.
    func builderClosure(_ v: KV, _ b: KBuilderRef) -> KV {
        guard case .function(let f) = v, case .closure = f.kind, f.builder == nil else { return v }
        let g = KFunction(f.kind)
        g.builder = b
        return .function(g)
    }

    /// A body run through a builder.
    func runBuilt(_ b: KBuilderRef, _ stmts: [KEStmt], _ env: KEnv, line: Int) throws -> KV {
        switch b {
        case .view:
            return .view(KView.group(try evalBuilder(stmts, env)))
        case .custom(let builder):
            let v = try builtBlock(builder, stmts, env, line: line)
            return builder.has("buildFinalResult") ? try builder.call("buildFinalResult", [nil], [v], line: line) : v
        }
    }

    /// The statements of one block, as the builder combines them.
    private func builtBlock(_ b: KBuilder, _ stmts: [KEStmt], _ env: KEnv, line: Int) throws -> KV {
        var parts: [KV] = []
        for s in stmts {
            try tick()
            let at = Self.line(of: s) > 0 ? Self.line(of: s) : line
            switch s {
            case .expr(let e):
                // A call that returns nothing (`print`) is a statement, not a component.
                if case .assign = e { _ = try eval(e, env); continue }
                let v = try eval(e, env)
                if case .void = v { continue }
                parts.append(b.has("buildExpression") ? try b.call("buildExpression", [nil], [v], line: at) : v)
            case .ifStmt(let conds, let then, let elseClause):
                parts.append(try builtIf(b, conds, then, elseClause, env, line: at))
            case .switchStmt(let subject, let cases):
                let value = try eval(subject, env)
                var picked: (Int, [KEStmt], KEnv)?
                for (i, c) in cases.enumerated() {
                    let scope = KEnv(parent: env)
                    var hit = c.isDefault
                    if !hit {
                        for (p, w) in c.patterns {
                            let trial = KEnv(parent: env)
                            if try match(p, value, trial, binding: false), try w.map({ truthy(try eval($0, trial)) }) ?? true {
                                scope.vars = trial.vars
                                hit = true
                                break
                            }
                        }
                    }
                    if hit { picked = (i, c.body, scope); break }
                }
                guard let (i, body, scope) = picked else { throw fail("No case of the switch matched", at) }
                parts.append(try either(b, try builtBlock(b, body, scope, line: at), index: i, count: cases.count, line: at))
            case .forIn(let pattern, let seq, let whereClause, let body, _):
                var items: [KV] = []
                for item in try sequence(try eval(seq, env)) {
                    let scope = KEnv(parent: env)
                    guard try match(pattern, item, scope, binding: true) else { continue }
                    if let w = whereClause, !truthy(try eval(w, scope)) { continue }
                    items.append(try builtBlock(b, body, scope, line: at))
                }
                guard b.has("buildArray") else { throw fail("Result builder '\(b.name)' has no buildArray(_:), so it can't take a 'for' loop", at) }
                parts.append(try b.call("buildArray", [nil], [.array(items)], line: at))
            default:
                if case .ret = try exec1(s, env) { throw fail("'return' can't be used inside a \(b.name) body", at) }
            }
        }
        if b.has("buildPartialBlock"), let first = parts.first {
            var acc = try b.call("buildPartialBlock", ["first"], [first], line: line)
            for p in parts.dropFirst() { acc = try b.call("buildPartialBlock", ["accumulated", "next"], [acc, p], line: line) }
            return acc
        }
        return try b.call("buildBlock", parts.map { _ in nil }, parts, line: line)
    }

    private func builtIf(_ b: KBuilder, _ conds: [KECondition], _ then: [KEStmt], _ elseClause: KEElse?, _ env: KEnv, line: Int) throws -> KV {
        let scope = KEnv(parent: env)
        let taken = try conditions(conds, scope)
        let limited = conds.contains { if case .available = $0 { return true }; return false } && b.has("buildLimitedAvailability")
        func thenValue() throws -> KV {
            let v = try builtBlock(b, then, scope, line: line)
            return limited ? try b.call("buildLimitedAvailability", [nil], [v], line: line) : v
        }
        guard let elseClause else {
            guard b.has("buildOptional") else { throw fail("Result builder '\(b.name)' has no buildOptional(_:), so it can't take an 'if' without 'else'", line) }
            return try b.call("buildOptional", [nil], [taken ? try thenValue() : .nilValue], line: line)
        }
        guard b.has("buildEither") else { throw fail("Result builder '\(b.name)' has no buildEither(first:) and buildEither(second:), so it can't take 'if'/'else'", line) }
        if taken { return try b.call("buildEither", ["first"], [try thenValue()], line: line) }
        let other: KV
        switch elseClause {
        case .block(let body): other = try builtBlock(b, body, KEnv(parent: env), line: line)
        case .elseIf(.ifStmt(let c, let t, let e)): other = try builtIf(b, c, t, e, env, line: line)
        case .elseIf(let s): other = try builtBlock(b, [s], env, line: line)
        }
        return try b.call("buildEither", ["second"], [other], line: line)
    }

    /// Case `index` of `count`, wrapped in `buildEither` as a balanced tree, as Swift does for `switch`.
    private func either(_ b: KBuilder, _ v: KV, index: Int, count: Int, line: Int) throws -> KV {
        if count <= 1 { return v }
        guard b.has("buildEither") else { throw fail("Result builder '\(b.name)' has no buildEither(first:) and buildEither(second:), so it can't take a 'switch'", line) }
        let half = (count + 1) / 2
        if index < half { return try b.call("buildEither", ["first"], [try either(b, v, index: index, count: half, line: line)], line: line) }
        return try b.call("buildEither", ["second"], [try either(b, v, index: index - half, count: count - half, line: line)], line: line)
    }

    /// Whether a value fits a declared type well enough to pick an overload by it.
    func fits(_ v: KV, _ t: KETypeRef) -> Bool {
        switch t.core {
        case .array: if case .array = v { return true }; return false
        case .dictionary: if case .dict = v { return true }; return false
        case .function: if case .function = v { return true }; return false
        case .tuple: if case .tuple = v { return true }; return false
        case .named(let n, _):
            if n.count == 1 || n == "Any" || n == "Self" || n == "Component" || n == "Expression" { return true }
            if v.isNil { return t.isOptional }
            if case .int = v, ["Double", "CGFloat", "Float"].contains(n) { return true }
            if case .array = v, n == "Array" || n == "Set" { return true }
            return conforms(v, t)
        default: return true
        }
    }
}
