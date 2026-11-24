//
//  KChecker.swift
//  Kiln's checker (PLAN.md §1.8)
//
//  One pass over the syntax tree, with a small static picture of each
//  value: a view, an app type, a registry type, or unknown. Every check
//  needs that picture to be certain, and "unknown" silences it, so the
//  checker only speaks where the engine would fail the same way when the
//  code ran. It asks the registry the questions the engine asks (`bind`
//  for overloads, the same lookups for members), so it can't drift from
//  what runs.
//

import Foundation

/// What the checker knows about a value.
indirect enum KSType: Equatable {
    case unknown
    /// A SwiftUI view: a bridged view, a modifier's result, one of the app's views.
    case view
    /// A value of a registry type, by the registry's name for it (`Double` for `CGFloat`).
    case native(String)
    case array(KSType)
    /// A value of one of the app's types (qualified name).
    case app(String)
    /// One of the app's types, named as a value (`Category.allCases`).
    case appMeta(String)
    /// A native type named as a value (`Color`, `Edge.Set`).
    case nativeMeta(String)
}

/// Whether code here can wait.
enum KCWait: Equatable {
    case allowed
    /// Can't tell (a closure stored for later, passed to the app's own function).
    case unknown
    /// It can't, and why: "a view's `body`".
    case forbidden(String, suggestion: String)
}

final class KCScope {
    let parent: KCScope?
    var names: [String: KSType] = [:]
    var funcs: [String: [KEFuncDecl]] = [:]
    init(_ parent: KCScope?) { self.parent = parent }

    func lookup(_ n: String) -> KSType? {
        var s: KCScope? = self
        while let c = s { if let t = c.names[n] { return t }; s = c.parent }
        return nil
    }

    func function(_ n: String) -> [KEFuncDecl]? {
        var s: KCScope? = self
        while let c = s { if let f = c.funcs[n] { return f }; s = c.parent }
        return nil
    }

    var allNames: [String] {
        var out: [String] = []
        var s: KCScope? = self
        while let c = s { out += c.names.keys; out += c.funcs.keys; s = c.parent }
        return out
    }
}

struct KCCtx {
    var scope: KCScope
    var selfType: KCType?
    var isStatic = false
    var wait: KCWait
    /// Inside an `await`: calls to `async` functions are fine.
    var covered = false
    /// In an extension on a native type (`extension Collection`): a bare
    /// name may be one of its members, which the checker doesn't list.
    var nativeSelf = false
}

extension KCCtx {
    static func make(nativeSelf: Bool, scope: KCScope, selfType: KCType?, isStatic: Bool = false, wait: KCWait) -> KCCtx {
        var c = KCCtx(scope: scope, selfType: selfType, isStatic: isStatic, wait: wait)
        c.nativeSelf = nativeSelf
        return c
    }
}

@MainActor
final class KChecker {
    let program: KEProgram
    let source: String
    let lines: [Substring]
    let decls: KCDecls
    let registry = KRegistry.shared
    private var issues: [KilnIssue] = []
    private var seen = Set<String>()
    private var stubsSeen = Set<String>()
    /// >0 while inferring a property's type: nothing is reported.
    private var silent = 0
    private var inferring = Set<ObjectIdentifier>()
    private var inferred: [ObjectIdentifier: KSType] = [:]
    private var openCache: [ObjectIdentifier: Bool] = [:]
    private let globalScope = KCScope(nil)

    /// The standard library's Swift (`KSwiftPrelude`): declared, not checked.
    private var prelude: Set<ObjectIdentifier> = []

    init(program: KEProgram, source: String) {
        var program = program
        let added = KSwiftPrelude.types(for: source, declared: Set(program.types.map(\.name)))
        program.types = added + program.types
        prelude = Set(added.map(ObjectIdentifier.init))
        self.program = program
        self.source = source
        lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        decls = KCDecls(program, source: source)
    }

    func run() -> [KilnIssue] {
        checkRoot()
        for t in decls.allTypes where !t.isProtocol && !t.decls.allSatisfy({ prelude.contains(ObjectIdentifier($0)) }) { checkRequirements(t) }
        for t in decls.allTypes {
            for d in t.decls where !prelude.contains(ObjectIdentifier(d)) { walkType(d, t) }
        }
        for (_, ext) in decls.extensions.sorted(by: { $0.key < $1.key }) {
            for d in ext.decls { walkType(d, nil) }
        }
        let top = KCCtx(scope: globalScope, selfType: nil,
                        wait: .forbidden("top-level code", suggestion: "Do the work in Task { … } or .task { … }"))
        for g in program.globals {
            if case .declaration(.type) = g { continue }      // walked with the app's types
            var c = top
            stmt(g, &c)
        }
        for f in program.functions { function(f, owner: nil, scope: globalScope, isStatic: false) }
        return issues
    }

    // MARK: - Reporting

    private func report(_ kind: KilnIssue.Kind, _ line: Int, _ message: String, suggestion: String? = nil,
                        needle: String? = nil, severity: KilnIssue.Severity = .error) {
        guard silent == 0 else { return }
        let key = "\(line)|\(message)"
        guard seen.insert(key).inserted else { return }
        issues.append(KilnIssue(severity: severity, kind: kind, line: line, column: needle.flatMap { column(of: $0, line: line) },
                                message: message, suggestion: suggestion))
    }

    /// A stub, once per symbol: the first place it's used.
    private func stub(_ symbol: String, _ line: Int, notes: String?, needle: String) {
        guard silent == 0, stubsSeen.insert(symbol).inserted else { return }
        report(.stub, line, "\(symbol) is accepted but has no effect yet", suggestion: notes.map(Self.plain), needle: needle, severity: .warning)
    }

    /// The 1-based column of `needle` on `line`, as a whole word.
    private func column(of needle: String, line: Int) -> Int? {
        guard line >= 1, line <= lines.count else { return nil }
        let text = lines[line - 1]
        var from = text.startIndex
        while let r = text.range(of: needle, range: from..<text.endIndex) {
            let before = r.lowerBound == text.startIndex ? nil : text[text.index(before: r.lowerBound)]
            let after = r.upperBound == text.endIndex ? nil : text[r.upperBound]
            let isWord = { (c: Character?) in c.map { $0.isLetter || $0.isNumber || $0 == "_" } ?? false }
            if !(needle.first.map { $0.isLetter || $0 == "_" } ?? false) || (!isWord(before) && !isWord(after)) {
                return text.distance(from: text.startIndex, to: r.lowerBound) + 1
            }
            from = r.upperBound
        }
        return nil
    }

    /// Notes are Markdown; a suggestion reads as a sentence.
    static func plain(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix(".") { t.removeLast() }
        return t
    }

    /// "Did you mean `.padding`?" for the closest name, if one is close.
    static func didYouMean(_ name: String, _ candidates: [String], prefix: String = "", suffix: String = "") -> String? {
        let lower = name.lowercased()
        var best: (String, Int)?
        for c in Set(candidates) where c != name && !c.isEmpty {
            let d = distance(lower, c.lowercased())
            let limit = max(1, min(3, name.count / 3))
            guard d <= limit else { continue }
            if best == nil || d < best!.1 || (d == best!.1 && c < best!.0) { best = (c, d) }
        }
        return best.map { "Did you mean `\(prefix)\($0.0)\(suffix)`?" }
    }

