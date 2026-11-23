//
//  KCheckDecls.swift
//  Kiln's checker: the app's own declarations
//
//  What the app declares, merged the way the engine merges it: a type with
//  all its extensions (and nested types), the app's protocols with their
//  extensions, extensions on types the app doesn't own (`extension View`,
//  `extension Color`), global functions and variables. Read from the syntax
//  tree alone, so whatever the parser accepts (§1.6's protocol extensions,
//  result builders, property wrappers, macros) is seen here generically.
//

import Foundation

/// One of the app's types (or protocols), with its extensions merged.
final class KCType {
    /// Qualified: `Outer.Inner`.
    let name: String
    var kind: KETypeKind
    var inherits: [String] = []
    var stored: [String: KEVarDecl] = [:]
    var computed: [String: KEVarDecl] = [:]
    var staticVars: [String: KEVarDecl] = [:]
    var methods: [String: [KEFuncDecl]] = [:]
    var staticMethods: [String: [KEFuncDecl]] = [:]
    var inits: [KEFuncDecl] = []
    var cases: [String: KEEnumCase] = [:]
    var nested: [String: KCType] = [:]
    var subscripts: [KEFuncDecl] = []
    var attributes: [KEAttribute] = []
    /// Its declarations (the type and its extensions), to walk.
    var decls: [KETypeDecl] = []
    weak var parent: KCType?

    init(name: String, kind: KETypeKind) {
        self.name = name
        self.kind = kind
    }

    var shortName: String { name.split(separator: ".").last.map(String.init) ?? name }
    var isEnum: Bool { kind == .enumType }
    var isClass: Bool { kind == .classType || kind == .actorType }
    var isProtocol: Bool { kind == .protocolType }

    func absorb(_ d: KETypeDecl) {
        decls.append(d)
        if d.kind != .extensionType { kind = d.kind }
        for i in d.inherits where !inherits.contains(i) { inherits.append(i) }
        attributes += d.attributes
        for p in d.properties {
            if p.isStatic { staticVars[p.name] = p }
            else if p.isComputed || d.kind == .extensionType { computed[p.name] = p }
            else { stored[p.name] = p }
            // `let (a, b) = …` in a type: every name it binds.
            for n in KCDecls.names(in: p.pattern) where n != p.name {
                if p.isStatic { staticVars[n] = p } else { stored[n] = p }
            }
        }
        for m in d.methods {
            if m.isStatic { staticMethods[m.name, default: []].append(m) } else { methods[m.name, default: []].append(m) }
        }
        inits += d.inits
        for c in d.cases { cases[c.name] = c }
        subscripts += d.subscripts
    }

    /// Has an instance member by this name, declared here (not inherited).
    func ownsInstance(_ n: String) -> Bool {
        stored[n] != nil || computed[n] != nil || methods[n] != nil
    }

    func ownsStatic(_ n: String) -> Bool {
        staticVars[n] != nil || staticMethods[n] != nil || cases[n] != nil || nested[n] != nil
    }
}

/// Members an app adds to a type it doesn't own (`extension View { … }`).
final class KCExtension {
    var instance: [String: [KEFuncDecl]] = [:]
    var instanceVars: [String: KEVarDecl] = [:]
    var statics: Set<String> = []
    var inits: [KEFuncDecl] = []
    var decls: [KETypeDecl] = []

    func has(_ n: String) -> Bool { instance[n] != nil || instanceVars[n] != nil }
}

/// Everything the app declares.
final class KCDecls {
    /// By qualified name, and by short name for nested types (as the engine does).
    private(set) var types: [String: KCType] = [:]
    /// Extensions on types the app doesn't declare, by the extended name's last part.
    private(set) var extensions: [String: KCExtension] = [:]
    /// Every instance member name any such extension adds (`extension Collection { var second }`):
    /// accepted on any value whose type the checker can't pin to an app type.
    private(set) var extensionMembers: Set<String> = []
    private(set) var extensionStatics: Set<String> = []
    private(set) var functions: [String: [KEFuncDecl]] = [:]
    private(set) var globals: [String: KEVarDecl] = [:]
    private(set) var typeAliases: [String: KETypeRef] = [:]
    /// Generic parameters and associated types anywhere in the source
    /// (`struct Box<Content: View>`): the parser skips the angle brackets,
    /// so these are read from the text.
    private(set) var genericNames: Set<String> = []

    init(_ program: KEProgram, source: String) {
        register(program.types, parent: nil)
        for d in program.types where d.kind == .extensionType { applyExtension(d, parent: nil) }
        for d in program.types { applyNestedExtensions(d) }
        for f in program.functions { functions[f.name, default: []].append(f) }
        for g in program.globals {
            switch g {
            case .variable(let v):
                for n in Self.names(in: v.pattern) { globals[n] = v }
            case .declaration(.typeAlias(let n, let t)):
                typeAliases[n] = t
            case .declaration(.function(let f)):
                functions[f.name, default: []].append(f)
            case .declaration(.type(let d)):
                register([d], parent: nil)
            default: break
            }
        }
        genericNames = Self.genericNames(in: source)
    }

