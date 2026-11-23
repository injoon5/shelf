//
//  KEProtocols.swift
//  Kiln's engine
//
//  Protocols as Swift has them (PLAN.md §1.6): requirements, extensions with
//  default implementations (constrained with `where Self: …` too), protocol
//  inheritance, and conformance that behaviour depends on: a custom `==` and
//  `hash(into:)`, `<`, `allCases`, `id`. A type's conformances are closed over
//  inheritance when the program loads, and each default implementation it
//  doesn't write itself becomes its member, so every lookup path finds it.
//

import SwiftUI

/// A protocol the app declares.
final class KProtocol {
    let name: String
    let decl: KETypeDecl
    /// `extension P { … }` and `extension P where Self: Q { … }`.
    var extensions: [KETypeDecl] = []

    init(_ decl: KETypeDecl) {
        self.name = decl.name
        self.decl = decl
    }

    var inherits: [String] { decl.inherits }
}

extension KInterpreter {

    // MARK: Swift's own protocols

    /// The standard library's and SwiftUI's protocol inheritance, as far as
    /// conformance checks need it.
    nonisolated static let builtinParents: [String: [String]] = [
        "Hashable": ["Equatable"],
        "Comparable": ["Equatable"],
        "Strideable": ["Comparable", "Equatable"],
        "Codable": ["Encodable", "Decodable"],
        "LocalizedError": ["Error"],
        "Error": ["Sendable"],
        "Identifiable": [],
        "Numeric": ["AdditiveArithmetic", "Equatable"],
        "SignedNumeric": ["Numeric", "AdditiveArithmetic", "Equatable"],
        // A Shape is a View too, but the engine draws the app's shapes as
        // shapes, so `View` isn't added here.
        "Shape": ["Animatable"],
        "InsettableShape": ["Shape", "Animatable"],
        "ObservableObject": ["AnyObject"],
        "RawRepresentable": [],
        "OptionSet": ["SetAlgebra", "RawRepresentable", "Equatable"],
        "Collection": ["Sequence"],
        "BidirectionalCollection": ["Collection", "Sequence"],
        "RandomAccessCollection": ["BidirectionalCollection", "Collection", "Sequence"],
        "MutableCollection": ["Collection", "Sequence"],
        "RangeReplaceableCollection": ["Collection", "Sequence"],
    ]

    /// What the native values conform to, and the other names an extension
    /// may use for them (`extension CGFloat` reaches a `Double`).
    nonisolated static let builtinProtocols: [String: [String]] = {
        let codable = ["Codable", "Encodable", "Decodable", "Sendable"]
        let numeric = ["Numeric", "SignedNumeric", "AdditiveArithmetic", "Comparable", "Equatable", "Hashable", "Strideable",
                       "CustomStringConvertible", "LosslessStringConvertible"] + codable
        let collection = ["Collection", "Sequence", "BidirectionalCollection"]
        return [
            "Int": ["BinaryInteger", "FixedWidthInteger", "SignedInteger", "Int64", "Int32", "UInt"] + numeric,
            "Double": ["BinaryFloatingPoint", "FloatingPoint", "CGFloat", "Float", "TimeInterval"] + numeric,
            "String": ["StringProtocol", "RangeReplaceableCollection", "Substring", "Comparable", "Equatable", "Hashable",
                       "CustomStringConvertible", "LosslessStringConvertible", "TextOutputStreamable"] + collection + codable,
            "Bool": ["Equatable", "Hashable", "CustomStringConvertible"] + codable,
            "Array": ["RandomAccessCollection", "MutableCollection", "RangeReplaceableCollection", "Equatable", "Hashable"] + collection + codable,
            "Set": ["SetAlgebra", "Collection", "Sequence", "Equatable", "Hashable"] + codable,
            "Dictionary": ["Collection", "Sequence", "Equatable", "Hashable"] + codable,
            "Range": ["Sequence", "Collection", "Equatable", "Hashable"],
            "Date": ["Comparable", "Equatable", "Hashable"] + codable,
            "UUID": ["Equatable", "Hashable", "CustomStringConvertible"] + codable,
            "URL": ["Equatable", "Hashable", "CustomStringConvertible"] + codable,
            "Color": ["View", "ShapeStyle", "Equatable", "Hashable"],
        ]
    }()

