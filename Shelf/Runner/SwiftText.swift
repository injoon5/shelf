/// An app's Swift source, one Unicode scalar at a time, each marked as code,
/// comment or string literal. `Outline` reads
/// source through this, so they agree on where code is.
///
/// It is a tolerant lexer, not a parser: it knows Swift's comments (nested
/// block comments too) and string literals (multi-line, raw and
/// interpolated ones), and anything it can't close, such as a file cut off
/// in the middle, runs to the end of its line or of the file.
struct SwiftText {
    enum Kind: Equatable { case code, comment, string }

    let scalars: [Unicode.Scalar]
    private(set) var kinds: [Kind]

    private var s: [Unicode.Scalar] { scalars }
    private var count: Int { scalars.count }

    init(_ source: String) {
        scalars = Array(source.unicodeScalars)
        kinds = Array(repeating: .code, count: scalars.count)
        var i = 0
        while i < count {
            if let end = commentEnd(i) {
                for k in i..<end { kinds[k] = .comment }
                i = end
            } else if let end = stringEnd(i) {
                for k in i..<end { kinds[k] = .string }
                i = end
            } else {
                i += 1
            }
        }
    }

    func isCode(_ i: Int) -> Bool { i < count && kinds[i] == .code }

    static func isIdentifier(_ c: Unicode.Scalar) -> Bool {
        c == "_" || c.properties.isAlphabetic || ("0"..."9").contains(c)
    }

    /// The end of a comment that starts at `i`, if one does.
    private func commentEnd(_ i: Int) -> Int? {
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
    private func stringEnd(_ i: Int, nesting: Int = 0) -> Int? {
        var j = i
        var hashes = 0
        while j < count && s[j] == "#" { hashes += 1; j += 1 }
        guard j < count, s[j] == "\"" else { return nil }
        if hashes > 0, i > 0, Self.isIdentifier(s[i - 1]) { return nil }
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
    private func interpolationEnd(_ i: Int, nesting: Int) -> Int {
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
}
