//
//  KEStdlib.swift
//  Kiln's engine
//
//  The language features Round 2C adds (PLAN.md §3, Round 2C): what Swift
//  does with the app's own types when it uses them as the standard library
//  does: `$0`/`$1` from one tuple, an app's `Sequence`, `callAsFunction`,
//  `@dynamicMemberLookup`, key paths read and written, subscript setters,
//  and printing optionals as `Optional(5)`.
//

import SwiftUI

// MARK: - `$n` in closures

/// The highest `$n` a closure's body uses (not counting closures inside it):
/// `{ "\($0)\($1)" }` given one pair takes its two halves, as Swift does.
enum KEClosureScan {
    static func maxAnonymous(_ c: KEClosure) -> Int {
        if let cached = c.anonymousMaxCache { return cached }
        var m = -1
        stmts(c.body) { e in
            if case .ident(let n, _) = e, n.hasPrefix("$"), let i = Int(n.dropFirst()) { m = max(m, i) }
        }
        c.anonymousMaxCache = m
        return m
    }

    static func stmts(_ s: [KEStmt], _ f: (KEExpr) -> Void) { for x in s { stmt(x, f) } }

    static func stmt(_ s: KEStmt, _ f: (KEExpr) -> Void) {
        switch s {
        case .expr(let e), .throwStmt(let e): expr(e, f)
        case .variable(let d): if let e = d.initial { expr(e, f) }
        case .assign(_, let t, let v, _): expr(t, f); expr(v, f)
        case .ifStmt(let c, let t, let e):
            conds(c, f); stmts(t, f)
            switch e {
            case .block(let b)?: stmts(b, f)
            case .elseIf(let s)?: stmt(s, f)
            case nil: break
            }
        case .guardStmt(let c, let b): conds(c, f); stmts(b, f)
        case .switchStmt(let subject, let cases):
            expr(subject, f)
            for c in cases {
                stmts(c.body, f)
                for (p, w) in c.patterns { pattern(p, f); if let w { expr(w, f) } }
            }
        case .forIn(let p, let seq, let w, let body, _): pattern(p, f); expr(seq, f); if let w { expr(w, f) }; stmts(body, f)
        case .whileStmt(let c, let b, _): conds(c, f); stmts(b, f)
        case .repeatWhile(let b, let c, _): stmts(b, f); expr(c, f)
        case .returnStmt(let e, _): if let e { expr(e, f) }
        case .doCatch(let b, let cs): stmts(b, f); for c in cs { stmts(c.body, f) }
        case .deferStmt(let b): stmts(b, f)
        case .declaration, .breakStmt, .continueStmt, .fallthroughStmt: break
        }
    }

    static func conds(_ cs: [KECondition], _ f: (KEExpr) -> Void) {
        for c in cs {
            switch c {
            case .expr(let e), .optionalBinding(_, let e): expr(e, f)
            case .casePattern(let p, let e): pattern(p, f); expr(e, f)
            case .available: break
            }
        }
    }

    static func pattern(_ p: KEPattern, _ f: (KEExpr) -> Void) {
        switch p {
        case .expression(let e): expr(e, f)
        case .tuple(let ps), .enumCase(_, _, let ps): for q in ps { pattern(q, f) }
        case .optional(let q), .cast(let q, _): pattern(q, f)
        case .wildcard, .binding, .typeCheck: break
        }
    }

    static func expr(_ e: KEExpr, _ f: (KEExpr) -> Void) {
        f(e)
        switch e {
        case .closure, .int, .double, .bool, .nilLit, .ident, .implicitMember, .keyPath, .selfRef, .typeExpr, .value, .regex:
            break
        case .string(let segs):
            for s in segs { if case .interp(let args) = s { for a in args { expr(a.value, f) } } }
        case .member(let b, _, _), .optionalChain(let b), .prefix(_, let b), .postfix(_, let b), .cast(let b, _, _),
             .tryExpr(_, let b), .awaitExpr(let b):
            expr(b, f)
        case .call(let c, let args, _), .subscriptAccess(let c, let args, _):
            expr(c, f); for a in args { expr(a.value, f) }
        case .binary(_, let l, let r, _): expr(l, f); expr(r, f)
        case .ternary(let a, let b, let c): expr(a, f); expr(b, f); expr(c, f)
        case .array(let xs): for x in xs { expr(x, f) }
        case .dictionary(let ps): for (k, v) in ps { expr(k, f); expr(v, f) }
        case .tuple(let xs): for (_, x) in xs { expr(x, f) }
        case .ifExpr(let c, let t, let o): conds(c, f); stmts(t, f); stmts(o, f)
        case .switchExpr(let s, let cases): expr(s, f); for c in cases { stmts(c.body, f) }
        case .assign(_, let t, let v, _): expr(t, f); expr(v, f)
        }
    }
}