    /// Swift's protocols whose extensions the app's types adopt
    /// (`extension Identifiable { … }`). `View`'s are applied to views directly.
    nonisolated static let adoptableBuiltinProtocols: Set<String> = [
        "Identifiable", "Equatable", "Hashable", "Comparable", "Codable", "Encodable", "Decodable", "CaseIterable",
        "CustomStringConvertible", "Error", "LocalizedError", "RawRepresentable", "Sendable", "ObservableObject",
        "Shape", "InsettableShape", "Animatable", "Strideable", "Sequence", "Collection",
    ]

    // MARK: Loading

    func registerProtocols(_ decls: [KETypeDecl]) {
        for d in decls {
            if d.kind == .protocolType { protocols[d.name] = KProtocol(d) }
            registerProtocols(d.nested)
        }
    }

    /// Everything a protocol or class inherits, transitively.
    func ancestors(of name: String) -> [String] {
        var out: [String] = []
        var seen: Set<String> = [name]
        var queue = [name]
        while let n = queue.popLast() {
            let parents = protocols[n]?.inherits ?? types[n].map { Array($0.declaredInherits) } ?? Self.builtinParents[n] ?? []
            for p in parents where seen.insert(p).inserted {
                out.append(p)
                queue.append(p)
            }
        }
        return out
    }

    /// After every declaration and extension is read: conformances closed
    /// over inheritance, default implementations adopted, the requirements
    /// checked, and the hooks `==`, `hash(into:)` and `<` set.
    func finalizeTypes() {
        var seen = Set<ObjectIdentifier>()
        let all = types.values.filter { seen.insert(ObjectIdentifier($0)).inserted }.sorted { $0.line < $1.line }
        // Superclasses before their subclasses.
        for t in all where t.isClass { inheritFromSuperclass(t, visiting: []) }
        for t in all { finalize(t) }
        for (key, protos) in builtinConformances {
            let ext = builtinExtensions[key] ?? KBuiltinExtension()
            builtinExtensions[key] = ext
            for p in protos { adoptDefaults(p, into: ext) }
        }
    }

    func finalize(_ t: KType) {
        guard !t.finalized else { return }
        t.finalized = true
        t.declaredInherits = t.declaredInherits.isEmpty ? t.conformances : t.declaredInherits
        // Enums without payloads are Equatable and Hashable; with a raw type, RawRepresentable.
        if t.isEnum, !t.cases.isEmpty, t.cases.allSatisfy({ $0.associated.isEmpty }) {
            t.conformances.formUnion(["Equatable", "Hashable"])
        }
        if t.rawType != nil { t.conformances.insert("RawRepresentable") }
        for c in Array(t.conformances) { t.conformances.formUnion(ancestors(of: c)) }

        // Default implementations: the type's own members win; then constrained
        // extensions, which are more specific; then plain ones.
        for name in t.conformances.sorted() {
            if let proto = protocols[name] {
                let exts = proto.extensions.filter { !$0.constraints.isEmpty } + proto.extensions.filter { $0.constraints.isEmpty }
                for ext in exts where constraintsHold(ext.constraints, t) { adopt(ext, into: t) }
            } else if Self.adoptableBuiltinProtocols.contains(name), let ext = builtinExtensions[name] {
                // `extension Identifiable { … }`, `extension Comparable { … }` on the app's types.
                adopt(ext, into: t)
            }
        }
        installHooks(t)
        checkRequirements(t)
    }

