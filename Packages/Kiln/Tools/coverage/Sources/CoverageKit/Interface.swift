// Parses a `.swiftinterface` into a tree of declarations.
//
// An interface is compiler-printed: one declaration per line, attributes either
// on their own lines or leading the declaration's line, and a type's members
// between a line ending in `{` and a line holding `}`. Inlinable bodies are
// skipped by counting braces. Module qualifiers (`SwiftUICore.View`,
// `SwiftUICore::View`) are removed, so every name reads as a source file would.

import Foundation

public struct Attribute: Equatable, Sendable {
    public var name: String
    public var args: [Token]?
}

public struct Param: Equatable, Sendable {
    /// The argument label, or `nil` when unlabelled (`_`).
    public var label: String?
    public var type: String
    public var hasDefault: Bool
    /// Attributes before the label (`@ViewBuilder`), by name.
    public var attributes: [String] = []
}

public struct Decl: Sendable {
    public enum Kind: String, Sendable {
        case `struct`, `class`, `enum`, `protocol`, `extension`, actor
        case `func`, initializer = "init", `var`, `let`, `subscript`, `case`, `typealias`, `associatedtype`, macro, other
    }

    public var kind: Kind
    public var name: String
    public var attributes: [Attribute] = []
    public var modifiers: [String] = []
    public var generics: String = ""
    public var inherits: [String] = []
    public var whereClause: String = ""
    public var params: [Param] = []
    public var returnType: String? = nil
    public var varType: String? = nil
    public var children: [Decl] = []
    public var line: Int = 0
    /// The whole header, normalized, for reports (`func padding(_ length: CGFloat) -> some View`).
    public var signature: String = ""

    public var isStatic: Bool { modifiers.contains("static") || modifiers.contains("class") }
    public var isTypeDecl: Bool { [.struct, .class, .enum, .protocol, .actor].contains(kind) }
    public var labels: [String] { params.map { $0.label ?? "_" } }
    public func has(_ attribute: String) -> Bool { attributes.contains { $0.name == attribute } }
}

public struct InterfaceFile: Sendable {
    public var module: String
    public var imports: [String]
    public var decls: [Decl]
}

public enum InterfaceParser {
    static let builtinModules: Set<String> = [
        "Swift", "SwiftUI", "SwiftUICore", "Foundation", "_Concurrency", "Combine", "CoreGraphics", "UIKit",
        "Charts", "Observation", "CoreTransferable", "UniformTypeIdentifiers", "DeveloperToolsSupport", "Spatial",
        "Symbols", "CoreFoundation", "Darwin", "_StringProcessing", "Accessibility", "CoreText", "QuartzCore",
    ]

    static let declKeywords: [String: Decl.Kind] = [
        "struct": .struct, "class": .class, "enum": .enum, "protocol": .protocol, "extension": .extension,
        "actor": .actor, "func": .func, "init": .initializer, "var": .var, "let": .let, "subscript": .subscript,
        "case": .case, "typealias": .typealias, "associatedtype": .associatedtype, "macro": .macro,
        "deinit": .other, "precedencegroup": .other, "operator": .other,
    ]

    static let modifierWords: Set<String> = [
        "public", "open", "internal", "fileprivate", "private", "package", "nonisolated", "final", "static",
        "mutating", "nonmutating", "override", "convenience", "required", "dynamic", "optional", "indirect",
        "lazy", "weak", "unowned", "__consuming", "consuming", "borrowing", "distributed", "isolated", "prefix",
        "postfix", "infix", "__setter_access", "_const", "reasync", "rethrows",
    ]

    /// Parses interface text. `module` is used when the file names none.
    public static func parse(_ text: String, module: String = "") -> InterfaceFile {
        // The module's own name and its imports are what qualifiers can name.
        var moduleName = module
        if let r = text.range(of: "-module-name ") {
            let rest = text[r.upperBound...]
            moduleName = String(rest.prefix { !$0.isWhitespace })
        }
        let tokens = Lexer.tokenize(text, policy: .firstBranch)
        var imports: [String] = []
        let lines = logicalLines(tokens)
        for l in lines {
            var k = 0
            while k < l.count, l[k].isPunct("@") { k += 2 }
            if k < l.count, l[k].isIdent("import") {
                var j = k + 1
                if j < l.count, ["struct", "class", "enum", "protocol", "func", "var", "typealias"].contains(l[j].text) { j += 1 }
                if j < l.count { imports.append(l[j].text) }
            }
        }
        var modules = builtinModules.union(imports)
        if !moduleName.isEmpty { modules.insert(moduleName) }
        var p = Builder(modules: modules)
        for l in lines { p.consume(l) }
        return InterfaceFile(module: moduleName, imports: imports, decls: p.finish())
    }