// MARK: - Native sequences

/// A native value that can be looped over (`for x in it`, `Array(it)`):
/// an `AnyIterator`, a `Data`'s bytes, a SIMD vector's scalars.
protocol KNativeSequence {
    @MainActor func elements(_ interp: KInterpreter) throws -> [KV]
}

/// A native number that isn't an `Int` or a `Double` (`UInt8`, `Int32`):
/// it reads as one wherever a number is read (`Data([b])`, `Int(b)`, `b < 5`).
protocol KNumericBox {
    var intValue: Int? { get }
    var doubleValue: Double { get }
}

extension KInterpreter {

    // MARK: - The app's sequences

    /// The elements of an app value that's a `Sequence` or an `IteratorProtocol`:
    /// its `makeIterator()`, then `next()` until nil. nil when it isn't one.
    func userSequenceElements(_ v: KV) throws -> [KV]? {
        guard let t = v.userType else { return nil }
        var iterator: KV
        if let make = t.methods["makeIterator"]?.first(where: { $0.params.isEmpty }) {
            iterator = try invoke(make, args: [], labels: [], selfContext: KSelfContext(type: t, location: .box(KBox(v))), parent: globalEnv)
        } else if t.methods["next"] != nil {
            iterator = v
        } else {
            return nil
        }
        guard let it = iterator.userType, let next = it.methods["next"]?.first(where: { $0.params.isEmpty }) else {
            return try sequence(iterator)
        }
        let box = KBox(iterator)
        var out: [KV] = []
        while true {
            let r = try invoke(next, args: [], labels: [], selfContext: KSelfContext(type: it, location: .box(box)), parent: globalEnv)
            if r.isNil { break }
            out.append(r)
            if out.count > 1_000_000 { throw fail("This sequence has too many elements to use here") }
        }
        return out
    }

    /// Whether an app type is a sequence (it has `makeIterator()` or `next()`).
    func isUserSequence(_ t: KType) -> Bool {
        t.methods["makeIterator"] != nil || t.methods["next"] != nil
    }

    // MARK: - callAsFunction