    /// `class Dog: Animal`: the superclass's members and conformances.
    private func inheritFromSuperclass(_ t: KType, visiting: Set<ObjectIdentifier>) {
        guard !t.inherited, !visiting.contains(ObjectIdentifier(t)) else { return }
        t.inherited = true
        guard let superName = t.declaredSuperclass(in: types), let sup = types[superName], sup.isClass, sup !== t else { return }
        inheritFromSuperclass(sup, visiting: visiting.union([ObjectIdentifier(t)]))
        t.superclass = sup
        t.conformances.formUnion(sup.conformances)
        let own = Set(t.stored.map(\.name))
        t.stored = sup.stored.filter { !own.contains($0.name) } + t.stored
        for (n, p) in sup.computed where t.computed[n] == nil && !own.contains(n) { t.computed[n] = p }
        for (n, ms) in sup.methods {
            let mine = t.methods[n] ?? []
            t.methods[n] = mine + ms.filter { m in !mine.contains { $0.signature == m.signature } }
        }
        for (n, ms) in sup.staticMethods where t.staticMethods[n] == nil { t.staticMethods[n] = ms }
        for (n, p) in sup.staticDecls where t.staticDecls[n] == nil { t.staticDecls[n] = p }
        if t.inits.isEmpty { t.inits = sup.inits }
        if t.subscripts.isEmpty { t.subscripts = sup.subscripts }
    }

    /// Whether `where Self: P, Self == T` holds for `t`. Constraints on
    /// associated types (`Element == Int`) can't be known here and hold.
    func constraintsHold(_ cs: [KEConstraint], _ t: KType) -> Bool {
        for c in cs where c.subject == "Self" {
            guard let n = c.type.name else { continue }
            switch c.relation {
            case .conforms: if t.name != n && !t.conformances.contains(n) { return false }
            case .same: if t.name != n { return false }
            }
        }
        return true
    }

    /// The members of `ext` that `t` doesn't have itself.
    private func adopt(_ ext: KETypeDecl, into t: KType) {
        for p in ext.properties {
            if p.isStatic {
                if t.staticDecls[p.name] == nil { t.staticDecls[p.name] = p }
            } else if t.computed[p.name] == nil, t.storedDecl(p.name) == nil {
                t.computed[p.name] = p
            }
        }
        for m in ext.methods where !m.isRequirement {
            if m.isStatic {
                if !(t.staticMethods[m.name] ?? []).contains(where: { $0.signature == m.signature }) { t.staticMethods[m.name, default: []].append(m) }
            } else if !(t.methods[m.name] ?? []).contains(where: { $0.signature == m.signature }) {
                t.methods[m.name, default: []].append(m)
            }
        }
        for i in ext.inits where !t.inits.contains(where: { $0.signature == i.signature }) && !t.extensionInits.contains(where: { $0.signature == i.signature }) {
            t.extensionInits.append(i)
        }
        if t.subscripts.isEmpty { t.subscripts = ext.subscripts }
        register(ext.nested, parent: t)
    }

    private func adopt(_ ext: KBuiltinExtension, into t: KType) {
        for (n, p) in ext.computed where t.computed[n] == nil && t.storedDecl(n) == nil { t.computed[n] = p }
        for (n, p) in ext.staticDecls where t.staticDecls[n] == nil { t.staticDecls[n] = p }
        for (n, ms) in ext.methods {
            for m in ms where !(t.methods[n] ?? []).contains(where: { $0.signature == m.signature }) { t.methods[n, default: []].append(m) }
        }
        for (n, ms) in ext.staticMethods {
            for m in ms where !(t.staticMethods[n] ?? []).contains(where: { $0.signature == m.signature }) { t.staticMethods[n, default: []].append(m) }
        }
    }

    /// `extension Int: Describable {}`: the protocol's defaults on a native type.
    private func adoptDefaults(_ protocolName: String, into ext: KBuiltinExtension) {
        for name in [protocolName] + ancestors(of: protocolName) {
            guard let proto = protocols[name] else { continue }
            for d in proto.extensions where d.constraints.allSatisfy({ $0.subject != "Self" }) {
                for p in d.properties {
                    if p.isStatic { if ext.staticDecls[p.name] == nil { ext.staticDecls[p.name] = p } }
                    else if ext.computed[p.name] == nil { ext.computed[p.name] = p }
                }
                for m in d.methods where !m.isRequirement {
                    if m.isStatic {
                        if !(ext.staticMethods[m.name] ?? []).contains(where: { $0.signature == m.signature }) { ext.staticMethods[m.name, default: []].append(m) }
                    } else if !(ext.methods[m.name] ?? []).contains(where: { $0.signature == m.signature }) {
                        ext.methods[m.name, default: []].append(m)
                    }
                }
            }
        }
    }

    // MARK: Hooks: Equatable, Hashable