    /// Groups tokens into logical lines: a line break inside (), [] or <> of an
    /// attribute continues the line.
    static func logicalLines(_ tokens: [Token]) -> [[Token]] {
        var out: [[Token]] = []
        var cur: [Token] = []
        var depth = 0
        var lastLine = -1
        for t in tokens {
            if t.line != lastLine && depth <= 0 && !cur.isEmpty {
                out.append(cur); cur = []; depth = 0
            }
            lastLine = t.line
            cur.append(t)
            if t.kind == .punct {
                if t.text == "(" || t.text == "[" { depth += 1 }
                if t.text == ")" || t.text == "]" { depth -= 1 }
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Removes module qualifiers: `Swift.Bool` → `Bool`, `SwiftUICore::View` → `View`.
    static func stripQualifiers(_ ts: [Token], modules: Set<String>) -> [Token] {
        var out: [Token] = []
        out.reserveCapacity(ts.count)
        var k = 0
        while k < ts.count {
            let t = ts[k]
            if t.kind == .ident, k + 2 < ts.count, ts[k + 2].kind == .ident, !ts[k + 1].spaceBefore {
                let sep = ts[k + 1]
                let afterDot = out.last?.isPunct(".") == true && !t.spaceBefore
                if sep.isPunct("::") || (sep.isPunct(".") && modules.contains(t.text) && !afterDot) {
                    var next = ts[k + 2]
                    next.spaceBefore = t.spaceBefore
                    out.append(next)
                    k += 3
                    continue
                }
            }
            out.append(t)
            k += 1
        }
        return out
    }

    /// Reads leading attributes (`@available(...)`, `@MainActor`, `@_Concurrency.MainActor`).
    static func attributes(_ l: [Token], from start: Int) -> ([Attribute], Int) {
        var attrs: [Attribute] = []
        var k = start
        while k + 1 < l.count, l[k].isPunct("@"), l[k + 1].kind == .ident {
            var name = l[k + 1].text
            k += 2
            while k + 1 < l.count, l[k].isPunct("."), !l[k].spaceBefore, l[k + 1].kind == .ident {
                name = l[k + 1].text
                k += 2
            }
            // A generic attribute: `@SliderTickBuilder<V>`.
            if k < l.count, l[k].isPunct("<"), !l[k].spaceBefore { k = l.balanced(from: k) }
            var args: [Token]? = nil
            if k < l.count, l[k].isPunct("("), !l[k].spaceBefore {
                let end = l.balanced(from: k)
                args = Array(l[(k + 1)..<max(k + 1, end - 1)])
                k = end
            }
            attrs.append(Attribute(name: name, args: args))
        }
        return (attrs, k)
    }

    static func params(_ inner: [Token]) -> [Param] {
        guard !inner.isEmpty else { return [] }
        return inner.splitTopLevel(",").compactMap { part -> Param? in
            var (attrs, k) = attributes(part, from: 0)
            guard let colon = part.firstTopLevel(from: k, where: { $0.isPunct(":") }) else { return nil }
            var names: [String] = []
            while k < colon { if part[k].kind == .ident { names.append(part[k].text) }; k += 1 }
            let label = names.first.flatMap { $0 == "_" ? nil : $0 }
            let rest = Array(part[(colon + 1)...])
            let eq = rest.firstTopLevel(where: { $0.isPunct("=") })
            let type = Array(rest[..<(eq ?? rest.count)]).joined()
            return Param(label: label, type: type, hasDefault: eq != nil, attributes: attrs.map(\.name))
        }
    }

    // MARK: - Building the tree

    struct Builder {
        let modules: Set<String>
        var stack: [Decl] = [Decl(kind: .other, name: "<file>")]
        var skipDepth = 0
        var pending: [Attribute] = []

        init(modules: Set<String>) { self.modules = modules }

        mutating func finish() -> [Decl] {
            while stack.count > 1 { pop() }
            return stack[0].children
        }

        mutating func pop() {
            let d = stack.removeLast()
            stack[stack.count - 1].children.append(d)
        }

        static func braceBalance(_ l: [Token]) -> Int {
            var b = 0
            for t in l where t.kind == .punct {
                if t.text == "{" { b += 1 } else if t.text == "}" { b -= 1 }
            }
            return b
        }

        mutating func consume(_ raw: [Token]) {
            let balance = Builder.braceBalance(raw)
            if skipDepth > 0 {
                skipDepth += balance
                return
            }
            if raw.first?.isPunct("}") == true {
                // `}` closes the current type or extension.
                if stack.count > 1 { pop() }
                // Anything more on the line (rare) would be a new scope; ignore it.
                return
            }
            let l = InterfaceParser.stripQualifiers(raw, modules: modules)
            var (attrs, k) = InterfaceParser.attributes(l, from: 0)
            if k >= l.count { pending += attrs; return }
            // Modifiers, with attributes interleaved (`nonisolated @preconcurrency public func`).
            var mods: [String] = []
            while k < l.count {
                let t = l[k]
                if t.isPunct("@") {
                    let (more, nk) = InterfaceParser.attributes(l, from: k)
                    if nk == k { break }
                    attrs += more; k = nk; continue
                }
                guard t.kind == .ident else { break }
                if t.text == "class", k + 1 < l.count, ["func", "var", "let", "subscript", "init"].contains(l[k + 1].text) {
                    mods.append("class"); k += 1; continue
                }
                if InterfaceParser.modifierWords.contains(t.text) {
                    mods.append(t.text); k += 1
                    if k < l.count, l[k].isPunct("("), !l[k].spaceBefore { k = l.balanced(from: k) }
                    continue
                }
                break
            }
            guard k < l.count, let kind = InterfaceParser.declKeywords[l[k].text], l[k].kind == .ident else {
                // `import`, statements, or something unknown: no declaration.
                pending = []
                if balance > 0 { skipDepth = balance }
                return
            }
            var d = Decl(kind: kind, name: "")
            d.attributes = pending + attrs
            pending = []
            d.modifiers = mods
            d.line = l[k].line
            let header = Array(l[k...])
            d.signature = InterfaceParser.signature(header)
            InterfaceParser.fillHeader(&d, Array(l[(k + 1)...]))
            let opensScope = (d.isTypeDecl || kind == .extension) && balance > 0
            if opensScope {
                stack.append(d)
            } else {
                stack[stack.count - 1].children.append(d)
                if balance > 0 { skipDepth = balance }
            }
        }
    }

    /// The header up to its body, for reports.
    static func signature(_ header: [Token]) -> String {
        let end = header.firstTopLevel(angles: false, where: { $0.isPunct("{") }) ?? header.count
        return Array(header[..<end]).joined()
    }

    static func genericClause(_ ts: [Token], _ k: inout Int) -> String {
        guard k < ts.count, ts[k].isPunct("<") else { return "" }
        let end = ts.balanced(from: k)
        let g = Array(ts[k..<end]).joined()
        k = end
        return g
    }

    /// Fills name, generics, inheritance, parameters and types from the tokens
    /// after the declaration keyword.
    static func fillHeader(_ d: inout Decl, _ ts: [Token]) {
        var k = 0
        func whereAndRest(from start: Int) {
            if let w = ts.firstTopLevel(from: start, where: { $0.isIdent("where") }) {
                let end = ts.firstTopLevel(from: w, angles: false, where: { $0.isPunct("{") }) ?? ts.count
                d.whereClause = Array(ts[(w + 1)..<end]).joined()
            }
        }
        switch d.kind {
        case .struct, .class, .enum, .protocol, .actor:
            guard k < ts.count else { return }
            d.name = ts[k].text; k += 1
            d.generics = genericClause(ts, &k)
            if k < ts.count, ts[k].isPunct(":") {
                let end = ts.firstTopLevel(from: k + 1, where: { $0.isIdent("where") || $0.isPunct("{") }) ?? ts.count
                d.inherits = Array(ts[(k + 1)..<end]).splitTopLevel(",").map(conformanceName).filter { !$0.isEmpty }
                k = end
            }
            whereAndRest(from: k)
        case .extension:
            let end = ts.firstTopLevel(where: { $0.isPunct(":") || $0.isIdent("where") || $0.isPunct("{") }) ?? ts.count
            let extended = Array(ts[0..<end])
            // `ModifiedContent<A, B>` extends `ModifiedContent`; `Text.Layout` stays dotted.
            let lt = extended.firstIndex { $0.isPunct("<") } ?? extended.count
            d.name = Array(extended[..<lt]).map(\.text).joined()
            k = end
            if k < ts.count, ts[k].isPunct(":") {
                let e2 = ts.firstTopLevel(from: k + 1, where: { $0.isIdent("where") || $0.isPunct("{") }) ?? ts.count
                d.inherits = Array(ts[(k + 1)..<e2]).splitTopLevel(",").map(conformanceName).filter { !$0.isEmpty }
                k = e2
            }
            whereAndRest(from: k)
        case .func, .initializer, .subscript, .macro:
            if d.kind == .func || d.kind == .macro {
                // A name, or an operator (`==`, `<`, `+`).
                if k < ts.count, ts[k].kind == .ident { d.name = ts[k].text; k += 1 }
                else {
                    var op = ""
                    while k < ts.count, ts[k].kind == .punct, !ts[k].isPunct("("), !(op.count > 0 && ts[k].spaceBefore) {
                        if ts[k].isPunct("<") && !op.isEmpty && ts[k].spaceBefore { break }
                        op += ts[k].text; k += 1
                    }
                    d.name = op
                }
            } else {
                d.name = d.kind == .initializer ? "init" : "subscript"
                if k < ts.count, ts[k].isPunct("?") || ts[k].isPunct("!") { d.name += ts[k].text; k += 1 }
            }
            d.generics = genericClause(ts, &k)
            if k < ts.count, ts[k].isPunct("(") {
                let end = ts.balanced(from: k)
                d.params = params(Array(ts[(k + 1)..<max(k + 1, end - 1)]))
                k = end
            }
            if let arrow = ts.firstTopLevel(from: k, where: { $0.isPunct("->") }) {
                let end = ts.firstTopLevel(from: arrow + 1, where: { $0.isIdent("where") || $0.isPunct("{") || $0.isPunct("=") }) ?? ts.count
                d.returnType = Array(ts[(arrow + 1)..<end]).joined()
                k = end
            }
            whereAndRest(from: k)
        case .var, .let:
            guard k < ts.count else { return }
            d.name = ts[k].text; k += 1
            if k < ts.count, ts[k].isPunct(":") {
                let end = ts.firstTopLevel(from: k + 1, where: { $0.isPunct("{") || $0.isPunct("=") }) ?? ts.count
                d.varType = Array(ts[(k + 1)..<end]).joined()
            }
        case .case, .typealias, .associatedtype:
            guard k < ts.count else { return }
            d.name = ts[k].text
            if d.kind == .typealias, let eq = ts.firstTopLevel(where: { $0.isPunct("=") }) {
                d.varType = Array(ts[(eq + 1)...]).joined()
            }
        case .other:
            d.name = ts.first?.text ?? ""
        }
    }

    /// `SwiftUICore.View` → `View`; `@unchecked Swift.Sendable` → `Sendable`;
    /// `~Copyable` → "" (a suppression, not a conformance).
    static func conformanceName(_ ts: [Token]) -> String {
        var ts = ts
        while true {
            if ts.first?.isPunct("@") == true { ts.removeFirst(min(2, ts.count)); continue }
            if let f = ts.first, f.kind == .ident, ["nonisolated", "isolated", "sending"].contains(f.text), ts.count > 1 {
                ts.removeFirst()
                if ts.first?.isPunct("(") == true { ts.removeFirst(min(ts.balanced(from: 0), ts.count)) }
                continue
            }
            break
        }
        if ts.first?.isPunct("~") == true { return "" }
        let lt = ts.firstIndex { $0.isPunct("<") } ?? ts.count
        return ts[..<lt].map(\.text).joined()
    }
}