    /// `adder(5)`: a value whose type has `callAsFunction`. `location` is where
    /// it lives, so a `mutating` one writes back.
    func callAsFunction(_ v: KV, location: KLocation?, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV? {
        guard let t = v.userType, let ms = t.methods["callAsFunction"] else { return nil }
        let labels = argExprs.map(\.label)
        guard let m = Self.fit(ms, labels, closures: Self.closureFlags(argExprs)) else {
            try requireLabels(nil, among: ms, labels, closures: Self.closureFlags(argExprs), name: "callAsFunction", owner: t.name, line: line)
            return nil
        }
        let args = try evalArgs(argExprs, env, params: m.params)
        return try invoke(m, args: args, labels: labels, selfContext: KSelfContext(type: t, location: location ?? .box(KBox(v))), parent: globalEnv)
    }

    // MARK: - Subscripts on the app's types

    /// The subscript these labels call: by its parameters' labels.
    func userSubscript(_ t: KType, _ labels: [String?], isStatic: Bool = false) -> KEFuncDecl? {
        let subs = t.subscripts.filter { $0.isStatic == isStatic }
        return Self.fit(subs, labels) ?? (labels.allSatisfy { $0 == nil } ? subs.first(where: { $0.params.first?.label == nil }) : nil)
    }

    /// `value[keyPath: \.a.b]`, read.
    func keyPathGet(_ base: KV, _ path: KV, _ line: Int) throws -> KV? {
        guard case .native(.keyPath(let comps)) = path else { return nil }
        var v = base
        for c in comps where c != "self" { v = try member(v, c, line: line) }
        return v
    }

    /// Where `value[keyPath: \.a.b]` lives, for a write.
    func keyPathLocation(_ base: KLocation, _ path: KV) throws -> KLocation? {
        guard case .native(.keyPath(let comps)) = path else { return nil }
        var loc = base
        for c in comps where c != "self" { loc = try memberLocation(loc, c) }
        return loc
    }

    /// The location a subscript on an app value stands for: its getter and
    /// setter, with `self` where the value lives (so a struct's setter writes back).
    func userSubscriptLocation(_ baseLoc: KLocation, _ base: KV, _ idx: [KV], _ labels: [String?], _ line: Int) throws -> KLocation? {
        let t: KType
        let isStatic: Bool
        switch base {
        case .type(.user(let ut)): t = ut; isStatic = true
        default:
            guard let ut = base.userType else { return nil }
            t = ut; isStatic = false
        }
        guard let sub = userSubscript(t, labels, isStatic: isStatic) else { return nil }
        let ctx = KSelfContext(type: t, location: isStatic ? .box(KBox(base)) : baseLoc, isStatic: isStatic)
        return .computed(get: { [unowned self] in
            try self.invoke(sub, args: idx, labels: labels, selfContext: ctx, parent: self.globalEnv)
        }, set: { [unowned self] v in
            guard let setter = sub.setter else { throw self.fail("Cannot assign through subscript: it's get-only", line) }
            let env = KEnv(parent: self.globalEnv, selfContext: ctx)
            try self.bindParameters(sub.params, args: idx, labels: labels, into: env, name: "subscript")
            env.declare(setter.0, self.coerce(v, to: sub.returnType))
            _ = try self.exec(setter.1, env)
        })
    }

    // MARK: - @dynamicMemberLookup

    /// `wrapper.name` on a `@dynamicMemberLookup` type with no member `name`:
    /// its `subscript(dynamicMember:)`, given the name or a key path to it.
    func dynamicMemberLocation(_ base: KV, _ name: String, _ baseLoc: KLocation) -> KLocation? {
        guard let t = base.userType, t.attributes.contains(where: { $0.name == "dynamicMemberLookup" }),
              let sub = t.subscripts.first(where: { !$0.isStatic && $0.params.first?.label == "dynamicMember" }) else { return nil }
        let byKeyPath = sub.params.first?.type?.name.map { $0.hasSuffix("KeyPath") } ?? false
        let arg: KV = byKeyPath ? .native(.keyPath([name])) : .string(name)
        return try? userSubscriptLocation(baseLoc, base, [arg], ["dynamicMember"], 0)
    }

    // MARK: - Printing optionals

    /// What Swift knows of an expression's type, where it matters for
    /// printing: whether it's an optional (`Optional(5)`), and inside arrays,
    /// dictionaries and tuples. nil when it can't tell, which prints the value plainly.
    func staticType(_ e: KEExpr, _ env: KEnv) -> KETypeRef? {
        let any = KETypeRef.named("Any", [])
        switch e {
        case .ident(let n, _):
            if let box = env.lookup(n) { return box.declaredType }
            if let ctx = env.nearestSelf, !ctx.isStatic { return ctx.type.propertyType(n) }
            return globalEnv.vars[n]?.declaredType
        case .member(.ident("Optional", _), "none", _):
            return .optional(any)
        case .call(.ident("Optional", _), let args, _), .call(.member(.ident("Optional", _), "some", _), let args, _):
            return .optional(args.first.flatMap { staticType($0.value, env) } ?? any)
        case .call(.typeExpr(.named("Optional", let g)), _, _):
            return .optional(g.first ?? any)
        case .tryExpr("try?", let x):
            let inner = staticType(x, env) ?? any
            return inner.isOptional ? inner : .optional(inner)
        case .cast(let x, "as", let t):
            // `x as Any` keeps what `x` is: an optional prints `Optional(…)`.
            if t.name == "Any" || t.name == "AnyObject" { return staticType(x, env) }
            return t
        case .cast(_, "as?", let t): return .optional(t)
        case .postfix("!", _): return nil
        case .member(let base, let name, _):
            if containsOptionalChain(base) { return .optional(any) }
            if case .selfRef = base, let ctx = env.nearestSelf, !ctx.isStatic { return ctx.type.propertyType(name) }
            if let t = peekUserType(base, env) { return t.propertyType(name) }
            if name == "first" || name == "last", peekIsCollection(base, env) { return .optional(any) }
            // Native properties that are optional collections: `.map` on them is Optional's.
            if name == "regularFileContents" || name == "fileWrappers" { return .optional(any) }
            return nil
        case .call(.member(let base, let name, _), let args, _):
            if containsOptionalChain(base) { return .optional(any) }
            if let t = peekUserType(base, env) {
                return Self.fit(t.methods[name] ?? [], args.map(\.label))?.returnType
            }
            let optional: Set<String> = ["first", "last", "min", "max", "randomElement", "popLast", "firstIndex", "lastIndex", "index"]
            if optional.contains(name), peekIsCollection(base, env) { return .optional(any) }
            // A string's searches find nothing as nil.
            let searches: Set<String> = ["range", "firstRange", "rangeOfCharacter", "firstMatch", "wholeMatch", "prefixMatch"]
            if searches.contains(name), peekUserType(base, env) == nil { return .optional(any) }
            return nil
        case .call(.ident(let n, _), let args, _):
            if env.lookup(n) == nil, let f = Self.fit(functions[n] ?? [], args.map(\.label)) { return f.returnType }
            if ["Int", "Double", "Float", "Bool", "URL", "UUID"].contains(n), args.count == 1,
               args[0].label == nil || args[0].label == "string" || args[0].label == "uuidString" {
                if case .string = args[0].value { return .optional(.named(n, [])) }
                if case .ident(let a, _) = args[0].value, case .string? = env.lookup(a)?.value { return .optional(.named(n, [])) }
            }
            return nil
        case .subscriptAccess(let base, let args, _):
            if args.contains(where: { $0.label == "default" }) { return nil }
            if case .ident(let b, _) = base, case .dict? = env.lookup(b)?.value { return .optional(any) }
            if case .dictionary(_, let v)? = staticType(base, env)?.core { return .optional(v) }
            return nil
        default:
            return nil
        }
    }

    private func containsOptionalChain(_ e: KEExpr) -> Bool {
        switch e {
        case .optionalChain: return true
        case .member(let b, _, _), .call(let b, _, _), .subscriptAccess(let b, _, _): return containsOptionalChain(b)
        default: return false
        }
    }

    /// The app type a plain name or member chain holds, read without running anything.
    private func peekUserType(_ e: KEExpr, _ env: KEnv) -> KType? {
        switch e {
        case .ident(let n, _):
            if let v = env.lookup(n)?.value { return v.userType }
            if let ctx = env.nearestSelf, !ctx.isStatic, let tn = ctx.type.propertyType(n)?.core.name { return types[tn] }
            return nil
        case .selfRef: return env.nearestSelf.flatMap { $0.isStatic ? nil : $0.type }
        case .member(let b, let n, _):
            guard let t = peekUserType(b, env), let tn = t.propertyType(n)?.core.name else { return nil }
            return types[tn]
        default: return nil
        }
    }

    private func peekIsCollection(_ e: KEExpr, _ env: KEnv) -> Bool {
        switch e {
        case .array, .string: return true
        case .ident(let n, _):
            switch env.lookup(n)?.value {
            case .array?, .set?, .string?, .dict?, .range?: return true
            default: return false
            }
        default: return false
        }
    }

    /// A value as Swift prints it, given what's known of its type: an optional
    /// shows as `Optional(5)`, and so do the optionals inside a collection.
    func describe(_ v: KV, as t: KETypeRef?, quoted: Bool = false) -> String {
        guard let t else { return describe(v, quoted: quoted) }
        var wrapped: KETypeRef?
        if case .optional(let w) = t { wrapped = w } else if case .named("Optional", let g) = t, g.count == 1 { wrapped = g[0] }
        if let w = wrapped {
            if v.isNil { return "nil" }
            return "Optional(" + describe(v, as: w, quoted: true) + ")"
        }
        switch (t, v) {
        case (.array(let e), .array(let xs)):
            return "[" + xs.map { describe($0, as: e, quoted: true) }.joined(separator: ", ") + "]"
        case (.dictionary(let kt, let vt), .dict(let d)):
            if d.isEmpty { return "[:]" }
            return "[" + d.map { "\(describe($0.key, as: kt, quoted: true)): \(describe($0.value, as: vt, quoted: true))" }.joined(separator: ", ") + "]"
        case (.tuple(let ts, _), .tuple(let xs, let labels)) where ts.count == xs.count:
            return "(" + xs.enumerated().map { i, x in
                (labels.indices.contains(i) && labels[i] != nil ? labels[i]! + ": " : "") + describe(x, as: ts[i], quoted: true)
            }.joined(separator: ", ") + ")"
        default:
            return describe(v, quoted: quoted)
        }
    }

    /// An argument to `print` or an interpolation: its value, shown as Swift
    /// shows its static type (an optional prints `Optional(…)`).
    func evalShown(_ e: KEExpr, _ env: KEnv) throws -> KV {
        let v = try eval(e, env)
        guard let t = staticType(e, env), Self.hasOptional(t) else { return v }
        return .native(.boxed(KBoxed("Optional", KShownValue(text: describe(v, as: t), value: v))))
    }

    static func hasOptional(_ t: KETypeRef) -> Bool {
        switch t {
        case .optional: return true
        case .named("Optional", _): return true
        case .array(let e): return hasOptional(e)
        case .dictionary(let k, let v): return hasOptional(k) || hasOptional(v)
        case .tuple(let ts, _): return ts.contains(where: hasOptional)
        default: return false
        }
    }
}

/// A value printed as Swift prints it for its static type (`Optional(5)`).
/// Only `print` and string interpolation see it.
struct KShownValue: Hashable, KDescribable {
    let text: String
    let value: KV
    func describe(_ interp: KInterpreter) -> String { text }
}

extension KInterpreter {