    /// A custom `==` and `hash(into:)` decide equality and hashing everywhere
    /// (`==`, `contains`, `firstIndex(of:)`, `Set`, `onChange(of:)`).
    private func installHooks(_ t: KType) {
        let staticCtx = KSelfContext(type: t, location: .box(KBox(.type(.user(t)))), isStatic: true)
        if let eq = t.staticMethods["=="]?.first(where: { $0.params.count == 2 }) {
            t.customEquals = { [weak self] a, b in
                guard Thread.isMainThread, let self else { return nil }
                return MainActor.assumeIsolated {
                    guard let r = try? self.invoke(eq, args: [a, b], labels: [nil, nil], selfContext: staticCtx, parent: self.globalEnv) else { return nil }
                    return self.truthy(r)
                }
            }
        }
        if let hash = t.methods["hash"]?.first(where: { $0.params.first?.label == "into" }) {
            t.customHash = { [weak self] v in
                guard Thread.isMainThread, let self else { return nil }
                return MainActor.assumeIsolated {
                    let hasher = KHasherBox()
                    let ctx = KSelfContext(type: t, location: .box(KBox(v)))
                    guard (try? self.invoke(hash, args: [.native(.object("Hasher", KRef(hasher)))], labels: ["into"], selfContext: ctx, parent: self.globalEnv)) != nil else { return nil }
                    return hasher.combined
                }
            }
        }
    }

    // MARK: Requirements

    /// A type that says it conforms to one of the app's protocols has every
    /// requirement, or a default for it. Missing ones are errors with the type's line.
    private func checkRequirements(_ t: KType) {
        for name in t.conformances.sorted() {
            guard let proto = protocols[name] else { continue }
            for p in proto.decl.properties {
                let has = p.isStatic ? (t.staticDecls[p.name] != nil || t.enumCase(p.name) != nil)
                    : (t.storedDecl(p.name) != nil || t.computed[p.name] != nil || (t.isEnum && p.name == "rawValue" && t.rawType != nil))
                if !has {
                    report(fail("'\(t.name)' doesn't conform to '\(name)': it has no '\(p.name)'\(p.type.map { " (\(name) requires var \(p.name): \($0))" } ?? "")", t.line))
                }
            }
            for m in proto.decl.methods where m.isRequirement {
                let candidates = m.isStatic ? (t.staticMethods[m.name] ?? []) : (t.methods[m.name] ?? [])
                if !candidates.contains(where: { $0.signature == m.signature }) {
                    // A payload case satisfies a static func requirement; an enum case a static var.
                    if m.isStatic, t.enumCase(m.name) != nil { continue }
                    let has = candidates.map(\.signature)
                    report(fail("'\(t.name)' doesn't conform to '\(name)': it has no \(m.signature)\(has.isEmpty ? "" : "; it has " + KInterpreter.list(has))", t.line))
                }
            }
        }
    }