    /// Edits between two names, a swap of neighbours counting as one (`nmae` → `name`).
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    static func list(_ items: [String]) -> String {
        if items.count <= 1 { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    // MARK: - The root

    private func checkRoot() {
        let hasView = decls.allTypes.contains { t in t.inherits.contains("View") || t.inherits.contains("App") || t.attributes.contains { $0.name == "main" } }
        if !hasView && program.previews.isEmpty {
            report(.noView, 0, "No SwiftUI view found", suggestion: "Write a `struct ContentView: View { var body: some View { … } }`")
        }
    }

    // MARK: - Protocol requirements

    /// Requirements Swift fills in itself, by protocol: `Identifiable`'s `id`
    /// for a class, `CaseIterable`'s `allCases` and `Comparable`'s `<` for an enum.
    private func synthesized(_ proto: String, _ requirement: String, _ t: KCType) -> Bool {
        switch (proto, requirement) {
        case ("Identifiable", "id"): return t.isClass
        case ("CaseIterable", "allCases"): return t.isEnum
        case ("Comparable", _): return true
        default: return false
        }
    }

    private func checkRequirements(_ t: KCType) {
        guard let line = t.decls.first(where: { $0.kind != .extensionType })?.line ?? t.decls.first?.line else { return }
        for p in t.inherits {
            guard let bridge = registry.protocols[p], decls.type(p, from: t.parent) == nil else { continue }
            for r in bridge.requirements where !r.hasSuffix("?") && !synthesized(p, r, t) {
                let name = r.split(separator: "(").first.map(String.init) ?? r
                if provides(t, name, isStatic: r == "allCases") != false { continue }
                let what = r.contains("(") ? "`\(r)`" : "`\(r)`"
                report(.missingRequirement, line, "'\(t.shortName)' adopts \(p) but has no \(what)",
                       suggestion: requirementHint(p, r), needle: t.shortName)
            }
        }
    }

    private func requirementHint(_ proto: String, _ r: String) -> String? {
        switch (proto, r) {
        case ("View", "body"): return "Add `var body: some View { … }`"
        case ("App", "body"): return "Add `var body: some Scene { WindowGroup { ContentView() } }`"
        case ("Shape", _), ("InsettableShape", "path(in:)"): return "Add `func path(in rect: CGRect) -> Path { … }`"
        case ("Identifiable", "id"): return "Add `let id = UUID()`"
        default: return nil
        }
    }

    /// Whether `t` (with what it inherits) has a member: true, false, or nil when it can't tell.
    private func provides(_ t: KCType, _ name: String, isStatic: Bool, visited: inout Set<ObjectIdentifier>) -> Bool? {
        guard visited.insert(ObjectIdentifier(t)).inserted else { return false }
        if isStatic ? t.ownsStatic(name) : (t.ownsInstance(name) || t.ownsStatic(name)) { return true }
        var unsure = false
        for i in t.inherits {
            if let a = decls.type(i, from: t.parent), a !== t {
                switch provides(a, name, isStatic: isStatic, visited: &visited) {
                case true?: return true
                case nil: unsure = true
                default: break
                }
            } else if let ext = decls.extensions[i], ext.has(name) || ext.statics.contains(name) {
                return true
            } else if !isClosed(i) {
                unsure = true
            }
        }
        if decls.extensionMembers.contains(name) || decls.extensionStatics.contains(name) { return true }
        return unsure ? nil : false
    }

    private func provides(_ t: KCType, _ name: String, isStatic: Bool) -> Bool? {
        var v = Set<ObjectIdentifier>()
        return provides(t, name, isStatic: isStatic, visited: &v)
    }

    // MARK: - What a type is

    /// Protocols whose members the checker knows completely: everything they
    /// give a type is in `protocolMembers`. A type that inherits anything
    /// else (a native class, an unbridged protocol) may have members the
    /// checker can't see, so it says nothing about that type's members.
    static let closedProtocols: Set<String> = [
        "View", "App", "Scene", "Shape", "InsettableShape", "ViewModifier", "PreviewProvider",
        "Identifiable", "Hashable", "Equatable", "Comparable", "CaseIterable", "Codable", "Decodable", "Encodable",
        "Error", "LocalizedError", "CustomStringConvertible", "CustomDebugStringConvertible", "ObservableObject",
        "Sendable", "AnyObject", "CodingKey",
        // An app's own control styles (Bridges/Controls/CustomStyles.swift): only `makeBody` makes one.
        "ButtonStyle", "PrimitiveButtonStyle", "ToggleStyle", "LabelStyle", "ProgressViewStyle", "GaugeStyle", "GroupBoxStyle",
        "LabeledContentStyle", "DisclosureGroupStyle", "ControlGroupStyle", "FormStyle", "MenuStyle", "TextEditorStyle",
        "NavigationSplitViewStyle", "DatePickerStyle", "ArrangementViewStyle",
        // An enum's raw value type.
        "String", "Int", "Double", "Float", "Character", "UInt", "Int8", "Int16", "Int32", "Int64", "CGFloat",
    ]

    static let protocolMembers: [String: Set<String>] = [
        "Hashable": ["hashValue", "hash"],
        "Error": ["localizedDescription"],
        "LocalizedError": ["localizedDescription", "errorDescription", "failureReason", "recoverySuggestion", "helpAnchor"],
        "ObservableObject": ["objectWillChange"],
        "Encodable": ["encode"],
        "Codable": ["encode"],
        "CustomStringConvertible": ["description"],
        "CustomDebugStringConvertible": ["debugDescription"],
        "CodingKey": ["stringValue", "intValue"],
    ]

    private func isClosed(_ name: String) -> Bool {
        Self.closedProtocols.contains(name) || decls.type(name, from: nil) != nil
    }

    /// Whether the type (or anything it inherits) inherits something the
    /// checker doesn't know the members of.
    private func isOpen(_ t: KCType) -> Bool {
        if let v = openCache[ObjectIdentifier(t)] { return v }
        openCache[ObjectIdentifier(t)] = false       // a cycle is closed
        var open = false
        for i in t.inherits {
            if let a = decls.type(i, from: t.parent), a !== t {
                if isOpen(a) { open = true }
            } else if !Self.closedProtocols.contains(i) {
                open = true
            }
        }
        if t.attributes.contains(where: { $0.name == "dynamicMemberLookup" }) { open = true }
        openCache[ObjectIdentifier(t)] = open
        return open
    }

    /// Conforms to `View` or `Shape`, directly or through one of the app's protocols.
    private func isViewType(_ t: KCType) -> Bool {
        var visited = Set<ObjectIdentifier>()
        func go(_ t: KCType) -> Bool {
            guard visited.insert(ObjectIdentifier(t)).inserted else { return false }
            for i in t.inherits {
                if ["View", "Shape", "InsettableShape"].contains(i) { return true }
                if let a = decls.type(i, from: t.parent), a !== t, go(a) { return true }
            }
            return false
        }
        return go(t)
    }

    private func adopts(_ t: KCType, _ proto: String) -> Bool {
        var visited = Set<ObjectIdentifier>()
        func go(_ t: KCType) -> Bool {
            guard visited.insert(ObjectIdentifier(t)).inserted else { return false }
            for i in t.inherits {
                if i == proto { return true }
                if let a = decls.type(i, from: t.parent), a !== t, go(a) { return true }
            }
            return false
        }
        return go(t)
    }

    // MARK: - Members of the app's types

    enum Found {
        case value(KSType)
        case function([KEFuncDecl], KCType?)
        case none
        /// Can't tell: it inherits something unknown.
        case unsure
    }

    /// An instance member of `t`, as the engine looks it up: the type and its
    /// extensions, then what it inherits from the app's classes and protocols.
    private func instanceMember(_ t: KCType, _ name: String) -> Found {
        var visited = Set<ObjectIdentifier>()
        return instanceMember(t, name, &visited)
    }

    private func instanceMember(_ t: KCType, _ name: String, _ visited: inout Set<ObjectIdentifier>) -> Found {
        guard visited.insert(ObjectIdentifier(t)).inserted else { return .none }
        if name == "init" { return .value(.unknown) }     // `self.init(…)` in an initializer
        if let d = t.stored[name] ?? t.computed[name] { return .value(propertyType(d, owner: t)) }
        if let fs = t.methods[name] { return .function(fs, t) }
        // A property wrapper's projection and storage: `recipe.$servings`, `_servings`.
        if let f = name.first, f == "$" || f == "_", let d = t.stored[String(name.dropFirst())], !d.attributes.isEmpty {
            return .value(.unknown)
        }
        var unsure = false
        for i in t.inherits {
            if let a = decls.type(i, from: t.parent), a !== t {
                switch instanceMember(a, name, &visited) {
                case .none: break
                case .unsure: unsure = true
                case let found: return found
                }
            } else {
                if let ext = decls.extensions[i] {
                    if let fs = ext.instance[name] { return .function(fs, nil) }
                    if let v = ext.instanceVars[name] { return .value(stype(v.type, from: nil)) }
                }
                if Self.protocolMembers[i]?.contains(name) == true { return .value(.unknown) }
                if !Self.closedProtocols.contains(i) { unsure = true }
            }
        }
        if t.isEnum && ["rawValue", "id", "hashValue"].contains(name) { return .value(.unknown) }
        if t.isClass && name == "id" && adopts(t, "Identifiable") { return .value(.unknown) }
        if ["self", "localizedDescription"].contains(name) { return .value(name == "self" ? .app(t.name) : .native("String")) }
        if decls.extensionMembers.contains(name) { return .value(.unknown) }
        // `@dynamicMemberLookup` answers any name; a `Sequence` has the standard library's members.
        if t.attributes.contains(where: { $0.name == "dynamicMemberLookup" }) { return .value(.unknown) }
        if t.methods["next"] != nil || t.methods["makeIterator"] != nil, registry.type("Sequence")?.methods[name] != nil
            || registry.type("Array")?.properties[name] != nil || registry.type("Array")?.methods[name] != nil { return .value(.unknown) }
        return unsure ? .unsure : .none
    }

    private func staticMember(_ t: KCType, _ name: String) -> Found {
        var visited = Set<ObjectIdentifier>()
        return staticMember(t, name, &visited)
    }

    private func staticMember(_ t: KCType, _ name: String, _ visited: inout Set<ObjectIdentifier>) -> Found {
        guard visited.insert(ObjectIdentifier(t)).inserted else { return .none }
        if name == "self" { return .value(.appMeta(t.name)) }
        if t.cases[name] != nil { return .value(.app(t.name)) }
        if let d = t.staticVars[name] { return .value(propertyType(d, owner: t)) }
        if let fs = t.staticMethods[name] { return .function(fs, t) }
        if let n = t.nested[name] { return .value(.appMeta(n.name)) }
        if name == "allCases", t.isEnum || adopts(t, "CaseIterable") { return .value(.array(.app(t.name))) }
        if name == "init" { return .value(.unknown) }
        var unsure = false
        for i in t.inherits {
            if let a = decls.type(i, from: t.parent), a !== t {
                switch staticMember(a, name, &visited) {
                case .none: break
                case .unsure: unsure = true
                case let found: return found
                }
            } else {
                if decls.extensions[i]?.statics.contains(name) == true { return .value(.unknown) }
                if !Self.closedProtocols.contains(i) { unsure = true }
            }
        }
        if decls.extensionStatics.contains(name) { return .value(.unknown) }
        return unsure ? .unsure : .none
    }

    private func memberNames(_ t: KCType, isStatic: Bool) -> [String] {
        var out: [String] = []
        var visited = Set<ObjectIdentifier>()
        func go(_ t: KCType) {
            guard visited.insert(ObjectIdentifier(t)).inserted else { return }
            if isStatic {
                out += t.staticVars.keys; out += t.staticMethods.keys; out += t.cases.keys; out += t.nested.keys
            } else {
                out += t.stored.keys; out += t.computed.keys; out += t.methods.keys
            }
            for i in t.inherits { if let a = decls.type(i, from: t.parent), a !== t { go(a) } }
        }
        go(t)
        return out
    }

    /// A property's type: as declared, or from its initial value.
    private func propertyType(_ d: KEVarDecl, owner: KCType?) -> KSType {
        if let t = d.type { return stype(t, from: owner) }
        if d.wrapper == "Environment" { return .unknown }
        let id = ObjectIdentifier(d)
        if let t = inferred[id] { return t }
        guard let initial = d.initial, inferring.insert(id).inserted else { return .unknown }
        silent += 1
        let t = expr(initial, KCCtx(scope: KCScope(globalScope), selfType: owner, isStatic: d.isStatic, wait: .unknown))
        silent -= 1
        inferring.remove(id)
        inferred[id] = t
        return t
    }

    // MARK: - Types as written

    /// What a declared type means for checking.
    func stype(_ ref: KETypeRef?, from owner: KCType?) -> KSType {
        guard let ref else { return .unknown }
        switch ref {
        case .optional(let w): return stype(w, from: owner)
        case .opaque(let w):
            // An app that declares its own `protocol Shape` means its own.
            if let n = w.name, ["View", "Shape", "InsettableShape"].contains(n), decls.type(n, from: owner) == nil { return .view }
            return .unknown
        case .array(let e): return .array(stype(e, from: owner))
        case .dictionary: return registry.type("Dictionary") != nil ? .native("Dictionary") : .unknown
        case .named(let n, _):
            if n == "AnyView" || n == "View" { return .view }
            if decls.genericNames.contains(n) || decls.typeAliases[n] != nil { return .unknown }
            if let t = decls.type(n, from: owner) { return .app(t.name) }
            if let b = registry.type(n) { return .native(b.name) }
            if registry.view(n) != nil { return .view }
            return .unknown
        default: return .unknown
        }
    }

    // MARK: - Walking declarations

    /// Walking an extension on a type the app doesn't declare.
    private var inNativeExtension = false

    private func walkType(_ d: KETypeDecl, _ t: KCType?) {
        let owner = t
        let saved = inNativeExtension
        inNativeExtension = t == nil && d.kind == .extensionType
        defer { inNativeExtension = saved }
        for p in d.properties { property(p, owner: owner) }
        for m in d.methods { function(m, owner: owner, scope: globalScope, isStatic: m.isStatic) }
        for i in d.inits { function(i, owner: owner, scope: globalScope, isStatic: false, kind: .initializer) }
        for s in d.subscripts { function(s, owner: owner, scope: globalScope, isStatic: s.isStatic, kind: .subscriptDecl) }
        // An extension on a type the app doesn't own walks its nested types here.
        if t == nil {
            for n in d.nested where n.kind != .extensionType { if let nt = decls.type(n.name, from: nil) { walkType(n, nt) } }
        }
    }

    private func property(_ p: KEVarDecl, owner: KCType?) {
        let base = KCCtx.make(nativeSelf: inNativeExtension, scope: KCScope(globalScope), selfType: owner, isStatic: p.isStatic,
                         wait: .forbidden("a stored property's initial value", suggestion: "Load it in .task { … } instead"))
        if let initial = p.initial { _ = expr(initial, base) }
        let isBody = p.name == "body" && owner.map(isViewType) == true
        let place = isBody ? "a view's `body`" : "a computed property"
        let wait = KCWait.forbidden(place, suggestion: "A view's body and computed properties run to the end without waiting. Do the work in Task { … } or .task { … }, or in an async function called from one")
        if let g = p.getter { block(g, KCCtx.make(nativeSelf: inNativeExtension, scope: KCScope(globalScope), selfType: owner, isStatic: p.isStatic, wait: wait)) }
        for (param, body) in [p.setter, p.willSet, p.didSet].compactMap({ $0 }) {
            let s = KCScope(globalScope)
            s.names[param] = .unknown
            block(body, KCCtx.make(nativeSelf: inNativeExtension, scope: s, selfType: owner, isStatic: p.isStatic,
                              wait: .forbidden("a property's observer", suggestion: "Start a Task { … } there instead")))
        }
    }

    enum FunctionKind { case function, initializer, subscriptDecl }

    private func function(_ f: KEFuncDecl, owner: KCType?, scope: KCScope, isStatic: Bool, kind: FunctionKind = .function) {
        let s = KCScope(scope)
        let wait: KCWait
        switch kind {
        case .initializer:
            wait = .forbidden("an `init`", suggestion: "An init runs to the end without waiting. Load the data in .task { … } instead")
        case .subscriptDecl:
            wait = .forbidden("a subscript", suggestion: "Do the work in an async function")
        case .function:
            wait = f.isAsync ? .allowed
                : .forbidden("`\(f.name)()`, which isn't `async`", suggestion: "Mark it `async` (`func \(f.name)(…) async`), and call it with `await`")
        }
        let outer = KCCtx.make(nativeSelf: inNativeExtension, scope: scope, selfType: owner, isStatic: isStatic, wait: .unknown)
        for p in f.params {
            if let dv = p.defaultValue { _ = expr(dv, outer) }
            // `_ xs: Int...` is an array of them.
            s.names[p.name] = p.isVariadic ? .array(stype(p.type, from: owner)) : stype(p.type, from: owner)
        }
        block(f.body, KCCtx.make(nativeSelf: inNativeExtension, scope: s, selfType: owner, isStatic: isStatic, wait: wait))
    }

    // MARK: - Statements

    private func block(_ stmts: [KEStmt], _ ctx: KCCtx) {
        var c = ctx
        c.scope = KCScope(ctx.scope)
        // Local functions and types are known in the whole block.
        for s in stmts {
            if case .declaration(.function(let f)) = s { c.scope.funcs[f.name, default: []].append(f) }
            if case .declaration(.type(let d)) = s { decls.registerLocal(d) }
        }
        for s in stmts { stmt(s, &c) }
    }

    private func stmt(_ s: KEStmt, _ c: inout KCCtx) {
        switch s {
        case .expr(let e):
            _ = expr(e, c)
        case .variable(let d):
            variable(d, &c)
        case .assign(_, let target, let value, _):
            _ = expr(target, c)
            _ = expr(value, c)
        case .ifStmt(let conds, let body, let other):
            let inner = conditions(conds, c)
            block(body, inner)
            switch other {
            case .block(let b)?: block(b, c)
            case .elseIf(let st)?:
                var cc = c
                stmt(st, &cc)
            case nil: break
            }
        case .guardStmt(let conds, let body):
            let inner = conditions(conds, c)
            block(body, c)
            // What the guard binds is known after it.
            for (n, t) in inner.scope.names { c.scope.names[n] = t }
        case .switchStmt(let subject, let cases):
            _ = expr(subject, c)
            switchCases(cases, c)
        case .forIn(let pattern, let seq, let whereClause, let body, _):
            var element = KSType.unknown
            if case .awaitExpr(let inner) = seq {
                awaitHere(inner.line, c)
                var cc = c
                cc.covered = true
                _ = expr(inner, cc)
            } else {
                let st = expr(seq, c)
                if case .array(let el) = st { element = el }
                if case .binary(let op, _, _, _) = seq, op == "..<" || op == "..." { element = .native("Int") }
            }
            var inner = c
            inner.scope = KCScope(c.scope)
            bind(pattern, element, inner.scope)
            if let w = whereClause { _ = expr(w, inner) }
            block(body, inner)
        case .whileStmt(let conds, let body, _):
            block(body, conditions(conds, c))
        case .repeatWhile(let body, let cond, _):
            block(body, c)
            _ = expr(cond, c)
        case .returnStmt(let e, _):
            if let e { _ = expr(e, c) }
        case .throwStmt(let e):
            _ = expr(e, c)
        case .doCatch(let body, let catches):
            block(body, c)
            for k in catches {
                var inner = c
                inner.scope = KCScope(c.scope)
                if let p = k.pattern { bind(p, .unknown, inner.scope) }
                inner.scope.names["error"] = .unknown
                block(k.body, inner)
            }
        case .deferStmt(let b):
            block(b, c)
        case .declaration(.function(let f)):
            function(f, owner: c.selfType, scope: c.scope, isStatic: c.isStatic)
        case .declaration(.type(let d)):
            if let t = decls.type(d.name, from: nil) { checkRequirements(t); walkType(d, t) }
        case .declaration, .breakStmt, .continueStmt, .fallthroughStmt:
            break
        }
    }

    private func variable(_ d: KEVarDecl, _ c: inout KCCtx) {
        var t = stype(d.type, from: c.selfType)
        if let g = d.getter {
            var inner = c
            inner.wait = .forbidden("a computed property", suggestion: "Do the work in Task { … } or an async function")
            block(g, inner)
        }
        if let initial = d.initial {
            var cc = c
            if d.isAsyncLet {
                awaitHere(d.line, c, what: "async let")
                cc.covered = true
            }
            let it = expr(initial, cc)
            if d.type == nil { t = it }
        }
        for (param, body) in [d.setter, d.willSet, d.didSet].compactMap({ $0 }) {
            var inner = c
            inner.scope = KCScope(c.scope)
            inner.scope.names[param] = .unknown
            block(body, inner)
        }
        bind(d.pattern, t, c.scope)
    }

    private func bind(_ p: KEPattern, _ t: KSType, _ scope: KCScope) {
        if case .binding(let n, _) = p { scope.names[n] = t; return }
        for n in KCDecls.names(in: p) { scope.names[n] = .unknown }
    }

    /// The conditions of an `if`, `guard` or `while`: what they bind is in the returned context.
    private func conditions(_ conds: [KECondition], _ c: KCCtx) -> KCCtx {
        var inner = c
        inner.scope = KCScope(c.scope)
        for cond in conds {
            switch cond {
            case .expr(let e): _ = expr(e, inner)
            case .optionalBinding(let p, let e): bind(p, expr(e, inner), inner.scope)
            case .casePattern(let p, let e): _ = expr(e, inner); bind(p, .unknown, inner.scope)
            case .available: break
            }
        }
        return inner
    }

    private func switchCases(_ cases: [KESwitchCase], _ c: KCCtx) {
        for k in cases {
            var inner = c
            inner.scope = KCScope(c.scope)
            for (p, _) in k.patterns { bind(p, .unknown, inner.scope) }
            for (_, w) in k.patterns { if let w { _ = expr(w, inner) } }
            block(k.body, inner)
        }
    }

    // MARK: - Waiting

    private func awaitHere(_ line: Int, _ c: KCCtx, what: String = "await") {
        guard case .forbidden(let place, let suggestion) = c.wait else { return }
        if place == "this closure" {
            report(.awaitNotAllowed, line, "This closure uses '\(what)', which it can't do here",
                   suggestion: "Wrap the code in Task { … }", needle: what == "await" ? "await" : "async")
        } else {
            report(.awaitNotAllowed, line, "'\(what)' can't be used in \(place)", suggestion: suggestion,
                   needle: what == "await" ? "await" : "async")
        }
    }

    private func needsAwait(_ name: String, _ line: Int, _ c: KCCtx) {
        guard !c.covered else { return }
        report(.missingAwait, line, "'\(name)' is async: call it with 'await'",
               suggestion: "Write `await` before it, inside Task { … }, .task { … } or another async function", needle: name)
    }

    // MARK: - Expressions

    @discardableResult
    func expr(_ e: KEExpr, _ c: KCCtx) -> KSType {
        switch e {
        case .int: return .native("Int")
        case .double: return .native("Double")
        case .bool: return .native("Bool")
        case .nilLit: return .unknown
        case .string(let segs):
            for seg in segs { if case .interp(let args) = seg { for a in args { _ = expr(a.value, c) } } }
            return .native("String")
        case .ident(let name, let line):
            return ident(name, line, c)
        case .implicitMember:
            return .unknown
        case .member(let base, let name, let line):
            return member(base, name, line, c)
        case .optionalChain(let inner):
            return expr(inner, c)
        case .call(let callee, let args, let line):
            return call(callee, args, line, c)
        case .subscriptAccess(let base, let args, _):
            let bt = expr(base, c)
            for a in args { _ = expr(a.value, c) }
            if case .array(let el) = bt, args.count == 1, args[0].label == nil {
                if case .binary(let op, _, _, _) = args[0].value, op.hasPrefix("..") { return bt }
                return el
            }
            return .unknown
        case .closure(let cl):
            closure(cl, c, wait: .unknown)
            return .unknown
        case .prefix(let op, let x):
            let t = expr(x, c)
            switch op {
            case "!": return .native("Bool")
            case "-", "+": return t
            default: return .unknown
            }
        case .postfix(let op, let x):
            let t = expr(x, c)
            return op == "!" ? t : .unknown
        case .binary(let op, let l, let r, _):
            let lt = expr(l, c), rt = expr(r, c)
            switch op {
            case "==", "!=", "<", ">", "<=", ">=", "&&", "||", "===", "!==", "~=": return .native("Bool")
            case "??": return lt == .unknown ? rt : lt
            case "+", "-", "*", "/", "%": return lt == rt ? lt : .unknown
            default: return .unknown
            }
        case .ternary(let a, let b, let d):
            _ = expr(a, c)
            let bt = expr(b, c), dt = expr(d, c)
            return bt == dt ? bt : .unknown
        case .array(let xs):
            let ts = xs.map { expr($0, c) }
            if let f = ts.first, ts.allSatisfy({ $0 == f }) { return .array(f) }
            return .array(.unknown)
        case .dictionary(let ps):
            for (k, v) in ps { _ = expr(k, c); _ = expr(v, c) }
            return .unknown
        case .tuple(let xs):
            for (_, x) in xs { _ = expr(x, c) }
            return .unknown
        case .keyPath:
            return .unknown
        case .cast(let x, let kind, let t):
            _ = expr(x, c)
            return kind == "is" ? .native("Bool") : stype(t, from: c.selfType)
        case .tryExpr(_, let x):
            return expr(x, c)
        case .awaitExpr(let x):
            awaitHere(x.line, c)
            var cc = c
            cc.covered = true
            return expr(x, cc)
        case .selfRef:
            guard let s = c.selfType else { return .unknown }
            return c.isStatic ? .appMeta(s.name) : .app(s.name)
        case .typeExpr(let t):
            if let n = t.name, let at = decls.type(n, from: c.selfType) { return .appMeta(at.name) }
            return .unknown
        case .ifExpr(let conds, let a, let b):
            block(a, conditions(conds, c))
            block(b, c)
            return .unknown
        case .switchExpr(let subject, let cases):
            _ = expr(subject, c)
            switchCases(cases, c)
            return .unknown
        case .assign(_, let target, let value, _):
            _ = expr(target, c)
            _ = expr(value, c)
            return .unknown
        case .value, .regex:
            return .unknown
        }
    }

    private func closure(_ cl: KEClosure, _ c: KCCtx, wait: KCWait) {
        var inner = c
        inner.scope = KCScope(c.scope)
        inner.covered = false
        inner.wait = wait
        for p in cl.params where p.name != "_" {
            inner.scope.names[p.name] = stype(p.type, from: c.selfType)
            // `ForEach($items) { $item in }` binds `item` too.
            if p.name.hasPrefix("$") { inner.scope.names[String(p.name.dropFirst())] = .unknown }
        }
        block(cl.body, inner)
    }

    // MARK: Names

    /// Whether a bare name is a value the code declared (so it isn't a type name).
    private func isValueName(_ name: String, _ c: KCCtx) -> Bool {
        if c.scope.lookup(name) != nil || c.scope.function(name) != nil { return true }
        if let s = c.selfType, s.stored[name] != nil || s.computed[name] != nil || s.staticVars[name] != nil { return true }
        return decls.globals[name] != nil || decls.functions[name] != nil
    }

    private func ident(_ name: String, _ line: Int, _ c: KCCtx) -> KSType {
        if name == "_" || name == "self" || name == "super" || name == "Self" { return .unknown }
        if name.hasPrefix("$"), name.dropFirst().allSatisfy(\.isNumber) { return .unknown }
        if let t = c.scope.lookup(name) { return t }
        if c.scope.function(name) != nil { return .unknown }
        if name.hasPrefix("$") || name.hasPrefix("_") {
            let base = String(name.dropFirst())
            if c.scope.lookup(base) != nil { return .unknown }
            if let s = c.selfType, case .value = instanceMember(s, base) { return .unknown }
            if decls.globals[base] != nil { return .unknown }
        }
        if let s = c.selfType {
            switch instanceMember(s, name) {
            case .value(let t): return t
            case .function: return .unknown
            case .unsure: return .unknown
            case .none: break
            }
            switch staticMember(s, name) {
            case .value(let t): return t
            case .function, .unsure: return .unknown
            case .none: break
            }
            if isViewType(s), registry.modifier(name) != nil { return .unknown }
            // A nested type sees its outer types' static members.
            var p = s.parent
            while let o = p {
                if case .none = staticMember(o, name) {} else { return .unknown }
                p = o.parent
            }
        }
        if let g = decls.globals[name] { return propertyType(g, owner: nil) }
        if decls.functions[name] != nil { return .unknown }
        if let t = decls.type(name, from: c.selfType) { return .appMeta(t.name) }
        if decls.genericNames.contains(name) || decls.typeAliases[name] != nil { return .unknown }
        if registry.function(name) != nil || registry.constant(name) != nil { return .unknown }
        if let f = name.first, !(f.isLetter || f == "_" || f == "$") { return .unknown }      // an operator: reduce(0, +)
        if c.nativeSelf { return .unknown }
        if let b = registry.type(name) { return .nativeMeta(b.name) }
        if isKnownTypeName(name) { return .nativeMeta(name) }
        if name.first?.isUppercase == true {
            reportUnknownType(name, line)
            return .unknown
        }
        report(.unknownName, line, "Cannot find '\(name)' in scope",
               suggestion: Self.didYouMean(name, visibleNames(c)), needle: name)
        return .unknown
    }

    private func visibleNames(_ c: KCCtx) -> [String] {
        var out = c.scope.allNames
        if let s = c.selfType { out += memberNames(s, isStatic: false); out += memberNames(s, isStatic: true) }
        out += decls.globals.keys
        out += decls.functions.keys
        out += registry.functions.keys
        return out
    }

    /// Type names the registry or Swift knows, or that the app declares or extends.
    private func isKnownTypeName(_ name: String) -> Bool {
        if registry.type(name) != nil || registry.view(name) != nil || registry.protocols[name] != nil
            || registry.wrappers[name] != nil { return true }
        if decls.type(name, from: nil) != nil || decls.genericNames.contains(name) || decls.typeAliases[name] != nil
            || decls.extensions[name] != nil { return true }
        if KInterpreter.styleName(name) != nil { return true }
        return Self.swiftTypes.contains(name) || symbolicTypes.contains(name)
    }

    /// Swift's own names a declaration can mention, which aren't values to bridge.
    static let swiftTypes: Set<String> = ["Any", "AnyObject", "Never", "Void", "Self", "Optional", "Error", "Element",
                                          "Key", "Value", "Index", "Wrapped", "Content", "Label", "Body"]

    /// Type names written in bridges' signatures (`Edge.Set`, `HorizontalAlignment`).
    private var symbolicTypes: Set<String> { registry.symbolicTypeNames }

    private func reportUnknownType(_ name: String, _ line: Int) {
        var candidates = Array(registry.types.keys) + Array(registry.views.keys)
        candidates += decls.allTypes.map(\.shortName)
        report(.unknownName, line, "Kiln doesn't have '\(name)'",
               suggestion: Self.didYouMean(name, candidates) ?? "It isn't part of what Kiln runs; use something from the prompt's \"What works\"",
               needle: name)
    }

    // MARK: Members

    /// The app type an expression names: `Category`, `Outer.Inner`, `Self`.
    private func appTypeNamed(_ e: KEExpr, _ c: KCCtx) -> KCType? {
        switch e {
        case .ident(let n, _):
            if n == "Self" { return c.selfType }
            if isValueName(n, c) { return nil }
            if let s = c.selfType, case .value = instanceMember(s, n) { return nil }
            return decls.type(n, from: c.selfType)
        case .member(let b, let n, _):
            return appTypeNamed(b, c)?.nested[n]
        case .typeExpr(let t):
            return t.name.flatMap { decls.type($0, from: c.selfType) }
        default:
            return nil
        }
    }

    /// The native type a bare capitalized name means here (not a value, not an app type).
    private func nativeTypeNamed(_ e: KEExpr, _ c: KCCtx) -> String? {
        guard case .ident(let n, _) = e, n.first?.isUppercase == true, n != "Self" else { return nil }
        if isValueName(n, c) || decls.type(n, from: c.selfType) != nil || decls.genericNames.contains(n) || decls.typeAliases[n] != nil { return nil }
        if let s = c.selfType {
            if case .value = instanceMember(s, n) { return nil }
            if case .value = staticMember(s, n) { return nil }
        }
        return n
    }

    private func member(_ base: KEExpr, _ name: String, _ line: Int, _ c: KCCtx) -> KSType {
        if let t = appTypeNamed(base, c) { return appStatic(t, name, line) }
        if let n = nativeTypeNamed(base, c) {
            if !isKnownTypeName(n) { reportUnknownType(n, line); return .unknown }
            return nativeStatic(n, name, line)
        }
        let bt = expr(base, c)
        switch bt {
        case .app(let n):
            guard let t = decls.type(n, from: nil) else { return .unknown }
            switch instanceMember(t, name) {
            case .value(let v): return v
            case .function, .unsure: return .unknown
            case .none:
                if isViewType(t) || isOpen(t) { return .unknown }
                report(.unknownMember, line, "Value of type '\(t.shortName)' has no member '\(name)'",
                       suggestion: Self.didYouMean(name, memberNames(t, isStatic: false)), needle: name)
                return .unknown
            }
        case .appMeta(let n):
            guard let t = decls.type(n, from: nil) else { return .unknown }
            return appStatic(t, name, line)
        case .nativeMeta(let n):
            return nativeStatic(n, name, line)
        case .native(let n):
            return nativeProperty(n, name, line)
        case .array:
            return nativeProperty("Array", name, line)
        case .view, .unknown:
            return .unknown
        }
    }

    private func appStatic(_ t: KCType, _ name: String, _ line: Int) -> KSType {
        switch staticMember(t, name) {
        case .value(let v): return v
        case .function, .unsure: return .unknown
        case .none:
            if isOpen(t) || t.isProtocol || name.first?.isUppercase == true { return .unknown }
            report(.unknownMember, line, "Type '\(t.shortName)' has no member '\(name)'",
                   suggestion: Self.didYouMean(name, memberNames(t, isStatic: true)), needle: name)
            return .unknown
        }
    }

    /// `Type.name` for a native type: a static property, or a symbolic value
    /// the engine makes for SwiftUI's enum-like types.
    private func nativeStatic(_ typeName: String, _ name: String, _ line: Int) -> KSType {
        guard let b = registry.type(typeName) else {
            if name.first?.isUppercase == true { return .nativeMeta(typeName + "." + name) }
            return .unknown
        }
        if b.support == .stub { stub("`\(b.name)`", line, notes: b.notes, needle: typeName) }
        if let p = b.staticProperties[name] {
            if p.support == .stub { stub("`\(typeName).\(name)`", line, notes: p.notes ?? b.notes, needle: name) }
            if p.isAsync { /* a static async property: rare; awaited by its caller */ }
            return b.membersInManifest ? .native(b.name) : .unknown
        }
        if name == "self" || name == "init" { return .unknown }
        if name.first?.isUppercase == true { return .nativeMeta(typeName + "." + name) }
        if b.anyStatic != nil || b.staticMethods[name] != nil { return .unknown }
        if decls.extensions[typeName]?.statics.contains(name) == true || decls.extensions[b.name]?.statics.contains(name) == true { return .unknown }
        if decls.extensionStatics.contains(name) { return .unknown }
        // A type with no static members listed is symbolic: the engine passes its members on by name.
        if b.staticProperties.isEmpty && b.staticMethods.isEmpty { return .unknown }
        report(.unknownMember, line, "Kiln's \(typeName) has no member '\(name)'",
               suggestion: Self.didYouMean(name, Array(b.staticProperties.keys) + Array(b.staticMethods.keys)), needle: name)
        return .unknown
    }

    /// `value.name` on a native value: its type's property, or a fallback's.
    private func nativeProperty(_ typeName: String, _ name: String, _ line: Int) -> KSType {
        guard registry.type(typeName) != nil else { return .unknown }
        var tn = typeName
        var visited = Set<String>()
        var candidates: [String] = []
        while let b = registry.type(tn), visited.insert(b.name).inserted {
            if let p = b.properties[name] {
                if p.support == .stub { stub("`\(b.name).\(name)`", line, notes: p.notes ?? b.notes, needle: name) }
                return .unknown
            }
            if b.methods[name] != nil || b.anyProperty != nil || b.anyMethod != nil { return .unknown }
            candidates += b.properties.keys
            guard let fb = b.fallback else { break }
            tn = fb
        }
        if name == "self" || decls.extensions[typeName]?.has(name) == true || decls.extensionMembers.contains(name) { return .unknown }
        report(.unknownMember, line, "Value of type '\(typeName)' has no member '\(name)'",
               suggestion: Self.didYouMean(name, candidates), needle: name)
        return .unknown
    }

    // MARK: Calls

    private func call(_ callee: KEExpr, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KSType {
        switch callee {
        case .ident(let name, _):
            return callNamed(name, args, line, c)
        case .member(let base, let name, _):
            if let t = appTypeNamed(base, c) { return appStaticCall(t, name, args, line, c) }
            if let n = nativeTypeNamed(base, c) {
                if !isKnownTypeName(n) { reportUnknownType(n, line); walkArgs(args, c, wait: .unknown); return .unknown }
                return nativeStaticCall(n, name, args, line, c)
            }
            let bt = expr(base, c)
            return methodCall(bt, name, args, line, c)
        case .typeExpr(let t):
            walkArgs(args, c, wait: .unknown)
            if let n = t.name, let at = decls.type(n, from: c.selfType) { return .app(at.name) }
            return .unknown
        default:
            _ = expr(callee, c)
            walkArgs(args, c, wait: .unknown)
            return .unknown
        }
    }

    private func callNamed(_ name: String, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KSType {
        if c.scope.lookup(name) != nil || name.hasPrefix("$") { walkArgs(args, c, wait: .unknown); return .unknown }
        if let fs = c.scope.function(name) { return appCall(fs, name, args, line, c, owner: c.selfType) }
        if let s = c.selfType {
            switch instanceMember(s, name) {
            case .function(let fs, let owner): return appCall(fs, name, args, line, c, owner: owner)
            case .value, .unsure: walkArgs(args, c, wait: .unknown); return .unknown
            case .none: break
            }
            switch staticMember(s, name) {
            case .function(let fs, let owner): return appCall(fs, name, args, line, c, owner: owner)
            case .value(let v):
                walkArgs(args, c, wait: .unknown)
                if case .appMeta(let n) = v { return .app(n) }
                return .unknown
            case .unsure: walkArgs(args, c, wait: .unknown); return .unknown
            case .none: break
            }
        }
        if let fs = decls.functions[name] { return appCall(fs, name, args, line, c, owner: nil) }
        if decls.globals[name] != nil { walkArgs(args, c, wait: .unknown); return .unknown }
        if let t = decls.type(name, from: c.selfType) {
            walkArgs(args, c, wait: .unknown)
            return .app(t.name)
        }
        if decls.genericNames.contains(name) || decls.typeAliases[name] != nil { walkArgs(args, c, wait: .unknown); return .unknown }
        if let ext = decls.extensions[name], let i = KInterpreter.pick(ext.inits, labels: args.map(\.label)),
           i.params.count >= args.count, !KBuiltins.prefersBuiltinInit(name, args.map(\.label)) {
            walkArgs(args, c, wait: .unknown)
            return registry.type(name).map { .native($0.name) } ?? .unknown
        }
        if let b = registry.view(name), b.constructible {
            if b.support == .stub { stub("`\(name)`", line, notes: b.notes, needle: name) }
            _ = bridgeCall(b.forms.map(\.overload), display: name, needle: name, args, line, c)
            return .view
        }
        if let f = registry.function(name) {
            if f.support == .stub { stub("`\(name)`", line, notes: f.notes, needle: name) }
            if let o = bridgeCall(f.forms.map(\.overload), display: name, needle: name, args, line, c), o.isAsync {
                needsAwait(name, line, c)
            }
            return .unknown
        }
        if let t = registry.type(name), !t.inits.isEmpty {
            if t.support == .stub { stub("`\(t.name)`", line, notes: t.notes, needle: name) }
            _ = bridgeCall(t.inits.map(\.overload), display: name, needle: name, args, line, c)
            return initResult(t)
        }
        if KInterpreter.styleName(name) != nil { walkArgs(args, c, wait: .unknown); return .unknown }
        walkArgs(args, c, wait: .unknown)
        if let s = c.selfType, isOpen(s) { return .unknown }
        if c.nativeSelf { return .unknown }
        if name.first?.isUppercase == true {
            if registry.type(name) != nil {
                report(.unknownName, line, "Kiln can't make a \(name) with \(name)(…)", needle: name)
            } else {
                reportUnknownType(name, line)
            }
        } else {
            report(.unknownName, line, "Cannot find '\(name)' in scope",
                   suggestion: Self.didYouMean(name, visibleNames(c)), needle: name)
        }
        return .unknown
    }

    /// A call to one of the app's functions or methods.
    private func appCall(_ fs: [KEFuncDecl], _ name: String, _ args: [KEArg], _ line: Int, _ c: KCCtx, owner: KCType?) -> KSType {
        let labels = args.map(\.label)
        let f = KInterpreter.pick(fs, labels: labels)
        if let f, f.isAsync, fs.allSatisfy(\.isAsync) || fs.count == 1 { needsAwait(name + "()", line, c) }
        walkArgs(args, c, wait: .unknown)
        guard let f else { return .unknown }
        if f.isViewBuilder { return .view }
        return stype(f.returnType, from: owner)
    }

    private func appStaticCall(_ t: KCType, _ name: String, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KSType {
        if let n = t.nested[name] { walkArgs(args, c, wait: .unknown); return .app(n.name) }
        if t.cases[name] != nil { walkArgs(args, c, wait: .unknown); return .app(t.name) }
        if name == "init" { walkArgs(args, c, wait: .unknown); return .app(t.name) }
        switch staticMember(t, name) {
        case .function(let fs, let owner): return appCall(fs, name, args, line, c, owner: owner)
        case .value, .unsure: walkArgs(args, c, wait: .unknown); return .unknown
        case .none:
            walkArgs(args, c, wait: .unknown)
            if isOpen(t) || t.isProtocol { return .unknown }
            report(.unknownMember, line, "Type '\(t.shortName)' has no member '\(name)'",
                   suggestion: Self.didYouMean(name, memberNames(t, isStatic: true)), needle: name)
            return .unknown
        }
    }

    private func nativeStaticCall(_ typeName: String, _ name: String, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KSType {
        guard let b = registry.type(typeName) else {
            walkArgs(args, c, wait: .unknown)
            return name == "init" && registry.view(typeName) != nil ? .view : .unknown
        }
        let display = typeName + "." + name
        if b.support == .stub { stub("`\(b.name)`", line, notes: b.notes, needle: typeName) }
        if let ms = b.staticMethods[name] {
            if let o = bridgeCall(ms.map(\.overload), display: display, needle: name, args, line, c), o.isAsync {
                needsAwait(display, line, c)
            }
            return .unknown
        }
        if name == "init", !b.inits.isEmpty {
            _ = bridgeCall(b.inits.map(\.overload), display: typeName, needle: name, args, line, c)
            return initResult(b)
        }
        walkArgs(args, c, wait: .unknown)
        if b.anyStaticMethod != nil || b.anyStatic != nil || b.staticProperties[name] != nil { return .unknown }
        if decls.extensions[typeName]?.statics.contains(name) == true || decls.extensionStatics.contains(name) { return .unknown }
        if b.staticProperties.isEmpty && b.staticMethods.isEmpty { return .unknown }
        report(.unknownMember, line, "Kiln's \(typeName) has no member '\(name)'",
               suggestion: Self.didYouMean(name, Array(b.staticProperties.keys) + Array(b.staticMethods.keys)), needle: name)
        return .unknown
    }

    private func methodCall(_ bt: KSType, _ name: String, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KSType {
        // `Optional.map`: Kiln keeps optionals unwrapped, so any value has it.
        if name == "map" || name == "flatMap", args.count == 1, bt != .view {
            if case .array = bt {} else if case .native = bt {} else { walkArgs(args, c, wait: .unknown); return .unknown }
        }
        switch bt {
        case .view:
            return viewMethod(name, args, line, c)
        case .app(let n):
            guard let t = decls.type(n, from: nil) else { walkArgs(args, c, wait: .unknown); return .unknown }
            switch instanceMember(t, name) {
            case .function(let fs, let owner): return appCall(fs, name, args, line, c, owner: owner)
            case .value, .unsure: walkArgs(args, c, wait: .unknown); return .unknown
            case .none: break
            }
            if isViewType(t) { return viewMethod(name, args, line, c) }
            walkArgs(args, c, wait: .unknown)
            if isOpen(t) { return .unknown }
            report(.unknownMember, line, "Value of type '\(t.shortName)' has no member '\(name)'",
                   suggestion: Self.didYouMean(name, memberNames(t, isStatic: false)), needle: name)
            return .unknown
        case .appMeta(let n):
            guard let t = decls.type(n, from: nil) else { walkArgs(args, c, wait: .unknown); return .unknown }
            return appStaticCall(t, name, args, line, c)
        case .nativeMeta(let n):
            if registry.type(n) != nil { return nativeStaticCall(n, name, args, line, c) }
            walkArgs(args, c, wait: .unknown)
            return .unknown
        case .array:
            return nativeMethod("Array", name, args, line, c)
        case .native(let n):
            return nativeMethod(n, name, args, line, c)
        case .unknown:
            walkArgs(args, c, wait: .unknown)
            return .unknown
        }
    }

    /// What `T(…)` makes, for checking its members: a `T`, when the bridge
    /// has members of its own. A bridge without any makes something else
    /// (the haptic generators make one shared stand-in), so it's unknown.
    private func initResult(_ t: KTypeBridge) -> KSType {
        if registry.view(t.name) != nil { return .view }
        let hasMembers = !t.methods.isEmpty || !t.properties.isEmpty || t.anyMethod != nil || t.anyProperty != nil || t.fallback != nil
        return hasMembers ? .native(t.name) : .unknown
    }

    /// `value.name(…)` on a native value: its type's methods, then each fallback's.
    private func nativeMethod(_ typeName: String, _ name: String, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KSType {
        guard registry.type(typeName) != nil else { walkArgs(args, c, wait: .unknown); return .unknown }
        if name == "map" || name == "flatMap" || name == "callAsFunction" { walkArgs(args, c, wait: .unknown); return .unknown }
        var tn = typeName
        var visited = Set<String>()
        var dynamic = false
        var candidates: [String] = []
        while let b = registry.type(tn), visited.insert(b.name).inserted {
            if let ms = b.methods[name] {
                if let o = bridgeCall(ms.map(\.overload), display: name, needle: name, args, line, c), o.isAsync {
                    needsAwait(name + "()", line, c)
                }
                return .unknown
            }
            if b.anyMethod != nil { dynamic = true }
            if b.properties[name] != nil { walkArgs(args, c, wait: .unknown); return .unknown }
            candidates += b.methods.keys
            guard let fb = b.fallback else { break }
            tn = fb
        }
        if dynamic || decls.extensions[typeName]?.has(name) == true || decls.extensionMembers.contains(name) {
            walkArgs(args, c, wait: .unknown)
            return .unknown
        }
        if ["Color", "Path"].contains(typeName) || registry.type(typeName)?.manifestKind == "view" {
            return viewMethod(name, args, line, c)
        }
        walkArgs(args, c, wait: .unknown)
        report(.unknownMember, line, "Value of type '\(typeName)' has no method '\(name)'",
               suggestion: Self.didYouMean(name, candidates), needle: name)
        return .unknown
    }

    /// A modifier, or the app's own `View` extension method, on a view.
    private func viewMethod(_ name: String, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KSType {
        for key in ["View", "Shape", "InsettableShape", "Text", "Image"] {
            if let fs = decls.extensions[key]?.instance[name] {
                let t = appCall(fs, name, args, line, c, owner: nil)
                return t == .unknown ? .view : t
            }
        }
        if let b = registry.modifier(name) {
            let o = bridgeCall(b.forms.map(\.overload), display: b.display, needle: name, args, line, c)
            if b.support == .stub || o?.isStub == true { stub("`.\(name)`", line, notes: o?.notes ?? b.notes, needle: name) }
            return .view
        }
        walkArgs(args, c, wait: .unknown)
        if decls.extensionMembers.contains(name) { return .view }
        // A method of the value itself (`Circle().path(in:)`).
        if registry.type("View")?.methods[name] != nil { return .unknown }
        var candidates = Array(registry.modifiers.keys)
        candidates += decls.extensions["View"].map { Array($0.instance.keys) } ?? []
        report(.unknownModifier, line, "Kiln doesn't support the .\(name)() modifier",
               suggestion: Self.didYouMean(name, candidates, prefix: "."), needle: name)
        return .view
    }

    /// Picks an overload as the engine does (labels, how each argument is
    /// written, then the OS), reports when none takes the call, checks
    /// bindings, and walks the arguments: closures where the bridge lets them wait.
    private func bridgeCall(_ overloads: [KOverload], display: String, needle: String, _ args: [KEArg], _ line: Int, _ c: KCCtx) -> KOverload? {
        let labels = args.map(\.label)
        let syntax = args.map { KArgSyntax($0.value) }
        var chosen: (KOverload, [Int])?
        var unavailable: KOverload?
        for o in overloads {
            guard let b = o.bind(labels, syntax) else { continue }
            if let a = o.availability, !a.isAvailable { unavailable = unavailable ?? o; continue }
            chosen = (o, b)
            break
        }
        guard let (o, binding) = chosen else {
            if let u = unavailable {
                report(.unavailable, line, "\(u.display(display)) needs iOS \(u.availability?.iOSString ?? "later")", needle: needle)
            } else {
                let written = display + "(" + labels.map { ($0 ?? "_") + ":" }.joined() + ")"
                var known: [String] = []
                for o in overloads where o.availability?.isAvailable ?? true {
                    let d = o.display(display)
                    if !known.contains(d) { known.append(d) }
                }
                report(.arguments, line, "Kiln has no \(written)",
                       suggestion: known.isEmpty ? nil : "It has \(Self.list(known))", needle: needle)
            }
            walkArgs(args, c, wait: .unknown)
            return nil
        }
        if !o.lenient {
            for (i, a) in args.enumerated() where o.params[binding[i]].kind == .binding {
                checkBinding(a.value, display: o.display(display), label: a.label, line: line, c)
            }
        }
        walkArgs(args, c, wait: o.closuresCanWait ? .allowed : .forbidden("this closure", suggestion: ""))
        return o
    }

    /// A value where a binding goes: `Toggle(isOn: isOn)` for `$isOn`.
    private func checkBinding(_ e: KEExpr, display: String, label: String?, line: Int, _ c: KCCtx) {
        let what = label.map { "'\($0)'" } ?? "the argument"
        switch e {
        case .bool, .array, .dictionary:
            report(.argumentType, line, "\(display): \(what) needs a binding such as $value, not a value", needle: label ?? "")
        case .ident(let n, _) where !n.hasPrefix("$"):
            if let t = c.scope.lookup(n) {
                if case .native(let tn) = t, ["Bool", "Int", "Double", "String"].contains(tn) {
                    report(.argumentType, line, "\(display): \(what) needs a binding such as $\(n), not the value", needle: n)
                }
                return
            }
            guard let s = c.selfType, let d = s.stored[n], d.type?.name != "Binding" else { return }
            if let w = d.wrapper {
                guard ["State", "Binding", "AppStorage", "SceneStorage", "Published", "FocusState"].contains(w) else { return }
            } else {
                guard d.attributes.isEmpty, case .native(let tn) = propertyType(d, owner: s),
                      ["Bool", "Int", "Double", "String"].contains(tn) else { return }
            }
            report(.argumentType, line, "\(display): \(what) needs a binding such as $\(n), not the value", needle: n)
        default:
            return
        }
    }

    private func walkArgs(_ args: [KEArg], _ c: KCCtx, wait: KCWait) {
        for a in args {
            if case .closure(let cl) = a.value { closure(cl, c, wait: wait) } else { _ = expr(a.value, c) }
        }
    }
}
