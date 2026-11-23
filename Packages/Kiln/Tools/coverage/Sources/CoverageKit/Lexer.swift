// A small Swift tokenizer, enough for `.swiftinterface` files and for scanning
// Kiln's own sources. It knows comments, strings (with interpolation, multi-line
// and raw), identifiers (backticks removed), numbers and punctuation, and it
// resolves `#if` blocks with a caller-supplied policy.

import Foundation

public struct Token: Equatable, Sendable {
    public enum Kind: Sendable { case ident, punct, string, number }
    public var kind: Kind
    public var text: String
    public var line: Int
    /// Whitespace (or a line break) came before this token.
    public var spaceBefore: Bool

    public init(_ kind: Kind, _ text: String, line: Int, spaceBefore: Bool = true) {
        self.kind = kind; self.text = text; self.line = line; self.spaceBefore = spaceBefore
    }

    public func isPunct(_ s: String) -> Bool { kind == .punct && text == s }
    public func isIdent(_ s: String) -> Bool { kind == .ident && text == s }
}

/// How `#if` blocks are resolved.
public enum ConditionPolicy: Sendable {
    /// Keep only the first branch of every `#if`. A `.swiftinterface` repeats a
    /// declaration in its `#else` branch for older compilers; the first is current.
    case firstBranch
    /// Evaluate `os(...)` and `canImport(...)` as an iOS build would; anything
    /// else falls back to the first branch. Used for Kiln's sources.
    case iOS
}

public struct Lexer {
    let bytes: [UInt8]
    let policy: ConditionPolicy
    var i = 0
    var line = 1
    var space = true
    var atLineStart = true
    var tokens: [Token] = []

    public static func tokenize(_ source: String, policy: ConditionPolicy = .firstBranch) -> [Token] {
        var l = Lexer(bytes: Array(source.utf8), policy: policy)
        l.run()
        return l.tokens
    }

    init(bytes: [UInt8], policy: ConditionPolicy) {
        self.bytes = bytes; self.policy = policy
    }

    // MARK: - Conditional compilation

    /// One open `#if`: whether its current branch is kept, and whether any branch was.
    struct Cond { var active: Bool; var taken: Bool; var parentActive: Bool }
    var conds: [Cond] = []
    var active: Bool { conds.last.map { $0.active } ?? true }

    func evaluate(_ condition: String) -> Bool? {
        guard case .iOS = policy else { return nil }
        let c = condition.replacingOccurrences(of: " ", with: "")
        func atom(_ a: String) -> Bool? {
            var a = Substring(a)
            var negate = false
            while a.hasPrefix("!") { negate.toggle(); a = a.dropFirst() }
            let v: Bool?
            if a.hasPrefix("os(") { v = a == "os(iOS)" }
            else if a.hasPrefix("canImport(") {
                let m = a.dropFirst("canImport(".count).dropLast()
                v = !["AppKit", "Cocoa", "WatchKit"].contains(String(m))
            } else if a.hasPrefix("targetEnvironment(") { v = false }
            else if a == "DEBUG" || a == "true" { v = true }
            else if a == "false" { v = false }
            else { v = nil }
            return v.map { negate ? !$0 : $0 }
        }
        if c.contains("||") {
            let parts = c.components(separatedBy: "||").map(atom)
            if parts.contains(where: { $0 == true }) { return true }
            return parts.allSatisfy { $0 == false } ? false : nil
        }
        if c.contains("&&") {
            let parts = c.components(separatedBy: "&&").map(atom)
            if parts.contains(where: { $0 == false }) { return false }
            return parts.allSatisfy { $0 == true } ? true : nil
        }
        return atom(c)
    }

    mutating func directive(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        func word(_ w: String) -> Bool { t == w || t.hasPrefix(w + " ") || t.hasPrefix(w + "(") || t.hasPrefix(w + "!") }
        if word("#if") {
            let parent = active
            let v = evaluate(String(t.dropFirst(3))) ?? true
            conds.append(Cond(active: parent && v, taken: v, parentActive: parent))
        } else if word("#elseif") {
            guard var c = conds.popLast() else { return }
            if c.taken { c.active = false }
            else {
                let v = evaluate(String(t.dropFirst(7))) ?? false
                c.active = c.parentActive && v
                c.taken = v
            }
            conds.append(c)
        } else if word("#else") {
            guard var c = conds.popLast() else { return }
            c.active = c.parentActive && !c.taken
            c.taken = true
            conds.append(c)
        } else if word("#endif") {
            _ = conds.popLast()
        }
    }

