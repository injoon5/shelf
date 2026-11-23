// Reads Kiln's 0.2.1-era engine statically, without compiling it, and records
// what its string switches know: each `case "…":` with the function, type and
// enclosing cases it sits in, plus string sets and dictionaries
// (`static let viewNames: Set<String> = [...]`) and `x == "…"` comparisons.
// InterimManifest turns these facts into a manifest. Nothing here edits the engine.

import Foundation

public struct CaseFact: Equatable, Sendable {
    public var file: String
    public var typeName: String
    public var function: String
    /// The switch's subject as written (`m.name`, `name`, `(typeName, name)`).
    public var subject: String
    /// Labels of the enclosing cases, outermost first.
    public var path: [String]
    /// This case's string labels. A tuple pattern `("Timer", "publish")` reads `Timer.publish`.
    public var labels: [String]
    /// The case does nothing: its body is `return view` or `break`.
    public var isStub: Bool
    /// `.name(.member` calls in the body, as `name.member` (`pickerStyle.segmented`).
    public var implicitCalls: [String]
    public var line: Int
}

public struct CollectionFact: Equatable, Sendable {
    public var file: String
    public var name: String
    public var values: [String]
    public var line: Int
}

public struct ComparisonFact: Equatable, Sendable {
    public var file: String
    public var typeName: String
    public var function: String
    /// What's compared (`m.name`, `name`, `n`).
    public var lhs: String
    public var value: String
    public var line: Int
}

public struct EngineFacts: Sendable {
    public var cases: [CaseFact] = []
    public var collections: [CollectionFact] = []
    public var comparisons: [ComparisonFact] = []
    public init() {}

    public mutating func merge(_ o: EngineFacts) {
        cases += o.cases; collections += o.collections; comparisons += o.comparisons
    }
}

public enum EngineScanner {
    enum ScopeKind { case type(String), function(String), switchBody, other }

    final class SwitchState {
        var subject: String
        var path: [String]
        var labels: [String]? = nil
        var caseLine = 0
        var bodyStart = 0
        init(subject: String, path: [String]) { self.subject = subject; self.path = path }
    }

    struct Scope {
        var kind: ScopeKind
        var parenDepth = 0
        var sw: SwitchState? = nil
    }