    // MARK: Building

    private func register(_ decls: [KETypeDecl], parent: KCType?) {
        for d in decls where d.kind != .extensionType {
            let full = parent.map { "\($0.name).\(d.name)" } ?? d.name
            let t = types[full] ?? KCType(name: full, kind: d.kind)
            t.parent = parent
            types[full] = t
            if types[d.name] == nil || parent == nil { types[d.name] = t }
            parent?.nested[d.name] = t
            t.absorb(d)
            register(d.nested, parent: t)
        }
    }

    /// A local type (declared in a function body): known from there on.
    func registerLocal(_ d: KETypeDecl) {
        if types[d.name] == nil { register([d], parent: nil) }
    }

    private func applyExtension(_ d: KETypeDecl, parent: KCType?) {
        if let t = type(d.name, from: parent) {
            t.absorb(d)
            register(d.nested, parent: t)
            for n in d.nested where n.kind == .extensionType { applyExtension(n, parent: t) }
            return
        }
        let key = d.name.split(separator: ".").last.map(String.init) ?? d.name
        let ext = extensions[key] ?? KCExtension()
        extensions[key] = ext
        ext.decls.append(d)
        for p in d.properties {
            if p.isStatic { ext.statics.insert(p.name); extensionStatics.insert(p.name) }
            else { ext.instanceVars[p.name] = p; extensionMembers.insert(p.name) }
        }
        for m in d.methods {
            if m.isStatic { ext.statics.insert(m.name); extensionStatics.insert(m.name) }
            else { ext.instance[m.name, default: []].append(m); extensionMembers.insert(m.name) }
        }
        ext.inits += d.inits
        register(d.nested, parent: nil)
        for n in d.nested where n.kind == .extensionType { applyExtension(n, parent: nil) }
    }

    /// Extensions declared inside a type (an extension's own nested
    /// extensions are applied with it).
    private func applyNestedExtensions(_ d: KETypeDecl) {
        guard d.kind != .extensionType else { return }
        let owner = types[d.name]
        for n in d.nested where n.kind == .extensionType { applyExtension(n, parent: owner) }
        for n in d.nested where n.kind != .extensionType { applyNestedExtensions(n) }
    }

    // MARK: Lookups

    /// The app type a name means from inside `context` (its nested types,
    /// then its parents', then the top level). `Outer.Inner` works too.
    func type(_ name: String, from context: KCType?) -> KCType? {
        if name.contains(".") {
            let parts = name.split(separator: ".").map(String.init)
            guard var t = type(parts[0], from: context) else { return types[name] }
            for p in parts.dropFirst() {
                guard let n = t.nested[p] else { return types[name] }
                t = n
            }
            return t
        }
        var c = context
        while let t = c {
            if let n = t.nested[name] { return n }
            c = t.parent
        }
        return types[name]
    }

    /// Every app type, once.
    var allTypes: [KCType] {
        var seen = Set<ObjectIdentifier>()
        return types.values.filter { seen.insert(ObjectIdentifier($0)).inserted }.sorted { $0.name < $1.name }
    }

    // MARK: Helpers

    static func names(in p: KEPattern) -> [String] {
        switch p {
        case .binding(let n, _): return [n]
        case .tuple(let ps): return ps.flatMap(names(in:))
        case .enumCase(_, _, let ps): return ps.flatMap(names(in:))
        case .optional(let p), .cast(let p, _): return names(in: p)
        case .wildcard, .expression, .typeCheck: return []
        }
    }

    /// `<T, Content: View>` after a declaration's name, and `associatedtype X`.
    static func genericNames(in source: String) -> Set<String> {
        var out: Set<String> = []
        let decl = #"\b(?:struct|class|enum|protocol|actor|func|init|extension|typealias|subscript)\b[^{\n]*?<([^<>{}]*(?:<[^<>{}]*>[^<>{}]*)*)>"#
        if let re = try? NSRegularExpression(pattern: decl) {
            let ns = source as NSString
            for m in re.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                let inner = ns.substring(with: m.range(at: 1))
                var depth = 0
                var piece = ""
                var pieces: [String] = []
                for ch in inner {
                    if ch == "<" { depth += 1 } else if ch == ">" { depth -= 1 }
                    if ch == ",", depth == 0 { pieces.append(piece); piece = "" } else { piece.append(ch) }
                }
                pieces.append(piece)
                for p in pieces {
                    let name = p.split(whereSeparator: { $0 == ":" || $0 == "=" || $0 == " " }).first.map(String.init) ?? ""
                    if let f = name.first, f.isLetter || f == "_" { out.insert(name) }
                }
            }
        }
        if let re = try? NSRegularExpression(pattern: #"\bassociatedtype\s+([A-Za-z_][A-Za-z0-9_]*)"#) {
            let ns = source as NSString
            for m in re.matches(in: source, range: NSRange(location: 0, length: ns.length)) { out.insert(ns.substring(with: m.range(at: 1))) }
        }
        return out
    }
}