    // MARK: - Scanning

    func peek(_ o: Int = 0) -> UInt8 { i + o < bytes.count ? bytes[i + o] : 0 }

    mutating func emit(_ k: Token.Kind, _ s: String) {
        tokens.append(Token(k, s, line: line, spaceBefore: space))
        space = false
        atLineStart = false
    }

    static func isIdentStart(_ c: UInt8) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c >= 0x80
    }
    static func isIdentBody(_ c: UInt8) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
    static func isDigit(_ c: UInt8) -> Bool { c >= 48 && c <= 57 }

    func text(_ from: Int, _ to: Int) -> String { String(decoding: bytes[from..<to], as: UTF8.self) }

    /// Reads to the end of the current line and returns it (without the newline).
    mutating func restOfLine() -> String {
        let s = i
        while i < bytes.count && bytes[i] != 10 { i += 1 }
        return text(s, i)
    }

    mutating func run() {
        while i < bytes.count {
            let c = bytes[i]
            if c == 10 { line += 1; i += 1; space = true; atLineStart = true; continue }
            if c == 32 || c == 9 || c == 13 { i += 1; space = true; continue }
            if atLineStart && c == 35 /* # */ {
                let save = i
                let rest = restOfLine()
                let t = rest.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("#if") || t.hasPrefix("#elseif") || t.hasPrefix("#else") || t.hasPrefix("#endif") {
                    // Strip a trailing comment from the condition.
                    let cond = t.components(separatedBy: "//").first ?? t
                    directive(cond)
                    continue
                }
                i = save
            }
            if !active {
                // Skip the whole line; only directives matter here.
                _ = restOfLine()
                continue
            }
            if c == 47 /* / */ && peek(1) == 47 { _ = restOfLine(); continue }
            if c == 47 && peek(1) == 42 {
                var depth = 0
                while i < bytes.count {
                    if bytes[i] == 47 && peek(1) == 42 { depth += 1; i += 2; continue }
                    if bytes[i] == 42 && peek(1) == 47 { depth -= 1; i += 2; if depth == 0 { break }; continue }
                    if bytes[i] == 10 { line += 1 }
                    i += 1
                }
                space = true
                continue
            }
            if c == 34 /* " */ { lexString(hashes: 0); continue }
            if c == 35 /* # */ {
                var h = 0
                while peek(h) == 35 { h += 1 }
                if peek(h) == 34 { i += h; lexString(hashes: h); continue }
            }
            if c == 96 /* ` */ {
                let s = i + 1
                i += 1
                while i < bytes.count && bytes[i] != 96 && bytes[i] != 10 { i += 1 }
                let t = text(s, i)
                if i < bytes.count && bytes[i] == 96 { i += 1 }
                emit(.ident, t)
                continue
            }
            if Lexer.isIdentStart(c) || (c == 35 && Lexer.isIdentStart(peek(1))) {
                let s = i
                i += 1
                while i < bytes.count && Lexer.isIdentBody(bytes[i]) { i += 1 }
                emit(.ident, text(s, i))
                continue
            }
            if Lexer.isDigit(c) {
                let s = i
                while i < bytes.count && (Lexer.isIdentBody(bytes[i]) || (bytes[i] == 46 && Lexer.isDigit(peek(1)))) { i += 1 }
                emit(.number, text(s, i))
                continue
            }
            // Punctuation. Multi-character forms that matter for headers; `<` and
            // `>` stay single so nested generics (`A<B<C>>`) balance.
            var matched = false
            for p in Lexer.multiPunct {
                if (0..<p.count).allSatisfy({ peek($0) == p[$0] }) {
                    i += p.count
                    emit(.punct, String(decoding: p, as: UTF8.self))
                    matched = true
                    break
                }
            }
            if matched { continue }
            i += 1
            emit(.punct, String(UnicodeScalar(c)))
        }
    }

    static let multiPunct: [[UInt8]] = ["...", "..<", "->", "::", "==", "!=", "&&", "||", "??", "<=", ">="].map { Array($0.utf8) }

    /// Lexes a string literal starting at `i` (at the opening quote, after any `#`s).
    mutating func lexString(hashes: Int) {
        let startLine = line
        let multi = peek(0) == 34 && peek(1) == 34 && peek(2) == 34
        let s = i
        i += multi ? 3 : 1
        func closes() -> Bool {
            if multi {
                guard peek(0) == 34 && peek(1) == 34 && peek(2) == 34 else { return false }
                return (0..<hashes).allSatisfy { peek(3 + $0) == 35 }
            }
            guard peek(0) == 34 else { return false }
            return (0..<hashes).allSatisfy { peek(1 + $0) == 35 }
        }
        while i < bytes.count {
            if closes() { i += (multi ? 3 : 1) + hashes; break }
            let c = bytes[i]
            if c == 10 {
                line += 1
                if !multi { break }
            }
            if c == 92 /* \ */ && (0..<hashes).allSatisfy({ peek(1 + $0) == 35 }) {
                let after = peek(1 + hashes)
                if after == 40 /* ( */ {
                    // Interpolation: skip to the balancing paren, minding nested strings.
                    i += 2 + hashes
                    var depth = 1
                    while i < bytes.count && depth > 0 {
                        let d = bytes[i]
                        if d == 34 { lexStringSkip(); continue }
                        if d == 40 { depth += 1 } else if d == 41 { depth -= 1 } else if d == 10 { line += 1 }
                        i += 1
                    }
                    continue
                }
                i += 2 + hashes
                continue
            }
            i += 1
        }
        let body = text(s, min(i, bytes.count))
        let saveLine = line
        line = startLine
        emit(.string, body)
        line = saveLine
    }

    /// Skips a nested plain string inside an interpolation.
    mutating func lexStringSkip() {
        i += 1
        while i < bytes.count && bytes[i] != 34 && bytes[i] != 10 {
            if bytes[i] == 92 { i += 1 }
            i += 1
        }
        i += 1
    }
}