    // MARK: - Members the app's types get from Swift

    /// A member an app value has without declaring it: a `@dynamicMemberLookup`
    /// type's dynamic member, or a `Sequence`'s (`count`, `first`, `lazy`…).
    func stdlibMember(_ base: KV, _ t: KType, _ name: String, _ line: Int) throws -> KV? {
        if let loc = dynamicMemberLocation(base, name, .box(KBox(base))) { return try read(loc) }
        if isUserSequence(t), let xs = try userSequenceElements(base) {
            return try member(.array(xs), name, line: line)
        }
        return nil
    }

    /// Cheap: whether an expression's kind can have an optional static type.
    static func mayBeOptional(_ e: KEExpr) -> Bool {
        switch e {
        case .ident, .member, .call, .subscriptAccess, .tryExpr, .cast, .optionalChain: return true
        default: return false
        }
    }

    /// `-v`, `~v`, `√v` on a value that isn't an `Int` or a `Double`: the app's
    /// `static prefix func -`, a global one, or a native type's (`prefix-`).
    func prefixOperator(_ op: String, _ v: KV, _ line: Int) throws -> KV? {
        let isOne: (KEFuncDecl) -> Bool = { $0.params.count == 1 }
        if let f = v.userType?.staticMethods[op]?.first(where: isOne) ?? functions[op]?.first(where: isOne) {
            return try invoke(f, args: [v], labels: [nil], selfContext: nil, parent: globalEnv)
        }
        if case .native = v { return try nativeOperator("prefix" + op, v, .void, line) }
        return nil
    }