    public static func scan(_ text: String, file: String) -> EngineFacts {
        let ts = Lexer.tokenize(text, policy: .iOS)
        var facts = EngineFacts()
        var scopes: [Scope] = [Scope(kind: .other)]
        var pending: ScopeKind? = nil
        var pendingSwitchStart: Int? = nil

        func currentType() -> String {
            for s in scopes.reversed() { if case .type(let n) = s.kind { return n } }
            return ""
        }
        func currentFunction() -> String {
            for s in scopes.reversed() { if case .function(let n) = s.kind { return n } }
            return ""
        }
        func casePath() -> [String] {
            scopes.compactMap { $0.sw?.labels }.map { $0.joined(separator: "|") }
        }
        func finishCase(_ sw: SwitchState, end: Int) {
            guard let labels = sw.labels else { return }
            let body = Array(ts[sw.bodyStart..<max(sw.bodyStart, end)])
            let words = body.map(\.text)
            let stub = words == ["return", "view"] || words == ["break"]
            var calls: [String] = []
            var j = 0
            while j + 4 < body.count {
                if body[j].isPunct("."), body[j + 1].kind == .ident, body[j + 2].isPunct("("),
                   body[j + 3].isPunct("."), body[j + 4].kind == .ident {
                    calls.append("\(body[j + 1].text).\(body[j + 4].text)")
                }
                j += 1
            }
            if !labels.isEmpty {
                facts.cases.append(CaseFact(file: file, typeName: currentType(), function: currentFunction(),
                                            subject: sw.subject, path: Array(casePath().dropLast()), labels: labels,
                                            isStub: stub, implicitCalls: calls, line: sw.caseLine))
            }
            sw.labels = nil
        }

        var k = 0
        while k < ts.count {
            let t = ts[k]
            let top = scopes.count - 1

            if t.kind == .punct {
                switch t.text {
                case "(", "[":
                    scopes[top].parenDepth += 1
                case ")", "]":
                    scopes[top].parenDepth -= 1
                case "{":
                    var s = Scope(kind: .other)
                    if scopes[top].parenDepth == 0, let p = pending {
                        s.kind = p
                        if case .switchBody = p, let st = pendingSwitchStart {
                            s.sw = SwitchState(subject: Array(ts[st..<k]).joined(), path: [])
                        }
                    }
                    pending = nil
                    pendingSwitchStart = nil
                    scopes.append(s)
                case "}":
                    if let sw = scopes[top].sw { finishCase(sw, end: k) }
                    if scopes.count > 1 { scopes.removeLast() }
                case "==":
                    if k + 1 < ts.count, ts[k + 1].kind == .string, k >= 1 {
                        var j = k - 1
                        var parts: [String] = []
                        while j >= 0, ts[j].kind == .ident {
                            parts.insert(ts[j].text, at: 0)
                            if j >= 2, ts[j - 1].isPunct(".") { j -= 2 } else { break }
                        }
                        if !parts.isEmpty {
                            facts.comparisons.append(ComparisonFact(file: file, typeName: currentType(), function: currentFunction(),
                                                                    lhs: parts.joined(separator: "."), value: unquote(ts[k + 1].text), line: t.line))
                        }
                    }
                default: break
                }
                k += 1
                continue
            }

            if t.kind == .ident {
                let next = k + 1 < ts.count ? ts[k + 1] : nil
                switch t.text {
                case "func":
                    if let n = next { pending = .function(n.text) }
                case "init" where next?.isPunct("(") == true || next?.isPunct("?") == true:
                    if k == 0 || !ts[k - 1].isPunct(".") { pending = .function("init") }
                case "struct", "class", "enum", "extension", "actor", "protocol":
                    if let n = next, n.kind == .ident, !(t.text == "class" && ["func", "var", "let"].contains(n.text)) {
                        pending = .type(n.text)
                    }
                case "switch":
                    pending = .switchBody
                    pendingSwitchStart = k + 1
                case "let", "var":
                    if let n = next, n.kind == .ident, let c = collection(ts, from: k + 2) {
                        if !c.isEmpty { facts.collections.append(CollectionFact(file: file, name: n.text, values: c, line: t.line)) }
                    }
                case "case", "default":
                    // A switch label, not `if case`, `guard case`, `for case` or `, case`.
                    let prev = k > 0 ? ts[k - 1] : nil
                    let isLabel = scopes[top].sw != nil && scopes[top].parenDepth == 0
                        && !(prev.map { ["if", "guard", "while", "for"].contains($0.text) || $0.isPunct(",") } ?? false)
                    if isLabel, let sw = scopes[top].sw {
                        finishCase(sw, end: k)
                        // Read up to the label's colon.
                        var j = k + 1
                        var depth = 0
                        while j < ts.count {
                            let u = ts[j]
                            if u.isPunct("(") || u.isPunct("[") { depth += 1 }
                            if u.isPunct(")") || u.isPunct("]") { depth -= 1 }
                            if depth == 0 && u.isPunct(":") { break }
                            j += 1
                        }
                        var labels: [String] = []
                        if t.text == "case" {
                            for item in Array(ts[(k + 1)..<min(j, ts.count)]).splitTopLevel(",", angles: false) {
                                if item.count == 1, item[0].kind == .string { labels.append(unquote(item[0].text)) }
                                else if item.first?.isPunct("(") == true, item.last?.isPunct(")") == true {
                                    let inner = Array(item.dropFirst().dropLast()).splitTopLevel(",", angles: false)
                                    if inner.allSatisfy({ $0.count == 1 && $0[0].kind == .string }) {
                                        labels.append(inner.map { unquote($0[0].text) }.joined(separator: "."))
                                    }
                                }
                            }
                        }
                        sw.labels = labels
                        sw.caseLine = t.line
                        sw.bodyStart = min(j + 1, ts.count)
                        k = j + 1
                        continue
                    }
                default: break
                }
            }
            k += 1
        }
        return facts
    }

    /// If `= [` follows (after an optional type annotation), the string elements or keys of that literal.
    static func collection(_ ts: [Token], from start: Int) -> [String]? {
        var k = start
        var steps = 0
        if k < ts.count, ts[k].isPunct(":") {
            // Skip the type annotation: `Set<String>`, `[String: Color]`.
            k += 1
            var depth = 0
            while k < ts.count, steps < 16 {
                let t = ts[k]
                if t.isPunct("[") || t.isPunct("<") || t.isPunct("(") { depth += 1 }
                if t.isPunct("]") || t.isPunct(">") || t.isPunct(")") { depth -= 1 }
                k += 1; steps += 1
                if depth == 0 && (k < ts.count && ts[k].isPunct("=")) { break }
            }
        }
        guard k + 1 < ts.count, ts[k].isPunct("="), ts[k + 1].isPunct("[") else { return nil }
        let end = ts.balanced(from: k + 1)
        let inner = Array(ts[(k + 2)..<max(k + 2, end - 1)])
        var out: [String] = []
        for item in inner.splitTopLevel(",", angles: false) {
            if item.count == 1, item[0].kind == .string { out.append(unquote(item[0].text)) }
            else if item.count >= 2, item[0].kind == .string, item[1].isPunct(":") { out.append(unquote(item[0].text)) }
        }
        return out
    }

    static func unquote(_ s: String) -> String {
        var t = Substring(s)
        while t.hasPrefix("#") { t = t.dropFirst() }
        while t.hasSuffix("#") { t = t.dropLast() }
        if t.hasPrefix("\"") { t = t.dropFirst() }
        if t.hasSuffix("\"") { t = t.dropLast() }
        return String(t)
    }
}
