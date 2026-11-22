import Foundation

/// A short description of an app for the change prompt when its full source
/// is left out (plan §9.2): header lines, every saved type in full, the `DB`
/// and `@AppStorage` key names, and every other type and function as a
/// signature with its body replaced by `{ … }`. No model is involved.
///
/// It reads the source with a small, tolerant scanner rather than a parser:
/// it matches braces while skipping comments and string literals (multi-line,
/// raw and interpolated ones too), and splits each type body into its
/// declarations. Whatever it can't make sense of, such as a file cut off in
/// the middle, it leaves as it is.
///
/// CONTRACT — signatures are fixed; bodies belong to the Create package.
enum Outline {
    static func make(from source: String) -> String {
        let scan = Scan(source)
        let decls = scan.declarations(0, scan.count)
        let types = scan.collectTypes(decls)
        let saved = savedTypeNames(types)

        var out: [String] = header(of: source)
        let db = scan.keys(#"DB\s*\.\s*(?:load|save|remove)\s*\(\s*"([^"\\\n]*)""#)
        let storage = scan.keys(#"@AppStorage\s*\(\s*"([^"\\\n]*)""#)
        var keyLines: [String] = []
        if !db.isEmpty { keyLines.append("// Saved with DB: " + db.map { "\"\($0)\"" }.joined(separator: ", ")) }
        if !storage.isEmpty { keyLines.append("// Saved with @AppStorage: " + storage.map { "\"\($0)\"" }.joined(separator: ", ")) }
        if !keyLines.isEmpty {
            if !out.isEmpty { out.append("") }
            out += keyLines
        }

        var body: [String] = []
        for decl in decls {
            let lines = scan.outline(decl, saved: saved)
            if lines.isEmpty { continue }
            // Imports stay together; every other top-level declaration gets a blank line before it.
            if !body.isEmpty && !(decl.kind == .other && scan.firstWord(decl) == "import" && body.last?.hasPrefix("import ") == true) {
                body.append("")
            }
            body += lines
        }
        if !out.isEmpty && !body.isEmpty { out.append("") }
        out += body
        return out.isEmpty ? "" : out.joined(separator: "\n") + "\n"
    }

    /// The `// Name:`, `// Icon:` and `// Tint:` lines, read the way `ReplyParser` reads them.
    static func header(of source: String) -> [String] {
        var lines: [String] = []
        var seen: Set<String> = []
        for line in ReplyParser.normalized(source).components(separatedBy: "\n") {
            if ReplyParser.isBlank(line) { continue }
            guard ReplyParser.hasPrefix(ReplyParser.trimmed(line), "//") else { break }
            if let (key, _) = ReplyParser.headerLine(line), seen.insert(key).inserted {
                lines.append(ReplyParser.trimmed(line))
            }
        }
        return lines
    }

    /// Types that are saved: `Codable`, `Encodable` or `Decodable` ones, and
    /// every type they hold in a stored property or an enum payload, all the
    /// way down.
    static func savedTypeNames(_ types: [Scan.TypeInfo]) -> Set<String> {
        let declared = Set(types.map(\.name))
        var conforming: Set<String> = []
        for t in types where !t.conformances.isDisjoint(with: ["Codable", "Encodable", "Decodable"]) {
            conforming.insert(t.name)
        }
        var saved = conforming
        var queue = Array(conforming)
        while let name = queue.popLast() {
            for t in types where t.name == name {
                for ref in t.references where declared.contains(ref) && !saved.contains(ref) {
                    saved.insert(ref)
                    queue.append(ref)
                }
            }
        }
        return saved
    }
}

// MARK: - Scanner

extension Outline {
    struct Scan {
        enum Kind: Equatable { case code, comment, string }

        let s: [Unicode.Scalar]
        var kind: [Kind]
        var count: Int { s.count }

        init(_ source: String) {
            s = Array(source.unicodeScalars)
            kind = Array(repeating: .code, count: s.count)
            markLiteralsAndComments()
        }

        // MARK: Lexing

        /// Marks every comment and string literal, so brace matching only sees code.
        mutating func markLiteralsAndComments() {
            var i = 0
            while i < count {
                if let end = commentEnd(i) {
                    for k in i..<end { kind[k] = .comment }
                    i = end
                } else if let end = stringEnd(i) {
                    for k in i..<end { kind[k] = .string }
                    i = end
                } else {
                    i += 1
                }
            }
        }

        /// The end of a comment that starts at `i`, if one does.
        func commentEnd(_ i: Int) -> Int? {
            guard i + 1 < count, s[i] == "/" else { return nil }
            if s[i + 1] == "/" {
                var j = i + 2
                while j < count && s[j] != "\n" { j += 1 }
                return j
            }
            guard s[i + 1] == "*" else { return nil }
            // Block comments nest in Swift.
            var depth = 1
            var j = i + 2
            while j < count && depth > 0 {
                if j + 1 < count && s[j] == "/" && s[j + 1] == "*" { depth += 1; j += 2 }
                else if j + 1 < count && s[j] == "*" && s[j + 1] == "/" { depth -= 1; j += 2 }
                else { j += 1 }
            }
            return j
        }

        /// The end of a string literal that starts at `i`, if one does:
        /// `"…"`, `"""…"""`, and raw `#"…"#` forms, with interpolations
        /// (which may hold strings of their own) skipped as code.
        func stringEnd(_ i: Int, nesting: Int = 0) -> Int? {
            var j = i
            var hashes = 0
            while j < count && s[j] == "#" { hashes += 1; j += 1 }
            guard j < count, s[j] == "\"" else { return nil }
            if hashes > 0, i > 0, isIdentifier(s[i - 1]) { return nil }
            let multiline = j + 2 < count && s[j + 1] == "\"" && s[j + 2] == "\""
            j += multiline ? 3 : 1
            while j < count {
                let c = s[j]
                if c == "\\" {
                    var k = j + 1
                    var h = 0
                    while h < hashes && k < count && s[k] == "#" { h += 1; k += 1 }
                    if h == hashes {
                        if k < count && s[k] == "(" {
                            // Absurdly deep nesting is read as the rest of the file being one string.
                            guard nesting < 32 else { return count }
                            j = interpolationEnd(k + 1, nesting: nesting + 1)
                            continue
                        }
                        j = k + 1
                        continue
                    }
                    j += 1
                    continue
                }
                if c == "\n" && !multiline { return j }   // an unterminated line: stop at its end
                if c == "\"" {
                    let quotes = multiline ? 3 : 1
                    if j + quotes - 1 < count && (0..<quotes).allSatisfy({ s[j + $0] == "\"" }) {
                        var k = j + quotes
                        var h = 0
                        while h < hashes && k < count && s[k] == "#" { h += 1; k += 1 }
                        if h == hashes { return k }
                    }
                }
                j += 1
            }
            return count
        }

        /// The index after the `)` that closes an interpolation whose code starts at `i`.
        func interpolationEnd(_ i: Int, nesting: Int) -> Int {
            var depth = 0
            var j = i
            while j < count {
                if let end = commentEnd(j) { j = end; continue }
                if let end = stringEnd(j, nesting: nesting) { j = max(end, j + 1); continue }
                switch s[j] {
                case "(": depth += 1
                case ")":
                    if depth == 0 { return j + 1 }
                    depth -= 1
                default: break
                }
                j += 1
            }
            return count
        }

        func isCode(_ i: Int) -> Bool { i < count && kind[i] == .code }

        func isIdentifier(_ c: Unicode.Scalar) -> Bool {
            c == "_" || c.properties.isAlphabetic || ("0"..."9").contains(c)
        }

        func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" }

        // MARK: Declarations

        enum DeclKind: Equatable { case type, function, property, other }

        struct Decl {
            var start: Int
            var end: Int
            var kind: DeclKind
            /// For a type: its name and the braces around its body.
            var name: String = ""
            var body: (open: Int, close: Int)? = nil
            var members: [Decl] = []
        }

        struct TypeInfo {
            var name: String
            var conformances: Set<String>
            var references: Set<String>
        }

        /// The declarations between `lo` and `hi`, each from its first code
        /// character to the end of its last.
        func declarations(_ lo: Int, _ hi: Int) -> [Decl] {
            var result: [Decl] = []
            var i = lo
            while i < hi {
                if !isCode(i) || isSpace(s[i]) || s[i] == ";" { i += 1; continue }
                let end = max(statementEnd(i, hi), i + 1)
                result.append(classify(i, end))
                i = end
            }
            return result
        }

        /// Where the statement that starts at `start` ends: at a line break or
        /// `;` outside any brackets, unless the next line plainly continues it.
        func statementEnd(_ start: Int, _ hi: Int) -> Int {
            if s[start] == "}" || s[start] == ")" || s[start] == "]" { return start + 1 }
            var depth = 0
            var i = start
            while i < hi {
                guard isCode(i) else { i += 1; continue }
                let c = s[i]
                switch c {
                case "{", "(", "[": depth += 1
                case "}", ")", "]":
                    if depth == 0 { return lastCode(before: i, from: start) + 1 }   // a stray closer ends it
                    depth -= 1
                case ";" where depth == 0:
                    return i
                case "\n" where depth == 0:
                    if !continues(start, i, hi) { return lastCode(before: i, from: start) + 1 }
                default: break
                }
                i += 1
            }
            // Unbalanced to the end: the rest is this statement.
            return lastCode(before: hi, from: start) + 1
        }

        /// Comments and whitespace; a string literal is significant.
        func isFiller(_ i: Int) -> Bool {
            kind[i] == .comment || kind[i] == .code && isSpace(s[i])
        }

        /// The last character before `i` that isn't a comment or whitespace.
        func lastCode(before i: Int, from start: Int) -> Int {
            var j = i - 1
            while j > start && isFiller(j) { j -= 1 }
            return max(j, start)
        }

        func nextCode(after i: Int, _ hi: Int) -> Int? {
            var j = i
            while j < hi && isFiller(j) { j += 1 }
            return j < hi ? j : nil
        }

        func text(_ a: Int, _ b: Int) -> String {
            var v = String.UnicodeScalarView()
            if a < b { v.append(contentsOf: s[a..<b]) }
            return String(v)
        }

        func codeText(_ a: Int, _ b: Int) -> String {
            var v = String.UnicodeScalarView()
            for k in a..<max(a, b) { v.append(kind[k] == .code ? s[k] : " ") }
            return String(v)
        }

        /// Whether the line break at `newline` continues the statement that
        /// began at `start`: after an attribute, a trailing `=` or `,`, or
        /// before a line that starts with `.`, `{`, `where` or an operator.
        func continues(_ start: Int, _ newline: Int, _ hi: Int) -> Bool {
            let last = lastCode(before: newline, from: start)
            let tail = codeText(max(start, last - 1), last + 1)
            if ["=", ","].contains(String(s[last])) && !tail.hasSuffix("==") { return true }
            if ["&&", "||", "->", "??"].contains(tail) { return true }
            if onlyAttributes(start, last + 1) { return true }
            guard let next = nextCode(after: newline, hi) else { return false }
            let ahead = codeText(next, min(hi, next + 6))
            if ahead.hasPrefix("..") { return false }
            for prefix in [".", "{", "?", ":", "&&", "||", "??", "->", "=", "where "] where ahead.hasPrefix(prefix) { return true }
            return false
        }

        /// `@MainActor`, `@available(iOS 17, *)` … with nothing after them yet.
        func onlyAttributes(_ a: Int, _ b: Int) -> Bool {
            var i = a
            var sawAttribute = false
            while i < b {
                if !isCode(i) || isSpace(s[i]) { i += 1; continue }
                guard s[i] == "@" else { return false }
                sawAttribute = true
                i += 1
                while i < b && isIdentifier(s[i]) { i += 1 }
                if i < b && s[i] == "(" { i = (matching(i, b) ?? b) + 1 }
            }
            return sawAttribute
        }

        /// The closer that matches the opener at `open`, in code, before `hi`.
        func matching(_ open: Int, _ hi: Int) -> Int? {
            let opener = s[open]
            let closer: Unicode.Scalar = opener == "{" ? "}" : opener == "(" ? ")" : "]"
            var depth = 0
            var i = open
            while i < hi {
                if isCode(i) {
                    if s[i] == opener { depth += 1 }
                    else if s[i] == closer {
                        depth -= 1
                        if depth == 0 { return i }
                    }
                }
                i += 1
            }
            return nil
        }

        /// The words a declaration starts with, past its attributes.
        func words(_ a: Int, _ b: Int, limit: Int = 12) -> [(word: String, at: Int)] {
            var out: [(String, Int)] = []
            var i = a
            while i < b && out.count < limit {
                if !isCode(i) || isSpace(s[i]) { i += 1; continue }
                if s[i] == "@" {
                    i += 1
                    while i < b && isIdentifier(s[i]) { i += 1 }
                    if i < b && s[i] == "(" { i = (matching(i, b) ?? b) + 1 }
                    continue
                }
                if s[i] == "#" || isIdentifier(s[i]) {
                    let w = i
                    i += 1
                    while i < b && isIdentifier(s[i]) { i += 1 }
                    out.append((text(w, i), w))
                    // `private(set)` and the like.
                    if i < b && s[i] == "(" && modifiers.contains(text(w, i)) { i = (matching(i, b) ?? b) + 1 }
                    continue
                }
                break
            }
            return out
        }

        let modifiers: Set<String> = ["public", "private", "fileprivate", "internal", "open", "package", "static", "final",
                                      "override", "mutating", "nonmutating", "lazy", "weak", "unowned", "convenience",
                                      "required", "dynamic", "nonisolated", "indirect", "optional", "prefix", "postfix",
                                      "infix", "isolated", "consuming", "borrowing", "distributed", "unsafe"]

        func firstWord(_ d: Decl) -> String? { words(d.start, d.end, limit: 1).first?.word }

        func classify(_ start: Int, _ end: Int) -> Decl {
            var decl = Decl(start: start, end: end, kind: .other)
            let ws = words(start, end)
            var k = 0
            while k < ws.count && (modifiers.contains(ws[k].word)
                   || ws[k].word == "class" && k + 1 < ws.count && ["func", "var", "let", "subscript", "init"].contains(ws[k + 1].word)) {
                k += 1
            }
            guard k < ws.count else { return decl }
            switch ws[k].word {
            case "struct", "class", "enum", "actor", "protocol", "extension":
                decl.kind = .type
                decl.name = typeName(after: ws[k].at + ws[k].word.unicodeScalars.count, end)
                if let open = firstBrace(start, end) {
                    if let close = matching(open, end) {
                        decl.body = (open, close)
                        decl.members = declarations(open + 1, close)
                    } else {
                        decl.kind = .other   // cut off: leave it as it is
                    }
                }
            case "func", "init", "deinit", "subscript":
                decl.kind = .function
            case "var", "let":
                decl.kind = .property
            default:
                break
            }
            return decl
        }

        /// `Todo` in `struct Todo<T>: Codable`, `Bar` in `extension Foo.Bar`.
        func typeName(after i: Int, _ end: Int) -> String {
            var j = i
            while j < end && isSpace(s[j]) { j += 1 }
            var name = ""
            while j < end {
                let w = j
                while j < end && isIdentifier(s[j]) { j += 1 }
                name = text(w, j)
                guard j < end, s[j] == "." else { break }
                j += 1
            }
            return name
        }

        /// The first `{` outside parentheses and brackets.
        func firstBrace(_ a: Int, _ b: Int) -> Int? {
            var depth = 0
            for i in a..<b where isCode(i) {
                switch s[i] {
                case "(", "[": depth += 1
                case ")", "]": depth = max(0, depth - 1)
                case "{" where depth == 0: return i
                default: break
                }
            }
            return nil
        }

        /// The last `{ … }` block of a statement, outside parentheses, if it ends the statement.
        func trailingBlock(_ d: Decl) -> (open: Int, close: Int)? {
            let last = lastCode(before: d.end, from: d.start)
            guard s[last] == "}", isCode(last) else { return nil }
            var depth = 0
            var i = last
            while i >= d.start {
                if isCode(i) {
                    if s[i] == "}" { depth += 1 }
                    if s[i] == "{" {
                        depth -= 1
                        if depth == 0 { return (i, last) }
                    }
                }
                i -= 1
            }
            return nil
        }

        /// The first `=` outside brackets that isn't part of `==` or `->`.
        func hasInitializer(_ d: Decl) -> Bool {
            var depth = 0
            for i in d.start..<d.end where isCode(i) {
                switch s[i] {
                case "(", "[", "{": depth += 1
                case ")", "]", "}": depth = max(0, depth - 1)
                case "=" where depth == 0:
                    let before = i > 0 ? s[i - 1] : " "
                    let after = i + 1 < count ? s[i + 1] : " "
                    if after != "=" && !["=", "!", "<", ">", "+", "-", "*", "/", "%", "&", "|"].contains(before) { return true }
                default: break
                }
            }
            return false
        }

        // MARK: Saved types

        func collectTypes(_ decls: [Decl]) -> [TypeInfo] {
            var out: [TypeInfo] = []
            for d in decls where d.kind == .type {
                var info = TypeInfo(name: d.name, conformances: [], references: [])
                // The inheritance clause: between the name and the body (or a `where`).
                let headEnd = d.body?.open ?? d.end
                if let colon = (d.start..<headEnd).first(where: { isCode($0) && s[$0] == ":" }) {
                    info.conformances = identifiers(colon + 1, headEnd)
                }
                for m in d.members {
                    let isCase = words(m.start, m.end, limit: 1).first?.word == "case"
                    if isCase || (m.kind == .property && isStored(m)) {
                        info.references.formUnion(identifiers(m.start, m.end))
                    }
                }
                out.append(info)
                out += collectTypes(d.members)
            }
            return out
        }

        func identifiers(_ a: Int, _ b: Int) -> Set<String> {
            var out: Set<String> = []
            var i = a
            while i < b {
                if isCode(i) && isIdentifier(s[i]) && !("0"..."9").contains(s[i]) {
                    let w = i
                    while i < b && isCode(i) && isIdentifier(s[i]) { i += 1 }
                    out.insert(text(w, i))
                } else {
                    i += 1
                }
            }
            return out
        }

        func isStored(_ d: Decl) -> Bool {
            if hasInitializer(d) { return true }
            guard let block = trailingBlock(d) else { return true }
            return isObserverBlock(block)
        }

        func isObserverBlock(_ block: (open: Int, close: Int)) -> Bool {
            guard let first = words(block.open + 1, block.close, limit: 1).first?.word else { return false }
            return first == "didSet" || first == "willSet"
        }

        func isAccessorRequirement(_ block: (open: Int, close: Int)) -> Bool {
            let inner = words(block.open + 1, block.close).map(\.word)
            return !inner.isEmpty && inner.allSatisfy { ["get", "set", "async", "throws", "mutating", "nonmutating"].contains($0) }
                && !(block.open + 1..<block.close).contains { isCode($0) && s[$0] == "{" }
        }

        // MARK: Keys

        /// The string literals a pattern captures, in code, in order of first use.
        func keys(_ pattern: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
            let source = text(0, count)
            let ns = source as NSString
            var seen: [String] = []
            // Map UTF-16 offsets back to scalar indices to check the match starts in code.
            var scalarAt: [Int] = []
            scalarAt.reserveCapacity(ns.length + 1)
            for (index, scalar) in s.enumerated() {
                for _ in 0..<scalar.utf16.count { scalarAt.append(index) }
            }
            scalarAt.append(count)
            for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
                guard match.range.location < scalarAt.count, isCode(scalarAt[match.range.location]) else { continue }
                let key = ns.substring(with: match.range(at: 1))
                if !seen.contains(key) { seen.append(key) }
            }
            return seen
        }

        // MARK: Output

        /// The start of the line `i` is on.
        func lineStart(_ i: Int) -> Int {
            var j = i
            while j > 0 && s[j - 1] != "\n" { j -= 1 }
            return j
        }

        func indentation(_ i: Int) -> String {
            let a = lineStart(i)
            var b = a
            while b < count && (s[b] == " " || s[b] == "\t") { b += 1 }
            return text(a, b)
        }

        /// The declaration's own text, from the start of its first line, without trailing spaces.
        func verbatim(_ a: Int, _ b: Int) -> [String] {
            let lead = indentation(a)
            let raw = lead + text(a, b)
            return raw.components(separatedBy: "\n").map { line in
                var l = Substring(line)
                while let last = l.last, last == " " || last == "\t" || last == "\r" { l = l.dropLast() }
                return String(l)
            }
        }

        /// `head { … }` with the head as written.
        func signature(_ d: Decl, open: Int) -> [String] {
            var lines = verbatim(d.start, lastCode(before: open, from: d.start) + 1)
            lines[lines.count - 1] += " { … }"
            return lines
        }

        func outline(_ d: Decl, saved: Set<String>) -> [String] {
            switch d.kind {
            case .type:
                guard let body = d.body else { return verbatim(d.start, d.end) }
                let isExtension = words(d.start, d.end).contains { $0.word == "extension" }
                if (saved.contains(d.name) && !isExtension) || d.name == "CodingKeys" {
                    return verbatim(d.start, d.end)
                }
                var lines = verbatim(d.start, lastCode(before: body.open, from: d.start) + 1)
                lines[lines.count - 1] += " {"
                var previousEnd = body.open + 1
                var first = true
                let memberIndent = indentation(d.start) + "    "
                for m in d.members {
                    var memberLines = outline(m, saved: saved)
                    if memberLines.isEmpty { continue }
                    // A member written on the same line as the brace gets an indented line of its own.
                    if lineStart(m.start) == lineStart(body.open) {
                        let own = indentation(m.start)
                        memberLines = memberLines.map { memberIndent + ($0.hasPrefix(own) ? String($0.dropFirst(own.count)) : $0) }
                    }
                    // Keep one blank line where the source had one or more.
                    if !first && text(previousEnd, m.start).components(separatedBy: "\n").count > 2 { lines.append("") }
                    lines += memberLines
                    previousEnd = m.end
                    first = false
                }
                lines.append(indentation(d.start) + "}")
                return lines
            case .function:
                guard let open = firstBrace(d.start, d.end) else { return verbatim(d.start, d.end) }
                return signature(d, open: open)
            case .property:
                guard let block = trailingBlock(d) else { return verbatim(d.start, d.end) }
                if isAccessorRequirement(block) { return verbatim(d.start, d.end) }
                if hasInitializer(d) && !isObserverBlock(block) { return verbatim(d.start, d.end) }
                return signature(d, open: block.open)
            case .other:
                // `#Preview { … }` and other top-level code with a body.
                if s[d.start] == "#", let open = firstBrace(d.start, d.end), matching(open, d.end) != nil,
                   !["#if", "#else", "#elseif", "#endif"].contains(firstWord(d) ?? "") {
                    return signature(d, open: open)
                }
                return verbatim(d.start, d.end)
            }
        }
    }
}