    /// `opt.map { … }` where `opt` is an optional (Kiln keeps optionals
    /// unwrapped): the closure on the value, or nil. nil when this `map` isn't Optional's.
    func optionalMap(_ baseExpr: KEExpr, _ base: KV, _ name: String, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV? {
        guard name == "map" || name == "flatMap", argExprs.count == 1 else { return nil }
        let staticOptional = staticType(baseExpr, env)?.isOptional ?? false
        let isCollection: Bool
        switch base {
        case .array, .set, .dict, .string, .range: isCollection = true
        case .int, .double, .bool, .tuple: isCollection = false
        case .structV, .enumV, .object: isCollection = base.userType.map(isUserSequence) ?? false
        default: return staticOptional && !base.isNil ? try applyOptionalMap(base, argExprs, env, line) : nil
        }
        if base.isNil { return staticOptional ? .nilValue : nil }
        guard staticOptional || !isCollection else { return nil }
        return try applyOptionalMap(base, argExprs, env, line)
    }

    private func applyOptionalMap(_ base: KV, _ argExprs: [KEArg], _ env: KEnv, _ line: Int) throws -> KV {
        let f = try eval(argExprs[0].value, env)
        switch f {
        case .function(let fn): return try call(fn, [base], [nil])
        default: return try callValue(f, [KEArg(label: nil, value: .value(base))], env, line)
        }
    }
}