    /// "a", "a and b", "a, b and c".
    nonisolated static func list(_ items: [String]) -> String {
        items.count <= 1 ? (items.first ?? "") : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    // MARK: Conformance of any value

    /// Whether a value is a `P` (or a `T`): `is`, `as?`, `where Element: P`.
    func valueConforms(_ v: KV, _ n: String) -> Bool {
        if n == "Any" { return true }
        if let ut = v.userType { return ut.name == n || ut.conformances.contains(n) || (n == "AnyObject" && ut.isClass) }
        let key = KBuiltins.extensionKey(v)
        if key == n { return true }
        if let ps = Self.builtinProtocols[key], ps.contains(n) { return true }
        if let ps = builtinConformances[key], ps.contains(n) { return true }
        if let ps = builtinConformances[key], ps.contains(where: { ancestors(of: $0).contains(n) }) { return true }
        return false
    }

    /// The members an `extension` on a native type or protocol gives a value,
    /// tried in order: its own type, then the protocols it conforms to.
    func builtinExtensionKeys(_ v: KV) -> [String] {
        let key = KBuiltins.extensionKey(v)
        var keys = [key]
        if let ps = Self.builtinProtocols[key] { keys += ps }
        if let ps = builtinConformances[key] { keys += ps.sorted() }
        return keys
    }

    func builtinExtensionMethod(_ base: KV, _ name: String, labels: [String?]?) -> KEFuncDecl? {
        for key in builtinExtensionKeys(base) {
            guard let ext = builtinExtensions[key], let ms = ext.methods[name] else { continue }
            let fitting = ms.filter { builtinConstraintsHold(ext.constraints[ObjectIdentifier($0)] ?? [], base) }
            if let m = Self.pick(fitting, labels: labels) { return m }
        }
        return nil
    }

    func builtinExtensionComputed(_ base: KV, _ name: String) -> KEVarDecl? {
        for key in builtinExtensionKeys(base) {
            guard let ext = builtinExtensions[key] else { continue }
            if let all = ext.computedAll[name], all.count > 1,
               let fit = all.last(where: { builtinConstraintsHold(ext.constraints[ObjectIdentifier($0)] ?? [], base) }) {
                return fit
            }
            if let p = ext.computed[name] { return p }
        }
        return nil
    }

    /// `extension Array where Element == Expense`: the elements say which.
    func builtinConstraintsHold(_ cs: [KEConstraint], _ base: KV) -> Bool {
        for c in cs {
            var sample: KV?
            switch (c.subject, base) {
            case ("Element", .array(let a)): sample = a.first
            case ("Element", .set(let s)): sample = s.first
            case ("Key", .dict(let d)): sample = d.keys.first
            case ("Value", .dict(let d)): sample = d.values.first
            case ("Self", _): sample = base
            default: continue
            }
            guard let v = sample, let n = c.type.name else { continue }
            switch c.relation {
            case .same:
                if v.userType.map({ $0.name != n }) ?? (KBuiltins.extensionKey(v) != n && !(Self.builtinProtocols[KBuiltins.extensionKey(v)] ?? []).contains(n)) { return false }
            case .conforms:
                if !valueConforms(v, n) { return false }
            }
        }
        return true
    }

    // MARK: Generic parameters

    /// `func make<T: P>(_ type: T.Type) -> T { T() }`: `T` names the type the
    /// call passed, so `T()`, `T.self` and `T.staticMember` work.
    func bindGenerics(_ decl: KEFuncDecl, _ env: KEnv) {
        guard !decl.generics.isEmpty else { return }
        for g in decl.generics where env.vars[g.name] == nil {
            for p in decl.params {
                guard let pt = p.type, let v = env.vars[p.name]?.value, let w = genericWitness(pt, g.name, v) else { continue }
                env.declare(g.name, w)
                break
            }
        }
    }

    private func genericWitness(_ t: KETypeRef, _ g: String, _ v: KV) -> KV? {
        switch t {
        case .named(let n, _) where n == g:
            if case .type = v { return v }
            return typeValue(of: v)
        case .optional(let w): return v.isNil ? nil : genericWitness(w, g, v)
        case .array(let e):
            if case .array(let items) = v, let first = items.first { return genericWitness(e, g, first) }
            return nil
        default: return nil
        }
    }

    func typeValue(of v: KV) -> KV? {
        if let ut = v.userType { return .type(.user(ut)) }
        switch v {
        case .nilValue, .void, .function, .view, .binding, .type: return nil
        default: return .type(.builtin(KBuiltins.extensionKey(v)))
        }
    }

    // MARK: Implicit members of a protocol

    /// `.circle` where `any Shape2D` is expected: the one conforming type
    /// whose static member it is (`extension Shape2D where Self == Circle`).
    func protocolImplicit(_ proto: String, _ name: String, _ args: [KV]?, labels: [String?]) throws -> KV? {
        guard protocols[proto] != nil else { return nil }
        var seen = Set<ObjectIdentifier>()
        let owners = types.values.filter { t in
            seen.insert(ObjectIdentifier(t)).inserted && t.conformances.contains(proto)
                && (t.staticDecls[name] != nil || t.staticMethods[name] != nil || t.enumCase(name) != nil)
        }
        guard owners.count == 1 else { return nil }
        return try implicitOn(owners[0], name, args, labels: labels)
    }
}

/// `hasher.combine(x)` in an app's `hash(into:)`: the values it combined.
final class KHasherBox {
    var combined: [KV] = []
}