// MARK: - Token helpers

extension Array where Element == Token {
    /// Joins tokens back into text, keeping the source's spacing.
    public func joined() -> String {
        var out = ""
        for (n, t) in enumerated() {
            if n > 0 && t.spaceBefore { out += " " }
            out += t.text
        }
        return out
    }

    /// Splits at top-level occurrences of `separator`, minding (), [], {} and <>.
    public func splitTopLevel(_ separator: String, angles: Bool = true) -> [[Token]] {
        var parts: [[Token]] = [[]]
        var depth = 0
        for t in self {
            if t.kind == .punct {
                switch t.text {
                case "(", "[", "{": depth += 1
                case ")", "]", "}": depth -= 1
                case "<" where angles: depth += 1
                case ">" where angles: depth -= 1
                default: break
                }
                if depth == 0 && t.text == separator { parts.append([]); continue }
            }
            parts[parts.count - 1].append(t)
        }
        return parts
    }

    /// Index of the first top-level token matching `match`, minding brackets.
    public func firstTopLevel(from start: Int = 0, angles: Bool = true, where match: (Token) -> Bool) -> Int? {
        var depth = 0
        var k = start
        while k < count {
            let t = self[k]
            if depth == 0 && match(t) { return k }
            if t.kind == .punct {
                switch t.text {
                case "(", "[", "{": depth += 1
                case ")", "]", "}": depth -= 1
                case "<" where angles: depth += 1
                case ">" where angles: depth -= 1
                default: break
                }
            }
            k += 1
        }
        return nil
    }

    /// Index just past the bracket that balances the opener at `open`.
    public func balanced(from open: Int) -> Int {
        guard open < count else { return count }
        let o = self[open].text
        let close: String = o == "(" ? ")" : o == "[" ? "]" : o == "{" ? "}" : ">"
        var depth = 0
        var k = open
        while k < count {
            let t = self[k]
            if t.kind == .punct {
                if t.text == o { depth += 1 } else if t.text == close { depth -= 1; if depth == 0 { return k + 1 } }
            }
            k += 1
        }
        return count
    }
}
